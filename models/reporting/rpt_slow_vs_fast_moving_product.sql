WITH product_turnover AS (

    SELECT

        fi.product_key,
        dp.product_id,
        dp.product_name,
        dp.category,

        AVG(fi.stock_turnover_ratio) AS avg_turnover_ratio,
        SUM(fi.sold_quantity) AS total_units_sold

    FROM {{ ref('fact_inventory') }} fi

    LEFT JOIN {{ ref('dim_product') }} dp
        ON fi.product_key = dp.product_key

    GROUP BY fi.product_key, dp.product_id, dp.product_name, dp.category

),

classified AS (

    SELECT

        *,

        CASE
            WHEN total_units_sold = 0 OR total_units_sold IS NULL
                THEN 'No Movement'
            ELSE
                CASE NTILE(3) OVER (
                    ORDER BY avg_turnover_ratio DESC NULLS LAST
                )
                    WHEN 1 THEN 'Fast-moving'
                    WHEN 2 THEN 'Moderate'
                    WHEN 3 THEN 'Slow-moving'
                END
        END AS movement_classification

    FROM product_turnover

)

SELECT *
FROM classified
ORDER BY avg_turnover_ratio DESC NULLS LAST