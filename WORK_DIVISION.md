# Work Division — Google Maps Navigation DBMS Project (DE repo)

This file records who owns which checkpoint/phase in this repository. The project
is strictly sequential — each checkpoint's deliverables depend on the previous
one's schema/queries — so the work is split by checkpoint, with the Group Lead
laying the foundation that the others build on.

Deadlines and file lists come from [`CHECKPOINTS.md`](CHECKPOINTS.md) and [`README.md`](README.md).

## Team

| Role | Name | Enrollment No. | GitHub | Checkpoints owned |
|---|---|---|---|---|
| Group Lead | **Ayush Kumar** | 2501010544 | ayushkumar8434 | **CP1** |
| Member 2 | **Amit Pal** | 2501010667 | amit-codes0836 | **CP2 + CP3** |
| Member 3 | **Prince Kumar Singh** | 2501010351 | the-prince-oss | **CP4** |

Repository: https://github.com/ayushkumar8434/Pocket_Phone_DE_2026

---

## Division

### Ayush Kumar (Group Lead) — CP1 · due Mon 16 Nov 2026 — ✅ doing now
**Phase 1 (Problem understanding) + Phase 2 (Schema design & load).** This is the
foundation every later phase runs against, so the lead owns it and lands it first.

Deliverables (all committed by the lead):
- `docs/01_problem_understanding.md` — P1–P8 restated, stakeholders, RT/RPT classification
- `sql/01_schema.sql` — `gmaps` schema: types, PK/FK, UNIQUE, ≥12 CHECK constraints, no tuning indexes
- `sql/02_load_data.sql` — `\copy` in dependency order + row-count verification
- `docs/02_schema_design.md` — data dictionary, ER, FDs/normal form, integrity checks, data problems
- `diagrams/er_diagram.png` (+ `er_diagram.mmd` source)

Unblocks: Amit's baseline (needs the schema loaded) and Prince's large-data run (needs the same schema + load script).

### Amit Pal (Member 2) — CP2 + CP3 · due Tue 17 + Thu 19 Nov 2026
**Phase 3 (Baseline timings) + Phase 4 (Optimization).** Measures today's speed,
then makes it fast without changing results.

Prerequisites: Ayush's `01_schema.sql` + `02_load_data.sql` loaded into a database.

Deliverables:
- CP2: `docs/03_baseline_timings.md` + `benchmarks/results/baseline/summary.csv` (+ raw plans R01…W05)
  - Run `./benchmarks/run_benchmark.sh <db> baseline`; 3 runs each, average; scan type + reason per query
- CP3: `sql/05_indexes.sql`, `sql/06_optimized_queries.sql`, `docs/04_optimization_report.md` + `benchmarks/results/optimized/summary.csv`
  - Indexes each justified; rewritten queries prove equal results; **find the wrong-result query (R13, NULL-in-subquery) and fix it**; report write-overhead and index storage
  - Run `./benchmarks/run_benchmark.sh <db> optimized 5 sql/06_optimized_queries.sql`

Unblocks: Prince's large-data run (needs the optimized queries `06_optimized_queries.sql` and indexes `05_indexes.sql`).

### Prince Kumar Singh (Member 3) — CP4 · due Mon 23 Nov 2026
**Phase 5 (Scalability).** Proves the design survives 20× and proposes 100×.

Prerequisites: Ayush's schema + load script, Amit's `05_indexes.sql` + `06_optimized_queries.sql`; faculty's `large_data.zip` (released ~Thu 19 Nov).

Deliverables:
- `docs/05_scalability_report.md` — results vs targets, growth analysis, what broke at scale, storage, partitioning + sharding + replicas + maintenance design, conclusion
- `sql/08_partitioning.sql` — `navigation_sessions` partition DDL (RANGE on `started_at`) + pruning proof
- `benchmarks/results/large/summary.csv` (+ raw plans) — run optimized queries on the large database only

---

## Dependency chain
```
CP1 (Ayush: schema + load)  ──►  CP2/CP3 (Amit: baseline + optimize)  ──►  CP4 (Prince: scale)
```
Each person commits their own files. **Every member must commit** (the tracker counts commits per author), so do not push someone else's work for them — push only your own checkpoint, then let the next person pull and continue.

## Conventions for everyone
- Branch: `main` (default branch; the tracker reads it).
- Never commit `seed_data/` or `large_data/` CSVs (`.gitignore` excludes them).
- Every timing number in a report must match a raw plan file under `benchmarks/results/` — invented numbers score 0 for the whole phase.
- Keep `queries/workload_30.sql` and `benchmarks/run_benchmark.sh` untouched (given).
