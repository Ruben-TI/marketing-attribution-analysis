-- Verification queries used throughout the project.
-- Run after loading data (load_to_postgres.py, load_fact_touchpoints.py)
-- and inserting model_results. Expected results are in the comments.

-- 1. Row counts
--    journeys = 3,860 | fact_touchpoints = 4,854 | model_results = 24
SELECT 'journeys' AS table_name, COUNT(*) AS row_count FROM journeys
UNION ALL
SELECT 'fact_touchpoints', COUNT(*) FROM fact_touchpoints
UNION ALL
SELECT 'model_results', COUNT(*) FROM model_results;

-- 2. Converters vs non-converters in the fact table
--    Conversion: 3,860 touchpoints / 2,381 users
--    Null:         994 touchpoints /   466 users
SELECT outcome,
       COUNT(*)                AS touchpoints,
       COUNT(DISTINCT user_id) AS users
FROM fact_touchpoints
GROUP BY outcome;

-- 3. journey_lengths view: 2,381 users / 3,860 touchpoints
SELECT COUNT(*) AS users, SUM(journey_length) AS touchpoints
FROM journey_lengths;

-- 4. Journey-length distribution (1 touchpoint = 1,403 converters, 59%)
SELECT journey_length, COUNT(*) AS users
FROM journey_lengths
GROUP BY journey_length
ORDER BY journey_length;

-- 5. Orphan checks: every fact key must match a dimension (expect 0 rows each)
SELECT DISTINCT r.model
FROM model_results r
LEFT JOIN dim_model m ON r.model = m.model
WHERE m.model IS NULL;

SELECT DISTINCT r.channel
FROM model_results r
LEFT JOIN dim_channel c ON r.channel = c.channel
WHERE c.channel IS NULL;

SELECT DISTINCT f.campaign
FROM fact_touchpoints f
LEFT JOIN dim_campaign c ON f.campaign = c.campaign
WHERE c.campaign IS NULL;
