# Phase 4 — Query optimization report

## Measurement source and method

Before averages below come from `benchmarks/results/baseline/summary.csv`;
after averages come from `benchmarks/results/optimized/summary.csv`. The raw
`EXPLAIN (ANALYZE, BUFFERS)` files in those directories provide the plan
evidence. The optimized workload was measured five times per query, with
writes rolled back by the benchmark script.

Improvement is calculated as `(before - after) / before * 100`; negative
percentages mean the optimized average was slower. Query descriptions are from
the comments in `queries/workload_30.sql`.

## Combined timing results

| Query | Before (ms) | Problem found in the plan | Optimization applied | After (ms) | Improvement % | Same result? |
|---|---:|---|---|---:|---:|---|
| R01: Restaurants near me, open restaurants within ~1 km of Koramangala | 3.963 | Seq Scan over places; no selective category/coordinate access path. | Partial B-tree on category and coordinates for open places. | 0.212 | 94.65% | Yes |
| R02: Place page details with Tuesday opening hours | 0.039 | Already uses the place and opening-hours primary keys. | Index only; no query rewrite. | 0.091 | -133.33% | Yes |
| R03: Bengaluru places with “biryani” in the name, best rated first | 14.088 | Seq Scan over places for city and leading-wildcard name search. | GIN trigram and city B-tree; latest plan combines bitmaps. | 0.750 | 94.68% | Yes |
| R04: Bengaluru restaurants open at 23:30 on Saturday | 8.578 | Seq Scans on places/opening-hours; no city/category index path. | Partial open-place B-tree; deterministic `place_id` tie-breaker. | 3.605 | 57.97% | Tied rating-5.0 rows can differ |
| R05: The 10 newest reviews of place 18 | 0.138 | Existing uniqueness index finds place reviews but cannot supply newest-first order. | `(place_id, created_at DESC)` B-tree including projected review values. | 0.174 | -26.09% | Yes |
| R06: User 1005’s saved places grouped by list | 0.064 | Existing primary key supports user lookup but not the complete list/time ordering. | User/list/time B-tree including place ID. | 0.137 | -114.06% | Yes |
| R07: Latest reading of each Outer Ring Road segment in Bengaluru | 9.331 | Seq Scans over roads and all traffic readings. | City/road-prefix B-tree and segment/time B-tree. | 1.749 | 81.26% | Yes |
| R08: Heavy/standstill Bengaluru traffic since 18:00 on 30 June 2026 | 7.395 | Seq Scan over traffic readings for congestion and time. | Partial time B-tree for heavy/standstill readings and road city index. | 0.065 | 99.12% | Yes |
| R09: Typical traffic by hour on segment 5 | 4.644 | Seq Scan over all traffic readings for one segment. | Segment-leading B-tree including time and speed. | 0.102 | 97.80% | Yes |
| R10: Bengaluru incidents reported on 30 June 2026 | 0.761 | Seq Scans; `DATE(reported_at)` obscures a timestamp range. | Half-open local-day range with `+05:30`; reported-time B-tree. | 0.068 | 91.06% | Yes |
| R11: Average ETA error per travel mode and month in 2026 | 23.215 | Full session Seq Scan for completed rows and extracted year. | Half-open year range with `+05:30`; partial completed-session B-tree. | 13.140 | 43.40% | Yes |
| R12: 10 most-navigated-to Mumbai places in the last 7 days of June 2026 | 10.053 | Seq Scans over sessions and places. | Started-time and city/place B-trees. | 1.801 | 82.08% | Yes |
| R13: Places never used as a navigation starting point | 20.057 | Seq Scan plus hashed `NOT IN`; any NULL origin makes the result empty. | `NOT EXISTS` anti-join and partial non-NULL origin B-tree. | 5.537 | 72.39% | No; intentional NULL fix |
| R14: Local Guides leaderboard by reviews in 2026 | 9.775 | Seq Scans over reviews and users; date filter lacks a selective date index. | Newest-first review B-tree supports the recent-date range. | 6.352 | 35.02% | Yes |
| R15: Places whose stored rating or review count differs from reviews | 29.629 | Full reviews/places join and grouped aggregate. | Review B-tree ordered by place, including rating for the aggregate. | 21.179 | 28.52% | Yes |
| R16: Permanently closed places still navigated to in 2026 | 13.031 | Seq Scan over sessions for destination/date matches. | Started-time B-tree narrows the session range. | 9.191 | 29.47% | Yes |
| R17: Destinations with most rerouting, at least five trips | 33.167 | Full session Seq Scan and aggregate by destination. | Destination/time B-tree exists, but broad grouping still uses a Seq Scan. | 33.012 | 0.47% | Yes |
| R18: Cancelled-navigation share per travel mode | 14.574 | Full session scan for an aggregate over all travel modes. | Index only; no query rewrite. | 14.341 | 1.60% | Yes |
| R19: Bengaluru hospitals’ navigation count and latest navigation | 12,985.436 | Two correlated subplans each Seq Scan all sessions per hospital. | Destination-leading B-tree supports count and latest-time lookups. | 5.726 | 99.96% | Yes |
| R20: Daily navigation counts and running total for June 2026 | 9.580 | Seq Scan with a date cast in the filter. | Half-open June range with `+05:30`; started-time B-tree. | 1.416 | 85.22% | Yes |
| R21: Places without opening hours, counted per category | 28.258 | Broad anti-join and category aggregation; scans places and opening hours. | Index only; removed unused category index; planner parallelizes broad scans. | 16.819 | 40.48% | Yes |
| R22: Newest reviews, page 2,001 (25 per page) | 15.679 | Seq Scan plus external merge sort, including temp-file I/O. | Descending created-time B-tree supplies ordered rows. | 4.469 | 71.50% | Yes |
| R23: Find an open place by Plus Code | 0.026 | Already uses the unique Plus Code index. | Index only; no query rewrite. | 0.081 | -211.54% | Yes |
| R24: Bengaluru restaurants with nearby same-name duplicate listings | 4.881 | Broad self-join/Seq Scan for same-name candidates. | City/category/name/place B-tree includes coordinates. | 4.053 | 16.96% | Yes |
| R25: Share of traffic readings above speed limit per road type | 26.821 | Full traffic scan and join, then aggregate all readings by road type. | Index only; broad aggregate still scans all readings. | 27.976 | -4.31% | Yes |
| W01: Start navigation from current location to place 18 | 0.619 | Insert; primary/foreign-key validation. | Indexes add maintenance work to the inserted row. | 0.969 | -56.54% | Yes |
| W02: User 1005 writes a review for place 18 | 0.514 | Insert with existing unique-conflict check. | New review index also requires maintenance. | 0.779 | -51.56% | Yes |
| W03: User 1005 saves place 18 to “Want to go” | 0.543 | Insert with existing saved-place primary-key conflict check. | New saved-place index also requires maintenance. | 0.805 | -48.25% | Yes |
| W04: Recompute every place’s rating and review count | 32.294 | Full review aggregate and place updates. | Review/place indexes add maintenance; aggregate still reads all reviews. | 54.538 | -68.88% | Yes |
| W05: Delete incident reports expired before June 2026 | 2.164 | Seq Scan for expiration cutoff. | Index only; no expiry index was retained. | 2.070 | 4.34% | Yes |
| **Total (sum of all 30 averages)** | **13,309.317** | — | — | **231.207** | **98.26%** | — |

