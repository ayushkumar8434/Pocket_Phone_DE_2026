-- =====================================================================
-- Google Maps Navigation Database - Table Partitioning
-- Phase 5: Scalability through partitioning for large datasets
-- =====================================================================

SET search_path TO gmaps;

\echo '===== TABLE PARTITIONING FOR SCALABILITY ====='
\echo ''
\echo 'WARNING: This script recreates tables with partitioning.'
\echo 'Run this on a TEST database first!'
\echo ''

-- =====================================================================
-- PARTITIONING STRATEGY
-- =====================================================================
-- 
-- Tables to partition based on growth characteristics:
-- 
-- 1. traffic_readings: 250K rows → millions (partition by date)
--    - Time-series data, queries filter by date range
--    - Old data can be archived/dropped
-- 
-- 2. navigation_sessions: 200K rows → millions (partition by date)
--    - Most queries filter by date or recent time periods
--    - Historical analysis needs date-range scans
-- 
-- 3. incident_reports: 12K rows → moderate growth (partition by date)
--    - Expired incidents deleted regularly
--    - Most queries are recent data
-- 
-- 4. place_reviews: 90K rows → large growth (partition by date)
--    - Reviews accumulate over time
--    - Most recent reviews are queried frequently
-- 
-- =====================================================================

-- =====================================================================
-- STEP 1: BACKUP EXISTING DATA (if migrating from non-partitioned)
-- =====================================================================

-- Backup tables before partitioning
-- CREATE TABLE traffic_readings_backup AS SELECT * FROM traffic_readings;
-- CREATE TABLE navigation_sessions_backup AS SELECT * FROM navigation_sessions;
-- CREATE TABLE incident_reports_backup AS SELECT * FROM incident_reports;
-- CREATE TABLE place_reviews_backup AS SELECT * FROM place_reviews;

-- =====================================================================
-- STEP 2: PARTITION TRAFFIC_READINGS BY MONTH
-- =====================================================================

\echo 'Setting up partitioned traffic_readings...'

-- Drop existing table (comment out if migrating live data)
-- DROP TABLE IF EXISTS traffic_readings CASCADE;

-- Create partitioned table
CREATE TABLE IF NOT EXISTS traffic_readings_partitioned (
    reading_id INTEGER NOT NULL,
    segment_id INTEGER NOT NULL,
    recorded_at TIMESTAMPTZ NOT NULL,
    avg_speed_kmph NUMERIC(5, 1) NOT NULL,
    congestion_level VARCHAR(20) NOT NULL,
    -- PRIMARY KEY RULE: on a partitioned table every PRIMARY KEY / UNIQUE constraint
    -- must include the partition column, so the key is (reading_id, recorded_at).
    CONSTRAINT traffic_part_pkey PRIMARY KEY (reading_id, recorded_at),
    CONSTRAINT traffic_part_fk_segment FOREIGN KEY (segment_id) 
        REFERENCES road_segments(segment_id) ON DELETE CASCADE,
    CONSTRAINT traffic_part_speed_nonneg CHECK (avg_speed_kmph >= 0),
    CONSTRAINT traffic_part_congestion_valid CHECK (
        congestion_level IN ('LOW', 'MODERATE', 'HEAVY', 'STANDSTILL')
    )
) PARTITION BY RANGE (recorded_at);

-- Create partitions for 2025-2027
CREATE TABLE traffic_readings_2025_01 PARTITION OF traffic_readings_partitioned
    FOR VALUES FROM ('2025-01-01') TO ('2025-02-01');
CREATE TABLE traffic_readings_2025_02 PARTITION OF traffic_readings_partitioned
    FOR VALUES FROM ('2025-02-01') TO ('2025-03-01');
CREATE TABLE traffic_readings_2025_03 PARTITION OF traffic_readings_partitioned
    FOR VALUES FROM ('2025-03-01') TO ('2025-04-01');
CREATE TABLE traffic_readings_2025_04 PARTITION OF traffic_readings_partitioned
    FOR VALUES FROM ('2025-04-01') TO ('2025-05-01');
