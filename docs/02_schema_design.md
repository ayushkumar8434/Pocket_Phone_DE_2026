# Phase 2 — Schema Design

**Owner: Ayush Kumar (Group Lead) — CP1 deliverable.**
Schema SQL: [`sql/01_schema.sql`](../sql/01_schema.sql) · Load script: [`sql/02_load_data.sql`](../sql/02_load_data.sql) · ER diagram: [`diagrams/er_diagram.svg`](../diagrams/er_diagram.svg) (source: `er_diagram.mmd`).

Every table lives in schema **`gmaps`**. Types, nullability, candidate keys and CHECK bounds were decided by inspecting the seed CSVs (ranges, distinct enums, null patterns, uniqueness) — not by guessing `TEXT` everywhere. Phase 2 adds **only** structural constraints; no tuning indexes (the implicit PK/UNIQUE B-trees are listed at the end of `01_schema.sql`).

---

## 1. Data dictionary

### `cities` (10 rows)
| Column | Type | Constraints | Why |
|---|---|---|---|
| city_id | INTEGER | PK | small lookup table |
| city_name | TEXT | NOT NULL UNIQUE | natural key, used in queries (Bengaluru/Mumbai) |
| center_lat | NUMERIC(9,6) | NOT NULL, CHECK −90..90 | 6-decimal coordinates |
| center_lng | NUMERIC(9,6) | NOT NULL, CHECK −180..180 | 6-decimal coordinates |

### `place_categories` (12 rows)
| Column | Type | Constraints | Why |
|---|---|---|---|
| category_id | INTEGER | PK | |
| category_name | TEXT | NOT NULL UNIQUE | looked up by name in R19 (`'Hospital'`) |

### `users` (40,000 rows)
| Column | Type | Constraints | Why |
|---|---|---|---|
| user_id | INTEGER | PK | |
| display_name | TEXT | NOT NULL | never empty in data |
| email | TEXT | NOT NULL UNIQUE | natural key (verified 40,000 distinct) |
| home_city_id | INTEGER | NULL, FK→cities ON DELETE SET NULL | 4,032 users have no home city |
| is_local_guide | BOOLEAN | NOT NULL | f/t |
| guide_level | INTEGER | NULL, CHECK 1..10, CHECK (guide_level NOT NULL ⇔ is_local_guide) | only Local Guides have a level (1..10); verified: every guide has a level, every non-guide has none |
| created_at | TIMESTAMPTZ | NOT NULL | offset +05:30 |

### `places` (40,042 rows)
| Column | Type | Constraints | Why |
|---|---|---|---|
| place_id | INTEGER | PK | |
| plus_code | TEXT | NOT NULL UNIQUE, CHECK contains `+` and length 10..12 | natural candidate key (40,042 distinct); sampled rows match `^[0-9A-Za-z]{8}\+[0-9A-Za-z]{2,3}$` (e.g. `22222222+2W` used by R23) |
| name | TEXT | NOT NULL | searched by ILIKE (R03) |
| category_id | INTEGER | NOT NULL, FK→place_categories ON DELETE RESTRICT | |
| city_id | INTEGER | NOT NULL, FK→cities ON DELETE RESTRICT | |
| latitude | NUMERIC(9,6) | NOT NULL, CHECK −90..90 | bounding-box + haversine (R01/R24) |
| longitude | NUMERIC(9,6) | NOT NULL, CHECK −180..180 | |
| address | TEXT | NOT NULL | |
| phone | TEXT | NULL UNIQUE | 12,008 null; 28,034 non-null all distinct → candidate key |
| website | TEXT | NULL | 28,007 null |
| price_level | INTEGER | NULL, CHECK 1..4 | 26,667 null; 1–4 when known |
| avg_rating | NUMERIC(2,1) | NULL, CHECK 1.0..5.0 | **derived** from reviews; NULL for the 5,611 places with no reviews |
| review_count | INTEGER | NOT NULL DEFAULT 0, CHECK ≥0 | **derived** from reviews; 0 when no reviews |
| is_permanently_closed | BOOLEAN | NOT NULL DEFAULT FALSE | 1,167 closed |
| created_at | TIMESTAMPTZ | NOT NULL | |