### Query rewrite scope

These queries have **no SQL rewrite; their change is index-only**: R01, R02,
R03, R05, R06, R07, R08, R09, R12, R14, R15, R16, R17, R18, R19, R21, R22,
R23, R24 and R25. R10, R11 and R20 expose timestamp ranges; R04 adds a
deterministic tie-breaker; R13 corrects NULL-sensitive anti-join semantics.

## Result comparison proof

The table below is from the last R01–R25 comparison batch. `Old-only` counts
rows from `original EXCEPT optimized`; `New-only` counts rows from
`optimized EXCEPT original`. `EXCEPT` is set-based and removes duplicates, so
these columns are distinct-row differences, not multiset difference counts.
The row counts are ordinary `count(*)` on each query result.

| Query | Original rows | Optimized rows | Old-only | New-only |
|---|---:|---:|---:|---:|
| R01 | 16 | 16 | 0 | 0 |
| R02 | 1 | 1 | 0 | 0 |
| R03 | 20 | 20 | 0 | 0 |
| R04 | 30 | 30 | 4 | 4 |
| R05 | 10 | 10 | 0 | 0 |
| R06 | 4 | 4 | 0 | 0 |
| R07 | 40 | 40 | 0 | 0 |
| R08 | 3 | 3 | 0 | 0 |
| R09 | 24 | 24 | 0 | 0 |
| R10 | 2 | 2 | 0 | 0 |
| R11 | 24 | 24 | 0 | 0 |
| R12 | 10 | 10 | 0 | 0 |
| R13 | 0 | 33,368 | 0 | 33,368 |
| R14 | 20 | 20 | 0 | 0 |
| R15 | 558 | 558 | 0 | 0 |
| R16 | 895 | 895 | 0 | 0 |
| R17 | 20 | 20 | 0 | 0 |
| R18 | 4 | 4 | 0 | 0 |
| R19 | 1,067 | 1,067 | 0 | 0 |
| R20 | 30 | 30 | 0 | 0 |
| R21 | 3 | 3 | 0 | 0 |
| R22 | 25 | 25 | 0 | 0 |
| R23 | 1 | 1 | 0 | 0 |
| R24 | 42 | 42 | 0 | 0 |
| R25 | 3 | 3 | 0 | 0 |

