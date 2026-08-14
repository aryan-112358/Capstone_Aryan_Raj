{% snapshot snapshot_orders %}

{{
    config(
        target_schema='SILVER',
        unique_key='order_id_clean',
        strategy='timestamp',
        updated_at='last_modified_date_clean',
        invalidate_hard_deletes=True
    )
}}

WITH unwrapped AS (

    SELECT
        ord.value AS order_json,
        LOADED_AT,
        SOURCE_FILE,
        BATCH_ID

    FROM {{ ref('b_orders') }},
         LATERAL FLATTEN(input => RAW_DATA:orders_data) ord
),

extracted AS (

    SELECT
        order_json:order_id::STRING AS order_id,
        order_json AS raw_data,
        LOADED_AT,
        SOURCE_FILE,
        BATCH_ID

    FROM unwrapped
),

cleaned AS (

    SELECT
        *,
        TRIM(order_id) AS order_id_clean,
        LOADED_AT AS last_modified_date_clean

    FROM extracted
)

SELECT
    order_id,
    order_id_clean,
    raw_data,
    LOADED_AT,
    SOURCE_FILE,
    BATCH_ID,
    last_modified_date_clean

FROM cleaned

WHERE order_id_clean IS NOT NULL
  AND order_id_clean <> ''

QUALIFY ROW_NUMBER() OVER (
    PARTITION BY order_id_clean
    ORDER BY LOADED_AT DESC
) = 1

{% endsnapshot %}