{% snapshot snapshot_inventory %}

{{
    config(
        target_schema='SILVER',
        unique_key='inventory_snapshot_key',
        strategy='timestamp',
        updated_at='stock_snapshot_at',
        invalidate_hard_deletes=True
    )
}}

WITH product_snapshots AS (

    SELECT

        TRIM(product_id) AS product_id,

        /* Product snapshot date */
        COALESCE(
            TRY_TO_DATE(
                raw_data:last_modified_date::STRING,
                'YYYY-MM-DD'
            ),
            TO_DATE(dbt_valid_from)
        ) AS snapshot_date,

        TRY_TO_NUMBER(
            raw_data:stock_quantity::STRING
        ) AS stock_quantity,

        TRY_TO_NUMBER(
            raw_data:reorder_level::STRING
        ) AS reorder_level,

        loaded_at,
        source_file,
        batch_id,

        dbt_valid_from,
        dbt_valid_to

    FROM {{ ref('snapshot_product') }}

    WHERE product_id IS NOT NULL
      AND TRIM(product_id) <> ''

),

/* =====================================================
   Remove duplicate product snapshots for same date
   ===================================================== */

observed_snapshots AS (

    SELECT

        product_id,

        snapshot_date,

        stock_quantity,

        reorder_level,

        loaded_at,

        source_file,

        batch_id,

        dbt_valid_from

    FROM product_snapshots

    WHERE snapshot_date IS NOT NULL

    QUALIFY ROW_NUMBER() OVER (

        PARTITION BY
            product_id,
            snapshot_date

        ORDER BY
            loaded_at DESC,
            dbt_valid_from DESC

    ) = 1

),

/* =====================================================
   Product date boundaries
   ===================================================== */

product_bounds AS (

    SELECT

        product_id,

        MIN(snapshot_date) AS min_snapshot_date,

        MAX(snapshot_date) AS max_snapshot_date

    FROM observed_snapshots

    GROUP BY product_id

),

/* =====================================================
   Date spine

   Generates every day between the first and last
   product snapshot.

   SEQ4() replaces the invalid G.SEQ reference.
   ===================================================== */

date_spine AS (

    SELECT

        b.product_id,

        DATEADD(
            DAY,
            SEQ4(),
            b.min_snapshot_date
        ) AS stock_date

    FROM product_bounds b

    CROSS JOIN TABLE(
        GENERATOR(
            ROWCOUNT => 5000
        )
    )

    WHERE DATEADD(
        DAY,
        SEQ4(),
        b.min_snapshot_date
    ) <= b.max_snapshot_date

),

/* =====================================================
   Put observed stock snapshots onto the daily spine
   ===================================================== */

daily_stock_raw AS (

    SELECT

        d.product_id,

        d.stock_date,

        o.stock_quantity AS observed_stock_quantity,

        o.reorder_level AS observed_reorder_level,

        o.loaded_at,

        o.source_file,

        o.batch_id

    FROM date_spine d

    LEFT JOIN observed_snapshots o

        ON d.product_id = o.product_id

       AND d.stock_date = o.snapshot_date

),

/* =====================================================
   Carry forward last observed stock

   Explicitly handles snapshot gaps, including
   the 12-day gap mentioned in the requirement.
   ===================================================== */

daily_stock_filled AS (

    SELECT

        product_id,

        stock_date,

        observed_stock_quantity,

        observed_reorder_level,

        LAST_VALUE(
            observed_stock_quantity
        ) IGNORE NULLS OVER (

            PARTITION BY product_id

            ORDER BY stock_date

            ROWS BETWEEN
                UNBOUNDED PRECEDING
                AND CURRENT ROW

        ) AS ending_stock,

        LAST_VALUE(
            observed_reorder_level
        ) IGNORE NULLS OVER (

            PARTITION BY product_id

            ORDER BY stock_date

            ROWS BETWEEN
                UNBOUNDED PRECEDING
                AND CURRENT ROW

        ) AS reorder_level,

        loaded_at,

        source_file,

        batch_id

    FROM daily_stock_raw

),