CREATE TABLE traffic_readings_2025_05 PARTITION OF traffic_readings_partitioned
    FOR VALUES FROM ('2025-05-01') TO ('2025-06-01');
CREATE TABLE traffic_readings_2025_06 PARTITION OF traffic_readings_partitioned
    FOR VALUES FROM ('2025-06-01') TO ('2025-07-01');
CREATE TABLE traffic_readings_2025_07 PARTITION OF traffic_readings_partitioned
    FOR VALUES FROM ('2025-07-01') TO ('2025-08-01');
CREATE TABLE traffic_readings_2025_08 PARTITION OF traffic_readings_partitioned
    FOR VALUES FROM ('2025-08-01') TO ('2025-09-01');
CREATE TABLE traffic_readings_2025_09 PARTITION OF traffic_readings_partitioned
    FOR VALUES FROM ('2025-09-01') TO ('2025-10-01');
CREATE TABLE traffic_readings_2025_10 PARTITION OF traffic_readings_partitioned
    FOR VALUES FROM ('2025-10-01') TO ('2025-11-01');
CREATE TABLE traffic_readings_2025_11 PARTITION OF traffic_readings_partitioned
    FOR VALUES FROM ('2025-11-01') TO ('2025-12-01');
CREATE TABLE traffic_readings_2025_12 PARTITION OF traffic_readings_partitioned
    FOR VALUES FROM ('2025-12-01') TO ('2026-01-01');

CREATE TABLE traffic_readings_2026_01 PARTITION OF traffic_readings_partitioned
    FOR VALUES FROM ('2026-01-01') TO ('2026-02-01');
CREATE TABLE traffic_readings_2026_02 PARTITION OF traffic_readings_partitioned
    FOR VALUES FROM ('2026-02-01') TO ('2026-03-01');
CREATE TABLE traffic_readings_2026_03 PARTITION OF traffic_readings_partitioned
    FOR VALUES FROM ('2026-03-01') TO ('2026-04-01');
CREATE TABLE traffic_readings_2026_04 PARTITION OF traffic_readings_partitioned
    FOR VALUES FROM ('2026-04-01') TO ('2026-05-01');
CREATE TABLE traffic_readings_2026_05 PARTITION OF traffic_readings_partitioned
    FOR VALUES FROM ('2026-05-01') TO ('2026-06-01');
CREATE TABLE traffic_readings_2026_06 PARTITION OF traffic_readings_partitioned
    FOR VALUES FROM ('2026-06-01') TO ('2026-07-01');
CREATE TABLE traffic_readings_2026_07 PARTITION OF traffic_readings_partitioned
    FOR VALUES FROM ('2026-07-01') TO ('2026-08-01');
CREATE TABLE traffic_readings_2026_08 PARTITION OF traffic_readings_partitioned
    FOR VALUES FROM ('2026-08-01') TO ('2026-09-01');
CREATE TABLE traffic_readings_2026_09 PARTITION OF traffic_readings_partitioned
    FOR VALUES FROM ('2026-09-01') TO ('2026-10-01');
CREATE TABLE traffic_readings_2026_10 PARTITION OF traffic_readings_partitioned
    FOR VALUES FROM ('2026-10-01') TO ('2026-11-01');
CREATE TABLE traffic_readings_2026_11 PARTITION OF traffic_readings_partitioned
    FOR VALUES FROM ('2026-11-01') TO ('2026-12-01');
CREATE TABLE traffic_readings_2026_12 PARTITION OF traffic_readings_partitioned
    FOR VALUES FROM ('2026-12-01') TO ('2027-01-01');

CREATE TABLE traffic_readings_2027_01 PARTITION OF traffic_readings_partitioned
    FOR VALUES FROM ('2027-01-01') TO ('2027-02-01');

-- Default partition for future data
CREATE TABLE traffic_readings_default PARTITION OF traffic_readings_partitioned DEFAULT;

