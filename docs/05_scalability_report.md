# Phase 5: Scalability Report (large dataset)

All numbers in this report were measured on this machine. Nothing is estimated unless the text says "estimate".

## 1. Setup

| Item | Value |
|------|-------|
| Machine | Apple M4, 16 GB RAM, macOS 27.2.1, local PostgreSQL |
| PostgreSQL | 17.11 (Homebrew), default settings: `shared_buffers` 128 MB, `work_mem` 4 MB, `effective_cache_size` 4 GB, `max_parallel_workers_per_gather` 2 |
| Seed database | `gmaps_seed`: `seed_data.zip`, 200,000 navigation sessions, 193 MB |
| Large database | `gmaps_large`: `large_data.zip`, 18,725,897 rows in 11 tables, 3,631 MB |
| Large row counts | 4,000,000 navigation sessions, 4,999,656 traffic readings, 5,045,376 opening hours, 800,853 places, 800,000 users, 1,799,990 reviews, 1,000,000 saved places, 240,000 incident reports, 40,000 road segments |
| Load steps | `sql/01_schema.sql`, then `sql/02_load_data.sql` with `seed_data/` replaced by `large_data/`, then `sql/05_indexes.sql` (ends with `VACUUM (ANALYZE)`) |
| Load time (large) | About 2.5 minutes for the 18.7 million rows (`COPY`), then about 3 minutes for the indexes and the materialized view |
| Benchmark | `./benchmarks/run_benchmark.sh gmaps_large large 3 sql/06_optimized_queries.sql` (3 runs, average, `EXPLAIN (ANALYZE, BUFFERS)`). Write queries run inside `BEGIN ... ROLLBACK` |
| Seed comparison | The same command on `gmaps_seed`. This is a fresh run with the current scripts, so seed and large use identical schema, indexes and queries |

Raw plans for all 3 runs of every query are in [`benchmarks/results/large/`](../benchmarks/results/large/), with the averages in `summary.csv`. The original 30 queries were not run on the large data, as the brief requires.

**Cache state.** The large benchmark was run twice on the final database, and `summary.csv` is the second run (warm cache). In the first run after the fixes, the first of the 3 runs of several light queries read cold pages, which raised their averages: R01 2.088 ms (warm 0.616), R03 29.602 ms (19.577), R04 16.673 ms (2.035) and R07 6.733 ms (3.960). R04 and R07 therefore exceed the 5 ms target on a cold cache and meet it on a warm one (section 3). The seed benchmark was run once. R02, R04, R05 and R06 are faster on large than on seed, and the seed runs are slower on all 3 runs (for example R04: 3.6, 4.1, 4.3 ms on seed, 2.9, 1.6, 1.6 ms on large). I did not find the cause. These queries take under 5 ms in both.

**Note on the committed Phase 4 results.** `benchmarks/results/optimized/summary.csv` names indexes (for example `places_open_category_geo_idx`) that `sql/05_indexes.sql` does not create. It cannot be reproduced from the SQL files in this repository. The "seed" column below is therefore a new run of the current scripts, not a copy of that file.

## 2. Results versus targets

All 30 queries meet their target on the large dataset with a warm cache. R04, R07 and R10 missed their 5 ms target on the first large run. R07 and R10 were fixed with a query and index change, and R04 is a cold-cache effect (section 3). Growth is large average divided by seed average.

