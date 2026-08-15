{{ config(
    materialized='view',
    schema='REPORTING'
) }}

/* =========================================================
   Reporting View: ROI by Campaign Type
   Doc: Marketing Effectiveness Dashboard > ROI by Campaign Type

   Groups by dim_campaign.campaign_type directly. If your
   actual column name differs from campaign_type, update the
   reference below to match.

   ROI per campaign is taken as the LATEST cumulative value
   recorded for that campaign in fact_marketingperformance
   (final ROI as of the most recent date on record), per the
   cumulative-to-date design of that fact table.
   ========================================================= */

WITH campaign_final_roi AS (

    SELECT

        campaign_key,
        MAX_BY(roi, date_key) AS final_roi

    FROM {{ ref('fact_marketingperformance') }}

    GROUP BY campaign_key

)

SELECT

    dc.campaign_type,

    COUNT(DISTINCT dc.campaign_key) AS campaign_count,
    ROUND(AVG(cfr.final_roi), 2) AS avg_roi,
    ROUND(MIN(cfr.final_roi), 2) AS min_roi,
    ROUND(MAX(cfr.final_roi), 2) AS max_roi

FROM campaign_final_roi cfr

LEFT JOIN {{ ref('dim_campaign') }} dc
    ON cfr.campaign_key = dc.campaign_key

WHERE dc.dbt_valid_to IS NULL

GROUP BY dc.campaign_type

ORDER BY avg_roi DESC