-- =====================================================================
-- Google Maps Navigation Database - Schema Definition
-- Phase 2: Database Schema from Seed Data
-- =====================================================================

-- Create and set the schema
DROP SCHEMA IF EXISTS gmaps CASCADE;
CREATE SCHEMA gmaps;
SET search_path TO gmaps;

-- =====================================================================
-- REFERENCE TABLES (Parent tables with no dependencies)
-- =====================================================================

-- Cities table
CREATE TABLE cities (
    city_id INTEGER PRIMARY KEY,
    city_name VARCHAR(100) NOT NULL,
    center_lat NUMERIC(9, 6) NOT NULL,
    center_lng NUMERIC(9, 6) NOT NULL,
    CONSTRAINT cities_unique_name UNIQUE (city_name),
    CONSTRAINT cities_lat_range CHECK (center_lat BETWEEN -90 AND 90),
    CONSTRAINT cities_lng_range CHECK (center_lng BETWEEN -180 AND 180)
);

-- Place categories table
CREATE TABLE place_categories (
    category_id INTEGER PRIMARY KEY,
    category_name VARCHAR(50) NOT NULL,
    CONSTRAINT categories_unique_name UNIQUE (category_name)
);

-- Users table
CREATE TABLE users (
    user_id INTEGER PRIMARY KEY,
    display_name VARCHAR(100) NOT NULL,
    email VARCHAR(255) NOT NULL,
    home_city_id INTEGER,
    is_local_guide BOOLEAN NOT NULL DEFAULT FALSE,
    guide_level INTEGER,
    created_at TIMESTAMPTZ NOT NULL,
    CONSTRAINT users_unique_email UNIQUE (email),
    CONSTRAINT users_fk_home_city FOREIGN KEY (home_city_id) 
        REFERENCES cities(city_id) ON DELETE SET NULL,
    CONSTRAINT users_guide_level_check CHECK (
        (is_local_guide = FALSE AND guide_level IS NULL) OR
        (is_local_guide = TRUE AND guide_level >= 1 AND guide_level <= 10)
    )
);

-- Road segments table
CREATE TABLE road_segments (
    segment_id INTEGER PRIMARY KEY,
    road_name VARCHAR(200) NOT NULL,
    city_id INTEGER NOT NULL,
    road_type VARCHAR(20) NOT NULL,
    start_lat NUMERIC(9, 6) NOT NULL,
    start_lng NUMERIC(9, 6) NOT NULL,
    end_lat NUMERIC(9, 6) NOT NULL,
    end_lng NUMERIC(9, 6) NOT NULL,
    length_m INTEGER NOT NULL,
    speed_limit_kmph INTEGER NOT NULL,
    CONSTRAINT segments_fk_city FOREIGN KEY (city_id) 
        REFERENCES cities(city_id) ON DELETE CASCADE,
    CONSTRAINT segments_lat_range CHECK (
        start_lat BETWEEN -90 AND 90 AND end_lat BETWEEN -90 AND 90
    ),
    CONSTRAINT segments_lng_range CHECK (
        start_lng BETWEEN -180 AND 180 AND end_lng BETWEEN -180 AND 180
    ),
    CONSTRAINT segments_length_positive CHECK (length_m > 0),
    CONSTRAINT segments_speed_limit_valid CHECK (speed_limit_kmph > 0 AND speed_limit_kmph <= 120),
    CONSTRAINT segments_road_type_valid CHECK (
        road_type IN ('HIGHWAY', 'ARTERIAL', 'COLLECTOR', 'LOCAL', 'SERVICE')
    )
);

-- =====================================================================
-- PLACES AND RELATED TABLES
-- =====================================================================