| Query | Seed (ms) | Large (ms) | Growth | Target | Meets? | Notes |
|-------|----------:|-----------:|-------:|-------:|:------:|-------|
| R01 | 0.395 | 0.616 | 1.6x | < 5 ms | Yes |  |
| R02 | 0.075 | 0.047 | 0.6x | < 5 ms | Yes |  |
| R03 | 2.696 | 19.577 | 7.3x | < 250 ms | Yes |  |
| R04 | 4.018 | 2.035 | 0.5x | < 5 ms | Yes | Met. First pass averaged 14.537 ms because run 1 was a cold buffer cache (40.5, 1.6, 1.5 ms). Same plan every run. See section 3. |
| R05 | 0.236 | 0.088 | 0.4x | < 5 ms | Yes |  |
| R06 | 0.145 | 0.047 | 0.3x | < 5 ms | Yes |  |
| R07 | 0.759 | 3.960 | 5.2x | < 5 ms | Yes | **Fixed.** Was 129.878 ms (Parallel Seq Scan of 5M readings + sort). Now LATERAL + covering index. See section 3. |
| R08 | 0.264 | 1.305 | 4.9x | < 5 ms | Yes |  |
| R09 | 0.443 | 0.359 | 0.8x | < 250 ms | Yes |  |
| R10 | 0.272 | 1.827 | 6.7x | < 5 ms | Yes | **Fixed.** Was 12.861 ms (Seq Scan: `DATE(reported_at) = ...` cannot use an index). Now range predicate + new index. See section 3. |
| R11 | 31.578 | 523.252 | 16.6x | < 5,000 ms | Yes |  |
| R12 | 2.514 | 36.610 | 14.6x | < 250 ms | Yes |  |
| R13 | 6.741 | 126.373 | 18.7x | < 250 ms | Yes |  |
| R14 | 6.910 | 66.522 | 9.6x | < 5,000 ms | Yes |  |
| R15 | 30.658 | 995.213 | 32.5x | < 5,000 ms | Yes |  |
| R16 | 4.607 | 39.694 | 8.6x | < 5,000 ms | Yes |  |
| R17 | 19.158 | 461.643 | 24.1x | < 5,000 ms | Yes |  |
| R18 | 12.085 | 133.913 | 11.1x | < 5,000 ms | Yes |  |
| R19 | 5.850 | 107.288 | 18.3x | < 5,000 ms | Yes |  |
| R20 | 1.519 | 34.147 | 22.5x | < 5,000 ms | Yes |  |
| R21 | 22.608 | 318.864 | 14.1x | < 5,000 ms | Yes |  |
| R22 | 4.870 | 5.825 | 1.2x | < 250 ms | Yes |  |
| R23 | 0.027 | 0.031 | 1.1x | < 5 ms | Yes |  |
| R24 | 6.040 | 51.706 | 8.6x | < 250 ms | Yes |  |
| R25 | 29.261 | 357.037 | 12.2x | < 5,000 ms | Yes |  |
| W01 | 0.847 | 0.890 | 1.1x | < 5 ms | Yes |  |
| W02 | 0.702 | 0.658 | 0.9x | < 5 ms | Yes |  |
| W03 | 0.760 | 1.551 | 2.0x | < 5 ms | Yes |  |
| W04 | 64.647 | 1,619.960 | 25.1x | < 2,000 ms | Yes | Met, with the smallest margin (1.6 s of 2 s). See section 8. |
| W05 | 2.254 | 216.907 | 96.2x | < 2,000 ms | Yes |  |

## 3. What broke at scale and how it was fixed

The first large run (before any fix) missed three real-time targets: R04 (14.537 ms), R07 (129.878 ms) and R10 (12.861 ms). Each was diagnosed from the plan.

### R07: latest traffic reading per segment (129.878 ms to 3.960 ms)

* **Plan before:** `Parallel Seq Scan on traffic_readings` (1,666,552 rows per worker, 36,608 buffers read), hash join to the 800 matching segments, then a sort of about 100,000 rows for `DISTINCT ON`. Runs: 144.0, 122.1, 123.5 ms.
* **Why it only shows at scale:** the planner reads every reading of the 800 segments and sorts them. That is about 100,000 rows on the large data, and about 20 times fewer on the seed data.
* **Fix:** read only the newest row per segment with `CROSS JOIN LATERAL (... ORDER BY recorded_at DESC LIMIT 1)`, backed by a covering index `idx_traffic_segment_time (segment_id, recorded_at DESC) INCLUDE (avg_speed_kmph, congestion_level)`.
* **Plan after:** 800 loops of `Index Only Scan using idx_traffic_segment_time`, `Heap Fetches: 0`, no sort. Runs: 4.5, 4.3, 3.1 ms. The old and new queries return identical rows (checked by hashing both result sets).
* **Condition:** the index-only scan needs the visibility map, so `sql/05_indexes.sql` now ends with `VACUUM (ANALYZE)`. Without a vacuum after the bulk load, `Heap Fetches` is not zero.

### R10: incidents for one day (12.861 ms to 1.827 ms)