**R13:** the original `NOT IN` returned zero rows because the origin subquery
contains NULLs. Replacing it with `NOT EXISTS` returns 33,368 places. A
`LEFT JOIN ... WHERE session_id IS NULL` anti-join also returned 33,368 rows;
both EXCEPT directions between those two corrected forms returned zero.

**R04:** each version returns 30 rows. The optimized `ORDER BY` adds
`place_id` after rating to make the boundary deterministic. The four
old-only and four new-only rows in this comparison were all rating `5.0`;
there were no differences at other ratings.

## Five largest read-query improvements by average time saved

Selection is based on `before average - after average` from the two summary
CSVs. Each excerpt below is the first run from that query’s raw plan file;
execution time in these excerpts is the individual raw run, not the five-run
average in the timing table.

### R19 — 12,979.710 ms saved on averages

`benchmarks/results/baseline/R19.txt`, run 1:

```text
Sort  (cost=13954773.04..13954776.27 rows=1291 width=40) (actual time=12916.437..12916.466 rows=1067.00 loops=1)
  ->  Seq Scan on places p  (cost=0.00..13954705.18 rows=1291 width=40) (actual time=13.704..12915.597 rows=1067.00 loops=1)
        SubPlan 1
          ->  Aggregate  (cost=5404.02..5404.03 rows=1 width=8) (actual time=6.015..6.015 rows=1.00 loops=1067)
                ->  Seq Scan on navigation_sessions n  (cost=0.00..5404.00 rows=6 width=0) (actual time=1.386..6.012 rows=5.09 loops=1067)
                      Rows Removed by Filter: 199995
        SubPlan 2
          ->  Aggregate  (cost=5404.02..5404.03 rows=1 width=8) (actual time=6.083..6.083 rows=1.00 loops=1067)
                ->  Seq Scan on navigation_sessions n_1  (cost=0.00..5404.00 rows=6 width=8) (actual time=1.394..6.080 rows=5.09 loops=1067)
                      Rows Removed by Filter: 199995
Execution Time: 12916.527 ms
```

`benchmarks/results/optimized/R19.txt`, run 1:

```text
Sort  (cost=14574.64..14577.85 rows=1285 width=40) (actual time=16.840..16.863 rows=1067.00 loops=1)
  ->  Bitmap Heap Scan on places p  (cost=65.59..14507.14 rows=1285 width=40) (actual time=1.610..16.731 rows=1067.00 loops=1)
        ->  Bitmap Index Scan on places_city_category_name_idx  (cost=0.00..65.27 rows=1285 width=0) (actual time=1.438..1.438 rows=1067.00 loops=1)
        SubPlan 1
          ->  Aggregate  (cost=8.54..8.55 rows=1 width=8) (actual time=0.013..0.013 rows=1.00 loops=1067)
                ->  Index Only Scan using navigation_dest_started_idx on navigation_sessions n  (cost=0.42..8.53 rows=6 width=0) (actual time=0.012..0.013 rows=5.09 loops=1067)
                      Index Cond: (dest_place_id = p.place_id)
        SubPlan 3
          ->  Result  (cost=1.77..1.78 rows=1 width=8) (actual time=0.001..0.001 rows=1.00 loops=1067)
                ->  Limit  (cost=0.42..1.77 rows=1 width=8) (actual time=0.001..0.001 rows=0.98 loops=1067)
                      ->  Index Only Scan using navigation_dest_started_idx on navigation_sessions n_1  (cost=0.42..8.53 rows=6 width=8) (actual time=0.000..0.000 rows=0.98 loops=1067)
                            Index Cond: (dest_place_id = p.place_id)
Execution Time: 16.922 ms
```