-- Create indexes on partitioned table
CREATE INDEX idx_traffic_part_segment_time ON traffic_readings_partitioned (segment_id, recorded_at DESC);
CREATE INDEX idx_traffic_part_congestion ON traffic_readings_partitioned (congestion_level, recorded_at DESC);
CREATE INDEX idx_traffic_part_segment_hour ON traffic_readings_partitioned (segment_id, recorded_at);

-- =====================================================================
-- STEP 3: PARTITION NAVIGATION_SESSIONS BY QUARTER
-- =====================================================================

\echo 'Setting up partitioned navigation_sessions...'

-- Create partitioned table
CREATE TABLE IF NOT EXISTS navigation_sessions_partitioned (
    session_id INTEGER NOT NULL,
    user_id INTEGER,
    origin_place_id INTEGER,
    origin_lat NUMERIC(9, 6) NOT NULL,
    origin_lng NUMERIC(9, 6) NOT NULL,
    dest_place_id INTEGER NOT NULL,
    travel_mode VARCHAR(20) NOT NULL,
    started_at TIMESTAMPTZ NOT NULL,
    distance_km NUMERIC(8, 2) NOT NULL,
    eta_minutes INTEGER NOT NULL,
    actual_minutes INTEGER,
    rerouted_count INTEGER NOT NULL DEFAULT 0,
    status VARCHAR(20) NOT NULL,
    -- PRIMARY KEY RULE: the partition column started_at must be part of the key.
    CONSTRAINT nav_part_pkey PRIMARY KEY (session_id, started_at),
    CONSTRAINT nav_part_fk_user FOREIGN KEY (user_id) 
        REFERENCES users(user_id) ON DELETE SET NULL,
    CONSTRAINT nav_part_fk_origin_place FOREIGN KEY (origin_place_id) 
        REFERENCES places(place_id) ON DELETE SET NULL,
    CONSTRAINT nav_part_fk_dest_place FOREIGN KEY (dest_place_id) 
        REFERENCES places(place_id) ON DELETE CASCADE,
    CONSTRAINT nav_part_origin_lat_range CHECK (origin_lat BETWEEN -90 AND 90),
    CONSTRAINT nav_part_origin_lng_range CHECK (origin_lng BETWEEN -180 AND 180),
    CONSTRAINT nav_part_distance_positive CHECK (distance_km > 0),
    CONSTRAINT nav_part_eta_positive CHECK (eta_minutes > 0),
    CONSTRAINT nav_part_actual_positive CHECK (actual_minutes IS NULL OR actual_minutes > 0),
    CONSTRAINT nav_part_rerouted_nonneg CHECK (rerouted_count >= 0),
    CONSTRAINT nav_part_travel_mode_valid CHECK (
        travel_mode IN ('DRIVE', 'TWO_WHEELER', 'TRANSIT', 'WALK', 'BICYCLE')
    ),
    CONSTRAINT nav_part_status_valid CHECK (
        status IN ('IN_PROGRESS', 'COMPLETED', 'CANCELLED')
    ),
    CONSTRAINT nav_part_completed_has_actual CHECK (
        (status = 'COMPLETED' AND actual_minutes IS NOT NULL) OR
        (status != 'COMPLETED')
    )
) PARTITION BY RANGE (started_at);

-- Create quarterly partitions for 2025-2027
CREATE TABLE navigation_sessions_2025_q1 PARTITION OF navigation_sessions_partitioned
    FOR VALUES FROM ('2025-01-01') TO ('2025-04-01');
CREATE TABLE navigation_sessions_2025_q2 PARTITION OF navigation_sessions_partitioned
    FOR VALUES FROM ('2025-04-01') TO ('2025-07-01');
CREATE TABLE navigation_sessions_2025_q3 PARTITION OF navigation_sessions_partitioned
    FOR VALUES FROM ('2025-07-01') TO ('2025-10-01');
CREATE TABLE navigation_sessions_2025_q4 PARTITION OF navigation_sessions_partitioned
    FOR VALUES FROM ('2025-10-01') TO ('2026-01-01');

CREATE TABLE navigation_sessions_2026_q1 PARTITION OF navigation_sessions_partitioned
    FOR VALUES FROM ('2026-01-01') TO ('2026-04-01');
