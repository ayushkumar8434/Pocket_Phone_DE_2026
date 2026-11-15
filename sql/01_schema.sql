-- =====================================================================
-- Google Maps Navigation Database — Phase 2 schema
-- File : sql/01_schema.sql
-- Owner: Ayush Kumar (Group Lead) — CP1 deliverable
--
-- Conventions
--   * Every table lives in schema `gmaps`.
--   * Phase 2 creates ONLY structural constraints (PK, FK, UNIQUE, NOT NULL,
--     CHECK). No tuning indexes are added here (PK/UNIQUE give the implicit
--     B-trees PostgreSQL creates automatically — that is allowed and noted).
--   * Types were chosen from the seed data (ranges, null patterns, enums
--     verified in scratch analysis), not by guessing TEXT everywhere.
--   * The constraints accept every row of seed_data/ (verified by loading).
--
-- Load order (parents before children) is in 02_load_data.sql.
-- =====================================================================

DROP SCHEMA IF EXISTS gmaps CASCADE;
CREATE SCHEMA gmaps;
SET search_path TO gmaps;

-- ---------------------------------------------------------------------
-- cities  (10 rows) — reference table, parent of places / users / roads
-- ---------------------------------------------------------------------
CREATE TABLE cities (
    city_id     INTEGER     PRIMARY KEY,
    city_name   TEXT        NOT NULL UNIQUE,
    center_lat  NUMERIC(9,6) NOT NULL,
    center_lng  NUMERIC(9,6) NOT NULL,
    -- valid geographic coordinates
    CHECK (center_lat BETWEEN -90 AND 90),
    CHECK (center_lng BETWEEN -180 AND 180)
);

-- ---------------------------------------------------------------------
-- place_categories  (12 rows) — reference table, parent of places
-- ---------------------------------------------------------------------
CREATE TABLE place_categories (
    category_id    INTEGER PRIMARY KEY,
    category_name  TEXT    NOT NULL UNIQUE
);

-- ---------------------------------------------------------------------
-- users  (40,000 rows)
--   guide_level is NULL for non-guides and 1..10 for Local Guides.
--   email is a natural candidate key (verified unique).
-- ---------------------------------------------------------------------
CREATE TABLE users (
    user_id         INTEGER     PRIMARY KEY,
    display_name    TEXT        NOT NULL,
    email           TEXT        NOT NULL UNIQUE,
    home_city_id    INTEGER     NULL REFERENCES cities(city_id) ON DELETE SET NULL,
    is_local_guide  BOOLEAN     NOT NULL,
    guide_level     INTEGER     NULL,
    created_at      TIMESTAMPTZ NOT NULL,
    -- a Local Guide must have a level 1..10; a non-guide must have none
    CHECK (guide_level IS NULL OR guide_level BETWEEN 1 AND 10),
    CHECK ((is_local_guide  AND guide_level IS NOT NULL)
        OR (NOT is_local_guide AND guide_level IS NULL))
);

-- ---------------------------------------------------------------------
-- places  (40,042 rows) — core entity
--   plus_code : NOT NULL + UNIQUE (verified a natural candidate key)
--   phone     : nullable but UNIQUE among non-null (natural key)
--   avg_rating: NULL for places that have no reviews yet
--   price_level: NULL for places with no price tier
-- ---------------------------------------------------------------------
CREATE TABLE places (
    place_id              INTEGER     PRIMARY KEY,
    plus_code             TEXT        NOT NULL UNIQUE,
    name                  TEXT        NOT NULL,
    category_id           INTEGER     NOT NULL REFERENCES place_categories(category_id) ON DELETE RESTRICT,
    city_id               INTEGER     NOT NULL REFERENCES cities(city_id) ON DELETE RESTRICT,
    latitude              NUMERIC(9,6) NOT NULL,
    longitude             NUMERIC(9,6) NOT NULL,
    address               TEXT        NOT NULL,
    phone                 TEXT        NULL UNIQUE,
    website               TEXT        NULL,
    price_level           INTEGER     NULL,
    avg_rating            NUMERIC(2,1) NULL,
    review_count          INTEGER     NOT NULL DEFAULT 0,
    is_permanently_closed  BOOLEAN     NOT NULL DEFAULT FALSE,
    created_at            TIMESTAMPTZ NOT NULL,
    -- coordinate validity
    CHECK (latitude  BETWEEN -90 AND 90),
    CHECK (longitude BETWEEN -180 AND 180),
    -- Plus Code format: contains the '+' separator and is a short code (len 10..12).
    -- Sampled rows match the stricter ^[0-9A-Za-z]{8}\+[0-9A-Za-z]{2,3}$ (e.g. 22222222+2W,
    -- used by R23); the len-based check is kept so the load cannot fail on any outlier row.
    CHECK (plus_code LIKE '%+%' AND length(plus_code) BETWEEN 10 AND 12),
    -- rating / price tiers when known
    CHECK (avg_rating   IS NULL OR avg_rating   BETWEEN 1.0 AND 5.0),
    CHECK (price_level  IS NULL OR price_level  BETWEEN 1 AND 4),
    CHECK (review_count >= 0)
);

