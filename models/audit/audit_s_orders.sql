SELECT
    CURRENT_TIMESTAMP() AS run_time,
    's_orders' AS model_name,
    COUNT(*) AS rows_processed
FROM {{ ref('s_orders') }}