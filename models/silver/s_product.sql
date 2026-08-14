{{ config(
    materialized='table',
    schema='SILVER'
) }}

WITH src_product AS (

    SELECT *

    FROM {{ ref('snapshot_product') }}

    /* Current active version of each product */

    WHERE dbt_valid_to IS NULL

),

cleaned AS (

    SELECT

        /* =================================================
           PRODUCT KEY
        ================================================= */

        TRIM(product_id) AS product_id,


        /* =================================================
           PRODUCT DETAILS
        ================================================= */

        INITCAP(
            TRIM(raw_data:name::STRING)
        ) AS product_name,

        INITCAP(
            TRIM(raw_data:brand::STRING)
        ) AS brand,

        INITCAP(
            TRIM(raw_data:category::STRING)
        ) AS category,

        INITCAP(
            TRIM(raw_data:subcategory::STRING)
        ) AS subcategory,

        INITCAP(
            TRIM(raw_data:product_line::STRING)
        ) AS product_line,

        INITCAP(
            TRIM(raw_data:color::STRING)
        ) AS color,

        INITCAP(
            TRIM(raw_data:size::STRING)
        ) AS size,

        TRIM(
            raw_data:dimensions::STRING
        ) AS dimensions,

        TRIM(
            raw_data:weight::STRING
        ) AS weight,

        TRIM(
            raw_data:warranty_period::STRING
        ) AS warranty_period,

        TRIM(
            raw_data:supplier_id::STRING
        ) AS supplier_id,


        /* =================================================
           PRODUCT DESCRIPTION
        ================================================= */

        TRIM(
            raw_data:short_description::STRING
        ) AS short_description,

        TRIM(
            raw_data:technical_specs::STRING
        ) AS technical_specs,

        /* Full product description */

        CONCAT_WS(
            ' | ',

            INITCAP(
                TRIM(raw_data:name::STRING)
            ),

            TRIM(
                raw_data:short_description::STRING
            ),

            TRIM(
                raw_data:technical_specs::STRING
            )

        ) AS full_description,


        /* =================================================
           PRICING
        ================================================= */

        TRY_TO_DECIMAL(
            raw_data:unit_price::STRING,
            18,
            2
        ) AS unit_price,

        TRY_TO_DECIMAL(
            raw_data:cost_price::STRING,
            18,
            2
        ) AS cost_price,


        /* =================================================
           INVENTORY
        ================================================= */

        TRY_TO_NUMBER(
            raw_data:stock_quantity::STRING
        ) AS stock_quantity,

        TRY_TO_NUMBER(
            raw_data:reorder_level::STRING
        ) AS reorder_level,


        /* =================================================
           DATES
        ================================================= */

        COALESCE(

            TRY_TO_DATE(
                raw_data:launch_date::STRING,
                'YYYY-MM-DD'
            ),

            TRY_TO_DATE(
                raw_data:launch_date::STRING,
                'DD-MM-YYYY'
            )

        ) AS launch_date,


        COALESCE(

            TRY_TO_DATE(
                raw_data:last_modified_date::STRING,
                'YYYY-MM-DD'
            ),

            TRY_TO_DATE(
                raw_data:last_modified_date::STRING,
                'DD-MM-YYYY'
            )

        ) AS last_modified_date,


        /* =================================================
           PRODUCT FLAG
        ================================================= */

        raw_data:is_featured::BOOLEAN
            AS is_featured,


        /* =================================================
           METADATA
        ================================================= */

        loaded_at,

        source_file,

        batch_id,

        dbt_valid_from,

        dbt_valid_to

    FROM src_product

),

final AS (

    SELECT

        *,


        /* =================================================
           1. PRODUCT HIERARCHY

           category > subcategory > product_line
        ================================================= */

        CONCAT_WS(
            ' > ',

            category,
            subcategory,
            product_line

        ) AS category_hierarchy,


        /* =================================================
           2. PROFIT MARGIN %

           ((unit_price - cost_price)
             / unit_price) * 100

           Guard against divide by zero.
        ================================================= */

        CASE

            WHEN unit_price > 0

            THEN ROUND(

                (
                    (
                        unit_price
                        - cost_price
                    )
                    / unit_price
                ) * 100,

                2

            )

            ELSE NULL

        END AS profit_margin_percentage,


        /* =================================================
           3. LOW STOCK FLAG

           stock_quantity < reorder_level
        ================================================= */

        CASE

            WHEN stock_quantity IS NOT NULL
             AND reorder_level IS NOT NULL
             AND stock_quantity < reorder_level

                THEN TRUE

            ELSE FALSE

        END AS low_stock_flag

    FROM cleaned

)

SELECT *

FROM final