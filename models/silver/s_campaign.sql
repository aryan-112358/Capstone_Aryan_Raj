{{ config(
    materialized='table',
    schema='SILVER'
) }}

WITH src_campaign AS (

    SELECT *

    FROM {{ ref('snapshot_campaign') }}

    /* Current active version */

    WHERE dbt_valid_to IS NULL

),

cleaned AS (

    SELECT

        /* =================================================
           CAMPAIGN KEY
        ================================================= */

        TRIM(campaign_id) AS campaign_id,


        /* =================================================
           BASIC CAMPAIGN DETAILS
        ================================================= */

        TRIM(
            raw_data:campaign_name::STRING
        ) AS campaign_name,

        INITCAP(
            TRIM(raw_data:campaign_type::STRING)
        ) AS campaign_type,

        INITCAP(
            TRIM(raw_data:channel::STRING)
        ) AS channel,

        TRIM(
            raw_data:description::STRING
        ) AS description,


        /* =================================================
           CAMPAIGN DATES
        ================================================= */

        TRY_TO_TIMESTAMP_NTZ(
            raw_data:start_date::STRING
        ) AS start_date,

        TRY_TO_TIMESTAMP_NTZ(
            raw_data:end_date::STRING
        ) AS end_date,

        TRY_TO_TIMESTAMP_NTZ(
            raw_data:last_modified_date::STRING
        ) AS last_modified_date,


        /* =================================================
           TARGET AUDIENCE
        ================================================= */

        TRIM(
            raw_data:target_audience::STRING
        ) AS target_audience,


        /* =================================================
           BUDGET
           
           Example:
           $24,005.75
           
           becomes:
           24005.75
        ================================================= */

        TRY_TO_DECIMAL(

            REGEXP_REPLACE(
                TRIM(raw_data:budget::STRING),
                '[$,]',
                ''
            ),

            18,
            2

        ) AS budget,


        /* =================================================
           TOTAL COST
           
           Example:
           $12,210.23
           
           becomes:
           12210.23
        ================================================= */

        TRY_TO_DECIMAL(

            REGEXP_REPLACE(
                TRIM(raw_data:total_cost::STRING),
                '[$,]',
                ''
            ),

            18,
            2

        ) AS total_cost,


        /* =================================================
           TOTAL REVENUE
           
           Example:
           $20,827.48
           
           becomes:
           20827.48
        ================================================= */

        TRY_TO_DECIMAL(

            REGEXP_REPLACE(
                TRIM(raw_data:total_revenue::STRING),
                '[$,]',
                ''
            ),

            18,
            2

        ) AS total_revenue,


        /* =================================================
           ROI CALCULATION

           IMPORTANT:
           Do NOT calculate ROI here.

           Requirement says Silver only converts the
           existing ROI string into numeric.

           Gold will calculate/validate actual ROI.
        ================================================= */

        TRY_TO_DECIMAL(
            TRIM(raw_data:roi_calculation::STRING),
            18,
            4
        ) AS roi_calculation,


        /* =================================================
           METADATA
        ================================================= */

        loaded_at,

        source_file,

        batch_id,

        dbt_valid_from,

        dbt_valid_to

    FROM src_campaign

),

final AS (

    SELECT

        *,


        /* =================================================
           1. CAMPAIGN DURATION

           Difference between start and end dates.
        ================================================= */

        CASE

            WHEN start_date IS NOT NULL
             AND end_date IS NOT NULL

            THEN DATEDIFF(
                DAY,
                start_date,
                end_date
            )

            ELSE NULL

        END AS campaign_duration_days,


        /* =================================================
           2. AUDIENCE SEGMENT

           Source examples:

           Students, 18-25, Campus
           Families, 25-50, Suburban
           Professionals, 30-50, Urban
           Seniors, 60+, All Areas

           Take the demographic group before
           the first comma.
        ================================================= */

        INITCAP(
            TRIM(
                SPLIT_PART(
                    target_audience,
                    ',',
                    1
                )
            )
        ) AS audience_segment,


        /* =================================================
           3. AUDIENCE AGE RANGE

           Examples:

           18-25
           25-50
           30-50
           60+
        ================================================= */

        TRIM(
            SPLIT_PART(
                target_audience,
                ',',
                2
            )
        ) AS audience_age_range,


        /* =================================================
           4. AUDIENCE LOCATION

           Examples:

           Campus
           Suburban
           Urban
           All Areas
        ================================================= */

        INITCAP(
            TRIM(
                SPLIT_PART(
                    target_audience,
                    ',',
                    3
                )
            )
        ) AS audience_location

    FROM cleaned

)

SELECT *

FROM final