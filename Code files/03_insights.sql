-- ============================================================
-- 03_INSIGHTS.SQL
-- PriceSense (simplified pipeline)
-- ============================================================
-- The old pipeline had 10 separate files (03-12) exploring
-- product performance, price buckets, demand curves, customer
-- segments, premium tolerance, trends, geography, occasions,
-- and competitors — each with 2-4 queries, ~2,000 lines total.
-- None of that output actually fed the recommendation engine;
-- it was exploratory. This file keeps the one genuinely useful
-- query from each theme, condensed. Nothing here is required by
-- 04_recommendation_engine.sql — run it only if you want the
-- supporting context.
-- ============================================================

-- Category performance: revenue, orders, and average price per category
SELECT category,
       COUNT(DISTINCT order_id)   AS orders,
       ROUND(SUM(revenue), 2)     AS revenue,
       ROUND(AVG(price), 2)       AS avg_price
FROM master_view
GROUP BY category
ORDER BY revenue DESC;

-- Which customer persona spends the most, and at what average price
SELECT persona,
       COUNT(DISTINCT user_id)    AS customers,
       ROUND(SUM(revenue), 2)     AS revenue,
       ROUND(AVG(price), 2)       AS avg_price_paid
FROM master_view
WHERE persona IS NOT NULL
GROUP BY persona
ORDER BY revenue DESC;

-- Top states and city tiers by revenue
SELECT state, tier_rank,
       COUNT(DISTINCT order_id) AS orders,
       ROUND(SUM(revenue), 2)   AS revenue
FROM master_view
WHERE state IS NOT NULL
GROUP BY state, tier_rank
ORDER BY revenue DESC
LIMIT 15;

-- Occasions that drive the most volume
SELECT occasion,
       SUM(quantity)            AS units,
       ROUND(SUM(revenue), 2)   AS revenue
FROM master_view
WHERE occasion IS NOT NULL
GROUP BY occasion
ORDER BY revenue DESC;

-- Our average price vs. competitor average price, per category
-- (competitor SKUs aren't mapped 1:1 to ours, so this is a
-- category-level market check, not a per-product one)
SELECT
    m.category,
    ROUND(AVG(m.price), 2)                    AS our_avg_price,
    ROUND((SELECT AVG(avg_comp_price) FROM clean_competitor_pricing), 2)
                                               AS market_avg_price
FROM master_view m
GROUP BY m.category
ORDER BY our_avg_price DESC;