CREATE TABLE navigation_sessions_2026_q2 PARTITION OF navigation_sessions_partitioned
    FOR VALUES FROM ('2026-04-01') TO ('2026-07-01');
CREATE TABLE navigation_sessions_2026_q3 PARTITION OF navigation_sessions_partitioned
    FOR VALUES FROM ('2026-07-01') TO ('2026-10-01');
CREATE TABLE navigation_sessions_2026_q4 PARTITION OF navigation_sessions_partitioned
    FOR VALUES FROM ('2026-10-01') TO ('2027-01-01');

CREATE TABLE navigation_sessions_2027_q1 PARTITION OF navigation_sessions_partitioned
    FOR VALUES FROM ('2027-01-01') TO ('2027-04-01');

-- Default partition
CREATE TABLE navigation_sessions_default PARTITION OF navigation_sessions_partitioned DEFAULT;

-- Create indexes on partitioned table
-- Plain started_at index: date-range queries need it inside each partition (pruning only picks the partitions)
CREATE INDEX idx_nav_part_started_at ON navigation_sessions_partitioned (started_at);
CREATE INDEX idx_nav_part_status_time ON navigation_sessions_partitioned (status, started_at);
CREATE INDEX idx_nav_part_dest_date ON navigation_sessions_partitioned (dest_place_id, started_at);
CREATE INDEX idx_nav_part_origin_place ON navigation_sessions_partitioned (origin_place_id) 
    WHERE origin_place_id IS NOT NULL;
CREATE INDEX idx_nav_part_mode_status ON navigation_sessions_partitioned (travel_mode, status);
CREATE INDEX idx_nav_part_dest_reroutes ON navigation_sessions_partitioned (dest_place_id, rerouted_count);

-- =====================================================================
-- STEP 4: PARTITION INCIDENT_REPORTS BY YEAR
-- =====================================================================

\echo 'Setting up partitioned incident_reports...'

CREATE TABLE IF NOT EXISTS incident_reports_partitioned (
    report_id INTEGER NOT NULL,
    segment_id INTEGER NOT NULL,
    user_id INTEGER NOT NULL,
    incident_type VARCHAR(30) NOT NULL,
    reported_at TIMESTAMPTZ NOT NULL,
    expires_at TIMESTAMPTZ NOT NULL,
    upvotes INTEGER NOT NULL DEFAULT 0,
    CONSTRAINT incidents_part_pkey PRIMARY KEY (report_id, reported_at),
    CONSTRAINT incidents_part_fk_segment FOREIGN KEY (segment_id) 
        REFERENCES road_segments(segment_id) ON DELETE CASCADE,
    CONSTRAINT incidents_part_fk_user FOREIGN KEY (user_id) 
        REFERENCES users(user_id) ON DELETE CASCADE,
    CONSTRAINT incidents_part_type_valid CHECK (
        incident_type IN ('ACCIDENT', 'ROADWORK', 'POLICE', 'CLOSURE', 'BREAKDOWN', 'WATERLOGGING')
    ),
    CONSTRAINT incidents_part_upvotes_nonneg CHECK (upvotes >= 0),
    CONSTRAINT incidents_part_expires_after CHECK (expires_at > reported_at)
) PARTITION BY RANGE (reported_at);

-- Create yearly partitions for 2025-2027
CREATE TABLE incident_reports_2025 PARTITION OF incident_reports_partitioned
    FOR VALUES FROM ('2025-01-01') TO ('2026-01-01');
CREATE TABLE incident_reports_2026 PARTITION OF incident_reports_partitioned
    FOR VALUES FROM ('2026-01-01') TO ('2027-01-01');
CREATE TABLE incident_reports_2027 PARTITION OF incident_reports_partitioned
    FOR VALUES FROM ('2027-01-01') TO ('2028-01-01');

CREATE TABLE incident_reports_default PARTITION OF incident_reports_partitioned DEFAULT;

-- Create indexes
CREATE INDEX idx_incidents_part_segment_date ON incident_reports_partitioned (segment_id, reported_at DESC);
CREATE INDEX idx_incidents_part_expires ON incident_reports_partitioned (expires_at);

