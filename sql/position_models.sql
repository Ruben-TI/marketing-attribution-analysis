-- Models 1-3: position-based attribution (Module 4)
-- Built on the numbered_touchpoints view (see schema.sql):
--   touchpoint_position = ROW_NUMBER() within each user's journey
--   max_position        = MAX(touchpoint_position) for that journey
-- Converters only: journeys end at each user's first conversion.

-- Model 1: First-touch - all credit to the first touchpoint
-- Expected: Display Ads 428, Direct Traffic 411, Referral 408,
--           Social Media 389, Email 374, Search Ads 371 (total 2,381)
SELECT channel,
       COUNT(*) AS first_touch_credit
FROM numbered_touchpoints
WHERE touchpoint_position = 1
GROUP BY channel
ORDER BY first_touch_credit DESC;

-- Model 2: Last-touch - all credit to the final touchpoint (the conversion)
-- Expected: Display Ads 415, Referral 412, Social Media 412,
--           Direct Traffic 402, Email 391, Search Ads 349 (total 2,381)
SELECT channel,
       COUNT(*) AS last_touch_credit
FROM numbered_touchpoints
WHERE touchpoint_position = max_position
GROUP BY channel
ORDER BY last_touch_credit DESC;

-- Model 3: Linear - each touchpoint gets 1 / (journey length) of the credit
-- Expected: Display Ads 424.5, Referral 410.0, Direct Traffic 405.2,
--           Social Media 396.8, Email 381.2, Search Ads 363.3 (total 2,381)
SELECT channel,
       ROUND(SUM(1.0 / max_position), 1) AS linear_credit
FROM numbered_touchpoints
GROUP BY channel
ORDER BY linear_credit DESC;

-- All three side by side (one row per channel)
-- FILTER (WHERE ...) counts only the rows matching each model's rule
SELECT channel,
       COUNT(*) FILTER (WHERE touchpoint_position = 1)            AS first_touch,
       COUNT(*) FILTER (WHERE touchpoint_position = max_position) AS last_touch,
       ROUND(SUM(1.0 / max_position), 1)                          AS linear
FROM numbered_touchpoints
GROUP BY channel
ORDER BY first_touch DESC;
