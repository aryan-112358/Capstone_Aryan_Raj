{{ config(
    materialized='table',
    schema='SILVER'
) }}

WITH src_supplier AS (

    SELECT *

    FROM {{ ref('snapshot_supplier') }}

    WHERE dbt_valid_to IS NULL

),

supplier_clean AS (

    SELECT

        /* =================================================
           Natural Key
           ================================================= */

        TRIM(supplier_id) AS supplier_id,


        /* =================================================
           Supplier Name
           ================================================= */

        INITCAP(
            TRIM(raw_data:supplier_name::STRING)
        ) AS supplier_name,


        /* =================================================
           Supplier Type
           ================================================= */

        INITCAP(
            TRIM(raw_data:supplier_type::STRING)
        ) AS supplier_type,


        /* =================================================
           Contact Information
           ================================================= */

        INITCAP(
            TRIM(
                raw_data:contact_information:contact_person::STRING
            )
        ) AS contact_person,


        LOWER(
            TRIM(
                raw_data:contact_information:email::STRING
            )
        ) AS email,


        REGEXP_REPLACE(
            TRIM(
                raw_data:contact_information:phone::STRING
            ),
            '[^0-9]',
            ''
        ) AS phone_number,


        INITCAP(
            TRIM(
                raw_data:contact_information:address::STRING
            )
        ) AS address,


        /* =================================================
           Combined Contact Information
           ================================================= */

        CONCAT_WS(
            ' | ',

            INITCAP(
                TRIM(
                    raw_data:contact_information:contact_person::STRING
                )
            ),

            LOWER(
                TRIM(
                    raw_data:contact_information:email::STRING
                )
            ),

            REGEXP_REPLACE(
                TRIM(
                    raw_data:contact_information:phone::STRING
                ),
                '[^0-9]',
                ''
            ),

            INITCAP(
                TRIM(
                    raw_data:contact_information:address::STRING
                )
            )

        ) AS contact_information,


        /* =================================================
           Payment Terms
           ================================================= */

        TRIM(
            raw_data:payment_terms::STRING
        ) AS payment_terms,


        /* =================================================
           Additional Supplier Attributes
           Kept in Silver because they may be useful in Gold
           ================================================= */

        raw_data:credit_rating::STRING AS credit_rating,

        raw_data:is_active::BOOLEAN AS is_active,

        TRY_TO_DATE(
            raw_data:last_order_date::STRING
        ) AS last_order_date,

        TRY_TO_NUMBER(
            raw_data:lead_time_days::STRING
        ) AS lead_time_days,

        TRY_TO_NUMBER(
            raw_data:minimum_order_quantity::STRING
        ) AS minimum_order_quantity,

        INITCAP(
            TRIM(
                raw_data:preferred_carrier::STRING
            )
        ) AS preferred_carrier,

        TRIM(
            raw_data:tax_id::STRING
        ) AS tax_id,

        LOWER(
            TRIM(
                raw_data:website::STRING
            )
        ) AS website,

        TRY_TO_NUMBER(
            raw_data:year_established::STRING
        ) AS year_established,


        /* =================================================
           Categories Supplied
           ================================================= */

        ARRAY_TO_STRING(
            raw_data:categories_supplied,
            ', '
        ) AS categories_supplied,


        /* =================================================
           Contract Details
           ================================================= */

        TRIM(
            raw_data:contract_details:contract_id::STRING
        ) AS contract_id,

        TRY_TO_DATE(
            raw_data:contract_details:start_date::STRING
        ) AS contract_start_date,

        TRY_TO_DATE(
            raw_data:contract_details:end_date::STRING
        ) AS contract_end_date,

        raw_data:contract_details:exclusivity::BOOLEAN
            AS contract_exclusivity,

        raw_data:contract_details:renewal_option::BOOLEAN
            AS contract_renewal_option,


        /* =================================================
           Performance Metrics
           ================================================= */

        TRY_TO_DECIMAL(
            raw_data:performance_metrics:average_delay_days::STRING,
            18,
            2
        ) AS average_delay_days,

        TRY_TO_DECIMAL(
            raw_data:performance_metrics:defect_rate::STRING,
            18,
            2
        ) AS defect_rate,

        TRY_TO_DECIMAL(
            raw_data:performance_metrics:on_time_delivery_rate::STRING,
            18,
            2
        ) AS on_time_delivery_rate,

        INITCAP(
            TRIM(
                raw_data:performance_metrics:quality_rating::STRING
            )
        ) AS quality_rating,

        TRY_TO_DECIMAL(
            raw_data:performance_metrics:response_time_hours::STRING,
            18,
            2
        ) AS response_time_hours,

        TRY_TO_DECIMAL(
            raw_data:performance_metrics:returns_percentage::STRING,
            18,
            2
        ) AS returns_percentage,


        /* =================================================
           Last Modified
           ================================================= */

        TRY_TO_TIMESTAMP_NTZ(
            raw_data:last_modified_date::STRING
        ) AS last_modified_date,


        /* =================================================
           Metadata
           ================================================= */

        loaded_at,

        source_file,

        batch_id,

        dbt_valid_from,

        dbt_valid_to

    FROM src_supplier

),

final AS (

    SELECT

        *

    FROM supplier_clean

    WHERE supplier_id IS NOT NULL
      AND TRIM(supplier_id) <> ''

)

SELECT *

FROM final