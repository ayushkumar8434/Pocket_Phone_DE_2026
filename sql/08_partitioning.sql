-- Phase 5: staged RANGE partitioning example for navigation_sessions.
-- Run after 01_schema.sql and 02_load_data.sql on a
-- disposable database. This creates a second copy; it does not rename,
-- replace, or drop the original table.
--
-- The monthly bounds use the dataset's +05:30 local-time convention. The
-- DEFAULT partition prevents inserts outside the pre-created range from
-- failing, but rows there must be monitored and moved before adding a
-- partition whose range overlaps them.
SET search_path TO gmaps, public;

CREATE TABLE navigation_sessions_partitioned (
    session_id        INTEGER     NOT NULL,
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
    CONSTRAINT navigation_sessions_partitioned_pkey
        PRIMARY KEY (session_id, started_at),
    CHECK (travel_mode IN ('DRIVE','TRANSIT','TWO_WHEELER','WALK')),
    CHECK (status IN ('COMPLETED','CANCELLED','IN_PROGRESS')),
    CHECK ((status = 'COMPLETED') = (actual_minutes IS NOT NULL)),
    CHECK (origin_lat BETWEEN -90 AND 90),
    CHECK (origin_lng BETWEEN -180 AND 180),
    CHECK (distance_km > 0),
    CHECK (eta_minutes > 0),
    CHECK (actual_minutes IS NULL OR actual_minutes > 0),
    CHECK (rerouted_count >= 0)
) PARTITION BY RANGE (started_at);

DO $partition$
DECLARE
    month_start TIMESTAMP WITHOUT TIME ZONE := TIMESTAMP '2025-01-01 00:00:00';
    month_end   TIMESTAMP WITHOUT TIME ZONE;
BEGIN
    WHILE month_start < TIMESTAMP '2027-01-01 00:00:00' LOOP
        month_end := month_start + INTERVAL '1 month';
        EXECUTE format(
            'CREATE TABLE gmaps.navigation_sessions_part_%s ' ||
            'PARTITION OF gmaps.navigation_sessions_partitioned ' ||
            'FOR VALUES FROM (%L::timestamptz) TO (%L::timestamptz)',
            to_char(month_start, 'YYYYMM'),
            to_char(month_start, 'YYYY-MM-DD HH24:MI:SS') || '+05:30',
            to_char(month_end, 'YYYY-MM-DD HH24:MI:SS') || '+05:30'
        );
        month_start := month_end;
    END LOOP;
END
$partition$;

CREATE TABLE navigation_sessions_part_default
    PARTITION OF navigation_sessions_partitioned DEFAULT;

INSERT INTO navigation_sessions_partitioned (
    session_id, user_id, origin_place_id, origin_lat, origin_lng, dest_place_id,
    travel_mode, started_at, distance_km, eta_minutes, actual_minutes,
    rerouted_count, status
)
SELECT
    session_id, user_id, origin_place_id, origin_lat, origin_lng, dest_place_id,
    travel_mode, started_at, distance_km, eta_minutes, actual_minutes,
    rerouted_count, status
FROM navigation_sessions;

-- Parent indexes create matching local indexes on every partition.
CREATE INDEX navigation_sessions_part_started_at_idx
    ON navigation_sessions_partitioned (started_at);

CREATE INDEX navigation_sessions_part_completed_started_idx
    ON navigation_sessions_partitioned (started_at)
    INCLUDE (travel_mode, actual_minutes, eta_minutes)
    WHERE status = 'COMPLETED';

CREATE INDEX navigation_sessions_part_dest_started_idx
    ON navigation_sessions_partitioned (dest_place_id, started_at DESC)
    INCLUDE (rerouted_count);

CREATE INDEX navigation_sessions_part_known_origin_idx
    ON navigation_sessions_partitioned (origin_place_id)
    WHERE origin_place_id IS NOT NULL;

ANALYZE navigation_sessions_partitioned;

-- Pruning proof: EXPLAIN should reference only the June 2026 partition,
-- navigation_sessions_part_202606, not all monthly partitions or DEFAULT.
EXPLAIN (COSTS OFF)
SELECT count(*)
FROM navigation_sessions_partitioned
WHERE started_at >= TIMESTAMPTZ '2026-06-01 00:00:00+05:30'
  AND started_at <  TIMESTAMPTZ '2026-07-01 00:00:00+05:30';
