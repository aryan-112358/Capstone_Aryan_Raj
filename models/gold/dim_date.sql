{{ config(
    materialized='table',
    schema='GOLD'
) }}

WITH date_spine AS (

    SELECT
        DATEADD(
            DAY,
            SEQ4(),
            TO_DATE('2024-04-01')
        ) AS full_date

    FROM TABLE(
        GENERATOR(
            ROWCOUNT => 1000
        )
    )

),

final AS (

    SELECT

        TO_NUMBER(
            TO_CHAR(full_date, 'YYYYMMDD')
        ) AS date_key,

        full_date,

        YEAR(full_date) AS year,

        'Q' || QUARTER(full_date) AS quarter,

        MONTH(full_date) AS month,

        WEEK(full_date) AS week,

        DAYOFWEEK(full_date) AS day_of_week,

        FALSE AS holiday_flag,

        CASE

            WHEN MONTH(full_date) IN (12, 1, 2)
                THEN 'Winter'

            WHEN MONTH(full_date) IN (3, 4, 5)
                THEN 'Spring'

            WHEN MONTH(full_date) IN (6, 7, 8)
                THEN 'Summer'

            ELSE 'Autumn'

        END AS season

    FROM date_spine

)

SELECT *
FROM final
WHERE full_date <= TO_DATE('2027-01-01')