* **Plan before:** `Parallel Seq Scan on incident_reports`, filter `date(reported_at) = '2026-06-30'`, 239,560 rows removed by the filter. Runs: 13.8, 12.0, 12.8 ms.
* **Why:** `DATE(reported_at) = ...` wraps the column in a function, so no index on `reported_at` can be used. On the seed data the scan is 12,000 rows and cheap. On the large data it is 240,000.
* **Fix:** the range `reported_at >= DATE '2026-06-30' AND reported_at < DATE '2026-06-30' + 1` (same rows), plus `idx_incidents_reported_at (reported_at DESC)`.
* **Plan after:** `Index Scan using idx_incidents_reported_at`, 12 buffers for the table. Runs: 1.9, 1.9, 1.6 ms.
* **Trade-off:** the extra index makes `incident_reports` writes slightly more expensive (W05 deletes 227,000 rows and now updates one more index).

### R04: open restaurants at 23:30 (14.537 ms to 2.035 ms)

The plan is the same on every run: `Index Scan using idx_places_city_rating`, then primary-key lookups into `opening_hours`, stopping after 30 rows. Run 1 took 40.5 ms because the index pages were not in the PostgreSQL buffer cache. Runs 2 and 3 took 1.6 and 1.5 ms. No query or index change was made. This is a cold-start effect, which matters after a restart or failover. A cache pre-warm step (`pg_prewarm` on `idx_places_city_rating` and `opening_hours_pkey`) would remove it in production.

### Problems that blocked the load itself

These are not slowdowns, but the large load did not run until they were fixed. All are in committed files.

| File | Problem | Fix |
|------|---------|-----|
| `sql/01_schema.sql` | `saved_places` CHECK allowed `Favorites` and `Visited`, but the data (seed and large) has `Favourites` and `Travel plans`. `COPY` failed on row 4. | CHECK now lists the four values in the data |
| `sql/01_schema.sql` | `incident_reports` CHECK allowed `HAZARD` and `JAM`, but the data has `BREAKDOWN` and `WATERLOGGING`. `COPY` failed. | CHECK now lists the six values in the data |
| `sql/05_indexes.sql` | `gin_trgm_ops` needs the `pg_trgm` extension, which was never created. | Added `CREATE EXTENSION IF NOT EXISTS pg_trgm` |
| `sql/05_indexes.sql` | `started_at::date` index: syntax error, and the cast is not immutable for `timestamptz` | Replaced with an index on `started_at` |
| `sql/05_indexes.sql` | The final summary query joined on columns that do not exist | Rewritten on `pg_stat_user_indexes` |
| `benchmarks/run_benchmark.sh` | Markers such as `-- @R01_OPT` in `06_optimized_queries.sql` were ignored, so no query ran | The script now accepts an `_OPT` suffix |
| `sql/08_partitioning.sql` | `UNIQUE (place_id, user_id)` on a partitioned table is not allowed, and the incident CHECK had the wrong values | See section 5 |

## 4. Growth analysis

The large data has 20 times the rows. How each query's time grew:

* **Stayed about the same (under 2.5x):** R01 (1.6x), R02 (0.6x), R04 (0.5x), R05 (0.4x), R06 (0.3x), R09 (0.8x), R22 (1.2x), R23 (1.1x), W01 (1.1x), W02 (0.9x), W03 (2.0x). These are primary-key lookups, `LIMIT` queries on an index, and index probes for one user, place or segment. A B-tree lookup grows with the logarithm of the table size, so 20x more rows adds at most one index level. Ratios under 1 are explained in section 1.
* **Grew 2.5x to 10x:** R03 (7.3x), R07 (5.2x), R08 (4.9x), R10 (6.7x), R14 (9.6x), R16 (8.6x), R24 (8.6x). These read a small slice of a bigger table or index (a city, a road, a name pattern), so they grow less than the table. I did not examine each plan for the exact cause.
* **Grew 10x to 20x, close to the data growth:** R11 (16.6x), R12 (14.6x), R13 (18.7x), R18 (11.1x), R19 (18.3x), R21 (14.1x), R25 (12.2x). They read a fixed share of a table (every session, review or reading, or a date range), so time is proportional to the rows read. About 20x is the expected result.
* **Grew more than 20x:** R15 (32.5x), R17 (24.1x), R20 (22.5x), W04 (25.1x), W05 (96.2x).
  * **R15 (32.5x) and W04 (25.1x)** aggregate all reviews. The plan changed shape: on seed it is a hash join of two sequential scans, on large it is a merge join over two index scans, which reads 1.8 million reviews in index order. Time per review rose from 0.33 to 0.55 microseconds (R15). I tested the hash plan on large with `work_mem = 256MB`: 1,083 ms against 948 ms for the merge plan, so it is not a plan mistake.
  * **R17 (24.1x) and R20 (22.5x)** read every session through an index-only scan. R20 also spilled a 2.6 MB sort to disk (`Sort Method: external merge  Disk: 2592kB`) at the default 4 MB `work_mem`. The large tables (3.6 GB) no longer fit in the 128 MB `shared_buffers`, which probably explains part of the extra cost. I did not test this.
  * **W05 (96x)** deletes about 94% of the incident rows in both databases (11,339 rows on seed, 226,751 on large). Time per deleted row went from 0.21 to 0.75 microseconds. The plan is a Seq Scan plus delete on both. I did not find the cause. It is far below its 2,000 ms target (217 ms).

