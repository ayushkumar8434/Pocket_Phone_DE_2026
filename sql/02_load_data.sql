-- =====================================================================
-- Google Maps Navigation Database — Phase 2 data load
-- File : sql/02_load_data.sql
-- Owner: Ayush Kumar (Group Lead) — CP1 deliverable
--
-- Loads the 11 seed CSVs into schema `gmaps`, in dependency order
-- (parents before children). Run AFTER 01_schema.sql on an empty database.
--
--   psql -d <your_db> -f sql/01_schema.sql
--   psql -d <your_db> -f sql/02_load_data.sql
--
-- \copy reads files relative to the directory psql is run from, so run
-- these commands from the project root (where seed_data/ lives).
-- CSV files themselves are NOT committed (see .gitignore).
-- =====================================================================
\set ON_ERROR_STOP on
SET search_path TO gmaps;
BEGIN;

-- parents
\copy cities            FROM 'seed_data/cities.csv'            WITH (FORMAT csv, HEADER true)
\copy place_categories  FROM 'seed_data/place_categories.csv'  WITH (FORMAT csv, HEADER true)
\copy users             FROM 'seed_data/users.csv'             WITH (FORMAT csv, HEADER true)
\copy places            FROM 'seed_data/places.csv'            WITH (FORMAT csv, HEADER true)
\copy road_segments     FROM 'seed_data/road_segments.csv'     WITH (FORMAT csv, HEADER true)

-- children of places / users / road_segments
\copy opening_hours     FROM 'seed_data/opening_hours.csv'     WITH (FORMAT csv, HEADER true)
\copy place_reviews     FROM 'seed_data/place_reviews.csv'     WITH (FORMAT csv, HEADER true)
\copy saved_places      FROM 'seed_data/saved_places.csv'      WITH (FORMAT csv, HEADER true)
\copy traffic_readings  FROM 'seed_data/traffic_readings.csv'  WITH (FORMAT csv, HEADER true)
\copy navigation_sessions FROM 'seed_data/navigation_sessions.csv' WITH (FORMAT csv, HEADER true)
\copy incident_reports  FROM 'seed_data/incident_reports.csv'  WITH (FORMAT csv, HEADER true)

COMMIT;

-- fresh planner statistics after the bulk load
ANALYZE;

-- =====================================================================
-- Row-count verification (expected counts from README / seed files)
-- =====================================================================
\echo '--- row counts (must match the README) ---'
SELECT 'cities' AS table_name, count(*) FROM cities
UNION ALL SELECT 'place_categories', count(*) FROM place_categories
UNION ALL SELECT 'users', count(*) FROM users
UNION ALL SELECT 'places', count(*) FROM places
UNION ALL SELECT 'road_segments', count(*) FROM road_segments
UNION ALL SELECT 'opening_hours', count(*) FROM opening_hours
UNION ALL SELECT 'place_reviews', count(*) FROM place_reviews
UNION ALL SELECT 'saved_places', count(*) FROM saved_places
UNION ALL SELECT 'traffic_readings', count(*) FROM traffic_readings
UNION ALL SELECT 'navigation_sessions', count(*) FROM navigation_sessions
UNION ALL SELECT 'incident_reports', count(*) FROM incident_reports
ORDER BY 1;
