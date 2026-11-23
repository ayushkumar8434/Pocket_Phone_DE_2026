# Phase 5: Scalability Report (large dataset)

All numbers in this report were measured on this machine. Nothing is estimated unless the text says "estimate" or "not tested".

## 1. Setup

| Item | Value |
|------|-------|
| Machine | Apple M4, 16 GB RAM, macOS, local PostgreSQL (other apps were running, see section 3) |
| PostgreSQL | 17.11 (Homebrew), default settings: `shared_buffers` 128 MB, `work_mem` 4 MB, `effective_cache_size` 4 GB, `max_parallel_workers_per_gather` 2 |
| Seed database | `seed_data.zip`: 200,000 navigation sessions, 159 MB |
| Large database | `large_data.zip`: 18,725,897 rows in 11 tables, 3,133 MB of tables and indexes |
| Large row counts | 4,000,000 navigation sessions, 4,999,656 traffic readings, 5,045,376 opening hours, 800,853 places, 800,000 users, 1,799,990 reviews, 1,000,000 saved places, 240,000 incident reports, 40,000 road segments |
| Load steps | `sql/01_schema.sql`, then `sql/02_load_data.sql` with `seed_data/` replaced by `large_data/` (the only change), then `sql/05_indexes.sql` (ends with `VACUUM (ANALYZE)`) |
| Load time (large) | 1 minute 45 seconds for the 18.7 million rows, 31 seconds for the indexes and `VACUUM (ANALYZE)` |
| Benchmark | `./benchmarks/run_benchmark.sh <db> large 3 sql/06_optimized_queries.sql` (3 runs per query, average, `EXPLAIN (ANALYZE, BUFFERS)`). Write queries run inside `BEGIN ... ROLLBACK` |
| Seed comparison | The same command on the seed database, with the same scripts. The seed column below is a new run, not the Phase 4 file |

Raw plans for all 3 runs of every query are in [`benchmarks/results/large/`](../benchmarks/results/large/), and `summary.csv` there has the average, median, minimum and maximum. The original 30 queries were not run on the large data, as the brief requires.

**Results are from the last of several passes.** I ran the whole benchmark 5 times on the final database. `summary.csv` is the last pass. It was run after earlier passes had warmed the cache. Pass 4 started with a cold cache, and its first runs were slow (R04 41 ms, R07 139 ms in run 1). The other passes are used in section 3 to show how much the borderline queries vary.

**Note on the SQL files.** The `sql/` files for schema, load, indexes, optimized queries and partitioning were written by the team in Phases 1 to 4 and produced the committed baseline and optimized results. Commit `9f94e08` deleted them and commit `9b258b6` replaced them with different versions. Those versions did not match the committed results (their indexes have other names) and could not load the data: the `saved_places` and `incident_reports` CHECK constraints rejected values that exist in the seed and large data. I restored the original files from the commit before `9f94e08`. I checked that they load the seed data, and that 25 of the 30 optimized plans on the seed data use the same scans as `benchmarks/results/optimized/summary.csv`. The only edits since the restore are the Phase 5 changes in section 3.

## 2. Results versus targets

Growth is the large average divided by the seed average. In the recorded pass, 28 of the 30 queries meet their target. R07 and W04 miss it. Section 3 explains both.

