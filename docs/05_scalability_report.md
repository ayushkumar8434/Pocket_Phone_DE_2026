# Phase 5 — Scalability report

## Status and measurement scope

The committed benchmark results measure the 200,000-session seed database,
not the faculty large database. On 16 Nov 2026, `large_data.zip` has not been
released into this workspace (the project brief schedules it for 19 Nov), and
`psql` is not installed here. Therefore no large-database timings, plans, or
database-size measurements are claimed below. The large result columns are
intentionally pending rather than estimated.

Seed averages below are from
[`benchmarks/results/optimized/summary.csv`](../benchmarks/results/optimized/summary.csv)
and use the five-run Phase 4 benchmark. The large run must use three runs as
required by the Phase 5 brief. Run it against a separate database after loading
the faculty files, applying `05_indexes.sql`, and running `ANALYZE`:

```sh
./benchmarks/run_benchmark.sh <large_db> large 3 sql/06_optimized_queries.sql
```

This runs the optimized workload only; the script rolls back W01–W05. It
creates one raw plan file per query and fills
`benchmarks/results/large/summary.csv`. That CSV currently contains only its
header, and no large raw plans exist yet. Do not interpret the seed timings as
large-target results.

## Results versus Phase 5 targets

The target column is the required average threshold on the large dataset.
`Pending` means the target has not yet been measured. Seed results happen to
be below these thresholds, but that is not evidence that the large dataset
passes.

| Query | Seed optimized avg (ms) | Large avg (ms) | Growth (large ÷ seed) | Large target |
|---|---:|---:|---:|---:|
| R01 | 0.212 | Pending | Pending | < 5 ms |
| R02 | 0.091 | Pending | Pending | < 5 ms |
| R03 | 0.750 | Pending | Pending | < 250 ms |
| R04 | 3.605 | Pending | Pending | < 5 ms |
| R05 | 0.174 | Pending | Pending | < 5 ms |
| R06 | 0.137 | Pending | Pending | < 5 ms |
| R07 | 1.749 | Pending | Pending | < 5 ms |
| R08 | 0.065 | Pending | Pending | < 5 ms |
| R09 | 0.102 | Pending | Pending | < 250 ms |
| R10 | 0.068 | Pending | Pending | < 5 ms |
| R11 | 13.140 | Pending | Pending | < 5,000 ms |
| R12 | 1.801 | Pending | Pending | < 250 ms |
| R13 | 5.537 | Pending | Pending | < 250 ms |
| R14 | 6.352 | Pending | Pending | < 5,000 ms |
| R15 | 21.179 | Pending | Pending | < 5,000 ms |
| R16 | 9.191 | Pending | Pending | < 5,000 ms |
| R17 | 33.012 | Pending | Pending | < 5,000 ms |
| R18 | 14.341 | Pending | Pending | < 5,000 ms |
| R19 | 5.726 | Pending | Pending | < 5,000 ms |
| R20 | 1.416 | Pending | Pending | < 5,000 ms |
| R21 | 16.819 | Pending | Pending | < 5,000 ms |
| R22 | 4.469 | Pending | Pending | < 250 ms |
| R23 | 0.081 | Pending | Pending | < 5 ms |
| R24 | 4.053 | Pending | Pending | < 250 ms |
| R25 | 27.976 | Pending | Pending | < 5,000 ms |
| W01 | 0.969 | Pending | Pending | < 5 ms |
| W02 | 0.779 | Pending | Pending | < 5 ms |
| W03 | 0.805 | Pending | Pending | < 5 ms |
| W04 | 54.538 | Pending | Pending | < 2,000 ms |
| W05 | 2.070 | Pending | Pending | < 2,000 ms |

The seed run is below the listed threshold for all 30 queries. This is only a
baseline check: large-data target status remains unassessed until the pending
run is recorded and its plans reviewed.

## Growth analysis and known pressure points

The supplied scale-up is expected to contain about 4,000,000 navigation
sessions, 5,000,000 traffic readings, 5,045,000 opening-hours rows, 801,000
places, and 1,800,000 reviews. Those are expected row counts, not counts
verified from a large-data load. No measured growth ratios are available yet;
the following are plan-based expectations to test, not results:

