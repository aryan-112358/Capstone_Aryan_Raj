{{ config(
    materialized='view',
    schema='REPORTING'
) }}

/* =========================================================
   Reporting View: On-time vs. Delayed Supply Analysis
   Doc: Supplier Performance > On-time vs. Delayed Supply
        Analysis

   Sourced from dim_supplier.on_time_delivery_rate (already a
   whole percentage, e.g. 82.90 meaning 82.90% -- confirmed via
   sample data, no /100 correction needed). delayed_rate is the
   simple complement (100 - on_time_delivery_rate).

   performance_tier thresholds are a documented, adjustable
   default: >=95% On Time (strong), 85-95% Acceptable, <85%
   Needs Improvement. Adjust to your organization's actual SLA
   standard if different.
   ========================================================= */

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