{{ config(
    materialized='table',
    schema='GOLD'
) }}

WITH src AS (

    SELECT *
    FROM {{ ref('s_product') }}

),

final AS (

    SELECT

        ROW_NUMBER() OVER (
            ORDER BY product_id
        ) AS product_key,

        product_id,

        product_name,
        category,
        subcategory,
        product_line,
        brand,

        color,
        size,

        unit_price,
        cost_price,

        supplier_id,

        full_description,

        stock_quantity,
        reorder_level,

        profit_margin_percentage,
        low_stock_flag,

        launch_date,
        last_modified_date,

        is_featured

    FROM src

)

SELECT *
FROM final