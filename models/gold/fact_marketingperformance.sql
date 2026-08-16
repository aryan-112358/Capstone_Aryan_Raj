WITH all_completed_orders AS (

    SELECT
        order_id,
        customer_id,
        campaign_id,
        order_date,
        line_revenue * (1 - (order_discount_amount / 100.0)) AS net_sales_amount

    FROM {{ ref('s_orders') }}

    WHERE order_status = 'completed'

),

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