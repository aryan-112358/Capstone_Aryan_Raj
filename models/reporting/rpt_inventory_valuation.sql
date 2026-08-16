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
    dp.subcategory,

    ls.snapshot_date AS as_of_date,
    ls.ending_stock AS ending_inventory,
    dp.cost_price,

    ROUND(ls.ending_stock * dp.cost_price, 2) AS inventory_value

FROM latest_snapshot ls

LEFT JOIN {{ ref('dim_product') }} dp
    ON ls.product_id = dp.product_id

WHERE ls.rn = 1

ORDER BY inventory_value DESC