{{ config(
    materialized='table',
    schema='GOLD'
) }}

/* =========================================================
   FACT_Inventory

   GRAIN: one row per product per date.

   Deviation from problem statement: the PS declares this
   fact's grain as "one row per product per store per date."
   The raw product source (b_product -> products_data) has
   no store_id or any store-level attribution field -- stock
   is reported as a single company-wide number per product
   per date. StoreKey is therefore not populated (NULL) and
   the grain is reduced to product/date, matching what the
   source data actually supports. SupplierKey is populated
   normally via DIM_Product -> supplier_id -> DIM_Supplier.
   ========================================================= */

WITH inventory AS (

    SELECT *
    FROM {{ ref('s_inventory') }}

),

joined AS (

    SELECT

        i.product_id,
        i.snapshot_date,

        dp.product_key,
        dd.date_key,
        ds.supplier_key,

        i.beginning_stock,
        i.purchased_quantity,
        i.sold_quantity,
        i.ending_stock,

        /* Inventory Value = ending stock x unit cost */
        i.ending_stock * dp.cost_price AS inventory_value

    FROM inventory i

    LEFT JOIN {{ ref('dim_product') }} dp
        ON i.product_id = dp.product_id

    LEFT JOIN {{ ref('dim_supplier') }} ds
        ON dp.supplier_id = ds.supplier_id

    LEFT JOIN {{ ref('dim_date') }} dd
        ON i.snapshot_date = dd.full_date

),

with_ratios AS (

    SELECT

        *,

        /* Stock Turnover Ratio = Sold / Average Inventory, guarded */
        CASE
            WHEN (beginning_stock + ending_stock) > 0
            THEN sold_quantity / ((beginning_stock + ending_stock) / 2.0)
            ELSE NULL
        END AS stock_turnover_ratio

    FROM joined

)

SELECT

    {{ dbt_utils.generate_surrogate_key(['product_id', 'snapshot_date']) }} AS inventory_key,

    product_key,
    date_key,
    CAST(NULL AS VARCHAR) AS store_key,   -- no store attribution in source data
    supplier_key,

    beginning_stock AS beginning_inventory,
    purchased_quantity,
    sold_quantity,
    ending_stock AS ending_inventory,

    inventory_value,
    stock_turnover_ratio,

    /* Supplier Contribution Percentage: at this grain there is one
       supplier per product per row, so this collapses to either 0
       or 100 per row -- it is only meaningful aggregated across
       products for a supplier, which the Supplier Performance
       reporting view should compute, not this fact table per row. */
    CAST(NULL AS NUMBER(5,2)) AS supplier_contribution_percentage

FROM with_ratios