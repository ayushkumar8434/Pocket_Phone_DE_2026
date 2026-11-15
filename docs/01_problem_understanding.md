# Phase 1 — Problem Understanding

**Google Maps India data team.** The production database has no documented schema — only CSV exports survive — and several product teams report slow or broken queries. Below each problem is restated in business terms, the stakeholder it hurts is named, and it is classified so that performance targets in Phase 5 can be set. Classification key: **[RT]** = customer-facing / real-time (must be fast for a live user or a minute-by-minute refresh); **[RPT]** = reporting / analytics (batch or dashboard, can be slower but must not time out).

---

## P1 — "Near me" / "open now" search is too slow  *(R01, R03, R04, R23)* **[RT]**
**Business need.** A traveller standing somewhere asks Google Maps for places around them that are open right now, ranked by distance and rating, and for a place by its Plus Code. The search must return in well under a second or the user switches apps.
**Stakeholders.** Traveller/driver (the person searching) and the **Search** team.
**Why slow today.** Distance uses `acos()/cos()/sin()` on every row of `places` (40k rows) with no spatial index, and "open now" must understand places that close after midnight (`closes < opens`). Plus Code lookup has no usable index either.
**Assumptions.** "Near me" is approximated by a lat/lng bounding box plus a great-circle distance for ranking; exact routing distance is out of scope for the query.

## P2 — Place page and "Saved" tab lag  *(R02, R05, R06, W02, W03)* **[RT]**
**Business need.** When a traveller opens a place, its details, today's opening hours and the newest reviews must appear instantly; saving a place to a list and posting a review must feel instant. Business owners care because this page is their shopfront.
**Stakeholders.** Traveller, **business owner** (their listing page), and the **Places** team.
**Why slow today.** Single-place lookups by `place_id` are fine, but "newest reviews of a place" and "saved places of a user grouped by list" scan large child tables (`place_reviews`, `saved_places`) without supporting indexes.
**Assumptions.** A user may rate a place at most once (re-rating updates the same review); a user may save the same place to several different lists.

## P3 — Live traffic + incident layers must refresh every minute  *(R07, R08, R10, W05)* **[RT]**
**Business need.** Every minute the map must show the latest reading per road segment, highlight heavy/standstill congestion, and show active incidents; expired incidents are purged by a housekeeping job.
**Stakeholders.** Traveller/driver (live map) and the **Traffic** team.
**Why slow today.** "Latest reading per segment" does a `DISTINCT ON ... ORDER BY recorded_at DESC` over 250k readings; incident/alert filters do not exploit an index on time or congestion.
**Assumptions.** A "live" layer is allowed to be up to one minute stale; only congestion levels `HEAVY`/`STANDSTILL` raise alerts.

## P4 — "Typical traffic" charts and road-safety reports are slow  *(R09, R25)* **[RPT]**
**Business need.** The traffic team builds average-speed-by-hour charts for a segment and over-speed share by road type for planning and safety reports.
**Stakeholders.** **Traffic** team (analysts) and indirectly the driver (safety).
**Why slow today.** These aggregate most of `traffic_readings` per segment/type with no pre-aggregation, so they are CPU-bound scans.
**Assumptions.** Reports tolerate minutes of staleness; a reading is "over the limit" when `avg_speed_kmph > speed_limit_kmph` of its segment.

## P5 — ETA accuracy, re-routing hotspots, trends; starting navigation must be instant  *(R11, R12, R17, R18, W01)* **mixed**
**Business need.** Starting a navigation (W01) must be instant for the driver; the **Routing & ETA** team needs monthly ETA-error reports, top-destination trends, and re-routing hotspots to improve the model.
**Stakeholders.** Traveller/driver (W01) and the **Routing & ETA** team (reports).
**Why slow today.** W01 is a single insert (fine once indexed); the reports group large `navigation_sessions` by month/destination with no supporting index or summary.
**Assumptions.** ETA error = `actual_minutes − eta_minutes` for completed trips only; "re-routing hotspot" = destinations with ≥5 trips ranked by average `rerouted_count`.
**Classification.** W01 = **[RT]**; R11/R12/R17/R18 = **[RPT]**.

## P6 — "Places never used as a start point" list is empty, which is impossible  *(R13)* **[RPT]**
**Business need.** The data team's list of places never used as a navigation origin is empty — that cannot be right, so the query is wrong, not the data.
**Stakeholders.** **Data team** (internal).
**Root cause (not a tuning issue).** `NOT IN (SELECT origin_place_id ...)` returns nothing because `origin_place_id` is nullable and contains NULLs; `x NOT IN (..., NULL, ...)` is never true under SQL three-valued logic. This is the **wrong-result query** flagged in Phase 4 and must be rewritten with `NOT EXISTS`/`LEFT JOIN ... IS NULL`.
**Assumptions.** A place with no navigation at all still counts as "never used as a start point".

## P7 — Data-quality checks time out  *(R15, R16, R21, R24, W04)* **[RPT]**
**Business need.** The data-quality team must routinely find stale `avg_rating`/`review_count`, permanently-closed places still navigated to, places missing opening hours, and duplicate listings; a nightly job recomputes ratings.
**Stakeholders.** **Data-quality team**, **business owner** (stale ratings misrepresent them), and indirectly the traveller (duplicates/missing hours).
**Why slow today.** Each check joins or anti-joins a large table with no helpful index; R24 is a self-join of `places` on name + coordinate proximity.
**Assumptions.** Duplicates ≈ same name within ~100 m (`abs(lat) < 0.001 AND abs(lng) < 0.001`); ratings are stored rounded to 1 decimal.

## P8 — Leaderboards, moderation and health reports are slow; volume will grow 20×  *(R14, R19, R20, R22)* **[RPT]**
**Business need.** Local-Guide leaderboards, the moderation console (deep-paginated newest reviews), hospital health reports and daily-volume running totals must keep working as navigation volume grows ~20× next year.
**Stakeholders.** **Local Guides** (leaderboard), **moderation** team (console), **Community/Analytics** team.
**Why slow today.** R22 uses `OFFSET 50000` (row-count grows with depth); R19 uses correlated subqueries per hospital; R14/R20 aggregate `place_reviews`/`navigation_sessions` fully.
**Assumptions.** "Page 2,001 at 25/page" is `OFFSET 50000`; keyset pagination is a valid replacement and is what Phase 5 must adopt at scale.

---

### Summary table

| # | Problem | Stakeholder | Class | Queries |
|---|---------|-------------|------|---------|
| P1 | Near-me / open-now search | Search, traveller | RT | R01 R03 R04 R23 |
| P2 | Place page + Saved tab | Places, owner, traveller | RT | R02 R05 R06 W02 W03 |
| P3 | Live traffic + incident layer | Traffic, driver | RT | R07 R08 R10 W05 |
| P4 | Typical-traffic + safety reports | Traffic | RPT | R09 R25 |
| P5 | ETA accuracy, trends, start-nav | Routing/ETA, driver | RT (W01) / RPT | R11 R12 R17 R18 W01 |
| P6 | "Never a start point" empty (wrong result) | Data team | RPT | R13 |
| P7 | Data-quality checks time out | Data-quality, owner | RPT | R15 R16 R21 R24 W04 |
| P8 | Leaderboards/moderation/health + 20× growth | Community/Analytics, Local Guides, moderation | RPT | R14 R19 R20 R22 |

**Targets implied for Phase 5:** RT queries (P1–P3, W01–W03) under 5 ms; interactive search/tools under 250 ms; reports/batch (P4, P5-reports, P6–P8) under 5 s / 2 s.
