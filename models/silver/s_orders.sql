{{ config(
    materialized='table',
    schema='SILVER'
) }}

WITH current_orders AS (

    SELECT
        order_id_clean AS order_id,
        raw_data,
        loaded_at,
        source_file,
        batch_id

    FROM {{ ref('snapshot_orders') }}

    WHERE dbt_valid_to IS NULL

),

/* =========================================================
   1. Extract order-level fields
========================================================= */

orders_extracted AS (

    SELECT

        order_id,

        raw_data:order_date::TIMESTAMP_NTZ
            AS order_date,

        raw_data:discount_amount::NUMBER(18,6)
            AS order_discount_amount,

        raw_data:shipping_cost::NUMBER(18,2)
            AS shipping_cost,

        raw_data:tax_amount::NUMBER(18,2)
            AS tax_amount,

        raw_data:shipping_date::TIMESTAMP_NTZ
            AS shipping_date,

        raw_data:delivery_date::TIMESTAMP_NTZ
            AS delivery_date,

        raw_data:estimated_delivery_date::TIMESTAMP_NTZ
            AS estimated_delivery_date,

        raw_data:customer_id::STRING
            AS customer_id,

        raw_data:employee_id::STRING
            AS employee_id,

        raw_data:store_id::STRING
            AS store_id,

        raw_data:campaign_id::STRING
            AS campaign_id,

        raw_data:order_source::STRING
            AS order_source,

        raw_data:order_status::STRING
            AS order_status,

        raw_data:payment_method::STRING
            AS payment_method,

        raw_data:shipping_method::STRING
            AS shipping_method,

        raw_data,

        loaded_at,
        source_file,
        batch_id

    FROM current_orders

),

/* =========================================================
   2. Flatten order_items
========================================================= */

order_items AS (

    SELECT

        o.order_id,

        item.value:product_id::STRING
            AS product_id,

        item.value:quantity::NUMBER
            AS quantity,

        item.value:unit_price::NUMBER(18,2)
            AS unit_price,

        item.value:cost_price::NUMBER(18,2)
            AS cost_price,

        item.value:discount_amount::NUMBER(18,6)
            AS item_discount_amount

    FROM orders_extracted o,

    LATERAL FLATTEN(
        input => o.raw_data:order_items
    ) item

),

/* =========================================================
   3. Aggregate order items to order grain
========================================================= */

order_item_agg AS (

    SELECT

        order_id,

        COUNT(DISTINCT product_id)
            AS total_items,

        SUM(quantity)
            AS total_quantity,

        /* Discount is stored as percentage in source.
           Convert to fraction before multiplication. */

        SUM(
            quantity
            * unit_price
            * (
                1 - (
                    COALESCE(item_discount_amount, 0) / 100
                )
            )
        ) AS line_revenue,

        SUM(
            quantity * cost_price
        ) AS line_cost,

        SUM(
            COALESCE(item_discount_amount, 0)
        ) AS total_discount

    FROM order_items

    GROUP BY order_id

),

/* =========================================================
   4. Combine order and order-item data
========================================================= */

combined AS (

    SELECT

        o.order_id,

        o.order_date,

        o.order_discount_amount,

        o.shipping_cost,

        o.tax_amount,

        o.shipping_date,

        o.delivery_date,

        o.estimated_delivery_date,

        o.customer_id,

        o.employee_id,

        o.store_id,

        o.campaign_id,

        o.order_source,

        o.order_status,

        o.payment_method,

        o.shipping_method,

        i.total_items,

        i.total_quantity,

        i.line_revenue,

        i.line_cost,

        i.total_discount,

        o.loaded_at,
        o.source_file,
        o.batch_id

    FROM orders_extracted o

    LEFT JOIN order_item_agg i
        ON o.order_id = i.order_id

),

/* =========================================================
   5. Calculate profitability
========================================================= */

profitability AS (

    SELECT

        *,

        (
            line_revenue
            * (
                1 - (
                    COALESCE(order_discount_amount, 0) / 100
                )
            )
        )
        - COALESCE(line_cost, 0)
        - COALESCE(shipping_cost, 0)
        - COALESCE(tax_amount, 0)

        AS profit_amount

    FROM combined

)

/* =========================================================
   6. Final Silver table
========================================================= */

SELECT

    order_id,

    customer_id,

    employee_id,

    store_id,

    campaign_id,

    order_source,

    order_status,

    payment_method,

    shipping_method,

    order_date,

    /* =====================================================
       Order time of day
    ===================================================== */

    CASE

        WHEN EXTRACT(HOUR FROM order_date) >= 5
         AND EXTRACT(HOUR FROM order_date) < 12
            THEN 'Morning'

        WHEN EXTRACT(HOUR FROM order_date) >= 12
         AND EXTRACT(HOUR FROM order_date) < 17
            THEN 'Afternoon'

        WHEN EXTRACT(HOUR FROM order_date) >= 17
         AND EXTRACT(HOUR FROM order_date) < 22
            THEN 'Evening'

        ELSE 'Night'

    END AS order_time_of_day,

    /* =====================================================
       Date attributes
    ===================================================== */

    WEEK(order_date)
        AS order_week,

    MONTH(order_date)
        AS order_month,

    QUARTER(order_date)
        AS order_quarter,

    YEAR(order_date)
        AS order_year,

    /* =====================================================
       Order item metrics
    ===================================================== */

    total_items,

    total_quantity,

    line_revenue,

    line_cost,

    total_discount,

    /* =====================================================
       Order discount
    ===================================================== */

    order_discount_amount,

    /* =====================================================
       Profitability
    ===================================================== */

    profit_amount,

    CASE

        WHEN line_revenue > 0

        THEN
            (profit_amount / line_revenue) * 100

        ELSE NULL

    END AS profit_margin_percentage,

    /* =====================================================
       Shipping calculations
    ===================================================== */

    CASE

        WHEN order_date IS NOT NULL
         AND shipping_date IS NOT NULL

        THEN DATEDIFF(
            DAY,
            order_date,
            shipping_date
        )

        ELSE NULL

    END AS processing_days,

    CASE

        WHEN shipping_date IS NOT NULL
         AND delivery_date IS NOT NULL

        THEN DATEDIFF(
            DAY,
            shipping_date,
            delivery_date
        )

        ELSE NULL

    END AS shipping_days,

    /* =====================================================
       Delivery status
    ===================================================== */

    CASE

        WHEN delivery_date IS NOT NULL
         AND delivery_date <= estimated_delivery_date

            THEN 'On Time'

        WHEN delivery_date IS NOT NULL
         AND delivery_date > estimated_delivery_date

            THEN 'Delayed'

        WHEN delivery_date IS NULL
         AND CURRENT_DATE() > estimated_delivery_date

            THEN 'Potentially Delayed'

        ELSE 'In Transit'

    END AS delivery_status,

    /* =====================================================
       Metadata
    ===================================================== */

    loaded_at,
    source_file,
    batch_id

FROM profitability