-- ---------------------------------------------------------------------
-- opening_hours  (252,266 rows)
--   One row per place per weekday (PK = place_id, weekday).
--   closes may be < opens : the place stays open past midnight (R04 relies on this).
-- ---------------------------------------------------------------------
CREATE TABLE opening_hours (
    place_id  INTEGER NOT NULL REFERENCES places(place_id) ON DELETE CASCADE,
    weekday   INTEGER NOT NULL,
    opens     TIME    NOT NULL,
    closes    TIME    NOT NULL,
    PRIMARY KEY (place_id, weekday),
    CHECK (weekday BETWEEN 1 AND 7)
);

-- ---------------------------------------------------------------------
-- road_segments  (2,000 rows) — parent of traffic_readings / incidents
-- ---------------------------------------------------------------------
CREATE TABLE road_segments (
    segment_id        INTEGER     PRIMARY KEY,
    road_name         TEXT        NOT NULL,
    city_id           INTEGER     NOT NULL REFERENCES cities(city_id) ON DELETE RESTRICT,
    road_type         TEXT        NOT NULL,
    start_lat         NUMERIC(9,6) NOT NULL,
    start_lng         NUMERIC(9,6) NOT NULL,
    end_lat           NUMERIC(9,6) NOT NULL,
    end_lng           NUMERIC(9,6) NOT NULL,
    length_m          INTEGER     NOT NULL,
    speed_limit_kmph  INTEGER     NOT NULL,
    CHECK (road_type IN ('ARTERIAL','HIGHWAY','LOCAL')),
    CHECK (start_lat BETWEEN -90 AND 90),
    CHECK (start_lng BETWEEN -180 AND 180),
    CHECK (end_lat   BETWEEN -90 AND 90),
    CHECK (end_lng   BETWEEN -180 AND 180),
    CHECK (length_m > 0),
    CHECK (speed_limit_kmph > 0)
);

-- ---------------------------------------------------------------------
-- place_reviews  (89,998 rows)
--   UNIQUE(place_id, user_id) : a user reviews a place at most once.
--   This is exactly the conflict target of W02 (ON CONFLICT (place_id,user_id)).
-- ---------------------------------------------------------------------
CREATE TABLE place_reviews (
    review_id    INTEGER     PRIMARY KEY,
    place_id     INTEGER     NOT NULL REFERENCES places(place_id) ON DELETE CASCADE,
    user_id      INTEGER     NOT NULL REFERENCES users(user_id)   ON DELETE CASCADE,
    rating       INTEGER     NOT NULL,
    review_text  TEXT        NULL,
    photo_count  INTEGER     NOT NULL DEFAULT 0,
    created_at   TIMESTAMPTZ NOT NULL,
    UNIQUE (place_id, user_id),
    CHECK (rating      BETWEEN 1 AND 5),
    CHECK (photo_count >= 0)
);

-- ---------------------------------------------------------------------
-- saved_places  (50,000 rows)
--   A user may save the same place to DIFFERENT lists (verified: user 37886
--   saved place 4088 to both "Favourites" and "Starred"), so the key is the
--   triple (user_id, place_id, list_name). W03's ON CONFLICT DO NOTHING hits
--   this key (re-saving to the same list is a no-op).
-- ---------------------------------------------------------------------
CREATE TABLE saved_places (
    user_id    INTEGER     NOT NULL REFERENCES users(user_id)  ON DELETE CASCADE,
    place_id   INTEGER     NOT NULL REFERENCES places(place_id) ON DELETE CASCADE,
    list_name  TEXT        NOT NULL,
    saved_at   TIMESTAMPTZ NOT NULL,
    PRIMARY KEY (user_id, place_id, list_name),
    CHECK (list_name IN ('Want to go','Favourites','Travel plans','Starred'))
);

