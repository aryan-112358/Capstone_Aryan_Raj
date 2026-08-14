{{ config(
    materialized='table',
    schema='SILVER'
) }}

WITH products_flattened AS (

    SELECT

        /* =====================================================
           Product information
           ===================================================== */

        UPPER(TRIM(
            product.value:product_id::STRING
        )) AS product_id,

        TRY_TO_NUMBER(
            product.value:stock_quantity::STRING
        ) AS stock_quantity,

        TRY_TO_NUMBER(
            product.value:reorder_level::STRING
        ) AS reorder_level,

        /* =====================================================
           Actual product snapshot date

           Example:
           products_2024-04-05.json
           -> 2024-04-05
           ===================================================== */

        TRY_TO_DATE(
            REGEXP_SUBSTR(
                SOURCE_FILE,
                '[0-9]{4}-[0-9]{2}-[0-9]{2}'
            )
        ) AS snapshot_date,

        SOURCE_FILE,

        ROW_NUMBER,

        LOADED_AT,

        BATCH_ID

    FROM {{ ref('b_product') }},

         LATERAL FLATTEN(
             INPUT => RAW_DATA:products_data
         ) product

),

/* =========================================================
   Remove duplicate product/date records
   ========================================================= */

deduped AS (

    SELECT *

    FROM products_flattened

    WHERE product_id IS NOT NULL
      AND snapshot_date IS NOT NULL

    QUALIFY ROW_NUMBER() OVER (

        PARTITION BY
            product_id,
            snapshot_date

        ORDER BY
            LOADED_AT DESC,
            SOURCE_FILE DESC,
            ROW_NUMBER DESC

    ) = 1

),

/* =========================================================
   Calculate beginning and ending stock
   ========================================================= */

stock_with_lag AS (

    SELECT

        product_id,

        snapshot_date,

        reorder_level,

        /* Previous product snapshot stock */

        LAG(
            stock_quantity
        ) OVER (

            PARTITION BY product_id

            ORDER BY snapshot_date

        ) AS beginning_stock,

        /* Current product snapshot stock */

        stock_quantity AS ending_stock,

        /* =================================================
           Gap detection

           Example:
           Apr 01 -> Apr 02 = 1 day
           Apr 02 -> Apr 03 = 1 day

           Apr 01 -> Apr 13 = 12 days
           ================================================= */

        DATEDIFF(

            DAY,

            LAG(
                snapshot_date
            ) OVER (

                PARTITION BY product_id

                ORDER BY snapshot_date

            ),

            snapshot_date

        ) AS days_since_last_snapshot,

        SOURCE_FILE,

        ROW_NUMBER,

        LOADED_AT,

        BATCH_ID

    FROM deduped

),

/* =========================================================
   Completed order quantities

   IMPORTANT:
   order_items contains product_id and quantity.

   BUG FIX: order_date arrives as a full ISO 8601 timestamp
   (e.g. 2024-07-22T14:05:02Z), not a plain date. The prior
   TRY_TO_DATE(..., 'YYYY-MM-DD' / 'DD-MM-YYYY') calls never
   matched that format and silently returned NULL for every
   row, so the join to snapshot_date never matched and
   sold_quantity was always 0.

   FIX: parse as a timestamp with TRY_TO_TIMESTAMP_NTZ, then
   cast directly to DATE with ::DATE (not TRY_TO_DATE, which
   errors on a TIMESTAMP_NTZ input).
   ========================================================= */

sold_quantities AS (

    SELECT

        UPPER(TRIM(
            item.value:product_id::STRING
        )) AS product_id,

        TRY_TO_TIMESTAMP_NTZ(
            ord.raw_data:order_date::STRING
        )::DATE AS sold_date,

        SUM(

            TRY_TO_NUMBER(
                item.value:quantity::STRING
            )

        ) AS sold_quantity

    FROM {{ ref('snapshot_orders') }} ord,

         LATERAL FLATTEN(
             INPUT => ord.raw_data:order_items
         ) item

    WHERE ord.dbt_valid_to IS NULL

      AND UPPER(
            TRIM(
                COALESCE(
                    ord.raw_data:status::STRING,
                    ord.raw_data:order_status::STRING
                )
            )
          ) = 'COMPLETED'

      AND item.value:product_id IS NOT NULL

      AND TRY_TO_NUMBER(
            item.value:quantity::STRING
          ) IS NOT NULL

    GROUP BY 1, 2

),

/* =========================================================
   Join stock snapshots with sales

   IMPORTANT:
   We preserve the original logic:

   snapshot_date = sold_date

   We are NOT changing this to an interval join because
   you specifically want the reference logic preserved.
   ========================================================= */

joined AS (

    SELECT

        s.product_id,

        s.snapshot_date,

        s.beginning_stock,

        s.ending_stock,

        s.reorder_level,

        s.days_since_last_snapshot,

        COALESCE(
            sq.sold_quantity,
            0
        ) AS sold_quantity,

        s.SOURCE_FILE,

        s.ROW_NUMBER,

        s.LOADED_AT,

        s.BATCH_ID

    FROM stock_with_lag s

    LEFT JOIN sold_quantities sq

        ON s.product_id = sq.product_id

       AND s.snapshot_date = sq.sold_date

)

/* =========================================================
   Final inventory table
   ========================================================= */

SELECT

    product_id,

    snapshot_date,

    beginning_stock,

    ending_stock,

    sold_quantity,

    /* =====================================================
       Inferred purchased quantity

       Purchased =
           Ending Stock
           - Beginning Stock
           + Sold Quantity

       Because there is no actual receiving/purchase event
       in the source data.
       ===================================================== */

    (
        ending_stock
        - COALESCE(
            beginning_stock,
            ending_stock
        )
        + sold_quantity
    ) AS purchased_quantity,

    /* =====================================================
       Low stock
       ===================================================== */

    CASE

        WHEN ending_stock < reorder_level

        THEN TRUE

        ELSE FALSE

    END AS low_stock_flag,

    /* =====================================================
       Snapshot gap
       ===================================================== */

    CASE

        WHEN days_since_last_snapshot > 1

        THEN TRUE

        ELSE FALSE

    END AS stale_snapshot_flag,

    days_since_last_snapshot,

    /* =====================================================
       Negative balance
       ===================================================== */

    CASE

        WHEN ending_stock < 0
          OR beginning_stock < 0

        THEN TRUE

        ELSE FALSE

    END AS negative_balance_flag,

    SOURCE_FILE,

    ROW_NUMBER,

    LOADED_AT,

    BATCH_ID

FROM joined

/* =========================================================
   First snapshot has no beginning stock and therefore
   cannot be used for day-over-day inventory calculations.
   ========================================================= */

WHERE beginning_stock IS NOT NULL