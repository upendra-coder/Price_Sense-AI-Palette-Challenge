-- LOGIC:
--   1. Base adjustment comes from elasticity:
--        inelastic        -> raise up to 10%
--        moderately elastic -> raise up to 6%
--        elastic           -> hold
--        highly elastic    -> reduce up to 6%
--   2. A few small additive bonuses (not multipliers, so they
--      can't compound into something extreme): trending product,
--      high-tier-city audience, underpriced vs. competitors.
--   3. Total adjustment capped at +/-20%.
--   4. A demand "cliff" (price band where volume drops >25% vs.
--      the prior $10 band) caps how high we'll recommend going.
--   5. Revenue/volume impact projected from elasticity:
--        Q_new = Q_old * (1 + elasticity * pct_price_change)

WITH
current_metrics AS (
    SELECT product_id, category, pack_size,
           ROUND(AVG(price), 2)      AS current_price,
           ROUND(SUM(revenue), 2)    AS current_revenue,
           SUM(quantity)             AS current_units
    FROM master_view
    GROUP BY product_id, category, pack_size
),

-- Demand cliff: first $10 price band where volume drops >25%
-- vs. the previous band (using $10 bands, not $1, so each band
-- has enough orders to be meaningful).

cliff_bands AS (
    SELECT product_id, FLOOR(price / 10) * 10 AS price_band,
           SUM(quantity) AS band_qty
    FROM master_view
    GROUP BY product_id, FLOOR(price / 10) * 10
    HAVING COUNT(*) >= 3
),
first_cliff AS (
    SELECT product_id, price_band AS cliff_price
    FROM (
        SELECT product_id, price_band,
               LAG(band_qty) OVER (PARTITION BY product_id ORDER BY price_band) AS prev_qty,
               band_qty,
               ROW_NUMBER() OVER (PARTITION BY product_id ORDER BY price_band) AS seq
        FROM cliff_bands
    )
    WHERE prev_qty IS NOT NULL
      AND (band_qty - prev_qty) * 100.0 / prev_qty < -25
    QUALIFY ROW_NUMBER() OVER (PARTITION BY product_id ORDER BY seq) = 1
),

-- Context bonuses (percentage points, additive)
signals AS (
    SELECT
        cm.product_id, cm.category, cm.pack_size,
        cm.current_price, cm.current_revenue, cm.current_units,
        COALESCE(pe.elasticity, 0.0)                        AS elasticity,
        COALESCE(fc.cliff_price, cm.current_price * 2)       AS cliff_price,

        -- trending claim -> +3pp
        (SELECT CASE WHEN is_high_protein = 1 OR is_plant_based = 1 THEN 3 ELSE 0 END
         FROM clean_product_metadata WHERE product_id = cm.product_id)  AS trend_bonus_pp,

        -- >40% of revenue from Tier-1 cities -> +2pp
        (SELECT CASE WHEN SUM(CASE WHEN tier_rank = 1 THEN revenue ELSE 0 END)
                          * 100.0 / NULLIF(SUM(revenue), 0) > 40 THEN 2 ELSE 0 END
         FROM master_view WHERE product_id = cm.product_id AND tier_rank IS NOT NULL) AS geo_bonus_pp,

        -- priced below market 25th percentile -> +3pp, above 75th -> -2pp
        CASE
            WHEN cm.current_price < (SELECT QUANTILE(avg_comp_price, 0.25) FROM clean_competitor_pricing) THEN 3
            WHEN cm.current_price > (SELECT QUANTILE(avg_comp_price, 0.75) FROM clean_competitor_pricing) THEN -2
            ELSE 0
        END                                                  AS comp_bonus_pp
    FROM current_metrics cm
    LEFT JOIN product_elasticity pe ON cm.product_id = pe.product_id
    LEFT JOIN first_cliff fc ON cm.product_id = fc.product_id
),

adjustment AS (
    SELECT *,
        CASE
            WHEN ABS(elasticity) < 0.5 THEN 10.0
            WHEN ABS(elasticity) < 1.0 THEN 6.0
            WHEN ABS(elasticity) < 2.0 THEN 0.0
            ELSE -6.0
        END + COALESCE(trend_bonus_pp,0) + COALESCE(geo_bonus_pp,0) + COALESCE(comp_bonus_pp,0)
                                                            AS raw_adj_pp
    FROM signals
),
recommendation AS (
    SELECT *,
        GREATEST(-20.0, LEAST(20.0, raw_adj_pp))            AS total_adj_pp
    FROM adjustment
),
priced AS (
    SELECT *,
        ROUND(
            CASE
                -- don't recommend raising past 88% of the demand cliff
                WHEN total_adj_pp > 0 THEN LEAST(
                    current_price * (1 + total_adj_pp / 100.0),
                    cliff_price * 0.88)
                -- don't cut more than 20% below current
                ELSE GREATEST(
                    current_price * (1 + total_adj_pp / 100.0),
                    current_price * 0.80)
            END, 2)                                          AS recommended_price
    FROM recommendation
),
impact AS (
    SELECT *,
        ROUND((recommended_price - current_price) / NULLIF(current_price, 0), 6) AS pct_price_change,
        ROUND(GREATEST(0, current_units * (1 + elasticity *
            ((recommended_price - current_price) / NULLIF(current_price, 0)))), 0) AS expected_units
    FROM priced
)
SELECT
    product_id, category, pack_size,
    current_price, recommended_price,
    ROUND(recommended_price - current_price, 2)                  AS price_change_abs,
    ROUND(pct_price_change * 100, 2)                              AS price_change_pct,
    current_revenue,
    ROUND(recommended_price * expected_units, 2)                  AS expected_revenue,
    ROUND(recommended_price * expected_units - current_revenue, 2) AS revenue_impact,
    current_units, expected_units,
    elasticity,
    CASE
        WHEN ABS(elasticity) < 0.5 THEN 'INELASTIC'
        WHEN ABS(elasticity) < 1.0 THEN 'MODERATELY ELASTIC'
        WHEN ABS(elasticity) < 2.0 THEN 'ELASTIC'
        ELSE 'HIGHLY ELASTIC'
    END                                                            AS elasticity_class,
    ROUND(cliff_price, 2)                                         AS demand_cliff_price,
    CASE
        WHEN price_change_pct >  8 THEN 'RAISE PRICE'
        WHEN price_change_pct >  2 THEN 'SLIGHT RAISE'
        WHEN price_change_pct > -2 THEN 'MAINTAIN'
        WHEN price_change_pct > -8 THEN 'SLIGHT REDUCE'
        ELSE 'REDUCE PRICE'
    END                                                            AS action,
    CASE
        WHEN ABS(elasticity) > 2.0 AND ABS(pct_price_change) > 0.05 THEN 'HIGH — monitor weekly'
        WHEN ABS(elasticity) > 1.0 AND ABS(pct_price_change) > 0.05 THEN 'MEDIUM — review after 2 weeks'
        WHEN recommended_price > cliff_price * 0.95 THEN 'MEDIUM — approaching demand cliff'
        ELSE 'LOW — safe to implement'
    END                                                            AS risk_level
FROM impact
ORDER BY revenue_impact DESC;
