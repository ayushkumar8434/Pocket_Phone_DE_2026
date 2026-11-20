-- =====================================================================
-- Google Maps Navigation Database - Data Loading Script
-- Phase 2: Load data from CSV files in the correct order
-- =====================================================================

SET search_path TO gmaps;

-- Disable triggers during load for performance (optional)
SET session_replication_role = replica;

-- =====================================================================
-- LOAD REFERENCE TABLES FIRST (no dependencies)
-- =====================================================================

\echo 'Loading cities...'
\copy cities FROM 'seed_data/cities.csv' WITH (FORMAT csv, HEADER true);

\echo 'Loading place_categories...'
\copy place_categories FROM 'seed_data/place_categories.csv' WITH (FORMAT csv, HEADER true);

\echo 'Loading users...'
\copy users FROM 'seed_data/users.csv' WITH (FORMAT csv, HEADER true);

\echo 'Loading road_segments...'
\copy road_segments FROM 'seed_data/road_segments.csv' WITH (FORMAT csv, HEADER true);

-- =====================================================================
-- LOAD TABLES WITH DEPENDENCIES
-- =====================================================================

\echo 'Loading places...'
\copy places FROM 'seed_data/places.csv' WITH (FORMAT csv, HEADER true);

\echo 'Loading opening_hours...'
\copy opening_hours FROM 'seed_data/opening_hours.csv' WITH (FORMAT csv, HEADER true);

\echo 'Loading place_reviews...'
\copy place_reviews FROM 'seed_data/place_reviews.csv' WITH (FORMAT csv, HEADER true);

\echo 'Loading saved_places...'
\copy saved_places FROM 'seed_data/saved_places.csv' WITH (FORMAT csv, HEADER true);

\echo 'Loading traffic_readings...'
\copy traffic_readings FROM 'seed_data/traffic_readings.csv' WITH (FORMAT csv, HEADER true);

\echo 'Loading incident_reports...'
\copy incident_reports FROM 'seed_data/incident_reports.csv' WITH (FORMAT csv, HEADER true);

\echo 'Loading navigation_sessions...'
\copy navigation_sessions FROM 'seed_data/navigation_sessions.csv' WITH (FORMAT csv, HEADER true);

-- Re-enable triggers
SET session_replication_role = DEFAULT;

-- =====================================================================
-- UPDATE STATISTICS
-- =====================================================================

\echo 'Analyzing tables for query optimizer...'
ANALYZE;

-- =====================================================================
-- VERIFY ROW COUNTS
-- =====================================================================

\echo ''
\echo '===== ROW COUNT VERIFICATION ====='
\echo 'Expected vs Actual:'
\echo ''

SELECT 'cities' AS table_name, COUNT(*) AS actual_count, 10 AS expected_count FROM cities
UNION ALL
SELECT 'place_categories', COUNT(*), 12 FROM place_categories
UNION ALL
SELECT 'users', COUNT(*), 40000 FROM users
UNION ALL
SELECT 'road_segments', COUNT(*), 2000 FROM road_segments
UNION ALL
SELECT 'places', COUNT(*), 40042 FROM places
UNION ALL
SELECT 'opening_hours', COUNT(*), 252266 FROM opening_hours
UNION ALL
SELECT 'place_reviews', COUNT(*), 89998 FROM place_reviews
UNION ALL
SELECT 'saved_places', COUNT(*), 50000 FROM saved_places
UNION ALL
SELECT 'traffic_readings', COUNT(*), 250000 FROM traffic_readings
UNION ALL
SELECT 'incident_reports', COUNT(*), 12000 FROM incident_reports
UNION ALL
SELECT 'navigation_sessions', COUNT(*), 200000 FROM navigation_sessions
ORDER BY table_name;

-- =====================================================================
-- INTEGRITY CHECKS
-- =====================================================================

\echo ''
\echo '===== INTEGRITY CHECK 1: Orphaned Foreign Keys ====='
\echo 'Check for any orphaned references (should return 0 rows for each):'
\echo ''