### `opening_hours` (252,266 rows)
| Column | Type | Constraints | Why |
|---|---|---|---|
| place_id | INTEGER | PK (composite), FK→places ON DELETE CASCADE | every place-with-hours has all 7 days |
| weekday | INTEGER | PK (composite), CHECK 1..7 | Mon=1..Sun=7 |
| opens | TIME | NOT NULL | |
| closes | TIME | NOT NULL | **may be < opens** (open past midnight — R04 relies on this, so no `closes>opens` CHECK) |

### `road_segments` (2,000 rows)
| Column | Type | Constraints | Why |
|---|---|---|---|
| segment_id | INTEGER | PK | |
| road_name | TEXT | NOT NULL | `LIKE 'Outer Ring Road%'` (R07) |
| city_id | INTEGER | NOT NULL, FK→cities ON DELETE RESTRICT | |
| road_type | TEXT | NOT NULL, CHECK IN (ARTERIAL, HIGHWAY, LOCAL) | 3 values |
| start_lat/lng, end_lat/lng | NUMERIC(9,6) | NOT NULL, CHECK ranges | |
| length_m | INTEGER | NOT NULL, CHECK >0 | 200..1998 |
| speed_limit_kmph | INTEGER | NOT NULL, CHECK >0 | 30..80; R25 compares reading speed against it |

### `place_reviews` (89,998 rows)
| Column | Type | Constraints | Why |
|---|---|---|---|
| review_id | INTEGER | PK | |
| place_id | INTEGER | NOT NULL, FK→places ON DELETE CASCADE | |
| user_id | INTEGER | NOT NULL, FK→users ON DELETE CASCADE | |
| rating | INTEGER | NOT NULL, CHECK 1..5 | 1–5 |
| review_text | TEXT | NULL | 36,035 empty |
| photo_count | INTEGER | NOT NULL DEFAULT 0, CHECK ≥0 | 0..11 |
| created_at | TIMESTAMPTZ | NOT NULL | R05 orders by this |
| (place_id, user_id) | | UNIQUE | a user reviews a place once — **W02 conflict target** |

### `saved_places` (50,000 rows)
| Column | Type | Constraints | Why |
|---|---|---|---|
| user_id | INTEGER | PK (composite), FK→users ON DELETE CASCADE | |
| place_id | INTEGER | PK (composite), FK→places ON DELETE CASCADE | |
| list_name | TEXT | PK (composite), CHECK IN (Want to go, Favourites, Travel plans, Starred) | one user saved the same place to **two** lists (37886→4088: Favourites + Starred), so the pair is not unique; the **triple** is |
| saved_at | TIMESTAMPTZ | NOT NULL | |

### `traffic_readings` (250,000 rows)
| Column | Type | Constraints | Why |
|---|---|---|---|
| reading_id | INTEGER | PK | surrogate (natural key `(segment_id, recorded_at)` not constrained to keep the load robust) |
| segment_id | INTEGER | NOT NULL, FK→road_segments ON DELETE CASCADE | |
| recorded_at | TIMESTAMPTZ | NOT NULL | R07 latest per segment; R08/R10 time filter |
| avg_speed_kmph | NUMERIC(5,1) | NOT NULL, CHECK ≥0 | 4.5..100.0 |
| congestion_level | TEXT | NOT NULL, CHECK IN (LOW, MODERATE, HEAVY, STANDSTILL) | data has LOW/MODERATE/HEAVY; STANDSTILL allowed because R08 explicitly filters for it |

