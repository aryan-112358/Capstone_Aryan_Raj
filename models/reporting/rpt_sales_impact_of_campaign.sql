SELECT

    dc.campaign_key,
    dc.campaign_id,
    dc.audience_segment,
    dc.start_date,
    dc.end_date,
    dc.budget,
    dc.total_cost,

    SUM(fmp.total_sales_influenced) AS total_sales_influenced,
    ROUND(SUM(fmp.total_sales_influenced) - dc.total_cost, 2) AS net_sales_gain,
    MAX_BY(fmp.roi, fmp.date_key) AS final_roi

FROM {{ ref('fact_marketingperformance') }} fmp

LEFT JOIN {{ ref('dim_campaign') }} dc
    ON fmp.campaign_key = dc.campaign_key

WHERE dc.dbt_valid_to IS NULL

GROUP BY
    dc.campaign_key,
    dc.campaign_id,
    dc.audience_segment,
    dc.start_date,
    dc.end_date,
    dc.budget,
    dc.total_cost

ORDER BY total_sales_influenced DESC