| Query | Seed (ms) | Large (ms) | Growth | Target | Meets? | Notes |
|-------|----------:|-----------:|-------:|-------:|:------:|-------|
| R01 | 0.096 | 0.756 | 7.9x | < 5 ms | Yes |  |
| R02 | 0.064 | 0.050 | 0.8x | < 5 ms | Yes |  |
| R03 | 2.938 | 21.183 | 7.2x | < 250 ms | Yes |  |
| R04 | 1.674 | 1.472 | 0.9x | < 5 ms | Yes | Fixed. First large run: 32.537 ms (Bitmap Heap Scan of 42,249 places, then sort). New index `places_open_city_category_rating_idx`. Section 3. |
| R05 | 0.476 | 0.098 | 0.2x | < 5 ms | Yes |  |
| R06 | 0.237 | 0.154 | 0.6x | < 5 ms | Yes |  |
| R07 | 0.767 | 5.815 | 7.6x | < 5 ms | **No** | **Misses 5 ms in the recorded pass** (runs 3.7, 6.4, 7.4 ms). Fixed from 133.165 ms with LATERAL. Section 3. |
| R08 | 0.266 | 1.178 | 4.4x | < 5 ms | Yes |  |
| R09 | 0.370 | 0.335 | 0.9x | < 250 ms | Yes |  |
| R10 | 0.205 | 1.563 | 7.6x | < 5 ms | Yes |  |
| R11 | 27.867 | 415.346 | 14.9x | < 5,000 ms | Yes |  |
| R12 | 2.577 | 17.184 | 6.7x | < 250 ms | Yes |  |
| R13 | 7.601 | 123.120 | 16.2x | < 250 ms | Yes | Fixed. First large run: 283.763 ms (145,339 heap fetches). `VACUUM (ANALYZE)` after the load. Section 3. |
| R14 | 8.951 | 67.186 | 7.5x | < 5,000 ms | Yes |  |
| R15 | 25.297 | 449.587 | 17.8x | < 5,000 ms | Yes |  |
| R16 | 10.262 | 43.550 | 4.2x | < 5,000 ms | Yes |  |
| R17 | 33.296 | 459.374 | 13.8x | < 5,000 ms | Yes |  |
| R18 | 16.514 | 190.657 | 11.5x | < 5,000 ms | Yes |  |
| R19 | 3.583 | 56.781 | 15.8x | < 5,000 ms | Yes |  |
| R20 | 1.794 | 33.870 | 18.9x | < 5,000 ms | Yes |  |
| R21 | 20.454 | 320.840 | 15.7x | < 5,000 ms | Yes |  |
| R22 | 4.741 | 5.348 | 1.1x | < 250 ms | Yes |  |
| R23 | 0.028 | 0.031 | 1.1x | < 5 ms | Yes |  |
| R24 | 5.620 | 34.584 | 6.2x | < 250 ms | Yes |  |
| R25 | 29.810 | 360.466 | 12.1x | < 5,000 ms | Yes |  |
| W01 | 0.734 | 0.906 | 1.2x | < 5 ms | Yes |  |
| W02 | 0.671 | 0.719 | 1.1x | < 5 ms | Yes |  |
| W03 | 0.759 | 1.810 | 2.4x | < 5 ms | Yes |  |
| W04 | 49.948 | 2,082.311 | 41.7x | < 2,000 ms | **No** | **Misses 2,000 ms in the recorded pass** (runs 1,162, 4,117, 968 ms; median 1,162 ms). Section 3. |
| W05 | 3.982 | 249.417 | 62.6x | < 2,000 ms | Yes |  |

## 3. What broke at scale and how it was fixed

The first run on the large data (original scripts, no Phase 5 changes) had three queries over their target. Each was diagnosed from the plan.

### R04: open restaurants at 23:30 (32.537 ms, now 1.472 ms)

* **Plan before:** `Parallel Bitmap Heap Scan` on `places` through `places_open_city_category_idx`. It fetched all 42,249 restaurants of city 1, sorted them by rating, and kept 30. Runs: 51.5, 25.5, 20.6 ms.
* **Why only at scale:** the index finds the rows but does not return them in rating order, so the number of rows fetched grows with the table.
* **Fix:** a new index `places_open_city_category_rating_idx (city_id, category_id, avg_rating DESC NULLS LAST, place_id) WHERE NOT is_permanently_closed` in `sql/05_indexes.sql`. The query stays the same.
* **Plan after:** `Index Scan` on the new index, 227 rows read, no sort. Runs: 0.9, 0.8, 2.7 ms. The old index `places_open_city_category_idx` is no longer used by R04 and could be dropped (not tested).

### R13: places never used as a navigation origin (283.763 ms, now 123.120 ms)