### R13 — 14.520 ms saved on averages; intended result correction

`benchmarks/results/baseline/R13.txt`, run 1:

```text
Seq Scan on places p  (cost=5404.00..6816.52 rows=20021 width=24) (actual time=20.474..20.475 rows=0.00 loops=1)
  Filter: (NOT (ANY (place_id = (hashed SubPlan 1).col1)))
  Rows Removed by Filter: 40042
  SubPlan 1
    ->  Seq Scan on navigation_sessions n  (cost=0.00..4904.00 rows=200000 width=4) (actual time=0.005..7.836 rows=200000.00 loops=1)
Execution Time: 20.512 ms
```

`benchmarks/results/optimized/R13.txt`, run 1:

```text
Merge Anti Join  (cost=0.57..2342.72 rows=34231 width=24) (actual time=0.051..6.006 rows=33368.00 loops=1)
  ->  Index Scan using places_pkey on places p  (cost=0.29..2144.46 rows=40042 width=24) (actual time=0.002..3.613 rows=40042.00 loops=1)
  ->  Index Only Scan using navigation_known_origin_idx on navigation_sessions n  (cost=0.28..208.67 rows=200000 width=4) (actual time=0.035..0.293 rows=7416.00 loops=1)
Execution Time: 6.614 ms
```

### R03 — 13.338 ms saved on averages

`benchmarks/results/baseline/R03.txt`, run 1:

```text
Limit  (cost=1519.58..1519.63 rows=20 width=33) (actual time=13.673..13.674 rows=20.00 loops=1)
  ->  Sort  (cost=1519.58..1520.23 rows=261 width=33) (actual time=13.672..13.672 rows=20.00 loops=1)
        ->  Seq Scan on places  (cost=0.00..1512.63 rows=261 width=33) (actual time=0.070..13.611 rows=268.00 loops=1)
              Rows Removed by Filter: 39774
Execution Time: 13.687 ms
```

`benchmarks/results/optimized/R03.txt`, run 1:

```text
Limit  (cost=796.42..796.47 rows=20 width=33) (actual time=0.847..0.848 rows=20.00 loops=1)
  ->  Sort  (cost=796.42..797.07 rows=260 width=33) (actual time=0.846..0.847 rows=20.00 loops=1)
        ->  Bitmap Heap Scan on places  (cost=176.48..789.50 rows=260 width=33) (actual time=0.363..0.796 rows=268.00 loops=1)
              Recheck Cond: ((name ~~* '%biryani%'::text) AND (city_id = 1))
              ->  BitmapAnd
                    ->  Bitmap Index Scan on places_name_trgm_idx  (cost=0.00..55.63 rows=1618 width=0) (actual time=0.156..0.156 rows=1668.00 loops=1)
                    ->  Bitmap Index Scan on places_city_place_idx  (cost=0.00..120.48 rows=6425 width=0) (actual time=0.159..0.159 rows=6442.00 loops=1)
Execution Time: 0.891 ms
```

### R21 — 11.439 ms saved on averages

`benchmarks/results/baseline/R21.txt`, run 1:

```text
Sort  (cost=9205.69..9205.72 rows=12 width=17) (actual time=43.554..43.555 rows=3.00 loops=1)
  ->  HashAggregate  (cost=9205.36..9205.48 rows=12 width=17) (actual time=43.546..43.547 rows=3.00 loops=1)
        ->  Hash Join  (cost=1814.22..9185.19 rows=4033 width=9) (actual time=42.486..43.302 rows=4004.00 loops=1)
              ->  Hash Right Anti Join  (cost=1812.95..9169.60 rows=4033 width=4) (actual time=42.472..43.048 rows=4004.00 loops=1)
                    ->  Seq Scan on opening_hours h  (cost=0.00..4170.66 rows=252266 width=4) (actual time=0.011..9.596 rows=252266.00 loops=1)
                    ->  Seq Scan on places p  (cost=0.00..1312.42 rows=40042 width=8) (actual time=0.002..7.186 rows=40042.00 loops=1)
Execution Time: 43.607 ms
```

`benchmarks/results/optimized/R21.txt`, run 1:

