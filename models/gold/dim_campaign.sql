WITH src AS (

    SELECT *
    FROM {{ ref('s_campaign') }}

),

final AS (

    SELECT

        /* Surrogate Key */
       {{ dbt_utils.generate_surrogate_key(['campaign_id']) }} AS campaign_key,

        /* Natural Key */
        campaign_id,

        /* Campaign Details */
        campaign_name,
        campaign_type,
        channel,
        description,

        /* Dates */
        start_date,
        end_date,
        last_modified_date,

        /* Audience */
        target_audience,
        audience_segment,
        audience_age_range,
        audience_location,

        /* Campaign Duration */
        campaign_duration_days,

        /* Financial Attributes */
        budget,
        total_cost,
        total_revenue,

        /* Metadata */
        loaded_at,
        source_file,
        batch_id,

        dbt_valid_from,
        dbt_valid_to

    FROM src

    WHERE campaign_id IS NOT NULL
      AND TRIM(campaign_id) <> ''

)

SELECT *
FROM final