* **Plan before:** `Index Only Scan using navigation_known_origin_idx` with `Heap Fetches: 145,339` and 110,042 buffers read from disk. The visibility map was empty because the load script only runs `ANALYZE`, so an "index-only" scan still visited the table for each row.
* **Fix:** `VACUUM (ANALYZE)` at the end of `sql/05_indexes.sql` (a maintenance step, no server setting changed).
* **Plan after:** `Heap Fetches: 1`. R15, R16, R17 and R19 also dropped between the first large run and the recorded pass (R15 815 to 450 ms, R16 120 to 44 ms, R17 1,290 to 459 ms, R19 194 to 57 ms). They use index-only scans too, so the vacuum is the likely cause. I did not test each one separately.

### R07: latest traffic reading per segment (133.165 ms, now 5.815 ms)

* **Plan before:** `Seq Scan on traffic_readings` (5 million rows), join to the 800 matching segments, then a sort of about 100,000 rows for `DISTINCT ON`. Runs: 143.4, 128.3, 127.8 ms.
* **Fix:** in `sql/06_optimized_queries.sql`, R07 now uses `CROSS JOIN LATERAL (... ORDER BY recorded_at DESC LIMIT 1)`. The existing index `traffic_segment_newest_idx` already holds the needed columns. The old and new queries return identical rows (checked by hashing both result sets on the large data).
* **Plan after:** 800 loops of `Index Only Scan using traffic_segment_newest_idx`, `Heap Fetches: 0`, no sort.
* **Why it still misses 5 ms in the recorded pass:** the three runs took 3.7, 6.4 and 7.4 ms. The query does 800 index lookups of about 3 buffers each, so its time depends on CPU speed. In 11 separate single runs outside the benchmark it took between 2.8 and 10.2 ms, and in the other three warm benchmark passes the average was 8.7, 7.7 and 7.3 ms. The IDE and the macOS malware scanner were using CPU while I ran these. I cannot say how much of the 5.8 ms is noise. The plan itself is minimal. A table holding the latest reading per segment would make R07 one primary-key join, but it needs a trigger or scheduled refresh on the traffic table, and I did not build or test it.

### W04: recompute every place rating (1,530 ms in the first large run, now 2,082 ms)

The plan is the same in every run: an `Index Only Scan` on `place_reviews_place_newest_idx` aggregated by place, a merge join with `places`, and an update of 11,270 changed rows. Typical run time is 1.0 to 1.2 s. In 3 of the 15 runs in the last five passes, one run took 3 to 4 seconds (4,117 ms in the recorded pass), which pushes the 3-run average above 2,000 ms. The plan did not change in those runs. A disk flush or checkpoint during the update is likely, but I did not check. The median of the recorded pass is 1,162 ms.

### Problems that blocked or confused the first load

The schema and load scripts needed no change after the SQL files were restored. The first attempt used the replaced files (section 1) and failed with CHECK constraint violations on `saved_places` and `incident_reports`.

## 4. Growth analysis

The large data has 20 times the rows. How each query's time grew:

* **Stayed about the same (under 2.5x):** R02 (0.8x), R04 (0.9x), R05 (0.2x), R06 (0.6x), R09 (0.9x), R22 (1.1x), R23 (1.1x), W01 (1.2x), W02 (1.1x), W03 (2.4x). These are primary-key lookups, `LIMIT` queries on an index, and index probes for one user, place or segment. A B-tree lookup grows with the logarithm of the table size, so 20x more rows adds at most one index level. Ratios under 1 are within the run-to-run noise of queries that take less than 0.5 ms.
* **Grew 2.5x to 10x:** R01 (7.9x), R03 (7.2x), R07 (7.6x), R08 (4.4x), R10 (7.6x), R12 (6.7x), R14 (7.5x), R16 (4.2x), R24 (6.2x). These read a small slice of a larger table or index (a city, a road, a name pattern, a date range), so they grow less than the table. I did not examine each plan for the exact cause.
* **Grew 10x to 20x, close to the data growth:** R11 (14.9x), R13 (16.2x), R15 (17.8x), R17 (13.8x), R18 (11.5x), R19 (15.8x), R20 (18.9x), R21 (15.7x), R25 (12.1x). They read a fixed share of a table (every session, review or reading), so time is proportional to the rows read. About 20x is expected.
* **Grew more than 20x:** W04 (41.7x), W05 (62.6x).
  * **W04 (41.7x)** aggregates all reviews and updates 11,270 rows (558 on seed). On seed it is a hash aggregate over a sequential scan, on large a merge join over index scans. Its recorded time includes the 4 second outlier described above, and its typical time of 1.0 to 1.2 s is 20 to 24x the seed time.
  * **W05 (62.6x)** deletes about 94% of the incident rows in both databases (11,339 rows on seed, 226,751 on large). The plan is a sequential scan plus delete in both. Its time ranged from 105 to 290 ms across the passes, so the ratio is mostly noise on a short write. I did not find a plan reason for any extra cost.

