{{ config(
    materialized='table',
    schema='GOLD'
) }}

/* =========================================================
   FACT_Inventory

   GRAIN: one row per product per date, with a store attached
   ONLY when a real completed sale occurred for that product
   in the interval (previous_snapshot_date, snapshot_date].

   By design (per explicit request): no cross join, no
   fabricated store rows. store_key/sold_quantity are NULL
   for product-dates where no store actually sold that
   product in the window -- this means the fact table does
   NOT literally satisfy the PS's declared "one row per
   product per store per date" grain when a product had zero
   sales that period (store dimension is simply absent for
   that row), but every row that does exist is a real,
   non-duplicated observation.

   beginning_inventory/ending_inventory/purchased_quantity
   remain company-wide values (source data has no real
   store-level stock breakdown) -- unavoidable regardless of
   join strategy, since that data doesn't exist per-store in
   the source at all.
   ========================================================= */

WITH inventory AS (

    SELECT *
    FROM {{ ref('s_inventory') }}

),

/* Completed sales at daily grain, per store */

sold_by_store_daily AS (

    SELECT

        UPPER(TRIM(item.value:product_id::STRING)) AS product_id,
        UPPER(TRIM(ord.raw_data:store_id::STRING)) AS store_id,

        TRY_TO_TIMESTAMP_NTZ(
            ord.raw_data:order_date::STRING
        )::DATE AS sold_date,

        SUM(TRY_TO_NUMBER(item.value:quantity::STRING)) AS sold_quantity

    FROM {{ ref('snapshot_orders') }} ord,

         LATERAL FLATTEN(INPUT => ord.raw_data:order_items) item

    WHERE ord.dbt_valid_to IS NULL

      AND UPPER(TRIM(
            COALESCE(
                ord.raw_data:status::STRING,
                ord.raw_data:order_status::STRING
            )
          )) = 'COMPLETED'

      AND item.value:product_id IS NOT NULL
      AND ord.raw_data:store_id IS NOT NULL
      AND TRY_TO_NUMBER(item.value:quantity::STRING) IS NOT NULL

    GROUP BY 1, 2, 3

),

/* Sum sales across the full snapshot interval per product+store,
   not an exact-date match -- snapshots can be several days apart. */

sold_by_store AS (

    SELECT

        i.product_id,
        i.snapshot_date,
        sbd.store_id,

        SUM(sbd.sold_quantity) AS sold_quantity

    FROM inventory i

    INNER JOIN sold_by_store_daily sbd
        ON i.product_id = sbd.product_id
       AND sbd.sold_date > i.previous_snapshot_date
       AND sbd.sold_date <= i.snapshot_date

    GROUP BY i.product_id, i.snapshot_date, sbd.store_id

),

/* LEFT JOIN: keeps every product-date from s_inventory. store_id and
   sold_quantity are NULL where no completed sale exists for that
   product in the interval -- no fabricated rows. */

joined AS (

    SELECT

        i.product_id,
        i.snapshot_date,
        sb.store_id,

        i.beginning_stock,
        i.purchased_quantity,
        sb.sold_quantity,
        i.ending_stock

    FROM inventory i

    LEFT JOIN sold_by_store sb
        ON i.product_id = sb.product_id
       AND i.snapshot_date = sb.snapshot_date

),

/* Company-wide daily total purchased quantity, denominator for
   Supplier Contribution % -- clamped against negative deltas */

daily_total_purchased AS (

    SELECT
        snapshot_date,
        SUM(GREATEST(purchased_quantity, 0)) AS total_purchased_all_products

    FROM inventory
    GROUP BY snapshot_date

),

daily_supplier_purchased AS (

    SELECT
        i.snapshot_date,
        dp.supplier_id,
        SUM(GREATEST(i.purchased_quantity, 0)) AS supplier_purchased_quantity

    FROM inventory i

    LEFT JOIN {{ ref('dim_product') }} dp
        ON i.product_id = dp.product_id

    GROUP BY i.snapshot_date, dp.supplier_id

),

with_dims AS (

    SELECT

        j.product_id,
        j.store_id,
        j.snapshot_date,

        dp.product_key,
        dd.date_key,
        ds_store.store_key,
        ds_supplier.supplier_key,
        dp.supplier_id,

        j.beginning_stock,
        j.purchased_quantity,
        COALESCE(j.sold_quantity, 0) AS sold_quantity,
        j.ending_stock,

        j.ending_stock * dp.cost_price AS inventory_value

    FROM joined j

    LEFT JOIN {{ ref('dim_product') }} dp
        ON j.product_id = dp.product_id

    LEFT JOIN {{ ref('dim_supplier') }} ds_supplier
        ON dp.supplier_id = ds_supplier.supplier_id

    LEFT JOIN {{ ref('dim_date') }} dd
        ON j.snapshot_date = dd.full_date

    LEFT JOIN {{ ref('dim_store') }} ds_store
        ON j.store_id = ds_store.store_id

),

with_ratios AS (

    SELECT

        *,

        CASE
            WHEN (beginning_stock + ending_stock) > 0
            THEN sold_quantity / ((beginning_stock + ending_stock) / 2.0)
            ELSE NULL
        END AS stock_turnover_ratio

    FROM with_dims

)

SELECT

    {{ dbt_utils.generate_surrogate_key(
        ['wr.product_id', 'wr.store_id', 'wr.snapshot_date']
    ) }} AS inventory_key,

    product_key,
    date_key,
    store_key,
    supplier_key,

    beginning_stock AS beginning_inventory,
    purchased_quantity,
    sold_quantity,
    ending_stock AS ending_inventory,

    inventory_value,
    stock_turnover_ratio,

    ROUND(
        CASE
            WHEN dtp.total_purchased_all_products > 0
            THEN (dsp.supplier_purchased_quantity
                  / dtp.total_purchased_all_products) * 100
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