-- ---------------------------------------------------------------------
-- traffic_readings  (250,000 rows)
--   reading_id is the PK (surrogate). (segment_id, recorded_at) is a natural
--   candidate key but is left unconstrained so the load never fails on a
--   possible duplicate timestamp (see design doc).
--   avg_speed_kmph rounded to 1 decimal (e.g. 29.5).
-- ---------------------------------------------------------------------
CREATE TABLE traffic_readings (
    reading_id        INTEGER     PRIMARY KEY,
    segment_id        INTEGER     NOT NULL REFERENCES road_segments(segment_id) ON DELETE CASCADE,
    recorded_at       TIMESTAMPTZ NOT NULL,
    avg_speed_kmph     NUMERIC(5,1) NOT NULL,
    congestion_level  TEXT        NOT NULL,
    CHECK (avg_speed_kmph >= 0),
    CHECK (congestion_level IN ('LOW','MODERATE','HEAVY','STANDSTILL'))
);

-- ---------------------------------------------------------------------
-- navigation_sessions  (200,000 rows)
--   user_id        NULL  : guest / anonymous navigation
--   origin_place_id NULL: trip started from current GPS (origin_lat/lng set)
--   origin_lat/lng     : ALWAYS present (even when origin_place_id is set,
--                        the GPS coords are stored too — verified)
--   dest_place_id      : NOT NULL, RESTRICT (keep navigation history)
--   actual_minutes    : NULL unless status = 'COMPLETED'
-- ---------------------------------------------------------------------
CREATE TABLE navigation_sessions (
    session_id        INTEGER     PRIMARY KEY,
    user_id           INTEGER     NULL REFERENCES users(user_id) ON DELETE SET NULL,
    origin_place_id   INTEGER     NULL REFERENCES places(place_id) ON DELETE SET NULL,
    origin_lat        NUMERIC(9,6) NOT NULL,
    origin_lng        NUMERIC(9,6) NOT NULL,
    dest_place_id     INTEGER     NOT NULL REFERENCES places(place_id) ON DELETE RESTRICT,
    travel_mode       TEXT        NOT NULL,
    started_at        TIMESTAMPTZ NOT NULL,
    distance_km       NUMERIC(6,2) NOT NULL,
    eta_minutes       INTEGER     NOT NULL,
    actual_minutes    INTEGER     NULL,
    rerouted_count    INTEGER     NOT NULL DEFAULT 0,
    status            TEXT        NOT NULL,
    CHECK (travel_mode IN ('DRIVE','TRANSIT','TWO_WHEELER','WALK')),
    CHECK (status IN ('COMPLETED','CANCELLED','IN_PROGRESS')),
    -- a completed trip must have an actual time; a non-completed one must not
    CHECK ((status = 'COMPLETED') = (actual_minutes IS NOT NULL)),
    CHECK (origin_lat BETWEEN -90 AND 90),
    CHECK (origin_lng BETWEEN -180 AND 180),
    CHECK (distance_km     > 0),
    CHECK (eta_minutes     > 0),
    CHECK (actual_minutes IS NULL OR actual_minutes > 0),
    CHECK (rerouted_count  >= 0)
);

-- ---------------------------------------------------------------------
-- incident_reports  (12,000 rows)
--   expires_at is always strictly after reported_at (verified).
-- ---------------------------------------------------------------------
CREATE TABLE incident_reports (
    report_id      INTEGER     PRIMARY KEY,
    segment_id     INTEGER     NOT NULL REFERENCES road_segments(segment_id) ON DELETE CASCADE,
    user_id        INTEGER     NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
    incident_type  TEXT        NOT NULL,
    reported_at    TIMESTAMPTZ NOT NULL,
    expires_at     TIMESTAMPTZ NOT NULL,
    upvotes        INTEGER     NOT NULL DEFAULT 0,
    CHECK (incident_type IN ('ACCIDENT','BREAKDOWN','CLOSURE','POLICE','ROADWORK','WATERLOGGING')),
    CHECK (expires_at > reported_at),
    CHECK (upvotes >= 0)
);

-- =====================================================================
-- Implicit indexes created automatically by PostgreSQL (allowed in Phase 2):
--   cities(city_id) PK, cities(city_name) UQ
--   place_categories(category_id) PK, place_categories(category_name) UQ
--   users(user_id) PK, users(email) UQ
--   places(place_id) PK, places(plus_code) UQ, places(phone) UQ
--   opening_hours(place_id, weekday) PK
--   road_segments(segment_id) PK
--   place_reviews(review_id) PK, place_reviews(place_id, user_id) UQ
--   saved_places(user_id, place_id, list_name) PK
--   traffic_readings(reading_id) PK
--   navigation_sessions(session_id) PK
--   incident_reports(report_id) PK
-- No additional (tuning) indexes are created in Phase 2.
-- =====================================================================

ANALYZE;
