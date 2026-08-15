{{ config(
    materialized='view',
    schema='REPORTING'
) }}

/* =========================================================
   Reporting View: Inventory Valuation
   Doc: Inventory Analysis > Inventory Valuation

   Sourced from s_inventory (product+date grain) rather than
   fact_inventory, to avoid the store fan-out duplication in
   fact_inventory (beginning/ending stock are company-wide
   values repeated identically across every store row there).
   Valuation is as of each product's most recent available
   snapshot.
   ========================================================= */

WITH latest_snapshot AS (

    SELECT

        product_id,
        snapshot_date,
        ending_stock,

        ROW_NUMBER() OVER (
            PARTITION BY product_id
            ORDER BY snapshot_date DESC
        ) AS rn

    FROM {{ ref('s_inventory') }}

)

SELECT

    dp.product_key,
    dp.product_id,
    dp.product_name,
    dp.category,

    ls.snapshot_date AS as_of_date,
    ls.ending_stock AS ending_inventory,
    dp.cost_price,

    ROUND(ls.ending_stock * dp.cost_price, 2) AS inventory_value

FROM latest_snapshot ls

LEFT JOIN {{ ref('dim_product') }} dp
    ON ls.product_id = dp.product_id

WHERE ls.rn = 1

ORDER BY inventory_value DESC