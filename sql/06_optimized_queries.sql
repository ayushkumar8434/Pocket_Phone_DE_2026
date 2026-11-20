-- =====================================================================
-- Google Maps DBMS Project: Optimized versions of the 30 queries
-- Phase 4: Query Optimization
-- 
-- INSTRUCTIONS:
-- - These are optimized versions of queries from workload_30.sql
-- - Each query produces the SAME results as the original
-- - Optimizations include: better indexes, query rewriting, CTEs, etc.
-- - Run with EXPLAIN (ANALYZE, BUFFERS) to verify improvements
-- =====================================================================

SET search_path TO gmaps;
BEGIN;

-- @R01_OPT
-- "Restaurants near me": open restaurants within ~1 km of Koramangala
-- OPTIMIZATION: Uses idx_places_category_location for category + bounding box
SELECT place_id, name, avg_rating,
       round((6371 * acos(least(1, cos(radians(12.9352)) * cos(radians(latitude)) * cos(radians(longitude) - radians(77.6245))
                                  + sin(radians(12.9352)) * sin(radians(latitude)))))::numeric, 3) AS km
FROM places
WHERE category_id = 1
  AND NOT is_permanently_closed
  AND latitude  BETWEEN 12.9352 - 0.009 AND 12.9352 + 0.009
  AND longitude BETWEEN 77.6245 - 0.0093 AND 77.6245 + 0.0093
ORDER BY km
LIMIT 20;

-- @R02_OPT
-- Place page: details with opening hours
-- OPTIMIZATION: Composite PK on opening_hours makes the join efficient
SELECT p.place_id, p.name, p.address, p.phone, p.avg_rating, p.review_count, h.opens, h.closes
FROM places p
LEFT JOIN opening_hours h ON h.place_id = p.place_id AND h.weekday = 2
WHERE p.place_id = 18;

-- @R03_OPT
-- Search: Bengaluru places with "biryani" in the name
-- OPTIMIZATION: idx_places_city_rating for sorting, GIN index for ILIKE
SELECT place_id, name, avg_rating, review_count
FROM places
WHERE city_id = 1 AND name ILIKE '%biryani%'
ORDER BY avg_rating DESC NULLS LAST, review_count DESC
LIMIT 20;

-- @R04_OPT
-- "Open now" filter: restaurants open at 23:30 on Saturday
-- OPTIMIZATION: idx_hours_weekday_times + idx_places_city_rating
WITH saturday_open AS (
    SELECT h.place_id
    FROM opening_hours h
    WHERE h.weekday = 6
      AND (   (h.opens < h.closes AND TIME '23:30' BETWEEN h.opens AND h.closes)
           OR (h.opens > h.closes AND (TIME '23:30' >= h.opens OR TIME '23:30' < h.closes)))
)
SELECT p.place_id, p.name, h.opens, h.closes
FROM places p
JOIN saturday_open so ON so.place_id = p.place_id
JOIN opening_hours h ON h.place_id = p.place_id AND h.weekday = 6
WHERE p.city_id = 1 AND p.category_id = 1 AND NOT p.is_permanently_closed
ORDER BY p.avg_rating DESC NULLS LAST
LIMIT 30;

-- @R05_OPT
-- Recent reviews of a place
-- OPTIMIZATION: idx_reviews_place_recent for efficient DESC scan
SELECT r.review_id, u.display_name, u.is_local_guide, r.rating, r.review_text, r.photo_count, r.created_at
FROM place_reviews r
JOIN users u ON u.user_id = r.user_id
WHERE r.place_id = 18
ORDER BY r.created_at DESC
LIMIT 10;

-- @R06_OPT
-- User's saved places grouped by list
-- OPTIMIZATION: idx_saved_user_list_time for efficient ordering
SELECT s.list_name, p.place_id, p.name, s.saved_at
FROM saved_places s
JOIN places p ON p.place_id = s.place_id
WHERE s.user_id = 1005
ORDER BY s.list_name, s.saved_at DESC;

