{{ config(
    materialized='table',
    schema='GOLD'
) }}

/* =========================================================
   FACT_Inventory

   GRAIN: one row per product per store per date.

   DATA LIMITATION: source product stock has no store
   breakdown -- beginning/ending stock and purchased_quantity
   are company-wide values duplicated across every store row
   for a product+date (not genuinely store-specific). Only
   sold_quantity (from orders, which does carry store_id) and
   supplier_contribution_percentage (a true cross-product
   aggregate) are genuinely accurate per store/supplier.
   ========================================================= */

WITH inventory AS (

    SELECT *
    FROM {{ ref('s_inventory') }}

),

active_stores AS (

    SELECT
        CAST(store_key AS VARCHAR) AS store_key,
        store_id
    FROM {{ ref('dim_store') }}

),

inventory_by_store AS (

    SELECT
        i.*,
        s.store_id,
        s.store_key

    FROM inventory i
    CROSS JOIN active_stores s

),

/* Completed sales at daily grain, per store */

sold_by_store_daily AS (

    SELECT

        UPPER(TRIM(item.value:product_id::STRING)) AS product_id,

        UPPER(TRIM(ord.raw_data:store_id::STRING)) AS store_id,

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

      AND ord.raw_data:store_id IS NOT NULL

      AND TRY_TO_NUMBER(
            item.value:quantity::STRING
          ) IS NOT NULL

    GROUP BY 1, 2, 3

),

/* =========================================================
   Sales between previous snapshot and current snapshot
   ========================================================= */

sold_by_store AS (

    SELECT

        ibs.product_id,
        ibs.store_id,
        ibs.snapshot_date,

        SUM(
            COALESCE(
                sbd.sold_quantity,
                0
            )
        ) AS sold_quantity

    FROM inventory_by_store ibs

    LEFT JOIN sold_by_store_daily sbd

        ON ibs.product_id = sbd.product_id

       AND UPPER(
            TRIM(ibs.store_id)
           ) = sbd.store_id

       AND sbd.sold_date > ibs.previous_snapshot_date

       AND sbd.sold_date <= ibs.snapshot_date

    GROUP BY
        ibs.product_id,
        ibs.store_id,
        ibs.snapshot_date

),

/* =========================================================
   Total purchased quantity
   ========================================================= */

daily_total_purchased AS (

    SELECT

        snapshot_date,

        SUM(
            GREATEST(
                purchased_quantity,
                0
            )
        ) AS total_purchased_all_products

    FROM inventory

    GROUP BY snapshot_date

),

/* =========================================================
   Supplier purchased quantity
   ========================================================= */

daily_supplier_purchased AS (

    SELECT

        i.snapshot_date,

        dp.supplier_id,

        SUM(
            GREATEST(
                i.purchased_quantity,
                0
            )
        ) AS supplier_purchased_quantity

    FROM inventory i

    LEFT JOIN {{ ref('dim_product') }} dp

        ON i.product_id = dp.product_id

    GROUP BY
        i.snapshot_date,
        dp.supplier_id

),

/* =========================================================
   Dimension joins
   ========================================================= */

joined AS (

    SELECT

        ibs.product_id,
        ibs.store_id,
        ibs.snapshot_date,

        /* Explicit VARCHAR casts for surrogate keys */

        CAST(
            dp.product_key AS VARCHAR
        ) AS product_key,

        CAST(
            dd.date_key AS VARCHAR
        ) AS date_key,

        CAST(
            ibs.store_key AS VARCHAR
        ) AS store_key,

        CAST(
            ds.supplier_key AS VARCHAR
        ) AS supplier_key,

        dp.supplier_id,

        ibs.beginning_stock,

        ibs.purchased_quantity,

        COALESCE(
            sb.sold_quantity,
            0
        ) AS sold_quantity,

        ibs.ending_stock,

        ibs.ending_stock
            * dp.cost_price
            AS inventory_value

    FROM inventory_by_store ibs

    LEFT JOIN sold_by_store sb

        ON ibs.product_id = sb.product_id

       AND UPPER(
            TRIM(ibs.store_id)
           ) = sb.store_id

       AND ibs.snapshot_date = sb.snapshot_date

    LEFT JOIN {{ ref('dim_product') }} dp

        ON ibs.product_id = dp.product_id

    LEFT JOIN {{ ref('dim_supplier') }} ds

        ON dp.supplier_id = ds.supplier_id

    LEFT JOIN {{ ref('dim_date') }} dd

        ON ibs.snapshot_date = dd.full_date

),

with_ratios AS (

    SELECT

        *,

        CASE

            WHEN (
                beginning_stock
                + ending_stock
            ) > 0

            THEN
                sold_quantity
                /
                (
                    (
                        beginning_stock
                        + ending_stock
                    ) / 2.0
                )

            ELSE NULL

        END AS stock_turnover_ratio

    FROM joined

)

SELECT

    /* =====================================================
       Inventory surrogate key
       ===================================================== */

    CAST(
        {{ dbt_utils.generate_surrogate_key(
            [
                'wr.product_id',
                'wr.store_id',
                'wr.snapshot_date'
            ]
        ) }}
        AS VARCHAR
    ) AS inventory_key,

    /* =====================================================
       Dimension surrogate keys
       ===================================================== */

    CAST(product_key AS VARCHAR) AS product_key,

    CAST(date_key AS VARCHAR) AS date_key,

    CAST(store_key AS VARCHAR) AS store_key,

    CAST(supplier_key AS VARCHAR) AS supplier_key,

    /* =====================================================
       Measures
       ===================================================== */

    beginning_stock AS beginning_inventory,

    purchased_quantity,

    sold_quantity,

    ending_stock AS ending_inventory,

    inventory_value,

    stock_turnover_ratio,

    /* =====================================================
       Supplier contribution
       ===================================================== */

    ROUND(

        CASE

            WHEN dtp.total_purchased_all_products > 0

            THEN
                (
                    dsp.supplier_purchased_quantity
                    /
                    dtp.total_purchased_all_products
                ) * 100

            ELSE NULL

        END,

        2

    ) AS supplier_contribution_percentage

FROM with_ratios wr

LEFT JOIN daily_total_purchased dtp

    ON wr.snapshot_date = dtp.snapshot_date

LEFT JOIN daily_supplier_purchased dsp

    ON wr.snapshot_date = dsp.snapshot_date

   AND wr.supplier_id = dsp.supplier_id