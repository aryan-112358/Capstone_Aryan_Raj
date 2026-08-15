{{ config(
    materialized='view',
    schema='REPORTING'
) }}

/* =========================================================
   Reporting View: Customer Engagement Metrics by Campaign
   Doc: Marketing Effectiveness Dashboard >
        Customer Engagement Metrics by Campaign

   New Customers Acquired is summed across daily rows
   (additive). Repeat Purchase Rate is taken as the latest
   cumulative value recorded for the campaign, per the
   cumulative-to-date design of fact_marketingperformance.
   ========================================================= */

SELECT

    dc.campaign_key,
    dc.campaign_id,
    dc.audience_segment,

    SUM(fmp.new_customers_acquired) AS total_new_customers_acquired,
    MAX_BY(fmp.repeat_purchase_rate, fmp.date_key) AS final_repeat_purchase_rate

FROM {{ ref('fact_marketingperformance') }} fmp

LEFT JOIN {{ ref('dim_campaign') }} dc
    ON fmp.campaign_key = dc.campaign_key

WHERE dc.dbt_valid_to IS NULL

GROUP BY dc.campaign_key, dc.campaign_id, dc.audience_segment

ORDER BY total_new_customers_acquired DESC