-- @R07_OPT
-- Latest traffic reading per segment
-- OPTIMIZATION: idx_traffic_segment_time for DISTINCT ON optimization
SELECT DISTINCT ON (t.segment_id) t.segment_id, s.road_name, t.recorded_at, t.avg_speed_kmph, t.congestion_level
FROM traffic_readings t
JOIN road_segments s ON s.segment_id = t.segment_id
WHERE s.city_id = 1 AND s.road_name LIKE 'Outer Ring Road%'
ORDER BY t.segment_id, t.recorded_at DESC;

-- @R08_OPT
-- Traffic alerts: heavy traffic segments
-- OPTIMIZATION: idx_traffic_congestion_time + idx_segments_city_road
SELECT s.segment_id, s.road_name, t.recorded_at, t.avg_speed_kmph, t.congestion_level
FROM traffic_readings t
JOIN road_segments s ON s.segment_id = t.segment_id
WHERE s.city_id = 1
  AND t.congestion_level IN ('HEAVY', 'STANDSTILL')
  AND t.recorded_at >= '2026-06-30 18:00:00+05:30'
ORDER BY t.recorded_at DESC;

-- @R09_OPT
-- Typical traffic by hour
-- OPTIMIZATION: idx_traffic_segment_hour for segment filtering
SELECT EXTRACT(HOUR FROM recorded_at) AS hour, round(avg(avg_speed_kmph), 1) AS avg_speed, count(*) AS readings
FROM traffic_readings
WHERE segment_id = 5
GROUP BY 1
ORDER BY 1;

-- @R10_OPT
-- Incident layer for a city on a date
-- OPTIMIZATION: idx_incidents_segment_date + idx_segments_city_road
SELECT i.report_id, i.incident_type, s.road_name, i.reported_at, i.expires_at, i.upvotes
FROM incident_reports i
JOIN road_segments s ON s.segment_id = i.segment_id
WHERE s.city_id = 1
  AND DATE(i.reported_at) = '2026-06-30'
ORDER BY i.reported_at DESC;

-- @R11_OPT
-- ETA quality metrics by mode and month
-- OPTIMIZATION: idx_nav_status_year_mode for filtered aggregation
SELECT date_trunc('month', started_at) AS month, travel_mode,
       round(avg(actual_minutes - eta_minutes), 2) AS avg_error_min, count(*) AS trips
FROM navigation_sessions
WHERE status = 'COMPLETED'
  AND started_at >= '2026-01-01' AND started_at < '2027-01-01'
GROUP BY 1, 2
ORDER BY 1, 2;

-- @R12_OPT
-- Most navigated destinations in Mumbai
-- OPTIMIZATION: idx_nav_dest_date for date filtering and grouping
SELECT p.place_id, p.name, count(*) AS navigations
FROM navigation_sessions n
JOIN places p ON p.place_id = n.dest_place_id
WHERE p.city_id = 2
  AND n.started_at >= '2026-06-24'
GROUP BY p.place_id, p.name
ORDER BY navigations DESC
LIMIT 10;

-- @R13_OPT
-- Places never used as origin
-- OPTIMIZATION: Rewritten using LEFT JOIN instead of NOT IN for better performance
SELECT p.place_id, p.name
FROM places p
LEFT JOIN navigation_sessions n ON n.origin_place_id = p.place_id
WHERE n.origin_place_id IS NULL;

-- @R14_OPT
-- Local Guides leaderboard
-- OPTIMIZATION: idx_reviews_user_date for date filtering
SELECT u.user_id, u.display_name, u.guide_level, count(*) AS reviews, sum(r.photo_count) AS photos
FROM place_reviews r
JOIN users u ON u.user_id = r.user_id
WHERE r.created_at >= '2026-01-01'
GROUP BY u.user_id, u.display_name, u.guide_level
ORDER BY reviews DESC, photos DESC
LIMIT 20;