-- Check 1: Places with invalid category_id
SELECT 'Places with invalid category' AS check_name, COUNT(*) AS violations
FROM places p
WHERE NOT EXISTS (SELECT 1 FROM place_categories c WHERE c.category_id = p.category_id);

-- Check 2: Places with invalid city_id
SELECT 'Places with invalid city' AS check_name, COUNT(*) AS violations
FROM places p
WHERE NOT EXISTS (SELECT 1 FROM cities c WHERE c.city_id = p.city_id);

-- Check 3: Reviews with invalid place_id
SELECT 'Reviews with invalid place' AS check_name, COUNT(*) AS violations
FROM place_reviews r
WHERE NOT EXISTS (SELECT 1 FROM places p WHERE p.place_id = r.place_id);

-- Check 4: Reviews with invalid user_id
SELECT 'Reviews with invalid user' AS check_name, COUNT(*) AS violations
FROM place_reviews r
WHERE NOT EXISTS (SELECT 1 FROM users u WHERE u.user_id = r.user_id);

-- Check 5: Navigation sessions with invalid destination
SELECT 'Nav sessions with invalid dest' AS check_name, COUNT(*) AS violations
FROM navigation_sessions n
WHERE NOT EXISTS (SELECT 1 FROM places p WHERE p.place_id = n.dest_place_id);

\echo ''
\echo '===== INTEGRITY CHECK 2: Data Quality ====='
\echo 'Verify computed/derived columns:'
\echo ''

-- Check 6: Places with mismatched review counts
SELECT 'Places with incorrect review_count' AS check_name, COUNT(*) AS violations
FROM places p
LEFT JOIN (
    SELECT place_id, COUNT(*) AS actual_count
    FROM place_reviews
    GROUP BY place_id
) r ON r.place_id = p.place_id
WHERE COALESCE(r.actual_count, 0) != p.review_count;

-- Check 7: Places with mismatched avg_rating
SELECT 'Places with incorrect avg_rating' AS check_name, COUNT(*) AS violations
FROM places p
LEFT JOIN (
    SELECT place_id, ROUND(AVG(rating), 1) AS actual_rating
    FROM place_reviews
    GROUP BY place_id
) r ON r.place_id = p.place_id
WHERE (p.avg_rating IS DISTINCT FROM r.actual_rating);

-- Check 8: Completed navigations without actual_minutes
SELECT 'Completed nav without actual_minutes' AS check_name, COUNT(*) AS violations
FROM navigation_sessions
WHERE status = 'COMPLETED' AND actual_minutes IS NULL;

\echo ''
\echo '===== INTEGRITY CHECK 3: Business Logic ====='
\echo 'Verify business rules:'
\echo ''

-- Check 9: Local Guides must have guide_level
SELECT 'Local Guides without level' AS check_name, COUNT(*) AS violations
FROM users
WHERE is_local_guide = TRUE AND guide_level IS NULL;

-- Check 10: Non-Local Guides should not have guide_level
SELECT 'Non-guides with level' AS check_name, COUNT(*) AS violations
FROM users
WHERE is_local_guide = FALSE AND guide_level IS NOT NULL;

-- Check 11: Incidents that expire before they were reported
SELECT 'Incidents expiring before reported' AS check_name, COUNT(*) AS violations
FROM incident_reports
WHERE expires_at <= reported_at;

-- Check 12: Navigation sessions with negative ETA error (for completed trips)
SELECT 'Completed trips statistics' AS check_name, 
       COUNT(*) AS total_completed,
       ROUND(AVG(actual_minutes - eta_minutes), 2) AS avg_eta_error_min,
       ROUND(MIN(actual_minutes - eta_minutes), 2) AS min_error,
       ROUND(MAX(actual_minutes - eta_minutes), 2) AS max_error
FROM navigation_sessions
WHERE status = 'COMPLETED';

\echo ''
\echo '===== EXISTING INDEXES (from PK and UNIQUE constraints) ====='
SELECT 
    schemaname,
    tablename, 
    indexname, 
    indexdef
FROM pg_indexes
WHERE schemaname = 'gmaps'
ORDER BY tablename, indexname;

\echo ''
\echo '===== DATA LOAD COMPLETE ====='