-- Places table
CREATE TABLE places (
    place_id INTEGER PRIMARY KEY,
    plus_code VARCHAR(20) NOT NULL,
    name VARCHAR(255) NOT NULL,
    category_id INTEGER NOT NULL,
    city_id INTEGER NOT NULL,
    latitude NUMERIC(9, 6) NOT NULL,
    longitude NUMERIC(9, 6) NOT NULL,
    address TEXT,
    phone VARCHAR(20),
    website VARCHAR(500),
    price_level INTEGER,
    avg_rating NUMERIC(2, 1),
    review_count INTEGER NOT NULL DEFAULT 0,
    is_permanently_closed BOOLEAN NOT NULL DEFAULT FALSE,
    created_at TIMESTAMPTZ NOT NULL,
    CONSTRAINT places_unique_plus_code UNIQUE (plus_code),
    CONSTRAINT places_fk_category FOREIGN KEY (category_id) 
        REFERENCES place_categories(category_id) ON DELETE RESTRICT,
    CONSTRAINT places_fk_city FOREIGN KEY (city_id) 
        REFERENCES cities(city_id) ON DELETE CASCADE,
    CONSTRAINT places_lat_range CHECK (latitude BETWEEN -90 AND 90),
    CONSTRAINT places_lng_range CHECK (longitude BETWEEN -180 AND 180),
    CONSTRAINT places_price_level_valid CHECK (price_level BETWEEN 1 AND 4),
    CONSTRAINT places_avg_rating_valid CHECK (avg_rating BETWEEN 1.0 AND 5.0),
    CONSTRAINT places_review_count_nonneg CHECK (review_count >= 0),
    CONSTRAINT places_plus_code_format CHECK (plus_code ~ '^[23456789CFGHJMPQRVWX]{8}\+[23456789CFGHJMPQRVWX]{2,3}$')
);

-- Opening hours table (composite primary key)
CREATE TABLE opening_hours (
    place_id INTEGER NOT NULL,
    weekday INTEGER NOT NULL,
    opens TIME NOT NULL,
    closes TIME NOT NULL,
    PRIMARY KEY (place_id, weekday),
    CONSTRAINT hours_fk_place FOREIGN KEY (place_id) 
        REFERENCES places(place_id) ON DELETE CASCADE,
    CONSTRAINT hours_weekday_valid CHECK (weekday BETWEEN 1 AND 7)
    -- Note: closes < opens is VALID (for places that close after midnight)
);

-- Place reviews table
CREATE TABLE place_reviews (
    review_id INTEGER PRIMARY KEY,
    place_id INTEGER NOT NULL,
    user_id INTEGER NOT NULL,
    rating INTEGER NOT NULL,
    review_text TEXT,
    photo_count INTEGER NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL,
    CONSTRAINT reviews_unique_user_place UNIQUE (place_id, user_id),
    CONSTRAINT reviews_fk_place FOREIGN KEY (place_id) 
        REFERENCES places(place_id) ON DELETE CASCADE,
    CONSTRAINT reviews_fk_user FOREIGN KEY (user_id) 
        REFERENCES users(user_id) ON DELETE CASCADE,
    CONSTRAINT reviews_rating_valid CHECK (rating BETWEEN 1 AND 5),
    CONSTRAINT reviews_photo_count_nonneg CHECK (photo_count >= 0)
);

-- Saved places table (composite primary key, M:N relationship)
CREATE TABLE saved_places (
    user_id INTEGER NOT NULL,
    place_id INTEGER NOT NULL,
    list_name VARCHAR(50) NOT NULL,
    saved_at TIMESTAMPTZ NOT NULL,
    PRIMARY KEY (user_id, place_id, list_name),
    CONSTRAINT saved_fk_user FOREIGN KEY (user_id) 
        REFERENCES users(user_id) ON DELETE CASCADE,
    CONSTRAINT saved_fk_place FOREIGN KEY (place_id) 
        REFERENCES places(place_id) ON DELETE CASCADE,
    CONSTRAINT saved_list_name_valid CHECK (
        list_name IN ('Starred', 'Want to go', 'Favourites', 'Travel plans')
    )
);

-- =====================================================================
-- TRAFFIC AND INCIDENTS
-- =====================================================================

-- Traffic readings table
CREATE TABLE traffic_readings (
    reading_id INTEGER PRIMARY KEY,
    segment_id INTEGER NOT NULL,
    recorded_at TIMESTAMPTZ NOT NULL,
    avg_speed_kmph NUMERIC(5, 1) NOT NULL,
    congestion_level VARCHAR(20) NOT NULL,
    CONSTRAINT traffic_fk_segment FOREIGN KEY (segment_id) 
        REFERENCES road_segments(segment_id) ON DELETE CASCADE,
    CONSTRAINT traffic_speed_nonneg CHECK (avg_speed_kmph >= 0),
    CONSTRAINT traffic_congestion_valid CHECK (
        congestion_level IN ('LOW', 'MODERATE', 'HEAVY', 'STANDSTILL')
    )
);

