-- =====================================================================
-- Google Maps Navigation Database - Index Optimization
-- Phase 4: Create indexes to optimize the 30 queries
-- =====================================================================

SET search_path TO gmaps;

\echo '===== CREATING PERFORMANCE INDEXES ====='
\echo ''

-- =====================================================================
-- INDEXES FOR PLACES TABLE (R01, R02, R03, R04, R23, R24)
-- =====================================================================

\echo 'Creating indexes for places table...'

-- R01: "Restaurants near me" - geospatial search by category
-- Composite index for category + bounding box search
CREATE INDEX idx_places_category_location ON places (category_id, latitude, longitude)
WHERE NOT is_permanently_closed;

-- R03: Search by name in a city (ILIKE queries)
-- GIN index for pattern matching
CREATE INDEX idx_places_city_name_gin ON places USING gin (name gin_trgm_ops)
WHERE city_id IS NOT NULL;

-- Additional B-tree index for city + rating ordering
CREATE INDEX idx_places_city_rating ON places (city_id, avg_rating DESC NULLS LAST, review_count DESC)
WHERE NOT is_permanently_closed;

-- R23: Plus code lookup (already has UNIQUE index, but add this for clarity)
-- The unique constraint already creates an index

-- R24: Duplicate detection by name and location in a city
CREATE INDEX idx_places_duplicate_check ON places (city_id, category_id, name, latitude, longitude);

-- R13, R16, R19: Places as navigation destinations
-- (place_id is PK, already indexed)

-- =====================================================================
-- INDEXES FOR OPENING_HOURS TABLE (R02, R04)
-- =====================================================================

\echo 'Creating indexes for opening_hours table...'

-- R02: Get hours for a specific place and weekday
-- Composite PK already exists (place_id, weekday)

-- R04: Find places open at specific times
-- Index for filtering by weekday and time range
CREATE INDEX idx_hours_weekday_times ON opening_hours (weekday, opens, closes);

-- =====================================================================
-- INDEXES FOR USERS TABLE (R05, R14)
-- =====================================================================

\echo 'Creating indexes for users table...'

-- R05: Join users with reviews
-- (user_id is PK, already indexed)

-- R14: Local Guides leaderboard
CREATE INDEX idx_users_local_guides ON users (is_local_guide, guide_level)
WHERE is_local_guide = TRUE;

-- =====================================================================
-- INDEXES FOR PLACE_REVIEWS TABLE (R05, R14, R15, R22)
-- =====================================================================

\echo 'Creating indexes for place_reviews table...'

-- R05: Recent reviews for a place
CREATE INDEX idx_reviews_place_recent ON place_reviews (place_id, created_at DESC);

-- R14: Count reviews per user with date filter
CREATE INDEX idx_reviews_user_date ON place_reviews (user_id, created_at);

-- R15: Aggregate reviews by place for data quality check
-- (place_id already has index from FK)

-- R22: Pagination by created_at
CREATE INDEX idx_reviews_created_at ON place_reviews (created_at DESC);

-- =====================================================================
-- INDEXES FOR SAVED_PLACES TABLE (R06)
-- =====================================================================

\echo 'Creating indexes for saved_places table...'

-- R06: User's saved places grouped by list
-- Composite PK already covers (user_id, place_id, list_name)
-- Add index optimized for query ordering
CREATE INDEX idx_saved_user_list_time ON saved_places (user_id, list_name, saved_at DESC);

-- =====================================================================
-- INDEXES FOR ROAD_SEGMENTS TABLE (R07, R08, R09, R10, R25)
-- =====================================================================

\echo 'Creating indexes for road_segments table...'

-- R07, R08: Filter segments by city and road name
CREATE INDEX idx_segments_city_road ON road_segments (city_id, road_name);

-- R25: Group by road type
CREATE INDEX idx_segments_road_type ON road_segments (road_type);

-- =====================================================================
-- INDEXES FOR TRAFFIC_READINGS TABLE (R07, R08, R09, R25)
-- =====================================================================

\echo 'Creating indexes for traffic_readings table...'

-- R07: Latest reading per segment (DISTINCT ON)
CREATE INDEX idx_traffic_segment_time ON traffic_readings (segment_id, recorded_at DESC);

-- R08: Filter by congestion level and time
CREATE INDEX idx_traffic_congestion_time ON traffic_readings (congestion_level, recorded_at DESC);

-- R09: Aggregate by segment
CREATE INDEX idx_traffic_segment_hour ON traffic_readings (segment_id, recorded_at);