/* =====================================================
   Completed order quantities

   Flatten order_items and retain only completed orders.
   ===================================================== */

completed_order_items AS (

    SELECT

        TRIM(
            ord.raw_data:order_id::STRING
        ) AS order_id,

        COALESCE(

            TRY_TO_DATE(
                ord.raw_data:order_date::STRING,
                'YYYY-MM-DD'
            ),

            TRY_TO_DATE(
                ord.raw_data:order_date::STRING,
                'DD-MM-YYYY'
            )

        ) AS order_date,

        TRIM(
            item.value:product_id::STRING
        ) AS product_id,

        TRY_TO_NUMBER(
            item.value:quantity::STRING
        ) AS quantity

    FROM {{ ref('snapshot_orders') }} ord,

         LATERAL FLATTEN(
             input => ord.raw_data:order_items
         ) item

    WHERE UPPER(
        COALESCE(
            ord.raw_data:status::STRING,
            ord.raw_data:order_status::STRING
        )
    ) = 'COMPLETED'

),

/* =====================================================
   Sold quantity per product per day
   ===================================================== */

daily_sales AS (

    SELECT

        product_id,

        order_date AS stock_date,

        SUM(
            COALESCE(quantity, 0)
        ) AS sold_quantity

    FROM completed_order_items

    WHERE product_id IS NOT NULL
      AND order_date IS NOT NULL
      AND quantity IS NOT NULL

    GROUP BY
        product_id,
        order_date

),

/* =====================================================
   Combine stock and sales
   ===================================================== */

combined AS (

    SELECT

        s.product_id,

        s.stock_date,

        s.ending_stock,

        s.reorder_level,

        COALESCE(
            ds.sold_quantity,
            0
        ) AS sold_quantity,

        s.observed_stock_quantity,

        s.loaded_at,

        s.source_file,

        s.batch_id

    FROM daily_stock_filled s

    LEFT JOIN daily_sales ds

        ON s.product_id = ds.product_id

       AND s.stock_date = ds.stock_date

),

/* =====================================================
   Beginning stock = previous day's ending stock
   ===================================================== */

with_beginning_stock AS (

    SELECT

        *,

        LAG(
            ending_stock
        ) OVER (

            PARTITION BY product_id

            ORDER BY stock_date

        ) AS beginning_stock

    FROM combined

),

/* =====================================================
   Final inventory calculations
   ===================================================== */

final_inventory AS (

    SELECT

        product_id,

        stock_date,

        beginning_stock,

        ending_stock,

        sold_quantity,

        reorder_level,

        observed_stock_quantity,

        CASE

            WHEN observed_stock_quantity IS NOT NULL
                THEN 'Observed'

            ELSE 'Carried Forward'

        END AS stock_snapshot_status,

        /* =============================================
           Inferred purchased quantity

           purchased_quantity =
               ending_stock
               - beginning_stock
               + sold_quantity
           ============================================= */

        CASE

            WHEN beginning_stock IS NOT NULL
             AND ending_stock IS NOT NULL

            THEN
                ending_stock
                - beginning_stock
                + sold_quantity

            ELSE NULL

        END AS purchased_quantity,

        /* =============================================
           Low stock
           ============================================= */

        CASE

            WHEN ending_stock IS NOT NULL
             AND reorder_level IS NOT NULL
             AND ending_stock < reorder_level

            THEN TRUE

            ELSE FALSE

        END AS low_stock_flag,

        loaded_at,

        source_file,

        batch_id

    FROM with_beginning_stock

)

SELECT

    /* =============================================
       Snapshot key
       ============================================= */

    product_id
        || '|'
        || TO_VARCHAR(stock_date)
        AS inventory_snapshot_key,

    product_id,

    stock_date,

    beginning_stock,

    ending_stock,

    sold_quantity,

    purchased_quantity,

    reorder_level,

    low_stock_flag,

    stock_snapshot_status,

    observed_stock_quantity,

    loaded_at,

    source_file,

    batch_id,

    TO_TIMESTAMP_NTZ(stock_date)
        AS stock_snapshot_at

FROM final_inventory

{% endsnapshot %}