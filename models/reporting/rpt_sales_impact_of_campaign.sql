{{ config(
    materialized='view',
    schema='REPORTING'
) }}

/* =========================================================
   Reporting View: Sales Impact of Marketing Campaigns
   Doc: Marketing Effectiveness Dashboard >
        Sales Impact of Marketing Campaigns

   Total Sales Influenced is summed across the daily rows in
   fact_marketingperformance (additive by design). Final ROI
   is the latest cumulative value recorded for the campaign.
   ========================================================= */

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