WITH supplier_purchases AS (

    SELECT

        dp.supplier_id,
        SUM(GREATEST(si.purchased_quantity, 0)) AS purchased_quantity

    FROM {{ ref('s_inventory') }} si

    LEFT JOIN {{ ref('dim_product') }} dp
        ON si.product_id = dp.product_id

    GROUP BY dp.supplier_id

),

with_share AS (

    SELECT

        supplier_id,
        purchased_quantity,

        ROUND(
            100.0 * purchased_quantity
            / NULLIF(SUM(purchased_quantity) OVER (), 0),
            2
        ) AS overall_contribution_percentage

    FROM supplier_purchases

)

SELECT

    ds.supplier_key,
    ws.supplier_id,
    ws.purchased_quantity,
    ws.overall_contribution_percentage,

    POWER(ws.overall_contribution_percentage, 2) AS hhi_contribution,

    CASE
        WHEN ws.overall_contribution_percentage > 25 THEN 'High'
        WHEN ws.overall_contribution_percentage > 10 THEN 'Medium'
        ELSE 'Low'
    END AS concentration_risk_flag

FROM with_share ws

LEFT JOIN {{ ref('dim_supplier') }} ds
    ON ws.supplier_id = ds.supplier_id

ORDER BY ws.overall_contribution_percentage DESC