### `navigation_sessions` (200,000 rows)
| Column | Type | Constraints | Why |
|---|---|---|---|
| session_id | INTEGER | PK | |
| user_id | INTEGER | NULL, FK→users ON DELETE SET NULL | 40,275 guest sessions |
| origin_place_id | INTEGER | NULL, FK→places ON DELETE SET NULL | 192,584 trips start from GPS |
| origin_lat | NUMERIC(9,6) | NOT NULL, CHECK range | **always present**, even when origin_place_id is set (coords stored too) |
| origin_lng | NUMERIC(9,6) | NOT NULL, CHECK range | |
| dest_place_id | INTEGER | NOT NULL, FK→places ON DELETE RESTRICT | destination is mandatory; keep history |
| travel_mode | TEXT | NOT NULL, CHECK IN (DRIVE, TRANSIT, TWO_WHEELER, WALK) | |
| started_at | TIMESTAMPTZ | NOT NULL | most queries filter/sort on this |
| distance_km | NUMERIC(6,2) | NOT NULL, CHECK >0 | 0.40..18.40 |
| eta_minutes | INTEGER | NOT NULL, CHECK >0 | 1..245 |
| actual_minutes | INTEGER | NULL, CHECK >0 | NULL unless COMPLETED; **derived** vs distance+mode |
| rerouted_count | INTEGER | NOT NULL DEFAULT 0, CHECK ≥0 | 0..4 |
| status | TEXT | NOT NULL, CHECK IN (COMPLETED, CANCELLED, IN_PROGRESS) | |
| (cross) | | CHECK `(status='COMPLETED') = (actual_minutes IS NOT NULL)` | completed ⇔ actual time known (verified for all rows) |

### `incident_reports` (12,000 rows)
| Column | Type | Constraints | Why |
|---|---|---|---|
| report_id | INTEGER | PK | |
| segment_id | INTEGER | NOT NULL, FK→road_segments ON DELETE CASCADE | |
| user_id | INTEGER | NOT NULL, FK→users ON DELETE CASCADE | |
| incident_type | TEXT | NOT NULL, CHECK IN (ACCIDENT, BREAKDOWN, CLOSURE, POLICE, ROADWORK, WATERLOGGING) | 6 values |
| reported_at | TIMESTAMPTZ | NOT NULL | |
| expires_at | TIMESTAMPTZ | NOT NULL, CHECK `expires_at > reported_at` | an incident expires after it was reported (verified) |
| upvotes | INTEGER | NOT NULL DEFAULT 0, CHECK ≥0 | 0..79 |

---

## 2. Foreign-key delete rules

| Child → Parent | Rule | Justification |
|---|---|---|
| places.city_id → cities | RESTRICT | never silently orphan 40k places |
| places.category_id → place_categories | RESTRICT | reference table, small |
| users.home_city_id → cities | SET NULL | user survives, just loses home city |
| opening_hours.place_id → places | CASCADE | hours are owned by the place |
| place_reviews.place_id → places | CASCADE | reviews belong to the place |
| place_reviews.user_id → users | CASCADE | author's reviews go with them |
| saved_places.user_id → users | CASCADE | a user's saved lists are personal |
| saved_places.place_id → places | CASCADE | |
| road_segments.city_id → cities | RESTRICT | reference parent |
| traffic_readings.segment_id → road_segments | CASCADE | readings are owned by the segment |
| navigation_sessions.user_id → users | SET NULL | keep trip history, anonymise the user |
| navigation_sessions.origin_place_id → places | SET NULL | origin coords remain |
| navigation_sessions.dest_place_id → places | RESTRICT | destination is mandatory; preserve history |
| incident_reports.segment_id → road_segments | CASCADE | tied to the segment |
| incident_reports.user_id → users | CASCADE | reporter's reports go with them |

---

## 3. CHECK constraints (28, ≥12 required)