R22 uses `OFFSET 50000`. It still runs in 5.825 ms on large because the `created_at` index returns the first 50,000 rows without a sort. Deeper pages cost more, so for a real client use keyset pagination: the "last seen" value is the `(created_at, review_id)` of the last row on the previous page, and the next page asks for `(created_at, review_id) < (last_created_at, last_review_id)`.

## 5. Storage (seed and large)

Total database size: seed 193 MB, large 3,631 MB (18.8x). Sizes by table, measured with `pg_table_size`, `pg_indexes_size` and `pg_total_relation_size`:

| Table | Seed table | Seed indexes | Large table | Large indexes | Large total |
|-------|-----------:|-------------:|------------:|--------------:|------------:|
| navigation_sessions | 23 MB | 38 MB | 454 MB | 747 MB | 1,201 MB |
| traffic_readings | 15 MB | 33 MB | 287 MB | 582 MB | 870 MB |
| opening_hours | 13 MB | 7.2 MB | 251 MB | 143 MB | 394 MB |
| place_reviews | 6.6 MB | 12 MB | 127 MB | 235 MB | 362 MB |
| places | 7.2 MB | 10 MB | 149 MB | 210 MB | 360 MB |
| users | 3.4 MB | 3.2 MB | 68 MB | 81 MB | 150 MB |
| saved_places | 2.8 MB | 3.9 MB | 57 MB | 77 MB | 134 MB |
| incident_reports | 0.9 MB | 1.2 MB | 18 MB | 23 MB | 40 MB |
| road_segments | 0.3 MB | 0.1 MB | 4.6 MB | 1.5 MB | 6.1 MB |

Indexes are larger than the tables for navigation, traffic, reviews, places, users and saved places. Storage grew about 19x for 20x the rows. The database total includes the `mv_place_stats` materialized view from `05_indexes.sql`.

## 6. Partitioning (tested on the large data)

`sql/08_partitioning.sql` runs on the large database and creates empty partitioned copies of `traffic_readings` (monthly), `navigation_sessions` (quarterly), `incident_reports` (yearly) and `place_reviews` (yearly), each with a DEFAULT partition and helper functions to add and drop partitions. I loaded `navigation_sessions_partitioned` with the 4,000,000 sessions (`INSERT ... SELECT`: 70.6 s with 6 indexes) and compared it with the unpartitioned table.

**Primary-key rule.** On a partitioned table every `PRIMARY KEY` and `UNIQUE` constraint must include the partition column. The key becomes `(session_id, started_at)`. It no longer guarantees that `session_id` is unique across partitions, so IDs must come from one shared sequence. For `place_reviews`, the old `UNIQUE (place_id, user_id)` is not allowed. It becomes `UNIQUE (place_id, user_id, created_at)`, which no longer stops a user reviewing a place twice. That rule would move into the application or a trigger. I fixed the script to follow this rule. Before the fix it failed on this constraint.

**Partition pruning.** A one-month query on `started_at` reads one of the 6 populated partitions:

```
EXPLAIN (ANALYZE, COSTS OFF)
SELECT travel_mode, count(*), round(avg(actual_minutes),1)
FROM navigation_sessions_partitioned
WHERE started_at >= '2026-03-01' AND started_at < '2026-04-01' AND status = 'COMPLETED'
GROUP BY travel_mode;
...
  ->  Parallel Index Scan using navigation_sessions_2026_q1_started_at_idx
        on navigation_sessions_2026_q1
```

Only `navigation_sessions_2026_q1` appears in the plan. Without a date filter, every partition is scanned.

| Measurement (4,000,000 sessions) | Not partitioned | Partitioned by quarter |
|----------------------------------|----------------:|-----------------------:|
| One-month aggregate (`started_at` range, 3 runs) | 14.6 to 14.8 ms | 15.5 to 17.0 ms |
| Remove the oldest 659,341 sessions (one quarter), rolled back | `DELETE`: 1,194 ms | `DETACH PARTITION`: 2.1 ms |