* **Likely to stay near constant for bounded lookups:** R02 and R23 use unique
  keys; R05/R06 and R08/R10 use selective indexes and return limited result
  sets. B-tree lookups grow slowly, though cache misses, index height, and
  contention can still increase latency. R01/R04/R07 have selective access
  paths but should be verified at the new cardinalities.
* **Likely to grow with the rows read:** R11 scans 56,299 qualifying session
  index entries at seed scale and takes 13.140 ms. R17 scans all 200,000
  sessions and takes 33.012 ms; R18 also aggregates the full session table.
  R15 aggregates all review rows, R21 scans places and opening hours, and R25
  aggregates traffic readings. If their qualifying fractions stay similar,
  these scans and aggregates grow approximately with table size.
* **Selectivity-dependent:** R12, R16, and R20 use timestamp ranges. Their
  growth depends on whether the large input preserves the date span or adds
  more rows within the same dates. R14 similarly depends on review-date
  distribution. R19's destination index removed the seed-scale repeated
  full-table scans, but its number of per-place probes can rise as the number
  of matching hospitals grows.
* **Potentially worse with workload shape:** R22 uses `OFFSET 50000`; the
  fixed query still walks past 50,000 ordered entries, but deeper pages become
  progressively more expensive. Replace application pagination with a
  stable keyset cursor (`created_at`, then `review_id`) before clients request
  deep pages. The supplied benchmark query remains unchanged for comparability.

### What the seed plans say can break

No scale-only failure has been observed because the large run is pending.
Existing plans already expose the pressure to watch:

* R17 and R18 remain full `navigation_sessions` scans; adding more ordinary
  indexes cannot eliminate their all-row aggregates.
* R11 reads tens of thousands of qualifying sessions and sorts/groups them.
  At 20× density, the annual report may approach a million input rows.
* R21, R15, and R25 are broad anti-join/aggregation workloads; their work is
  tied to opening-hours, reviews, and traffic row counts.
* W04 grew from 32.294 ms before tuning to 54.538 ms after tuning on seed
  data. It recomputes all review aggregates and updates places while
  maintaining indexes. Its batch target is generous, but large-run latency
  and WAL volume need to be checked.
* The R19 optimized five-run average is 5.726 ms, with a 2.788–16.922 ms
  observed run range in its raw plans. It is well below the analytics target
  at seed scale but has noticeable run-to-run variation.

If a large run misses target, retain its before-fix plan, make the smallest
query/index/summary change that addresses the measured plan, then save an
after-fix plan and rerun that query on the large database. Do not infer a fix
from the expected row count alone.

## Storage

Actual seed index sizes are available from the Phase 4 report; total database
sizes for either dataset are not available in this workspace. The four
optimized navigation indexes total **20,185,088 bytes** on the
**23,789,568-byte** seed navigation table. They are about 85% of that table's
heap size, before free space, WAL, or any other indexes are counted.

| Navigation relation component | Seed measured (bytes) | 20× linear estimate (bytes) | 100× linear estimate (bytes) |
|---|---:|---:|---:|
| `navigation_sessions` table | 23,789,568 | 475,791,360 | 2,378,956,800 |
| Four Phase 4 navigation indexes | 20,185,088 | 403,701,760 | 2,018,508,800 |
| Table + those indexes | 43,974,656 | 879,493,120 | 4,397,465,600 |

The 20× and 100× figures are arithmetic extrapolations from seed relation
sizes, not observed storage. They assume unchanged row width, partial-index
selectivity, and index bloat; actual sizes can differ. They exclude every
other table/index, TOAST, free space, replication, and temporary migration
copies. Measure the complete database and relation split on both loaded
databases using:

```sql
SELECT pg_size_pretty(pg_database_size(current_database())) AS database_size;

SELECT c.relname AS table_name,
       pg_size_pretty(pg_relation_size(c.oid)) AS heap_size,
       pg_size_pretty(pg_indexes_size(c.oid)) AS indexes_size,
       pg_size_pretty(pg_total_relation_size(c.oid)) AS total_size
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'gmaps' AND c.relkind IN ('r', 'p')
ORDER BY pg_total_relation_size(c.oid) DESC;
```

## 100× architecture proposal

### Partitioning