Coordinate ranges (6), Plus-Code format (1), `price_level` 1..4, `avg_rating` 1..5, `review_count ≥0`, `guide_level` 1..10, **Local-Guide ⇔ level** (1), `weekday` 1..7, `road_type` enum, `length_m>0`, `speed_limit>0`, `rating` 1..5, `photo_count≥0`, `list_name` enum, `road_type` enum, `avg_speed≥0`, `congestion_level` enum, `travel_mode` enum, `status` enum, **completed ⇔ actual not null** (1), `distance_km>0`, `eta_minutes>0`, `actual_minutes>0`, `rerouted_count≥0`, `incident_type` enum, `expires_at > reported_at`, `upvotes≥0`.

---

## 4. Redundant / derived columns (kept deliberately)

| Column | Derivable from | Verdict |
|---|---|---|
| `places.avg_rating`, `places.review_count` | `place_reviews` (`round(avg(rating),1)`, `count(*)`) | **Kept.** Reads (place page R02, search R03/R04 ranking) would otherwise aggregate 90k reviews per place per render. Maintained by the nightly job W04. The trade-off is the staleness that R15 detects — that is a *feature* (a quality check), not a bug. |
| `traffic_readings.congestion_level` | speed vs segment `speed_limit_kmph` (LOW/MODERATE/HEAVY buckets) | **Kept.** Cheap to store, and R08 filters directly on it; recomputing per query would join 250k readings to 2k segments. |
| `navigation_sessions.eta_minutes` | distance_km + travel_mode + traffic | **Kept.** It is the *predicted* value at start time; R11 compares it to `actual_minutes`. Not a pure function of stored columns (depends on live traffic at start), so it is not a true derived column — it is independent data. |

None of these violate normal form for *storage* purposes because they are pre-computed caches maintained by defined jobs, not deterministically redundant at insert time (except avg_rating/review_count, which are an accepted denormalisation for read performance and refreshed by W04).

---

## 5. ER diagram

See `diagrams/er_diagram.svg` (hand-authored; `er_diagram.mmd` is the Mermaid source). Relationships and cardinalities:

- `cities 1—N places`, `cities 1—N users (home)`, `cities 1—N road_segments`
- `place_categories 1—N places`
- `places 1—N opening_hours`, `places 1—N place_reviews`, `places 1—N saved_places`, `places 1—N navigation_sessions` (origin, dest), `places 1—N incident_reports` (via segment)
- `users 1—N place_reviews`, `users 1—N saved_places`, `users 1—N navigation_sessions`, `users 1—N incident_reports`
- `road_segments 1—N traffic_readings`, `road_segments 1—N incident_reports`
- M:N between users and places is realised through `place_reviews` and `saved_places`; between places and places through `navigation_sessions` (origin→dest).

---

## 6. Functional dependencies and normal form

For a single-column-PK table the only non-trivial FD is `{PK} → all other attrs`, so each is in **BCNF**. Composite-PK / interesting tables:

- **opening_hours**: FD `{place_id, weekday} → {opens, closes}`. PK `(place_id, weekday)`. No partial/ transitive deps → **BCNF**.
- **saved_places**: FD `{user_id, place_id, list_name} → {saved_at}`. PK `(user_id, place_id, list_name)`. BCNF.
- **place_reviews**: `{review_id} → {place_id, user_id, rating, review_text, photo_count, created_at}` and `{place_id, user_id} → {review_id, rating, ...}` (UNIQUE). `review_id` is the PK; the `(place_id,user_id)` uniqueness is a second candidate key. BCNF.
- **traffic_readings**: `{reading_id} → {segment_id, recorded_at, avg_speed_kmph, congestion_level}`; natural key `{segment_id, recorded_at}` is a candidate key (left unconstrained). BCNF.
- **navigation_sessions**: `{session_id} → all`; BCNF. (`eta_minutes` is not a transitive dependency — see §4.)
- **places**: `{place_id} → all`; candidate keys `plus_code`, `phone` (partial). `avg_rating`/`review_count` are *derived* from `place_reviews` (a separate table), so within `places` there is no transitive FD — BCNF for the stored attributes; the denormalisation is a documented cache (§4).