R22 uses `OFFSET 50000` and runs in 5.348 ms on large because the `created_at` index returns the first 50,000 rows without a sort. Deeper pages cost more, so for a real client use keyset pagination: the "last seen" value is the `(created_at, review_id)` of the last row on the previous page, and the next page asks for rows with `(created_at, review_id) < (last_created_at, last_review_id)`.

## 5. Storage (seed and large)

Database size: seed 159 MB, large 3,133 MB of tables and indexes (20.7x). Sizes by table, from `pg_table_size`, `pg_indexes_size` and `pg_total_relation_size`:

| Table | Seed total | Large table | Large indexes | Large total |
|-------|-----------:|------------:|--------------:|------------:|
| navigation_sessions | 46 MB | 454 MB | 469 MB | 923 MB |
| traffic_readings | 33 MB | 288 MB | 372 MB | 659 MB |
| places | 20 MB | 144 MB | 372 MB | 515 MB |
| opening_hours | 18 MB | 251 MB | 109 MB | 360 MB |
| place_reviews | 17 MB | 127 MB | 212 MB | 339 MB |
| users | 6.6 MB | 69 MB | 81 MB | 150 MB |
| saved_places | 7.2 MB | 57 MB | 86 MB | 143 MB |
| incident_reports | 1.9 MB | 18 MB | 19 MB | 37 MB |
| road_segments | 0.5 MB | 4.6 MB | 3.0 MB | 7.6 MB |

On the large data, indexes (1,722 MB) are larger than the tables (1,411 MB). The new R04 index is part of the `places` figure.

## 6. Partitioning (tested on the large data)

`sql/08_partitioning.sql` builds `navigation_sessions_partitioned`, partitioned by RANGE on `started_at`: 24 monthly partitions (January 2025 to December 2026) and a DEFAULT partition. It copies the 4,000,000 sessions and creates 4 indexes. On the large data the script ran in 52.6 seconds without errors.

**Primary-key rule.** A primary key or unique constraint on a partitioned table must include the partition column. The key is therefore `(session_id, started_at)`, which no longer guarantees that `session_id` is unique across partitions. Session ids must come from one shared sequence.

