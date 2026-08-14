{% snapshot snapshot_store %}

{{
    config(
        target_schema='SILVER',
        unique_key='store_id',
        strategy='timestamp',
        updated_at='last_modified_date',
        invalidate_hard_deletes=True
    )
}}

WITH unwrapped AS (

    SELECT
        st.value AS store_json,
        LOADED_AT,
        SOURCE_FILE,
        BATCH_ID

    FROM {{ ref('b_store') }},

         LATERAL FLATTEN(
             input => RAW_DATA:stores_data
         ) st

),

prepared AS (

    SELECT

        TRIM(
            store_json:store_id::STRING
        ) AS store_id,

        TRY_TO_TIMESTAMP_NTZ(
            store_json:last_modified_date::STRING
        ) AS last_modified_date,

        store_json AS raw_data,

        LOADED_AT,
        SOURCE_FILE,
        BATCH_ID

    FROM unwrapped

)

SELECT

    store_id,

    last_modified_date,

    raw_data,

    LOADED_AT,

    SOURCE_FILE,

    BATCH_ID

FROM prepared

WHERE store_id IS NOT NULL
  AND store_id <> ''

QUALIFY ROW_NUMBER() OVER (

    PARTITION BY store_id
    ORDER BY
        last_modified_date DESC,
        LOADED_AT DESC

) = 1

{% endsnapshot %}