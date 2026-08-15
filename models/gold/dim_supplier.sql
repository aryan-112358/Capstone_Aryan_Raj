{{ config(
    materialized='table',
    schema='GOLD'
) }}

WITH src AS (

    SELECT *
    FROM {{ ref('s_supplier') }}

),

final AS (

    SELECT

      {{ dbt_utils.generate_surrogate_key(['supplier_id']) }} AS supplier_key,
        supplier_id,

        supplier_name,

        contact_information,

        payment_terms,

        supplier_type,

        on_time_delivery_rate

    FROM src

    WHERE supplier_id IS NOT NULL
      AND TRIM(supplier_id) <> ''

)

SELECT *
FROM final