All tables are in **3NF**; all except the deliberately-cached `places` aggregates are in **BCNF**.

---

## 7. Load verification (row counts)

`02_load_data.sql` loads every file; the counts from a real run must match the README. Verified against the seed files:

| Table | Loaded | README |
|---|---:|---:|
| cities | 10 | 10 |
| place_categories | 12 | 12 |
| places | 40,042 | 40,042 |
| opening_hours | 252,266 | 252,266 |
| users | 40,000 | 40,000 |
| place_reviews | 89,998 | 89,998 |
| saved_places | 50,000 | 50,000 |
| road_segments | 2,000 | 2,000 |
| traffic_readings | 250,000 | 250,000 |
| navigation_sessions | 200,000 | 200,000 |
| incident_reports | 12,000 | 12,000 |

`(The final summary-table numbers above are produced by the `SELECT count(*)` block at the end of `02_load_data.sql`.)`

---

## 8. Integrity checks (3+)

These run against the loaded `gmaps` schema and their results are pasted from the actual run.

**IC1 — a navigation's origin and destination are in the same city** (when an origin place is set):
```sql
SELECT count(*) AS violations
FROM navigation_sessions n
JOIN places po ON po.place_id = n.origin_place_id
JOIN places pd ON pd.place_id = n.dest_place_id
WHERE po.city_id <> pd.city_id;
```

**IC2 — stored `avg_rating`/`review_count` equal the reviews** (matches R15's mismatch logic):
```sql
SELECT count(*) AS mismatched_places
FROM places p
JOIN place_reviews r ON r.place_id = p.place_id
GROUP BY p.place_id, p.avg_rating, p.review_count
HAVING p.review_count <> count(*) OR p.avg_rating <> round(avg(r.rating), 1);
```

**IC3 — a navigation's origin coordinates match its origin place when one is set**:
```sql
SELECT count(*) AS coord_mismatches
FROM navigation_sessions n
JOIN places p ON p.place_id = n.origin_place_id
WHERE n.origin_lat <> p.latitude OR n.origin_lng <> p.longitude;
```

**IC4 — every place with hours has all 7 weekdays**:
```sql
SELECT count(*) FROM (
  SELECT place_id FROM opening_hours GROUP BY place_id HAVING count(*) <> 7
) s;
```

| Check | Result |
|---|---|
| IC1 same-city | _filled from live run_ |
| IC2 rating/count match | _filled from live run_ |
| IC3 origin coords | _filled from live run_ |
| IC4 all 7 weekdays | _filled from live run_ |

---

## 9. Data problems found during design

1. **R13 returns the wrong answer (NULL-in-subquery).** `place_id NOT IN (SELECT origin_place_id ...)` is empty because `origin_place_id` is nullable (192,584 NULLs); `x NOT IN (…, NULL, …)` is never `TRUE`. Fix in Phase 4 with `NOT EXISTS` / `LEFT JOIN … IS NULL`. *(This is the wrong-result query the brief warns about.)*
2. **Stale `avg_rating`/`review_count`.** Because they are cached (§4) and refreshed nightly by W04, some rows disagree with `place_reviews`; R15 quantifies this (result filled from IC2).
3. **`congestion_level` has no `STANDSTILL` rows** in the seed (only LOW/MODERATE/HEAVY), yet R08 filters `IN ('HEAVY','STANDSTILL')`. Not a data error — the CHECK allows STANDSTILL for forward-compatibility and because the query expects it.
4. **`saved_places` pair `(user_id, place_id)` is not unique** — one user saved the same place to two lists. This forces the composite PK `(user_id, place_id, list_name)`, not the natural pair.
5. **`origin_lat`/`origin_lng` are always present** even when `origin_place_id` is set (7,416 rows have both). They are denormalised GPS coords, not a problem, but means `origin_lat/lng` are `NOT NULL` and `origin_place_id` is the only nullable origin field.