-- =====================================================================
-- STEP 5: PARTITION PLACE_REVIEWS BY YEAR
-- =====================================================================

\echo 'Setting up partitioned place_reviews...'

CREATE TABLE IF NOT EXISTS place_reviews_partitioned (
    review_id INTEGER NOT NULL,
    place_id INTEGER NOT NULL,
    user_id INTEGER NOT NULL,
    rating INTEGER NOT NULL,
    review_text TEXT,
    photo_count INTEGER NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL,
    CONSTRAINT reviews_part_pkey PRIMARY KEY (review_id, created_at),
    CONSTRAINT reviews_part_fk_place FOREIGN KEY (place_id) 
        REFERENCES places(place_id) ON DELETE CASCADE,
    CONSTRAINT reviews_part_fk_user FOREIGN KEY (user_id) 
        REFERENCES users(user_id) ON DELETE CASCADE,
    CONSTRAINT reviews_part_rating_valid CHECK (rating BETWEEN 1 AND 5),
    CONSTRAINT reviews_part_photo_count_nonneg CHECK (photo_count >= 0),
    -- UNIQUE (place_id, user_id) is not allowed here because it does not include created_at.
    -- The same rule applies to the key: one review per (place, user) must be enforced by the
    -- application or by a trigger once the table is partitioned.
    CONSTRAINT reviews_part_unique UNIQUE (place_id, user_id, created_at)
) PARTITION BY RANGE (created_at);

-- Create yearly partitions
CREATE TABLE place_reviews_2019 PARTITION OF place_reviews_partitioned
    FOR VALUES FROM ('2019-01-01') TO ('2020-01-01');
CREATE TABLE place_reviews_2020 PARTITION OF place_reviews_partitioned
    FOR VALUES FROM ('2020-01-01') TO ('2021-01-01');
CREATE TABLE place_reviews_2021 PARTITION OF place_reviews_partitioned
    FOR VALUES FROM ('2021-01-01') TO ('2022-01-01');
CREATE TABLE place_reviews_2022 PARTITION OF place_reviews_partitioned
    FOR VALUES FROM ('2022-01-01') TO ('2023-01-01');
CREATE TABLE place_reviews_2023 PARTITION OF place_reviews_partitioned
    FOR VALUES FROM ('2023-01-01') TO ('2024-01-01');
CREATE TABLE place_reviews_2024 PARTITION OF place_reviews_partitioned
    FOR VALUES FROM ('2024-01-01') TO ('2025-01-01');
CREATE TABLE place_reviews_2025 PARTITION OF place_reviews_partitioned
    FOR VALUES FROM ('2025-01-01') TO ('2026-01-01');
CREATE TABLE place_reviews_2026 PARTITION OF place_reviews_partitioned
    FOR VALUES FROM ('2026-01-01') TO ('2027-01-01');
CREATE TABLE place_reviews_2027 PARTITION OF place_reviews_partitioned
    FOR VALUES FROM ('2027-01-01') TO ('2028-01-01');

CREATE TABLE place_reviews_default PARTITION OF place_reviews_partitioned DEFAULT;

-- Create indexes
CREATE INDEX idx_reviews_part_place_recent ON place_reviews_partitioned (place_id, created_at DESC);
CREATE INDEX idx_reviews_part_user_date ON place_reviews_partitioned (user_id, created_at);
CREATE INDEX idx_reviews_part_created_at ON place_reviews_partitioned (created_at DESC);

-- =====================================================================
-- STEP 6: DATA MIGRATION (if migrating from existing tables)
-- =====================================================================