-- @R15_OPT
-- Data quality: mismatched ratings
-- OPTIMIZATION: More efficient grouping with HAVING clause
SELECT p.place_id, p.avg_rating, p.review_count, round(avg(r.rating), 1) AS actual_rating, count(*) AS actual_reviews
FROM places p
JOIN place_reviews r ON r.place_id = p.place_id
GROUP BY p.place_id, p.avg_rating, p.review_count
HAVING p.review_count <> count(*) OR p.avg_rating <> round(avg(r.rating), 1)
ORDER BY p.place_id;

-- @R16_OPT
-- Closed places still being navigated to
-- OPTIMIZATION: idx_nav_dest_year for date filtering
SELECT p.place_id, p.name, count(*) AS navigations_2026
FROM places p
JOIN navigation_sessions n ON n.dest_place_id = p.place_id
WHERE p.is_permanently_closed
  AND n.started_at >= '2026-01-01'
GROUP BY p.place_id, p.name
ORDER BY navigations_2026 DESC;

-- @R17_OPT
-- Destinations with most rerouting
-- OPTIMIZATION: idx_nav_dest_reroutes for grouping
SELECT dest_place_id, count(*) AS trips, round(avg(rerouted_count), 2) AS avg_reroutes
FROM navigation_sessions
GROUP BY dest_place_id
HAVING count(*) >= 5
ORDER BY avg_reroutes DESC
LIMIT 20;

-- @R18_OPT
-- Cancellation rate by travel mode
-- OPTIMIZATION: idx_nav_mode_status for mode grouping
SELECT travel_mode, count(*) AS sessions,
       round(100.0 * count(*) FILTER (WHERE status = 'CANCELLED') / count(*), 1) AS cancelled_pct
FROM navigation_sessions
GROUP BY travel_mode
ORDER BY cancelled_pct DESC;

-- @R19_OPT
-- Hospital navigation statistics
-- OPTIMIZATION: Rewritten with LEFT JOIN instead of scalar subqueries
WITH hospital_category AS (
    SELECT category_id FROM place_categories WHERE category_name = 'Hospital'
),
hospital_places AS (
    SELECT p.place_id, p.name
    FROM places p, hospital_category hc
    WHERE p.category_id = hc.category_id AND p.city_id = 1
)
SELECT 
    hp.place_id, 
    hp.name,
    COALESCE(COUNT(n.session_id), 0) AS navigations,
    MAX(n.started_at) AS last_navigation_at
FROM hospital_places hp
LEFT JOIN navigation_sessions n ON n.dest_place_id = hp.place_id
GROUP BY hp.place_id, hp.name
ORDER BY navigations DESC;

-- @R20_OPT
-- Daily navigation volume with running total
-- OPTIMIZATION: Optimized date casting and window function
SELECT day, sessions, sum(sessions) OVER (ORDER BY day) AS running_total
FROM (
    SELECT started_at::date AS day, count(*) AS sessions
    FROM navigation_sessions
    WHERE started_at >= '2026-06-01' AND started_at < '2026-07-01'
    GROUP BY 1
) d
ORDER BY day;

-- @R21_OPT
-- Places without opening hours by category
-- OPTIMIZATION: NOT EXISTS is generally efficient for this pattern
SELECT c.category_name, count(*) AS places_without_hours
FROM places p
JOIN place_categories c ON c.category_id = p.category_id
WHERE NOT EXISTS (SELECT 1 FROM opening_hours h WHERE h.place_id = p.place_id)
GROUP BY c.category_name
ORDER BY places_without_hours DESC;

-- @R22_OPT
-- Review pagination
-- OPTIMIZATION: idx_reviews_created_at for efficient DESC ordering with OFFSET
SELECT review_id, place_id, user_id, rating, created_at
FROM place_reviews
ORDER BY created_at DESC
OFFSET 50000
LIMIT 25;

-- @R23_OPT
-- Plus code lookup
-- OPTIMIZATION: UNIQUE index on plus_code makes this extremely fast
SELECT place_id, name, latitude, longitude
FROM places
WHERE plus_code = '22222222+2W';

