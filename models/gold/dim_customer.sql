WITH src AS (

    SELECT *
    FROM {{ ref('s_customer') }}

),

final AS (

    SELECT

        /* Surrogate key */
        ROW_NUMBER() OVER (
            ORDER BY customer_id
        ) AS customer_key,

        /* Natural key */
        customer_id,

        first_name,
        last_name,
        full_name,

        email,
        is_valid_email,

        phone_number,
        is_valid_phone,

        birth_date,
        registration_date,
        last_purchase_date,

        age,
        customer_segment,

        street,
        city,
        state,
        country,
        zip_code,
        full_address,

        occupation,
        income_bracket,
        loyalty_tier,
        preferred_communication,
        preferred_payment_method,

        marketing_opt_in,

        total_purchases,
        total_spend

    FROM src

)

SELECT *
FROM final