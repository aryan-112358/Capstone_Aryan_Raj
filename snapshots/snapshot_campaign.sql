{% snapshot snapshot_campaign %}

{{
    config(
        target_schema='SILVER',
        unique_key='campaign_id',
        strategy='timestamp',
        updated_at='last_modified_date',
        invalidate_hard_deletes=True
    )
}}

WITH unwrapped AS (

    SELECT

        camp.value AS campaign_json,

        LOADED_AT,
        SOURCE_FILE,
        BATCH_ID

    FROM {{ ref('b_campaign') }},

         LATERAL FLATTEN(
             input => RAW_DATA:campaigns_data
         ) camp

),

prepared AS (

    SELECT

        /* =================================================
           CAMPAIGN KEY
        ================================================= */

        TRIM(
            campaign_json:campaign_id::STRING
        ) AS campaign_id,


        /* =================================================
           LAST MODIFIED DATE
        ================================================= */

        TRY_TO_TIMESTAMP_NTZ(
            campaign_json:last_modified_date::STRING
        ) AS last_modified_date,


        /* =================================================
           COMPLETE RAW CAMPAIGN RECORD
        ================================================= */

        campaign_json AS raw_data,

        LOADED_AT,

        SOURCE_FILE,

        BATCH_ID

    FROM unwrapped

)

SELECT

    campaign_id,

    last_modified_date,

    raw_data,

    LOADED_AT,

    SOURCE_FILE,

    BATCH_ID

FROM prepared

WHERE campaign_id IS NOT NULL
  AND campaign_id <> ''

QUALIFY ROW_NUMBER() OVER (

    PARTITION BY campaign_id

    ORDER BY
        last_modified_date DESC,
        LOADED_AT DESC

) = 1

{% endsnapshot %}