-- Uncomment and run these if migrating from non-partitioned tables:
-- 
-- INSERT INTO traffic_readings_partitioned SELECT * FROM traffic_readings_backup;
-- INSERT INTO navigation_sessions_partitioned SELECT * FROM navigation_sessions_backup;
-- INSERT INTO incident_reports_partitioned SELECT * FROM incident_reports_backup;
-- INSERT INTO place_reviews_partitioned SELECT * FROM place_reviews_backup;
-- 
-- -- Verify counts match
-- SELECT 'traffic_readings' AS table_name, 
--        (SELECT COUNT(*) FROM traffic_readings_backup) AS old_count,
--        (SELECT COUNT(*) FROM traffic_readings_partitioned) AS new_count;
-- 
-- -- Drop old tables and rename partitioned tables
-- DROP TABLE traffic_readings;
-- ALTER TABLE traffic_readings_partitioned RENAME TO traffic_readings;

-- =====================================================================
-- STEP 7: PARTITION MAINTENANCE FUNCTIONS
-- =====================================================================

\echo 'Creating partition maintenance functions...'

-- Function to create new traffic_readings partitions automatically
CREATE OR REPLACE FUNCTION create_traffic_partition_for_month(month_date DATE)
RETURNS void AS $$
DECLARE
    partition_name TEXT;
    start_date DATE;
    end_date DATE;
BEGIN
    partition_name := 'traffic_readings_' || to_char(month_date, 'YYYY_MM');
    start_date := date_trunc('month', month_date);
    end_date := start_date + INTERVAL '1 month';
    
    EXECUTE format(
        'CREATE TABLE IF NOT EXISTS %I PARTITION OF traffic_readings_partitioned 
         FOR VALUES FROM (%L) TO (%L)',
        partition_name, start_date, end_date
    );
END;
$$ LANGUAGE plpgsql;

-- Function to drop old traffic_readings partitions
CREATE OR REPLACE FUNCTION drop_old_traffic_partitions(months_to_keep INTEGER DEFAULT 12)
RETURNS void AS $$
DECLARE
    partition_record RECORD;
    cutoff_date DATE;
BEGIN
    cutoff_date := date_trunc('month', CURRENT_DATE - (months_to_keep || ' months')::INTERVAL);
    
    FOR partition_record IN 
        SELECT tablename 
        FROM pg_tables 
        WHERE schemaname = 'gmaps' 
          AND tablename LIKE 'traffic_readings_2%'
          AND tablename < 'traffic_readings_' || to_char(cutoff_date, 'YYYY_MM')
    LOOP
        EXECUTE 'DROP TABLE IF EXISTS ' || partition_record.tablename || ' CASCADE';
        RAISE NOTICE 'Dropped partition: %', partition_record.tablename;
    END LOOP;
END;
$$ LANGUAGE plpgsql;

-- =====================================================================
-- STEP 8: AUTOMATED PARTITION CREATION (Optional - requires pg_cron)
-- =====================================================================

-- Example: Create next month's partition automatically
-- Requires pg_cron extension: CREATE EXTENSION pg_cron;
-- 
-- SELECT cron.schedule(
--     'create-monthly-traffic-partition',
--     '0 0 25 * *',  -- Run on 25th of each month
--     $$SELECT create_traffic_partition_for_month(CURRENT_DATE + INTERVAL '1 month')$$
-- );

-- =====================================================================
-- VERIFICATION
-- =====================================================================

\echo ''
\echo '===== PARTITIONING SUMMARY ====='

SELECT 
    nmsp_parent.nspname AS schema,
    parent.relname AS parent_table,
    child.relname AS partition_name,
    pg_get_expr(child.relpartbound, child.oid) AS partition_bounds,
    pg_size_pretty(pg_total_relation_size(child.oid)) AS size
FROM pg_inherits
JOIN pg_class parent ON pg_inherits.inhparent = parent.oid
JOIN pg_class child ON pg_inherits.inhrelid = child.oid
JOIN pg_namespace nmsp_parent ON nmsp_parent.oid = parent.relnamespace
WHERE nmsp_parent.nspname = 'gmaps'
ORDER BY parent.relname, child.relname;

\echo ''
\echo '===== PARTITIONING COMPLETE ====='
\echo ''
\echo 'NEXT STEPS:'
\echo '1. Test queries on partitioned tables'
\echo '2. Compare performance with non-partitioned versions'
\echo '3. Set up automated partition creation for future dates'
\echo '4. Implement partition archival/dropping policy'