-- Incident reports table
CREATE TABLE incident_reports (
    report_id INTEGER PRIMARY KEY,
    segment_id INTEGER NOT NULL,
    user_id INTEGER NOT NULL,
    incident_type VARCHAR(30) NOT NULL,
    reported_at TIMESTAMPTZ NOT NULL,
    expires_at TIMESTAMPTZ NOT NULL,
    upvotes INTEGER NOT NULL DEFAULT 0,
    CONSTRAINT incidents_fk_segment FOREIGN KEY (segment_id) 
        REFERENCES road_segments(segment_id) ON DELETE CASCADE,
    CONSTRAINT incidents_fk_user FOREIGN KEY (user_id) 
        REFERENCES users(user_id) ON DELETE CASCADE,
    CONSTRAINT incidents_type_valid CHECK (
        incident_type IN ('ACCIDENT', 'ROADWORK', 'POLICE', 'CLOSURE', 'BREAKDOWN', 'WATERLOGGING')
    ),
    CONSTRAINT incidents_upvotes_nonneg CHECK (upvotes >= 0),
    CONSTRAINT incidents_expires_after_reported CHECK (expires_at > reported_at)
);

-- =====================================================================
-- NAVIGATION SESSIONS
-- =====================================================================

-- Navigation sessions table
CREATE TABLE navigation_sessions (
    session_id INTEGER PRIMARY KEY,
    user_id INTEGER,  -- NULL for anonymous users
    origin_place_id INTEGER,  -- NULL when starting from GPS coordinates
    origin_lat NUMERIC(9, 6) NOT NULL,
    origin_lng NUMERIC(9, 6) NOT NULL,
    dest_place_id INTEGER NOT NULL,
    travel_mode VARCHAR(20) NOT NULL,
    started_at TIMESTAMPTZ NOT NULL,
    distance_km NUMERIC(8, 2) NOT NULL,
    eta_minutes INTEGER NOT NULL,
    actual_minutes INTEGER,  -- NULL until completed/cancelled
    rerouted_count INTEGER NOT NULL DEFAULT 0,
    status VARCHAR(20) NOT NULL,
    CONSTRAINT nav_fk_user FOREIGN KEY (user_id) 
        REFERENCES users(user_id) ON DELETE SET NULL,
    CONSTRAINT nav_fk_origin_place FOREIGN KEY (origin_place_id) 
        REFERENCES places(place_id) ON DELETE SET NULL,
    CONSTRAINT nav_fk_dest_place FOREIGN KEY (dest_place_id) 
        REFERENCES places(place_id) ON DELETE CASCADE,
    CONSTRAINT nav_origin_lat_range CHECK (origin_lat BETWEEN -90 AND 90),
    CONSTRAINT nav_origin_lng_range CHECK (origin_lng BETWEEN -180 AND 180),
    CONSTRAINT nav_distance_positive CHECK (distance_km > 0),
    CONSTRAINT nav_eta_positive CHECK (eta_minutes > 0),
    CONSTRAINT nav_actual_positive CHECK (actual_minutes IS NULL OR actual_minutes > 0),
    CONSTRAINT nav_rerouted_nonneg CHECK (rerouted_count >= 0),
    CONSTRAINT nav_travel_mode_valid CHECK (
        travel_mode IN ('DRIVE', 'TWO_WHEELER', 'TRANSIT', 'WALK', 'BICYCLE')
    ),
    CONSTRAINT nav_status_valid CHECK (
        status IN ('IN_PROGRESS', 'COMPLETED', 'CANCELLED')
    ),
    CONSTRAINT nav_completed_has_actual CHECK (
        (status = 'COMPLETED' AND actual_minutes IS NOT NULL) OR
        (status != 'COMPLETED')
    )
);

-- =====================================================================
-- END OF SCHEMA
-- =====================================================================

-- Display created tables
\dt gmaps.*
