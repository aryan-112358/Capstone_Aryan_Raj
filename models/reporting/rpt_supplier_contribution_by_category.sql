{{ config(
    materialized='view',
    schema='REPORTING'
) }}

/* =========================================================
   Reporting View: Supplier Contribution by Product Category
   Doc: Supplier Performance > Supplier Contribution by
        Product Category

   Sourced from s_inventory (product+date grain), NOT
   fact_inventory, to avoid the store fan-out duplication in
   fact_inventory -- purchased_quantity there is a company-wide
   value repeated identically across every store row, so
   summing directly from fact_inventory would inflate totals
   by a factor of store count.

   Negative purchased_quantity deltas (inferred, can go
   negative due to unobserved shrinkage/returns) are clamped
   to 0 before aggregation, consistent with fact_inventory's
   own supplier_contribution_percentage calculation.
   ========================================================= */

WITH supplier_category_purchases AS (

    SELECT

        dp.supplier_id,
        dp.category,

        SUM(GREATEST(si.purchased_quantity, 0)) AS purchased_quantity

    FROM {{ ref('s_inventory') }} si

    LEFT JOIN {{ ref('dim_product') }} dp
        ON si.product_id = dp.product_id

    GROUP BY dp.supplier_id, dp.category

)

SELECT

    ds.supplier_key,
    scp.supplier_id,
    scp.category,
    scp.purchased_quantity,

    ROUND(
        100.0 * scp.purchased_quantity
        / NULLIF(SUM(scp.purchased_quantity) OVER (PARTITION BY scp.category), 0),
        2
    ) AS category_contribution_percentage

FROM supplier_category_purchases scp

LEFT JOIN {{ ref('dim_supplier') }} ds
    ON scp.supplier_id = ds.supplier_id

ORDER BY scp.category, category_contribution_percentage DESC