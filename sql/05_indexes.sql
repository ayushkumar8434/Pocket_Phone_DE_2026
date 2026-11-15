-- Phase 4 tuning indexes.
-- Run after sql/01_schema.sql and sql/02_load_data.sql.
-- Primary-key and UNIQUE indexes are already supplied by Phase 2.
SET search_path TO gmaps, public;
CREATE EXTENSION IF NOT EXISTS pg_trgm;

-- R01 uses this partial B-tree: category_id equality leads, followed by the
-- latitude/longitude bounding-box columns; closed rows are excluded up front.
CREATE INDEX places_open_category_geo_idx
    ON places (category_id, latitude, longitude)
    WHERE NOT is_permanently_closed;

-- R03 uses this GIN index with trigrams to support the leading-and-trailing-
-- wildcard substring predicate. Its bitmap is combined with the city bitmap
-- from places_city_place_idx; name is its only key because no other indexed
-- column is part of the text search.
CREATE INDEX places_name_trgm_idx
    ON places USING gin (name gin_trgm_ops);

-- R04 uses this partial B-tree: equality columns city_id/category_id lead,
-- then place_id supports the join to opening_hours; avg_rating is included
-- for output ordering without being a search key. Closed rows are excluded.
CREATE INDEX places_open_city_category_idx
    ON places (city_id, category_id, place_id) INCLUDE (avg_rating)
    WHERE NOT is_permanently_closed;

-- R05 and R15 use this B-tree. place_id equality leads, then created_at DESC
-- supplies newest-first review order; user_id, rating and photo_count are
-- included to cover selected and aggregate values without widening the key.
-- In particular, place_id is a key column and rating is INCLUDEd.
CREATE INDEX place_reviews_place_newest_idx
    ON place_reviews (place_id, created_at DESC)
    INCLUDE (user_id, rating, photo_count);

-- R06 uses this B-tree: user_id equality leads, list_name matches the first
-- ordering column, and saved_at DESC matches the within-list ordering;
-- place_id is included for the places join without adding it to the key.
CREATE INDEX saved_places_user_list_saved_idx
    ON saved_places (user_id, list_name, saved_at DESC)
    INCLUDE (place_id);

-- R07, R08 and R10 use this B-tree on road_segments. city_id equality leads;
-- road_name with text_pattern_ops supports R07's prefix LIKE; segment_id is
-- included for traffic joins without changing key order.
CREATE INDEX road_segments_city_road_idx
    ON road_segments (city_id, road_name text_pattern_ops)
    INCLUDE (segment_id);

-- R07 and R09 use this B-tree: segment_id equality leads and recorded_at DESC
-- provides newest-first rows for DISTINCT ON; speed and congestion are
-- included to cover selected traffic values and R09's speed aggregate.
CREATE INDEX traffic_segment_newest_idx
    ON traffic_readings (segment_id, recorded_at DESC)
    INCLUDE (avg_speed_kmph, congestion_level);

-- R08 uses this partial B-tree: recorded_at leads for its time range and
-- descending output order, followed by segment_id for the road join; included
-- traffic columns cover output. The predicate omits other congestion rows.
CREATE INDEX traffic_alert_time_idx
    ON traffic_readings (recorded_at DESC, segment_id)
    INCLUDE (avg_speed_kmph, congestion_level)
    WHERE congestion_level IN ('HEAVY', 'STANDSTILL');

-- R10 uses this B-tree: reported_at leads for the day range and descending
-- order; segment_id and projected incident attributes are included to cover
-- the join and output without extending the search key.
CREATE INDEX incident_reports_reported_at_idx
    ON incident_reports (reported_at DESC)
    INCLUDE (segment_id, incident_type, expires_at, upvotes);

-- R11 uses this partial B-tree: started_at leads for the year range; status
-- is fixed by the predicate, and aggregate columns are included for a possible
-- index-only scan.
CREATE INDEX navigation_completed_started_idx
    ON navigation_sessions (started_at)
    INCLUDE (travel_mode, actual_minutes, eta_minutes)
    WHERE status = 'COMPLETED';

-- R19 uses this B-tree for correlated destination count/max lookups:
-- dest_place_id equality leads, started_at DESC supports the latest timestamp.
-- rerouted_count is included but the latest R17 plan scans the full table.
CREATE INDEX navigation_dest_started_idx
    ON navigation_sessions (dest_place_id, started_at DESC)
    INCLUDE (rerouted_count);

-- R03 and R12 use this B-tree: city_id equality leads, followed by place_id
-- for joins and place lookup. R03's latest plan combines its city bitmap with
-- the name bitmap from places_name_trgm_idx using BitmapAnd.
CREATE INDEX places_city_place_idx
    ON places (city_id, place_id);

-- R13 uses this partial B-tree for the NOT EXISTS anti-join. The origin key
-- supports equality matching; excluding NULLs omits origins that cannot match
-- a place id and avoids NOT IN's NULL behavior.
CREATE INDEX navigation_known_origin_idx
    ON navigation_sessions (origin_place_id)
    WHERE origin_place_id IS NOT NULL;

-- R12, R16 and R20 use this B-tree for timestamp range restrictions. The
-- leading started_at key makes each half-open date interval indexable; R20
-- reads matching timestamps from an index-only scan.
CREATE INDEX navigation_started_at_idx
    ON navigation_sessions (started_at);

-- R14 and R22 use this B-tree: created_at DESC directly supplies newest-first
-- order; R14 scans the qualifying recent range and R22 advances to its OFFSET
-- without a separate sort.
CREATE INDEX place_reviews_newest_idx
    ON place_reviews (created_at DESC);

-- R19 and R24 use this B-tree: city_id/category_id equalities lead, then name
-- narrows same-name candidates and place_id supports the ordered self-join
-- condition; coordinates are included for R24's proximity test.
CREATE INDEX places_city_category_name_idx
    ON places (city_id, category_id, name, place_id)
    INCLUDE (latitude, longitude);

ANALYZE;
