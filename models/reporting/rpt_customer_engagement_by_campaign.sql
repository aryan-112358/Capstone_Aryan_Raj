SELECT

    dc.campaign_key,
    dc.campaign_id,
    dc.campaign_name,
    dc.campaign_type,
    dc.audience_segment,

    SUM(fmp.new_customers_acquired) AS total_new_customers_acquired,
    MAX_BY(fmp.repeat_purchase_rate, dd.full_date) AS final_repeat_purchase_rate

FROM {{ ref('fact_marketingperformance') }} fmp

LEFT JOIN {{ ref('dim_campaign') }} dc
    ON fmp.campaign_key = dc.campaign_key

LEFT JOIN {{ ref('dim_date') }} dd
    ON fmp.date_key = dd.date_key

WHERE dc.dbt_valid_to IS NULL

GROUP BY
    dc.campaign_key,
    dc.campaign_id,
    dc.campaign_name,
    dc.campaign_type,
    dc.audience_segment

ORDER BY total_new_customers_acquired DESC