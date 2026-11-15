# Phase 3 — Baseline timings

## Method and environment

The baseline workload was run against the loaded `AMIT8080` database before
applying the Phase 4 indexes:

```sh
./benchmarks/run_benchmark.sh AMIT8080 baseline
```

Each query ran three times; write queries were wrapped in a transaction and
rolled back by the benchmark script. Run times below are transcribed from the
`Execution Time` lines in each raw plan. Averages are the generated
`avg_ms` values in `benchmarks/results/baseline/summary.csv`. Phases 3 and 4
used the same laptop.

Environment: PostgreSQL 18.4 (Postgres.app), `TimeZone = Asia/Kolkata`,
`work_mem = 4MB`; schema and seed row counts match `sql/02_load_data.sql`.
Raw plans for all 25 reads and five writes are in
`benchmarks/results/baseline/`.

## Results

| Query description | Type | Run 1 (ms) | Run 2 (ms) | Run 3 (ms) | Average (ms) | Scan type | Reason |
|---|---|---:|---:|---:|---:|---|---|
| R01: Restaurants near me, open restaurants within ~1 km of Koramangala | READ | 4.352 | 3.948 | 3.589 | 3.963 | Seq Scan `places` | No baseline index on category/coordinates; distance is calculated and sorted. |
| R02: Place page details with Tuesday opening hours | READ | 0.040 | 0.041 | 0.036 | 0.039 | Index Scan `places_pkey`, `opening_hours_pkey` | Both point lookups use Phase 2 primary-key indexes. |
| R03: Bengaluru places with “biryani” in the name, best rated first | READ | 13.687 | 13.989 | 14.589 | 14.088 | Seq Scan `places` | Leading-wildcard `ILIKE` and city filter have no baseline tuning index. |
| R04: Bengaluru restaurants open at 23:30 on Saturday | READ | 9.225 | 7.934 | 8.576 | 8.578 | Seq Scan `opening_hours`, `places` | Weekday/time and city/category filters have no baseline tuning index. |
| R05: The 10 newest reviews of place 18 | READ | 0.153 | 0.132 | 0.130 | 0.138 | Bitmap Heap/Index Scan `place_reviews`; Index Scan `users_pkey` | Existing review uniqueness index narrows by place, but newest-first rows need sorting. |
| R06: User 1005’s saved places grouped by list | READ | 0.067 | 0.066 | 0.059 | 0.064 | Index Scan `saved_places_pkey`, `places_pkey` | Saved-place primary key begins with `user_id`. |
| R07: Latest reading of each Outer Ring Road segment in Bengaluru | READ | 9.514 | 9.205 | 9.273 | 9.331 | Seq Scan `traffic_readings`, `road_segments` | No baseline index for latest readings or city/road-prefix selection. |
| R08: Heavy/standstill Bengaluru traffic since 18:00 on 30 June 2026 | READ | 7.411 | 7.443 | 7.331 | 7.395 | Seq Scan `traffic_readings`; Index Scan `road_segments_pkey` | Traffic congestion/time predicates are unindexed. |
| R09: Typical traffic by hour on segment 5 | READ | 4.848 | 4.540 | 4.544 | 4.644 | Seq Scan `traffic_readings` | `segment_id` has no baseline index. |
| R10: Bengaluru incidents reported on 30 June 2026 | READ | 0.787 | 0.773 | 0.723 | 0.761 | Seq Scan `incident_reports`, `road_segments` | Report-day expression and city join filter are unindexed. |
| R11: Average ETA error per travel mode and month in 2026 | READ | 23.832 | 22.828 | 22.984 | 23.215 | Seq Scan `navigation_sessions` | Status and year predicates are unindexed; year is extracted from the timestamp. |
| R12: 10 most-navigated-to Mumbai places in the last 7 days of June 2026 | READ | 10.040 | 10.085 | 10.034 | 10.053 | Seq Scan `navigation_sessions`, `places` | Start date and city/destination join filters have no baseline tuning index. |
| R13: Places never used as a navigation starting point | READ | 20.512 | 19.824 | 19.835 | 20.057 | Seq Scan `places`, `navigation_sessions` | `NOT IN` hashes all origins; NULL origins make the original query return zero rows. |
| R14: Local Guides leaderboard by reviews in 2026 | READ | 9.590 | 9.610 | 10.126 | 9.775 | Seq Scan `place_reviews`, `users` | Review date filtering and reviewer grouping are unindexed. |
| R15: Places whose stored rating or review count differs from reviews | READ | 28.737 | 28.473 | 31.678 | 29.629 | Seq Scan `place_reviews`, `places` | Reviews are fully scanned and grouped without a place-key index. |
| R16: Permanently closed places still navigated to in 2026 | READ | 13.274 | 13.168 | 12.650 | 13.031 | Seq Scan `navigation_sessions`, `places` | Session date and destination join have no baseline tuning index. |
| R17: Destinations with most rerouting, at least five trips | READ | 34.243 | 32.838 | 32.421 | 33.167 | Seq Scan `navigation_sessions` | The query aggregates the complete session table. |
| R18: Cancelled-navigation share per travel mode | READ | 14.655 | 14.404 | 14.662 | 14.574 | Seq Scan `navigation_sessions` | The per-mode aggregate reads all sessions. |
| R19: Bengaluru hospitals’ navigation count and latest navigation | READ | 12,916.527 | 13,079.244 | 12,960.536 | 12,985.436 | Seq Scan `place_categories`, `places`, `navigation_sessions` | Correlated count/max subqueries repeatedly scan sessions for hospital destinations. |
| R20: Daily navigation counts and running total for June 2026 | READ | 10.066 | 9.318 | 9.355 | 9.580 | Seq Scan `navigation_sessions` | Date cast prevents a simple start-time range scan. |
| R21: Places without opening hours, counted per category | READ | 43.607 | 20.672 | 20.494 | 28.258 | Seq Scan `opening_hours`, `places`, `place_categories`; Hash Anti/Join | Place/hour existence and category grouping require broad scans. |
| R22: Newest reviews, page 2,001 (25 per page) | READ | 15.862 | 15.465 | 15.710 | 15.679 | Seq Scan `place_reviews` | Newest-first ordering and large offset require scanning and sorting. |
| R23: Find an open place by Plus Code | READ | 0.029 | 0.024 | 0.026 | 0.026 | Index Scan `places_plus_code_key` | Phase 2 UNIQUE constraint supplies the lookup index. |
| R24: Bengaluru restaurants with nearby same-name duplicate listings | READ | 4.904 | 4.899 | 4.839 | 4.881 | Seq Scan `places` | Same-name and geographic self-join filters lack tuning indexes. |
| R25: Share of traffic readings above speed limit per road type | READ | 26.866 | 26.422 | 27.174 | 26.821 | Seq Scan `traffic_readings`, `road_segments` | Aggregate reads all traffic rows and joins on an unindexed traffic key. |
| W01: Start navigation from current location to place 18 | WRITE | 0.856 | 0.491 | 0.510 | 0.619 | No scan node | Insert cost includes tuple creation and existing PK/FK checks. |
| W02: User 1005 writes a review for place 18 | WRITE | 0.558 | 0.519 | 0.464 | 0.514 | No scan node | Insert uses the existing unique conflict-target index. |
| W03: User 1005 saves place 18 to “Want to go” | WRITE | 0.576 | 0.534 | 0.520 | 0.543 | No scan node | Insert uses the saved-place composite primary key for conflict checking. |
| W04: Recompute every place’s rating and review count | WRITE | 32.457 | 32.148 | 32.278 | 32.294 | Seq Scan `places`, `place_reviews` | Recomputing aggregates reads all reviews and updates matching places. |
| W05: Delete incident reports expired before June 2026 | WRITE | 2.225 | 2.104 | 2.162 | 2.164 | Seq Scan `incident_reports` | `expires_at` has no baseline index. |
| **Total (sum of averages)** | — | — | — | — | **13,309.317** | — | — |

The raw-plan R21 run 1 took 43.607 ms, versus 20.672 ms in run 2 and
20.494 ms in run 3; its plan shape and shared-buffer count remained the same
(2,564 shared hits), while the first run’s table scans took longer.

R19 was the clear baseline outlier at about 13 seconds. R13 returned zero rows
because SQL `NOT IN` is NULL-sensitive; Phase 4 corrects that behavior.

## Average verification

All 30 averages above match `avg_ms` in
`benchmarks/results/baseline/summary.csv` to three decimal places. Each was
checked against the three `Execution Time` values in its raw plan file. No
average mismatches were found.
