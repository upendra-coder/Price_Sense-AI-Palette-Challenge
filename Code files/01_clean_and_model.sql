-- ============================================================
-- 01_CLEAN_AND_MODEL.SQL
-- PriceSense (simplified pipeline)
-- ============================================================
-- Cleans the 5 raw tables and builds the single "master_view"
-- that every downstream file reads from. This replaces the old
-- 01_data_cleaning.sql + 02_data_model.sql (merged: the cleaning
-- rules and the join were always two halves of one step).
-- ============================================================

-- 1. Transactions: drop duplicate order_ids, refunds (negative
--    price/qty), and extreme outliers (>5000, a data-entry error).
CREATE OR REPLACE VIEW clean_transactions AS
SELECT
    order_id, user_id, product_id, price, quantity,
    ROUND(price * quantity, 2)                    AS revenue,
    CAST(timestamp AS TIMESTAMP)                  AS order_ts,
    channel
FROM (
    SELECT *,
        ROW_NUMBER() OVER (PARTITION BY order_id ORDER BY timestamp) AS rn
    FROM transactions
)
WHERE rn = 1 AND price > 0 AND quantity > 0 AND price < 5000;

-- 2. Product metadata: fix known category typos, fill blanks,
--    and derive the claim/ingredient flags used in later analysis.
CREATE OR REPLACE VIEW clean_product_metadata AS
SELECT
    product_id,
    CASE
        WHEN category IS NULL THEN 'Unknown'
        WHEN TRIM(category) = 'Proten Shake' THEN 'Protein Shake'
        WHEN TRIM(category) = 'Protein bar ' THEN 'Protein Bar'
        ELSE TRIM(category)
    END                                            AS category,
    TRIM(claims)                                   AS claims,
    COALESCE(TRIM(ingredient_tags), 'Unknown')     AS ingredient_tags,
    CASE WHEN LOWER(claims) LIKE '%high-protein%' OR LOWER(claims) LIKE '%high protein%'
         THEN 1 ELSE 0 END                         AS is_high_protein,
    CASE WHEN LOWER(claims) LIKE '%plant-based%' OR LOWER(claims) LIKE '%plant based%'
         THEN 1 ELSE 0 END                         AS is_plant_based,
    CASE WHEN LOWER(claims) LIKE '%low-sugar%' OR LOWER(claims) LIKE '%low sugar%'
         THEN 1 ELSE 0 END                         AS is_low_sugar,
    TRIM(pack_size)                                AS pack_size
FROM product_metadata;

-- 3. Consumer insights: fill blanks with explicit labels.
CREATE OR REPLACE VIEW clean_consumer_insights AS
SELECT
    user_id,
    COALESCE(TRIM(persona), 'unclassified')        AS persona,
    TRIM(income_bracket)                           AS income_bracket
FROM consumer_insights;

-- 4. Geography/occasion: trim text, rank city tiers.
CREATE OR REPLACE VIEW clean_geography_occasion AS
SELECT
    order_id, TRIM(state) AS state, TRIM(occasion) AS occasion,
    CASE TRIM(city_tier) WHEN 'Tier 1' THEN 1 WHEN 'Tier 2' THEN 2
         WHEN 'Tier 3' THEN 3 ELSE 99 END           AS tier_rank
FROM geography_occasion;

-- 5. Competitor pricing: drop nulls/zeros, keep an average per
--    competitor SKU (there's no FK to our own product_ids).
CREATE OR REPLACE VIEW clean_competitor_pricing AS
SELECT competitor_product_id, AVG(price) AS avg_comp_price
FROM competitor_pricing
WHERE price IS NOT NULL AND price > 0
GROUP BY competitor_product_id;

-- ============================================================
-- MASTER VIEW — every downstream file reads only this.
-- ============================================================
CREATE OR REPLACE VIEW master_view AS
SELECT
    t.order_id, t.user_id, t.product_id, t.price, t.quantity,
    t.revenue, t.order_ts, t.channel,
    p.category, p.pack_size, p.is_high_protein, p.is_plant_based, p.is_low_sugar,
    c.persona, c.income_bracket,
    g.state, g.occasion, g.tier_rank
FROM clean_transactions t
JOIN clean_product_metadata p ON t.product_id = p.product_id
LEFT JOIN clean_consumer_insights c ON t.user_id = c.user_id
LEFT JOIN clean_geography_occasion g ON t.order_id = g.order_id;

-- Sanity check: row counts should be close to source transaction count
SELECT COUNT(*) AS master_rows, COUNT(DISTINCT product_id) AS products
FROM master_view;