Partitioning did not speed up the date-range query at this size. The unpartitioned table already has an index on `started_at`, so pruning saves little. The benefit is in maintenance. Dropping or archiving a quarter is a metadata change, not a 1.2 second delete that leaves dead rows to vacuum. I added `idx_nav_part_started_at` to the script because the first test without it fell back to a sequential scan of the quarter (23.4 ms).

## 7. Architecture for 100x

The 100x figures below come from the large measurements, assuming 100x the seed rows (20 million sessions, 25 million traffic readings).

### Partitioning

* **navigation_sessions:** RANGE on `started_at`, quarterly now, monthly at 100x. Most queries filter on dates, and archiving is a `DETACH`.
* **traffic_readings:** RANGE on `recorded_at`, monthly. It is the fastest-growing table (about 870 MB at 20x, around 4.3 GB at 100x if growth is linear). Old months can be dropped with `drop_old_traffic_partitions()` from the script (the helper functions were created but not tested).
* **incident_reports** and **place_reviews:** yearly. They are small enough that this is for retention more than speed.
* **Not partitioned:** `places`, `users`, `opening_hours`. They are looked up by key, not by time.
* Pre-create future partitions before each period starts and alert on any rows in a DEFAULT partition.

### Sharding

Do not shard before measuring. At 20x the whole database is 3.6 GB and every real-time query is under 4 ms on a laptop. If a single writer becomes the limit, shard by **city or region**. "Near me" searches (R01, R03, R04), live traffic (R07 to R10) and incidents are local to a city, so they stay on one shard. Queries that cross shards are the global reports (R11, R17, R18, R20, R25) and a user's navigation history across cities (R13). Handle those with scatter-gather, or with summary tables fed to a reporting database. Sharding by user would make every "near me" and traffic query cross-shard, so I would not do that. Sharding by time is what partitioning already does inside one server. Watch for one very large city skewing a shard.

### Read replicas and caching

* **Replica:** the reports R11 to R21 and R25 (all under 1 s on large), the data-quality checks R14 and R15, and R19 and R20 if turned into summary tables. They tolerate replica lag.
* **Primary:** W01 to W05 and any read that must see a write immediately. R07, R08 and R10 (live traffic and incidents) can use a replica only while lag stays under the one-minute freshness limit.
* **Cache:** the latest traffic snapshot (R07) with a 30 to 60 second TTL, place details (R02), and popular searches. Do not cache per-user lists (R06, R13) without the user in the cache key.

### Maintenance

* **Autovacuum:** index-only scans (R07, R11, R17, R18, R20) only work while the visibility map is current. After a bulk load, run `VACUUM (ANALYZE)`, as `05_indexes.sql` now does. For `navigation_sessions` and `traffic_readings`, which are append-only, lower `autovacuum_vacuum_insert_scale_factor` (for example to 0.02) so inserts alone trigger a vacuum. I did not test this setting.
* **Archiving:** detach quarters older than the retention period and keep them in a separate archive table or database.
* **Summary tables:** `mv_place_stats` must be refreshed with `REFRESH MATERIALIZED VIEW CONCURRENTLY` on a schedule, and the refresh time measured as data grows.

## 8. Conclusion

Yes, the database is ready for 20x the volume on this hardware, with a warm cache. All 30 queries meet their targets, the real-time queries are under 4 ms, and the slowest report (R15) takes 995 ms against a 5,000 ms target.

Remaining risks:

* **W04** (recompute all place ratings) takes 1,620 ms against a 2,000 ms limit. It aggregates all 1.8 million reviews and joins 800,000 places, so 100x the seed data (5x the large data) would exceed the limit. It should run in batches of places.
* **R15, R11, R17 and R21** each take 300 to 1,000 ms and grow with the data. At 5x the large data they would take several seconds (an estimate, not measured). They should move to summary tables or a replica.
* **Cold cache:** on a cold cache R04 averaged 16.7 ms and R07 6.7 ms, above the 5 ms target. After a restart or failover the first requests will be slower. Pre-warming the hot indexes removes this.
* **Hardware:** all results are from one laptop with default PostgreSQL settings. A server with more `shared_buffers` and `work_mem` should do better, but I did not measure that.
* **Partitioning** is tested but not applied to the main tables, because swapping tables needs a migration window and a shared ID sequence.