**Partition pruning.** A query for June 2026 reads only one partition (from the script's own `EXPLAIN`):

```
Parallel Seq Scan on navigation_sessions_part_202606 navigation_sessions_partitioned
```

| Measurement (4,000,000 sessions) | Not partitioned | Partitioned by month |
|----------------------------------|----------------:|---------------------:|
| June 2026 aggregate by travel mode (3 runs) | 26.9, 19.0, 14.1 ms | 16.9, 14.7, 13.4 ms |
| Remove January 2025 (227,107 sessions), rolled back | `DELETE`: 430.6 ms | `DETACH PARTITION`: 2.1 ms |

Pruning makes the one-month query a little faster in the first run and about the same in the others, because the unpartitioned table already has a good index for it. The larger benefit is maintenance. Detaching or dropping a month is a metadata change, while the `DELETE` rewrites 227,000 rows and leaves dead rows to vacuum.

## 7. Architecture for 100x

The 100x figures assume 100 times the seed rows (20 million sessions, 25 million traffic readings), which is 5 times the large data. Any estimate below is linear and not tested.

### Partitioning

* **navigation_sessions:** RANGE on `started_at`, monthly, as in `08_partitioning.sql`. Most queries filter on dates, and archiving is a `DETACH`.
* **traffic_readings:** RANGE on `recorded_at`, monthly. It is one of the largest tables (659 MB at 20x, about 3.3 GB at 100x if linear). Old months are dropped as whole partitions.
* **incident_reports** and **place_reviews:** yearly, mostly for retention.
* **Not partitioned:** `places`, `users`, `opening_hours`. They are read by key, not by time.
* Create future partitions before each month starts, and alert on rows in the DEFAULT partition.

### Sharding

Do not shard before measuring. At 20x the whole database is 3.1 GB, and 11 of the 12 real-time queries are under 2 ms on a laptop. If a single writer becomes the limit, shard by **city or region**. "Near me" searches (R01, R03, R04), live traffic (R07 to R10) and incidents are local to a city, so they stay on one shard. The cross-shard queries are the global reports (R11, R17, R18, R20, R25) and a user's navigation history across cities (R13). Handle those with scatter-gather, or with summary tables in a reporting database. Sharding by user would make every "near me" and traffic query cross-shard, so I would not do that. Sharding by time is what partitioning already does inside one server. A large city can skew one shard.

### Read replicas and caching

* **Replica:** the reports R11 to R21 and R25 (all under 0.5 s on large), and the data-quality checks R14 and R15. They tolerate replica lag.
* **Primary:** W01 to W05 and any read that must see a write at once. R07, R08 and R10 (live traffic and incidents) can use a replica only while lag stays under the one-minute freshness limit.
* **Cache:** the latest traffic snapshot (R07) with a 30 to 60 second lifetime, place details (R02) and popular searches. Do not cache per-user lists (R06, R13) without the user in the cache key.

### Maintenance

* **VACUUM and the visibility map:** the R13 result shows what happens without it: 145,339 heap fetches and 284 ms instead of 123 ms. After any bulk load, run `VACUUM (ANALYZE)`. For append-only tables such as `navigation_sessions` and `traffic_readings`, a lower `autovacuum_vacuum_insert_scale_factor` (for example 0.02) makes inserts alone trigger a vacuum. I did not test this setting.
* **Archiving:** detach months older than the retention period into an archive table or database.
* **Dead rows from rolled-back writes:** W04 and W05 left dead rows in `places` and `incident_reports` after each rolled-back run (134,658 dead rows in `places` after 12 runs). Production runs of W04 need a vacuum afterwards.

## 8. Conclusion

The database is close to ready for 20x the volume on this hardware. 28 of the 30 queries meet their targets in the recorded pass, the slowest report (R17) takes 459 ms against 5,000 ms, and the two misses are borderline and explained: R07 at 5.8 ms against 5 ms, and W04 at 2,082 ms against 2,000 ms because of one slow run.

Remaining risks:

* **R07** sits around the 5 ms limit on this laptop (2.8 to 10.2 ms). A latest-reading summary table would remove the risk (not tested).
* **W04** takes about 1 to 1.2 s but had single runs of 3 to 4 s. It rewrites rating columns for every changed place, so at 5x the data it would exceed 2 s. It should run in batches of places.
* **R11, R15, R17 and R21** take 300 to 460 ms and grow with the data. At 5x they would take 1.5 to 2.3 s (an estimate). They are good candidates for a replica or summary tables.
* **Cold cache:** the first run after a restart is slower (R04 took 41 ms and R07 139 ms in a cold first run).
* **Hardware:** all results are from one laptop with default PostgreSQL settings and other applications running. A server with more `shared_buffers` and `work_mem` should do better, but I did not measure that.
* **Partitioning** is tested but not applied to the main tables, because swapping tables needs a migration window and a shared id sequence.
