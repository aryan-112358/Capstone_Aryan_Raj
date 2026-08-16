SELECT
    CURRENT_TIMESTAMP() AS run_time,
    'fact_marketingperformance' AS model_name,
    COUNT(*) AS rows_processed
FROM {{ ref('fact_marketingperformance') }}