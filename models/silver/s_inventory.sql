WITH products_flattened AS (

    SELECT

        UPPER(
            TRIM(product.value:product_id::STRING)
        ) AS product_id,

        TRY_TO_NUMBER(
            product.value:stock_quantity::STRING
        ) AS stock_quantity,

        TRY_TO_NUMBER(
            product.value:reorder_level::STRING
        ) AS reorder_level,

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

stock_history AS (

    SELECT

        product_id,
        snapshot_date,
        reorder_level,
        stock_quantity AS ending_stock,

        LAG(snapshot_date) OVER (
            PARTITION BY product_id
            ORDER BY snapshot_date
        ) AS previous_snapshot_date,

        LAG(stock_quantity) OVER (
            PARTITION BY product_id
            ORDER BY snapshot_date
        ) AS beginning_stock,

        SOURCE_FILE,
        ROW_NUMBER,
        LOADED_AT,
        BATCH_ID

    FROM deduped

),

stock_with_lag AS (

    SELECT

        product_id,
        snapshot_date,
        previous_snapshot_date,
        beginning_stock,
        ending_stock,
        reorder_level,

        DATEDIFF(
            DAY,
            previous_snapshot_date,
            snapshot_date
        ) AS days_since_last_snapshot,

        SOURCE_FILE,
        ROW_NUMBER,
        LOADED_AT,
        BATCH_ID

    FROM stock_history

),

/* =========================================================
   Completed order quantities, kept at daily grain here --
   summed into the correct interval in the join below.
   ========================================================= */

sold_quantities AS (

    SELECT

        UPPER(
            TRIM(item.value:product_id::STRING)
        ) AS product_id,

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
   FIX: sold_quantity must cover every completed sale that
   happened SINCE the previous snapshot, not just sales that
   landed exactly on the snapshot date. Snapshots are sparse
   (can be many days apart per product), so matching on a
   single exact day was silently discarding almost all real
   sales -- that's why purchased_quantity was coming out at
   ~0 or negative. This sums sold_quantities across the full
   (previous_snapshot_date, snapshot_date] interval instead
   of an exact-date match.
   ========================================================= */

joined AS (

    SELECT

        s.product_id,
        s.snapshot_date,
        s.previous_snapshot_date,
        s.beginning_stock,
        s.ending_stock,
        s.reorder_level,
        s.days_since_last_snapshot,
        s.SOURCE_FILE,
        s.ROW_NUMBER,
        s.LOADED_AT,
        s.BATCH_ID,

        SUM(COALESCE(sq.sold_quantity, 0)) AS sold_quantity

    FROM stock_with_lag s

    LEFT JOIN sold_quantities sq

        ON s.product_id = sq.product_id
       AND sq.sold_date > s.previous_snapshot_date
       AND sq.sold_date <= s.snapshot_date

    GROUP BY
        s.product_id,
        s.snapshot_date,
        s.previous_snapshot_date,
        s.beginning_stock,
        s.ending_stock,
        s.reorder_level,
        s.days_since_last_snapshot,
        s.SOURCE_FILE,
        s.ROW_NUMBER,
        s.LOADED_AT,
        s.BATCH_ID

)

SELECT

    product_id,
    snapshot_date,
    previous_snapshot_date,

    beginning_stock,
    ending_stock,
    sold_quantity,

    (
        ending_stock
        - COALESCE(beginning_stock, ending_stock)
        + sold_quantity
    ) AS purchased_quantity,

    CASE
        WHEN ending_stock IS NOT NULL
         AND reorder_level IS NOT NULL
         AND ending_stock < reorder_level
        THEN TRUE
        ELSE FALSE
    END AS low_stock_flag,

    CASE
        WHEN days_since_last_snapshot > 1
        THEN TRUE
        ELSE FALSE
    END AS stale_snapshot_flag,

    days_since_last_snapshot,

    CASE
        WHEN ending_stock < 0
          OR beginning_stock < 0
        THEN TRUE
        ELSE FALSE
    END AS negative_balance_flag,

    reorder_level,

    SOURCE_FILE,
    ROW_NUMBER,
    LOADED_AT,
    BATCH_ID

FROM joined

WHERE beginning_stock IS NOT NULL