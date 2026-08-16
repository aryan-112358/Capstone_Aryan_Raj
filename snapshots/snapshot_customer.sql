{% snapshot snapshot_customer %}

{{
    config(
        target_schema='SILVER',
        unique_key='customer_id',
        strategy='timestamp',
        updated_at='last_modified_date',
        invalidate_hard_deletes=True
    )
}}

WITH unwrapped AS (

    SELECT
        cust.value AS customer_json,
        CAST(LOADED_AT AS TIMESTAMP_NTZ) AS LOADED_AT,
        SOURCE_FILE,
        BATCH_ID

    FROM {{ ref('b_customer') }},

         LATERAL FLATTEN(
             input => RAW_DATA:customers_data
         ) cust

),

prepared AS (

    SELECT

        TRIM(
            customer_json:customer_id::STRING
        ) AS customer_id,

        TRY_TO_TIMESTAMP_NTZ(
            customer_json:last_modified_date::STRING
        ) AS last_modified_date,

        customer_json AS raw_data,

        LOADED_AT,
        SOURCE_FILE,
        BATCH_ID

    FROM unwrapped

)

SELECT

    customer_id,

    CAST(last_modified_date AS TIMESTAMP_NTZ) AS last_modified_date,

    raw_data,

    LOADED_AT,
    SOURCE_FILE,
    BATCH_ID

FROM prepared

WHERE customer_id IS NOT NULL
  AND customer_id <> ''

QUALIFY ROW_NUMBER() OVER (
    PARTITION BY customer_id
    ORDER BY
        last_modified_date DESC,
        LOADED_AT DESC
) = 1

{% endsnapshot %}