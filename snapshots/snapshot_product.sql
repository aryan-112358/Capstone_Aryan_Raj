{% snapshot snapshot_product %}

{{
    config(
        target_schema='SILVER',
        unique_key='product_id',
        strategy='timestamp',
        updated_at='last_modified_date',
        invalidate_hard_deletes=True
    )
}}

WITH unwrapped AS (

    SELECT
        prod.value AS product_json,
        LOADED_AT,
        SOURCE_FILE,
        BATCH_ID

    FROM {{ ref('b_product') }},

         LATERAL FLATTEN(
             input => RAW_DATA:products_data
         ) prod

),

prepared AS (

    SELECT

        TRIM(
            product_json:product_id::STRING
        ) AS product_id,

        TRY_TO_TIMESTAMP_NTZ(
            product_json:last_modified_date::STRING
        ) AS last_modified_date,

        product_json AS raw_data,

        LOADED_AT,
        SOURCE_FILE,
        BATCH_ID

    FROM unwrapped

)

SELECT

    product_id,

    last_modified_date,

    raw_data,

    LOADED_AT,

    SOURCE_FILE,

    BATCH_ID

FROM prepared

WHERE product_id IS NOT NULL
  AND product_id <> ''

QUALIFY ROW_NUMBER() OVER (

    PARTITION BY product_id

    ORDER BY
        last_modified_date DESC,
        LOADED_AT DESC

) = 1

{% endsnapshot %}