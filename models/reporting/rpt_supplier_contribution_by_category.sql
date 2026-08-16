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