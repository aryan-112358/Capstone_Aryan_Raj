{{ config(
    materialized='table',
    schema='GOLD'
) }}

/* =========================================================
   FACT_MarketingPerformance

   GRAIN: one row per campaign per date.

   ATTRIBUTION RULE (per doc requirement -- must be explicit):
   an order is attributed to whatever CAMPAIGN_ID is recorded
   directly on it in s_orders. No last-touch or lookback-window
   logic is applied, since the source data assigns campaign
   attribution at the order level already. Orders are also
   guarded to fall within the campaign's own start/end window.

   DOCUMENTED ASSUMPTION (spec ambiguity): the PS declares this
   fact's grain as per-date, but ROI and Repeat Purchase Rate
   reference "TotalCampaignCost" -- a single whole-campaign
   figure, not a daily one. Applying total campaign cost against
   a single day's sales would produce a meaningless ROI swing.
   Resolution: Total Sales Influenced and New Customers Acquired
   are DAILY (additive across dates, safe to roll up in reporting
   views). ROI and Repeat Purchase Rate are computed CUMULATIVE-
   TO-DATE per campaign, producing a trend line that only makes
   sense against the fixed total campaign cost. Confirm this
   interpretation if the spec author is available.

   Only COMPLETED orders count toward sales/customer metrics,
   consistent with how completed-order filtering is applied
   elsewhere in this project's Silver layer (Inventory).
   ========================================================= */

WITH all_completed_orders AS (

    SELECT
        order_id,
        customer_id,
        campaign_id,
        order_date,
        line_revenue * (1 - order_discount_amount) AS net_sales_amount

    FROM {{ ref('s_orders') }}

    WHERE order_status = 'completed'

),

/* A customer's true first-ever purchase, across ALL their
   orders (campaign-attributed or not) -- this is what makes
   "New Customers Acquired" mean the same thing as the doc's
   "not in any prior FACT_Sales" check, without needing a
   correlated subquery. */

customer_first_purchase AS (

    SELECT
        customer_id,
        MIN(order_date) AS first_purchase_date

    FROM all_completed_orders

    GROUP BY customer_id

),

campaign_orders AS (

    SELECT

        o.order_id,
        o.customer_id,
        o.campaign_id,
        o.order_date,
        o.net_sales_amount,

        CASE
            WHEN o.order_date = fp.first_purchase_date THEN TRUE
            ELSE FALSE
        END AS is_first_purchase,

        CASE
            WHEN o.order_date != fp.first_purchase_date THEN TRUE
            ELSE FALSE
        END AS is_repeat_purchase

    FROM all_completed_orders o

    INNER JOIN customer_first_purchase fp
        ON o.customer_id = fp.customer_id

    WHERE o.campaign_id IS NOT NULL

),

/* Bring in campaign window bounds to guard against any order
   whose campaign_id is set but whose order_date falls outside
   that campaign's declared active window (data quality check,
   mirrors the doc's BETWEEN StartDate AND EndDate condition). */

campaign_orders_bounded AS (

    SELECT

        co.*,
        dc.campaign_key,
        dc.total_cost

    FROM campaign_orders co

    INNER JOIN {{ ref('dim_campaign') }} dc
        ON co.campaign_id = dc.campaign_id
       AND dc.dbt_valid_to IS NULL
       AND co.order_date BETWEEN dc.start_date AND dc.end_date

),

daily_agg AS (

    SELECT

        campaign_key,
        total_cost,
        CAST(order_date AS DATE) AS activity_date,

        SUM(net_sales_amount) AS daily_sales_influenced,

        COUNT(DISTINCT
            CASE WHEN is_first_purchase THEN customer_id END
        ) AS daily_new_customers,

        COUNT(DISTINCT
            CASE WHEN is_repeat_purchase THEN customer_id END
        ) AS daily_repeat_customers,

        COUNT(DISTINCT
            CASE WHEN is_first_purchase THEN customer_id END
        ) AS daily_first_purchase_customers

    FROM campaign_orders_bounded

    GROUP BY campaign_key, total_cost, CAST(order_date AS DATE)

),

with_cumulative AS (

    SELECT

        *,

        SUM(daily_sales_influenced) OVER (
            PARTITION BY campaign_key
            ORDER BY activity_date
            ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        ) AS cumulative_sales_influenced,

        SUM(daily_repeat_customers) OVER (
            PARTITION BY campaign_key
            ORDER BY activity_date
            ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        ) AS cumulative_repeat_customers,

        SUM(daily_first_purchase_customers) OVER (
            PARTITION BY campaign_key
            ORDER BY activity_date
            ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        ) AS cumulative_first_purchase_customers

    FROM daily_agg

)

SELECT

    {{ dbt_utils.generate_surrogate_key(['campaign_key', 'activity_date']) }}
        AS marketing_performance_key,

    campaign_key,
    dd.date_key,

    daily_sales_influenced AS total_sales_influenced,
    daily_new_customers AS new_customers_acquired,

    /* Repeat Purchase Rate: cumulative repeat / cumulative first-purchase,
       trending as the campaign progresses. Guarded against divide-by-zero. */
    CASE
        WHEN cumulative_first_purchase_customers > 0
        THEN ROUND(
            100.0 * cumulative_repeat_customers / cumulative_first_purchase_customers,
            2
        )
        ELSE NULL
    END AS repeat_purchase_rate,

    /* ROI: cumulative sales influenced to date vs. fixed total campaign
       cost, guarded against divide-by-zero. */
    CASE
        WHEN total_cost > 0
        THEN ROUND(
            (cumulative_sales_influenced - total_cost) / total_cost * 100,
            2
        )
        ELSE NULL
    END AS roi

FROM with_cumulative wc

LEFT JOIN {{ ref('dim_date') }} dd
    ON wc.activity_date = dd.full_date