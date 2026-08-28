-- ============================================================
-- 02_ELASTICITY.SQL
-- PriceSense (simplified pipeline)
-- ============================================================
-- Per-product price elasticity of demand (PED), using a robust
-- log-log arc-elasticity method. This is the one piece of real
-- statistical modeling in the project, so it's kept in full —
-- but computed ONCE and saved as a table, instead of being
-- copy-pasted again inside the recommendation engine.
--
-- METHOD (why each step exists):
--   1. Trim each product's price to its 5th-95th percentile.
--      Removes bundle/data-entry outliers that don't reflect a
--      real pricing decision.
--   2. Split each product's remaining orders into 4 equal-count
--      price bands (NTILE) — comparing quartiles is far more
--      stable than comparing raw $1 price steps, which have too
--      few orders each to mean anything.
--   3. Require >= 5 orders per band, or drop it.
--   4. Elasticity between adjacent bands = %ΔQuantity / %ΔPrice,
--      via logs: e = (ln Q2 - ln Q1) / (ln P2 - ln P1).
--   5. Average the 3 band-to-band elasticities, weighted by how
--      many orders were behind each step (sparser steps count less).
--   6. Clamp the result to [-3, 3] — anything beyond that is noise,
--      not a real consumer elasticity.
-- ============================================================

CREATE OR REPLACE TABLE product_elasticity AS
WITH
trimmed AS (
    SELECT product_id, category, price, quantity,
           QUANTILE(price, 0.05) OVER (PARTITION BY product_id) AS p5,
           QUANTILE(price, 0.95) OVER (PARTITION BY product_id) AS p95
    FROM master_view
),
banded AS (
    SELECT product_id, category, price, quantity,
           NTILE(4) OVER (PARTITION BY product_id ORDER BY price) AS price_band
    FROM trimmed
    WHERE price BETWEEN p5 AND p95
),
band_agg AS (
    SELECT product_id, category, price_band,
           AVG(price) AS band_price, SUM(quantity) AS band_qty, COUNT(*) AS band_orders
    FROM banded
    GROUP BY product_id, category, price_band
    HAVING COUNT(*) >= 5
),
steps AS (
    SELECT
        a1.product_id, a1.category,
        CASE
            WHEN a2.band_price = a1.band_price THEN NULL
            ELSE GREATEST(-4.0, LEAST(4.0,
                (LN(a2.band_qty::FLOAT) - LN(a1.band_qty::FLOAT))
                / (LN(a2.band_price) - LN(a1.band_price))
            ))
        END                                          AS step_elasticity,
        LEAST(a1.band_orders, a2.band_orders)         AS step_weight
    FROM band_agg a1
    JOIN band_agg a2
        ON a1.product_id = a2.product_id AND a2.price_band = a1.price_band + 1
)
SELECT
    s.product_id,
    s.category,
    ROUND(GREATEST(-3.0, LEAST(3.0,
        SUM(s.step_elasticity * s.step_weight) / NULLIF(SUM(s.step_weight), 0)
    )), 4)                                           AS elasticity,
    SUM(s.step_weight)                                AS estimation_confidence,
    m.avg_price, m.total_revenue, m.total_units
FROM steps s
JOIN (
    SELECT product_id, ROUND(AVG(price), 2) AS avg_price,
           ROUND(SUM(revenue), 2) AS total_revenue, SUM(quantity) AS total_units
    FROM master_view GROUP BY product_id
) m ON s.product_id = m.product_id
WHERE s.step_elasticity IS NOT NULL
GROUP BY s.product_id, s.category, m.avg_price, m.total_revenue, m.total_units;

-- Quick look: which products/categories are most price-sensitive
SELECT
    product_id, category, elasticity,
    CASE
        WHEN ABS(elasticity) < 0.5 THEN 'INELASTIC'
        WHEN ABS(elasticity) < 1.0 THEN 'MODERATELY ELASTIC'
        WHEN ABS(elasticity) < 2.0 THEN 'ELASTIC'
        ELSE 'HIGHLY ELASTIC'
    END AS elasticity_class
FROM product_elasticity
ORDER BY ABS(elasticity) DESC
LIMIT 15;