-- R25: Join with segments for speed analysis
-- (segment_id already indexed from FK)

-- =====================================================================
-- INDEXES FOR INCIDENT_REPORTS TABLE (R10)
-- =====================================================================

\echo 'Creating indexes for incident_reports table...'

-- R10: Filter incidents by segment and date
CREATE INDEX idx_incidents_segment_date ON incident_reports (segment_id, reported_at DESC);

-- W05: Delete expired incidents
CREATE INDEX idx_incidents_expires ON incident_reports (expires_at);

-- =====================================================================
-- INDEXES FOR NAVIGATION_SESSIONS TABLE (R11, R12, R13, R16, R17, R18, R19, R20, W01)
-- =====================================================================

\echo 'Creating indexes for navigation_sessions table...'

-- R11: ETA quality by mode and time
CREATE INDEX idx_nav_status_year_mode ON navigation_sessions (status, started_at, travel_mode)
WHERE status = 'COMPLETED';

-- R12: Most navigated destinations in a city with date filter
CREATE INDEX idx_nav_dest_date ON navigation_sessions (dest_place_id, started_at);

-- R13: Find places never used as origin (NOT IN query)
CREATE INDEX idx_nav_origin_place ON navigation_sessions (origin_place_id)
WHERE origin_place_id IS NOT NULL;

-- R16: Navigations to permanently closed places
-- (dest_place_id already indexed from FK)
CREATE INDEX idx_nav_dest_year ON navigation_sessions (dest_place_id, started_at)
WHERE started_at >= '2026-01-01';

-- R17: Reroute statistics by destination
CREATE INDEX idx_nav_dest_reroutes ON navigation_sessions (dest_place_id, rerouted_count);

-- R18: Status and mode distribution
CREATE INDEX idx_nav_mode_status ON navigation_sessions (travel_mode, status);

-- R19: Navigations per destination (subquery optimization)
-- (dest_place_id already indexed)

-- R20: Daily aggregation
CREATE INDEX idx_nav_started_date ON navigation_sessions (started_at::date, started_at);

-- Additional index for general navigation queries
CREATE INDEX idx_nav_status_time ON navigation_sessions (status, started_at);

-- =====================================================================
-- MATERIALIZED VIEWS (Optional - for heavy analytical queries)
-- =====================================================================

\echo 'Creating materialized views for analytical queries...'

-- Materialized view for place statistics (helps R15, R16, R19)
CREATE MATERIALIZED VIEW mv_place_stats AS
SELECT 
    p.place_id,
    p.name,
    p.category_id,
    p.city_id,
    p.avg_rating AS stored_rating,
    p.review_count AS stored_count,
    COALESCE(ROUND(AVG(r.rating), 1), 0) AS actual_rating,
    COUNT(r.review_id) AS actual_review_count,
    COALESCE(SUM(CASE WHEN n.status = 'COMPLETED' THEN 1 ELSE 0 END), 0) AS total_navigations,
    MAX(n.started_at) AS last_navigation_at
FROM places p
LEFT JOIN place_reviews r ON r.place_id = p.place_id
LEFT JOIN navigation_sessions n ON n.dest_place_id = p.place_id
GROUP BY p.place_id, p.name, p.category_id, p.city_id, p.avg_rating, p.review_count;

CREATE UNIQUE INDEX idx_mv_place_stats_pk ON mv_place_stats (place_id);
CREATE INDEX idx_mv_place_stats_city_cat ON mv_place_stats (city_id, category_id);

-- Refresh command (should be run periodically)
-- REFRESH MATERIALIZED VIEW CONCURRENTLY mv_place_stats;

-- =====================================================================
-- STATISTICS UPDATE
-- =====================================================================

\echo ''
\echo 'Analyzing tables after index creation...'
ANALYZE;

-- =====================================================================
-- INDEX SUMMARY
-- =====================================================================

\echo ''
\echo '===== INDEX CREATION SUMMARY ====='
SELECT 
    schemaname,
    tablename, 
    indexname, 
    pg_size_pretty(pg_relation_size(indexname::regclass)) AS index_size,
    idx_scan AS times_used,
    idx_tup_read AS tuples_read,
    idx_tup_fetch AS tuples_fetched
FROM pg_indexes
JOIN pg_stat_user_indexes USING (schemaname, tablename, indexname)
WHERE schemaname = 'gmaps'
ORDER BY tablename, indexname;

\echo ''
\echo '===== INDEXES CREATED SUCCESSFULLY ====='
