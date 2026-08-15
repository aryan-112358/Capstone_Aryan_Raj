{{ config(
    materialized='table',
    schema='GOLD'
) }}

WITH src AS (

    SELECT *
    FROM {{ ref('s_store') }}

),

final AS (

    SELECT

        {{ dbt_utils.generate_surrogate_key(['store_id']) }} AS store_key,

        store_id,

        store_name,

        CONCAT_WS(
            ', ',
            street,
            city,
            state,
            country,
            zip_code
        ) AS address,

        region,
        store_type,
        opening_date,
        store_size_category AS size_category

    FROM src

    WHERE store_id IS NOT NULL
      AND TRIM(store_id) <> ''

)

SELECT *
FROM final