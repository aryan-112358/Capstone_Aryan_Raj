SELECT

    ds.supplier_key,
    ds.supplier_id,
    ds.supplier_name,
    ds.supplier_type,

    ds.on_time_delivery_rate,
    ROUND(100 - ds.on_time_delivery_rate, 2) AS delayed_rate,

    CASE
        WHEN ds.on_time_delivery_rate >= 95 THEN 'On Time'
        WHEN ds.on_time_delivery_rate >= 85 THEN 'Acceptable'
        ELSE 'Needs Improvement'
    END AS performance_tier

FROM {{ ref('dim_supplier') }} ds

ORDER BY ds.on_time_delivery_rate DESC