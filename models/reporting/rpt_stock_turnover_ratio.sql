SELECT

    fi.product_key,

    dp.product_id,
    dp.product_name,
    dp.category,
    dp.subcategory,
    dp.brand,

    AVG(fi.stock_turnover_ratio) AS avg_stock_turnover_ratio,

    SUM(fi.sold_quantity) AS total_sold_quantity,

    SUM(fi.beginning_inventory) AS total_beginning_inventory,

    SUM(fi.ending_inventory) AS total_ending_inventory

FROM {{ ref('fact_inventory') }} fi

LEFT JOIN {{ ref('dim_product') }} dp
    ON fi.product_key = dp.product_key

GROUP BY

    fi.product_key,
    dp.product_id,
    dp.product_name,
    dp.category,
    dp.subcategory,
    dp.brand
ORDER BY avg_stock_turnover_ratio DESC