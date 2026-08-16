WITH date_spine AS (

    {{ dbt_utils.date_spine(
        datepart="day",
        start_date="to_date('2024-04-01')",
        end_date="dateadd(day, 1, to_date('2024-09-27'))"
    ) }}

),

final AS (

    SELECT

        {{ dbt_utils.generate_surrogate_key(['date_day']) }} AS date_key,

        date_day AS full_date,

        YEAR(date_day) AS year,

        'Q' || QUARTER(date_day) AS quarter,

        MONTH(date_day) AS month,

        WEEK(date_day) AS week,

        DAYOFWEEK(date_day) AS day_of_week,

        /* US federal holidays falling within the data window
           (2024-04-01 to 2024-09-27): Memorial Day, Juneteenth,
           Independence Day, Labor Day. Fixed-date/rule-based,
           not an exhaustive holiday calendar -- extend this list
           if the data window changes. */
        CASE
            WHEN date_day = '2024-05-27' THEN TRUE  -- Memorial Day
            WHEN date_day = '2024-06-19' THEN TRUE  -- Juneteenth
            WHEN date_day = '2024-07-04' THEN TRUE  -- Independence Day
            WHEN date_day = '2024-09-02' THEN TRUE  -- Labor Day
            ELSE FALSE
        END AS holiday_flag,

        CASE

            WHEN MONTH(date_day) IN (12, 1, 2)
                THEN 'Winter'

            WHEN MONTH(date_day) IN (3, 4, 5)
                THEN 'Spring'

            WHEN MONTH(date_day) IN (6, 7, 8)
                THEN 'Summer'

            ELSE 'Fall'

        END AS season

    FROM date_spine

)

SELECT *
FROM final