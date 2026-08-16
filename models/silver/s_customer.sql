WITH src_customer AS (

    SELECT *

    FROM {{ ref('snapshot_customer') }}

    /* Only the currently active snapshot record */

    WHERE dbt_valid_to IS NULL

),

cleaned AS (

    SELECT

        /* =================================================
           CUSTOMER
        ================================================= */

        TRIM(customer_id) AS customer_id,

        INITCAP(
            TRIM(raw_data:first_name::STRING)
        ) AS first_name,

        INITCAP(
            TRIM(raw_data:last_name::STRING)
        ) AS last_name,

        /* Requirement:
           FirstName || ' ' || LastName
        */

        CONCAT(
            INITCAP(
                TRIM(raw_data:first_name::STRING)
            ),
            ' ',
            INITCAP(
                TRIM(raw_data:last_name::STRING)
            )
        ) AS full_name,


        /* =================================================
           EMAIL VALIDATION AND CLEANING
        ================================================= */

        LOWER(
            TRIM(raw_data:email::STRING)
        ) AS email,

        CASE

            WHEN REGEXP_LIKE(
                LOWER(
                    TRIM(raw_data:email::STRING)
                ),
                '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$'
            )

            THEN TRUE

            ELSE FALSE

        END AS is_valid_email,


        /* =================================================
           PHONE VALIDATION AND CLEANING
        ================================================= */

        /* Remove spaces, brackets, dots, hyphens,
           plus signs and other non-numeric characters */

        REGEXP_REPLACE(
            TRIM(raw_data:phone::STRING),
            '[^0-9]',
            ''
        ) AS phone_number,

        CASE

            WHEN LENGTH(
                REGEXP_REPLACE(
                    TRIM(raw_data:phone::STRING),
                    '[^0-9]',
                    ''
                )
            ) BETWEEN 10 AND 15

            THEN TRUE

            ELSE FALSE

        END AS is_valid_phone,


        /* =================================================
           DATES
        ================================================= */

        COALESCE(

            TRY_TO_DATE(
                raw_data:birth_date::STRING,
                'YYYY-MM-DD'
            ),

            TRY_TO_DATE(
                raw_data:birth_date::STRING,
                'DD-MM-YYYY'
            )

        ) AS birth_date,


        COALESCE(

            TRY_TO_DATE(
                raw_data:registration_date::STRING,
                'YYYY-MM-DD'
            ),

            TRY_TO_DATE(
                raw_data:registration_date::STRING,
                'DD-MM-YYYY'
            )

        ) AS registration_date,


        COALESCE(

            TRY_TO_DATE(
                raw_data:last_purchase_date::STRING,
                'YYYY-MM-DD'
            ),

            TRY_TO_DATE(
                raw_data:last_purchase_date::STRING,
                'DD-MM-YYYY'
            )

        ) AS last_purchase_date,


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
           STANDARDIZED ADDRESS
        ================================================= */

        INITCAP(
            TRIM(raw_data:address:street::STRING)
        ) AS street,

        INITCAP(
            TRIM(raw_data:address:city::STRING)
        ) AS city,

        UPPER(
            TRIM(raw_data:address:state::STRING)
        ) AS state,

        UPPER(
            TRIM(raw_data:address:country::STRING)
        ) AS country,

        TRIM(
            raw_data:address:zip_code::STRING
        ) AS zip_code,


        /* Standardized complete address */

        CONCAT(
            INITCAP(
                TRIM(raw_data:address:street::STRING)
            ),
            ', ',
            INITCAP(
                TRIM(raw_data:address:city::STRING)
            ),
            ', ',
            UPPER(
                TRIM(raw_data:address:state::STRING)
            ),
            ', ',
            UPPER(
                TRIM(raw_data:address:country::STRING)
            ),
            ' ',
            TRIM(
                raw_data:address:zip_code::STRING
            )
        ) AS full_address,


        /* =================================================
           OTHER CUSTOMER ATTRIBUTES
        ================================================= */

        INITCAP(
            TRIM(raw_data:occupation::STRING)
        ) AS occupation,

        INITCAP(
            TRIM(raw_data:income_bracket::STRING)
        ) AS income_bracket,

        INITCAP(
            TRIM(raw_data:loyalty_tier::STRING)
        ) AS loyalty_tier,

        INITCAP(
            TRIM(raw_data:preferred_communication::STRING)
        ) AS preferred_communication,

        INITCAP(
            TRIM(raw_data:preferred_payment_method::STRING)
        ) AS preferred_payment_method,

        raw_data:marketing_opt_in::BOOLEAN
            AS marketing_opt_in,

        TRY_TO_NUMBER(
            raw_data:total_purchases::STRING
        ) AS total_purchases,

        TRY_TO_DECIMAL(
            raw_data:total_spend::STRING,
            18,
            2
        ) AS total_spend,


        /* =================================================
           METADATA
        ================================================= */

        loaded_at,

        source_file,

        batch_id,

        dbt_valid_from,

        dbt_valid_to

    FROM src_customer

),

final AS (

    SELECT

        *,


        /* =================================================
           CUSTOMER AGE
        ================================================= */

        CASE

            WHEN birth_date IS NOT NULL

            THEN DATEDIFF(
                YEAR,
                birth_date,
                CURRENT_DATE()
            )

            ELSE NULL

        END AS age,


        /* =================================================
           CUSTOMER SEGMENT
           
           Young       = 18-35
           Middle-aged = 36-55
           Senior      = 56+
        ================================================= */

        CASE

            WHEN birth_date IS NULL
                THEN NULL

            WHEN DATEDIFF(
                YEAR,
                birth_date,
                CURRENT_DATE()
            ) BETWEEN 18 AND 35

                THEN 'Young'

            WHEN DATEDIFF(
                YEAR,
                birth_date,
                CURRENT_DATE()
            ) BETWEEN 36 AND 55

                THEN 'Middle-aged'

            WHEN DATEDIFF(
                YEAR,
                birth_date,
                CURRENT_DATE()
            ) >= 56

                THEN 'Senior'

            ELSE NULL

        END AS customer_segment

    FROM cleaned

)

SELECT *

FROM final