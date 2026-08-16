WITH src AS (

    SELECT *

    FROM {{ ref('snapshot_store') }}

    -- Current active version of each store
    WHERE dbt_valid_to IS NULL

),

store_clean AS (

    SELECT


        TRIM(store_id) AS store_id,


        INITCAP(
            TRIM(raw_data:store_name::STRING)
        ) AS store_name,

        INITCAP(
            TRIM(raw_data:store_type::STRING)
        ) AS store_type,

        INITCAP(
            TRIM(raw_data:region::STRING)
        ) AS region,

        TRIM(
            raw_data:manager_id::STRING
        ) AS manager_id,


        /* =================================================
           DATES
        ================================================= */

        COALESCE(

            TRY_TO_DATE(
                raw_data:opening_date::STRING,
                'YYYY-MM-DD'
            ),

            TRY_TO_DATE(
                raw_data:opening_date::STRING,
                'DD-MM-YYYY'
            )

        ) AS opening_date,

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
           FINANCIAL / PERFORMANCE INPUTS
        ================================================= */

        TRY_TO_DECIMAL(
            raw_data:current_sales::STRING,
            18,
            2
        ) AS current_sales,

        TRY_TO_DECIMAL(
            raw_data:sales_target::STRING,
            18,
            2
        ) AS sales_target,

        TRY_TO_DECIMAL(
            raw_data:monthly_rent::STRING,
            18,
            2
        ) AS monthly_rent,

        TRY_TO_NUMBER(
            raw_data:size_sq_ft::STRING
        ) AS size_sq_ft,

        TRY_TO_NUMBER(
            raw_data:employee_count::STRING
        ) AS employee_count,

        raw_data:is_active::BOOLEAN AS is_active,


        /* =================================================
           ADDRESS STANDARDIZATION
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


        /* =================================================
           FULL STANDARDIZED ADDRESS
        ================================================= */

        CONCAT_WS(
            ', ',

            INITCAP(
                TRIM(raw_data:address:street::STRING)
            ),

            INITCAP(
                TRIM(raw_data:address:city::STRING)
            ),

            UPPER(
                TRIM(raw_data:address:state::STRING)
            ),

            CONCAT(
                UPPER(
                    TRIM(raw_data:address:country::STRING)
                ),
                ' ',
                TRIM(
                    raw_data:address:zip_code::STRING
                )
            )

        ) AS full_address,


        /* =================================================
           POSTAL CODE VALIDATION
           
           Source data is US postal-code data.
           Valid formats:
             12345
             12345-6789
        ================================================= */

        CASE

            WHEN REGEXP_LIKE(
                TRIM(raw_data:address:zip_code::STRING),
                '^[0-9]{5}(-[0-9]{4})?$'
            )

            THEN TRUE

            ELSE FALSE

        END AS is_valid_postal_code,


        /* =================================================
           CONTACT
        ================================================= */

        CASE

            WHEN REGEXP_LIKE(
                LOWER(
                    TRIM(raw_data:email::STRING)
                ),
                '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$'
            )

            THEN LOWER(
                TRIM(raw_data:email::STRING)
            )

            ELSE NULL

        END AS email,


        REGEXP_REPLACE(
            TRIM(
                raw_data:phone_number::STRING
            ),
            '[^0-9]',
            ''
        ) AS phone_number,


        /* =================================================
           OPERATING HOURS
        ================================================= */

        TRIM(
            raw_data:operating_hours:weekdays::STRING
        ) AS weekdays,

        TRIM(
            raw_data:operating_hours:weekends::STRING
        ) AS weekends,

        TRIM(
            raw_data:operating_hours:holidays::STRING
        ) AS holidays,


        /* =================================================
           SERVICES
        ================================================= */

        ARRAY_TO_STRING(
            raw_data:services,
            ', '
        ) AS services,


        /* =================================================
           METADATA
        ================================================= */

        loaded_at,

        source_file,

        batch_id,

        dbt_valid_from,

        dbt_valid_to

    FROM src

),

store_final AS (

    SELECT

        store_id,

        store_name,

        store_type,

        region,

        manager_id,

        opening_date,

        last_modified_date,

        current_sales,

        sales_target,

        monthly_rent,

        size_sq_ft,

        employee_count,

        is_active,

        street,

        city,

        state,

        country,

        zip_code,

        full_address,

        is_valid_postal_code,

        email,

        phone_number,

        weekdays,

        weekends,

        holidays,

        services,


        /* =================================================
           1. STORE SIZE CATEGORY

           < 5000       = Small
           5000-10000   = Medium
           > 10000      = Large
        ================================================= */

        CASE

            WHEN size_sq_ft IS NULL
                THEN NULL

            WHEN size_sq_ft < 5000
                THEN 'Small'

            WHEN size_sq_ft >= 5000
             AND size_sq_ft <= 10000
                THEN 'Medium'

            WHEN size_sq_ft > 10000
                THEN 'Large'

            ELSE NULL

        END AS store_size_category,


        /* =================================================
           2. STORE AGE IN YEARS
        ================================================= */

        CASE

            WHEN opening_date IS NOT NULL

            THEN DATEDIFF(
                YEAR,
                opening_date,
                CURRENT_DATE()
            )

            ELSE NULL

        END AS store_age_years,


        /* =================================================
           3. SALES TARGET ACHIEVEMENT %
           
           (current_sales / sales_target) * 100
           
           Guard against divide-by-zero
        ================================================= */

        CASE

            WHEN sales_target > 0

            THEN ROUND(
                (
                    current_sales
                    / sales_target
                ) * 100,
                2
            )

            ELSE NULL

        END AS sales_target_achievement_percentage,


        /* =================================================
           4. REVENUE PER SQ FT
           
           current_sales / size_sq_ft
           
           Guard against divide-by-zero
        ================================================= */

        CASE

            WHEN size_sq_ft > 0

            THEN ROUND(
                current_sales
                / size_sq_ft,
                2
            )

            ELSE NULL

        END AS revenue_per_sq_ft,


        /* =================================================
           5. EMPLOYEE EFFICIENCY
           
           current_sales / employee_count
           
           Guard against divide-by-zero
        ================================================= */

        CASE

            WHEN employee_count > 0

            THEN ROUND(
                current_sales
                / employee_count,
                2
            )

            ELSE NULL

        END AS employee_efficiency,


        /* =================================================
           6. PERFORMANCE ISSUE FLAG
           
           Achievement < 90%
        ================================================= */

        CASE

            WHEN sales_target > 0
             AND (
                    (
                        current_sales
                        / sales_target
                    ) * 100
                 ) < 90

            THEN 'Yes'

            ELSE 'No'

        END AS performance_issue_flag,


        /* =================================================
           METADATA
        ================================================= */

        loaded_at,

        source_file,

        batch_id,

        dbt_valid_from,

        dbt_valid_to

    FROM store_clean

)

SELECT *

FROM store_final