```text
Sort  (cost=7282.40..7282.43 rows=12 width=17) (actual time=20.956..21.022 rows=3.00 loops=1)
  ->  Finalize GroupAggregate  (cost=7279.69..7282.19 rows=12 width=17) (actual time=20.947..21.014 rows=3.00 loops=1)
        ->  Gather Merge  (cost=7279.69..7281.97 rows=20 width=17) (actual time=20.944..21.010 rows=3.00 loops=1)
              ->  Partial HashAggregate  (cost=6279.34..6279.46 rows=12 width=17) (actual time=19.436..19.437 rows=1.50 loops=2)
                    ->  Parallel Hash Right Anti Join  (cost=1706.90..6268.18 rows=2232 width=9) (actual time=18.920..19.302 rows=2002.00 loops=2)
                          ->  Parallel Seq Scan on opening_hours h  (cost=0.00..3131.92 rows=148392 width=4) (actual time=0.202..7.682 rows=126133.00 loops=2)
                          ->  Parallel Seq Scan on places p  (cost=0.00..1327.54 rows=23554 width=13) (actual time=0.001..0.979 rows=20021.00 loops=2)
Execution Time: 21.080 ms
```

### R22 — 11.210 ms saved on averages

`benchmarks/results/baseline/R22.txt`, run 1:

```text
Limit  (cost=9339.48..9339.54 rows=25 width=24) (actual time=15.272..15.274 rows=25.00 loops=1)
  ->  Sort  (cost=9214.48..9439.47 rows=89998 width=24) (actual time=13.168..14.377 rows=50025.00 loops=1)
        Sort Method: external merge  Disk: 3000kB
        ->  Seq Scan on place_reviews  (cost=0.00..1739.98 rows=89998 width=24) (actual time=0.004..4.576 rows=89998.00 loops=1)
Execution Time: 15.862 ms
```

`benchmarks/results/optimized/R22.txt`, run 1:

```text
Limit  (cost=1770.27..1771.16 rows=25 width=24) (actual time=5.023..5.025 rows=25.00 loops=1)
  ->  Index Scan using place_reviews_newest_idx on place_reviews  (cost=0.29..3186.19 rows=89998 width=24) (actual time=0.008..4.179 rows=50025.00 loops=1)
Execution Time: 5.037 ms
```

## Write overhead

The change is `after average - before average`; positive values mean slower
writes. Each is the change between the three-run baseline average and the
five-run optimized average.

| Query | Before (ms) | After (ms) | Added time (ms) | Relative change |
|---|---:|---:|---:|---:|
| W01 | 0.619 | 0.969 | 0.350 | +56.54% |
| W02 | 0.514 | 0.779 | 0.265 | +51.56% |
| W03 | 0.543 | 0.805 | 0.262 | +48.25% |
| W04 | 32.294 | 54.538 | 22.244 | +68.88% |
| W05 | 2.164 | 2.070 | -0.094 | -4.34% |

The insert overheads are small in absolute time for this data set. W04 pays
the largest cost because it scans and aggregates reviews and updates places
while maintaining the added indexes. Since this workload describes W04 as a
nightly job, that added time is likely acceptable at the stated cadence, but
would need review if the job became frequent. The benchmark rolls writes back;
these measurements compare statement execution and are not a production
write-throughput test.

## Index storage

The following values are `pg_relation_size` measurements from `AMIT8080` after
the 16 retained indexes were created. “Table bytes” is the table relation size
for the table owning that index (not table plus all indexes). The total size
of the 16 added indexes is **55,894,016 bytes**.

| Added index | Table | Index bytes | Table bytes |
|---|---|---:|---:|
| incident_reports_reported_at_idx | incident_reports | 737,280 | 933,888 |
| navigation_completed_started_idx | navigation_sessions | 7,356,416 | 23,789,568 |
| navigation_dest_started_idx | navigation_sessions | 8,134,656 | 23,789,568 |
| navigation_known_origin_idx | navigation_sessions | 180,224 | 23,789,568 |
| navigation_started_at_idx | navigation_sessions | 4,513,792 | 23,789,568 |
| place_reviews_newest_idx | place_reviews | 2,031,616 | 6,881,280 |
| place_reviews_place_newest_idx | place_reviews | 4,489,216 | 6,881,280 |
| places_city_category_name_idx | places | 3,399,680 | 7,184,384 |
| places_city_place_idx | places | 917,504 | 7,184,384 |
| places_name_trgm_idx | places | 4,022,272 | 7,184,384 |
| places_open_category_geo_idx | places | 1,785,856 | 7,184,384 |
| places_open_city_category_idx | places | 1,687,552 | 7,184,384 |
| road_segments_city_road_idx | road_segments | 131,072 | 245,760 |
| saved_places_user_list_saved_idx | saved_places | 2,596,864 | 2,940,928 |
| traffic_alert_time_idx | traffic_readings | 1,482,752 | 15,204,352 |
| traffic_segment_newest_idx | traffic_readings | 12,427,264 | 15,204,352 |