-- @R24_OPT
-- Duplicate listings detection
-- OPTIMIZATION: idx_places_duplicate_check for efficient self-join
SELECT a.place_id, b.place_id AS duplicate_id, a.name
FROM places a
JOIN places b ON b.name = a.name AND b.place_id > a.place_id
             AND abs(b.latitude - a.latitude) < 0.001 AND abs(b.longitude - a.longitude) < 0.001
WHERE a.city_id = 1 AND a.category_id = 1;

-- @R25_OPT
-- Road safety: speed limit violations
-- OPTIMIZATION: idx_segments_road_type for grouping
SELECT s.road_type, count(*) AS readings,
       round(100.0 * count(*) FILTER (WHERE t.avg_speed_kmph > s.speed_limit_kmph) / count(*), 1) AS over_limit_pct
FROM traffic_readings t
JOIN road_segments s ON s.segment_id = t.segment_id
GROUP BY s.road_type
ORDER BY over_limit_pct DESC;

-- @W01_OPT
-- Start navigation
-- OPTIMIZATION: Simple insert, already fast
INSERT INTO navigation_sessions (session_id, user_id, origin_lat, origin_lng, dest_place_id, travel_mode,
                                 started_at, distance_km, eta_minutes, status)
VALUES (90000001, 1005, 12.935200, 77.624500, 18, 'TWO_WHEELER', '2026-07-01 20:00:00+05:30', 4.20, 14, 'IN_PROGRESS');

-- @W02_OPT
-- Write review
-- OPTIMIZATION: UNIQUE constraint on (place_id, user_id) makes conflict check efficient
INSERT INTO place_reviews (review_id, place_id, user_id, rating, review_text, photo_count, created_at)
VALUES (90000001, 18, 1005, 4, 'Good food, slow service', 2, '2026-07-01 21:00:00+05:30')
ON CONFLICT (place_id, user_id) DO NOTHING;

-- @W03_OPT
-- Save place
-- OPTIMIZATION: Composite PK makes conflict check efficient
INSERT INTO saved_places (user_id, place_id, list_name, saved_at)
VALUES (1005, 18, 'Want to go', '2026-07-01 21:05:00+05:30')
ON CONFLICT DO NOTHING;

-- @W04_OPT
-- Recompute place ratings
-- OPTIMIZATION: More efficient with CTE and better filtering
WITH new_stats AS (
    SELECT place_id, round(avg(rating), 1) AS avg_rating, count(*) AS n 
    FROM place_reviews 
    GROUP BY place_id
)
UPDATE places p
SET avg_rating = ns.avg_rating, review_count = ns.n
FROM new_stats ns
WHERE ns.place_id = p.place_id
  AND (p.avg_rating IS DISTINCT FROM ns.avg_rating OR p.review_count <> ns.n);

-- @W05_OPT
-- Delete expired incidents
-- OPTIMIZATION: idx_incidents_expires makes WHERE clause efficient
DELETE FROM incident_reports
WHERE expires_at < '2026-06-01';

-- @END
ROLLBACK;

-- =====================================================================
-- ADDITIONAL OPTIMIZATION NOTES
-- =====================================================================
-- 
-- 1. R01: Geospatial queries benefit from spatial indexes (PostGIS) but
--    current composite B-tree index provides good bounding-box performance
-- 
-- 2. R03: GIN trigram index (pg_trgm extension) dramatically speeds up
--    ILIKE queries. Ensure extension is created: CREATE EXTENSION pg_trgm;
-- 
-- 3. R13: Rewritten from NOT IN to LEFT JOIN for better performance
--    with large datasets
-- 
-- 4. R19: Rewritten from correlated subqueries to LEFT JOIN for better
--    performance
-- 
-- 5. Materialized views can cache expensive aggregations but need
--    periodic refresh
-- 
-- 6. VACUUM and ANALYZE should be run regularly to maintain statistics
--    and reclaim space
-- 
-- =====================================================================
