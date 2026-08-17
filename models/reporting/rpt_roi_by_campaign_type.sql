WITH campaign_final_metrics AS (

    SELECT
        fmp.campaign_key,

        MAX_BY(
            fmp.roi,
            dd.full_date
        ) AS final_roi,

        MAX_BY(
            fmp.total_sales_influenced,
            dd.full_date
        ) AS final_sales_influenced

    FROM {{ ref('fact_marketingperformance') }} fmp

    LEFT JOIN {{ ref('dim_date') }} dd
        ON fmp.date_key = dd.date_key

    GROUP BY
        fmp.campaign_key
)

SELECT

    dc.campaign_type,

    COUNT(DISTINCT dc.campaign_key) AS campaign_count,

    ROUND(AVG(cfm.final_roi), 2) AS avg_roi,

    ROUND(
        SUM(cfm.final_sales_influenced),
        2
    ) AS total_sales_influenced

FROM campaign_final_metrics cfm

LEFT JOIN {{ ref('dim_campaign') }} dc
    ON cfm.campaign_key = dc.campaign_key

WHERE dc.dbt_valid_to IS NULL

GROUP BY
    dc.campaign_type

ORDER BY
    avg_roi DESC