The three zero-scan indexes removed from the earlier set were
`place_reviews_created_user_idx`, `places_category_idx`, and
`incident_reports_expires_at_idx`.

## Queries I could not speed up enough

“Could not speed up” here means the plans remain dominated by broad scans or
aggregation; it does not mean every average was unchanged. R21, R15, R11 and
R04 did improve, but still have material work in their plans.

| Query | Before → after average (ms) | What the latest plan shows |
|---|---:|---|
| R17 | 33.167 → 33.012 | Seq Scan reads all 200,000 sessions, then groups by destination; the destination index cannot avoid the full-table aggregate. |
| R18 | 14.574 → 14.341 | Aggregates every session by travel mode; no selective predicate can reduce the scan. |
| R25 | 26.821 → 27.976 | Parallel Seq Scan reads all traffic rows and joins all road segments before aggregation; it is slightly slower after indexing. |
| R21 | 28.258 → 16.819 | Parallel anti-join still scans opening hours and places; grouping follows. The removed category index had zero scans and would not avoid scanning hours. |
| R15 | 29.629 → 21.179 | Index-only scan still reads all 89,998 review rows for per-place aggregation, then compares every grouped place. |
| R11 | 23.215 → 13.140 | Partial index-only scan still reads 56,299 qualifying session rows, then sorts and aggregates them into month/mode groups. |
| R04 | 8.578 → 3.605 | City/category index reduces place candidates, then probes the opening-hours primary key and evaluates time predicates; first optimized run was slower while warming pages. |

## Index rationale

These are the 16 retained indexes from `sql/05_indexes.sql`; the query IDs
below match the query-specific comments next to each definition.

| Index | Query IDs in latest plans | Type and key-order rationale |
|---|---|---|
| places_open_category_geo_idx | R01 | Partial B-tree; category equality first, then latitude/longitude bounding box; omits closed places. |
| places_name_trgm_idx | R03 | GIN with `gin_trgm_ops`; supports substring `ILIKE '%text%'`. R03 combines this name bitmap with the city bitmap via `BitmapAnd`. |
| places_open_city_category_idx | R04 | Partial B-tree; city/category equalities first, then place ID for the hours join; includes rating; omits closed places. |
| place_reviews_place_newest_idx | R05, R15 | B-tree; place equality first and descending creation time for newest reviews; user ID, rating, and photo count are included, not key columns. |
| saved_places_user_list_saved_idx | R06 | B-tree; user equality first, then list name and descending saved time for requested ordering; place ID included for the join. |
| road_segments_city_road_idx | R07, R08, R10 | B-tree; city equality first, then `text_pattern_ops` road name for prefix search; segment ID included for joins. |
| traffic_segment_newest_idx | R07, R09 | B-tree; segment equality first, then descending recorded time for latest-per-segment; speed and congestion included. |
| traffic_alert_time_idx | R08 | Partial B-tree; time range/order first, segment second for join; includes output fields and only heavy/standstill rows. |
| incident_reports_reported_at_idx | R10 | B-tree; reported time first for day range/order; segment and projected incident fields included. |
| navigation_completed_started_idx | R11 | Partial B-tree; started time first for year range; completed status is fixed by predicate and aggregate fields are included. |
| navigation_dest_started_idx | R19 | B-tree; destination equality first, descending start time for latest lookup; reroute count included. |
| places_city_place_idx | R03, R12 | B-tree; city equality first, place ID second for place lookup/join. R03 combines it with the trigram bitmap. |
| navigation_known_origin_idx | R13 | Partial B-tree; origin equality supports anti-join and excludes NULL origins that cannot match a place. |
| navigation_started_at_idx | R12, R16, R20 | B-tree; started time is the range predicate and supports index-only access for R20. |
| place_reviews_newest_idx | R14, R22 | Descending B-tree on creation time; supports the recent review range and newest-first pagination without a sort. |
| places_city_category_name_idx | R19, R24 | B-tree; city/category equalities first, then name and place ID for candidate matching; coordinates included for distance checks. |

R03’s latest five-run plans all use both `places_name_trgm_idx` and
`places_city_place_idx` in a `BitmapAnd`; the five-run average is 0.750 ms.