Partition `navigation_sessions` by **RANGE (`started_at`)**, monthly. The
window makes R11/R12/R16/R20 prune old periods, supports time-based archiving,
and bounds per-partition maintenance. The 20× projection is roughly 4 million
sessions; a 100× projection from the 200,000-row seed is roughly 20 million.
Those are planning inputs, not evidence that a specific server is saturated.
[`sql/08_partitioning.sql`](../sql/08_partitioning.sql) builds a staged,
monthly partitioned copy over the seed time span plus a DEFAULT partition,
copies the loaded table, creates the relevant indexes, and runs an EXPLAIN
pruning check. Execute it on a disposable/staging database: it temporarily
duplicates the navigation table and must not be used as part of the large
benchmark setup.

PostgreSQL requires every `PRIMARY KEY` or `UNIQUE` constraint on a
partitioned table to include all partition-key columns. The staged table
therefore has `PRIMARY KEY (session_id, started_at)`, which does **not** by
itself enforce global uniqueness of `session_id`. Keep IDs globally unique
through a central sequence/ID allocator or a small unpartitioned ID registry
if that database-enforced guarantee is required. Validate foreign-key and
application assumptions before swapping the staged table into service.

### Sharding

Do not shard merely because the projected row count is larger. First measure
CPU, storage, WAL, write latency, and replica lag on the partitioned primary;
20 million sessions may remain manageable on one PostgreSQL cluster.
If a single writer becomes the bottleneck, shard location-local entities by
**city/region** so places, road segments, and traffic for a map region can be
co-located. Place/session queries can route by destination city, but a user's
history then fans out across regions, and cross-city journeys, R13, and global
aggregates (R11, R17, R18, R20, R25) need scatter/gather or asynchronous
global summaries. Avoid sharding navigation sessions by user alone: R12/R16
and map/traffic operations are location-oriented. Use a separate global ID
allocator and plan for hot-city skew; a city key alone is not guaranteed to
balance load.

### Replicas and cache

Send R11–R22 and R25 reporting reads to asynchronous read replicas where their
freshness tolerance permits; R13/R15/R16/R21/R24 are also suitable for
replicas for data-quality runs. R19/R20 can use materialized hourly/daily
summaries on a replica instead of repeatedly aggregating base facts. Route
W01–W05 and any read-after-write operation to the primary. R07/R08/R10 can
use a replica only while observed lag remains inside the one-minute live-layer
freshness budget; otherwise use the primary.

Cache stable place/category details and repeated search results briefly, with
invalidation on place/review/hour changes. Cache or publish the latest traffic
snapshot with a 30–60 second TTL, bounded by the one-minute freshness
requirement. Do not cache personalized or mutable results without including
their user/filter inputs in the key and defining invalidation. Moderation
pagination should use a `(created_at, review_id)` cursor rather than relying
on cached deep `OFFSET` pages.

### Maintenance and retention

Pre-create future monthly partitions before each month starts and alert on
rows landing in DEFAULT. Run `ANALYZE` after bulk loads and partition
attachment; monitor per-partition dead tuples, index size, autovacuum lag, and
replica lag. Tune per-table autovacuum scale factors only from observed write
rates and vacuum duration; avoid a fixed aggressive setting that causes
unnecessary I/O. Use routine `VACUUM (ANALYZE)` where autovacuum is not
keeping up, and schedule index maintenance only when bloat measurements
justify it.

Detach and archive closed time partitions only under an approved retention
policy; keep the archive queryable for historical reports. Refresh
materialized ETA/destination summaries incrementally or on a scheduled
cadence, publish their freshness timestamp, and monitor refresh cost. Back up
partition DDL and verify restore/replication procedures as partitions are
added or detached.

## Conclusion

The seed evidence supports the indexing work for the current workload: the
optimized report records a 98.26% reduction in the sum of the 30 averages.
Several broad aggregates remain linear in the rows they read, while selective
queries have useful index paths. The design has a credible 20×/100× path
through partition pruning, measured capacity gates, replicas, and (only if
needed) region-aware sharding. It is **not yet proven ready for 20×**: the
large dataset has not been benchmarked, target status and full storage are
pending, and the large plans must be reviewed before claiming a scale pass.
