# DATE probe harness

One repeatable benchmark for every task of the probe. It loads twin
hypertables that differ only in the type of their time column, runs a fixed
query set against both, compresses them, and writes CSVs plus a human summary
under `experiments/date-probe/results/`.

Nothing here touches engine code. Tasks that do change the engine run this
same harness before and after their change and compare the CSVs.

```
harness/
  pg/start.sh pg/stop.sh   dedicated benchmark cluster on port 5433
  sql/                     the steps, in order: setup schema load snapshot
                           compress queries cagg storage export-* summary
  run.sh                   one variant end to end -> 3 result files
  repro.sh                 the chunk-exclusion evidence, Q1 side by side
```

## Running it

The harness exercises the system-wide extension, which every worktree on this
machine shares, so it runs under the install lock and right after installing
your own build:

```bash
experiments/date-probe/bin/locked.sh bash -c \
  'make -C build install && experiments/date-probe/harness/run.sh --variant baseline --scale small'

experiments/date-probe/bin/locked.sh bash -c \
  'make -C build install && experiments/date-probe/harness/repro.sh'
```

`run.sh` restarts the cluster, drops and recreates the database, loads,
measures and stops the cluster again, so nothing is left running. The restart
matters: the postmaster loads `timescaledb` through
`shared_preload_libraries` and keeps that copy for its whole life, so a
cluster left running from an earlier session would serve the build that was
installed back then, possibly from another worktree. `repro.sh` reuses the
database `run.sh` left behind (the data directory survives the stop), so run it
after `run.sh`, with the same `--db` if you changed it.

Baseline numbers are only valid from a worktree that is unmodified apart from
`experiments/`.

## Cluster

`pg/start.sh` initializes `experiments/date-probe/.pgdata` (gitignored) on port
5433 and starts it. PostgreSQL refuses to run as root, so the data directory is
owned by the `postgres` OS user and every server command goes through
`runuser -u postgres`; the script also makes the directories above `.pgdata`
traversable, which a git worktree under a root-owned home is not by default.
Both scripts are idempotent. Settings: `shared_preload_libraries=timescaledb`,
telemetry off, `shared_buffers=2GB`, `work_mem=64MB`,
`maintenance_work_mem=512MB`, `max_worker_processes=16`, `timezone=UTC`.

`pg/stop.sh --destroy` also deletes the data directory; use it when a schema
change makes the old database useless.

All SQL runs as `psql -X -p 5433 -U postgres`.

## Schema

```sql
metrics_date(day date, device_id int, region_id int, seq bigint,
             v1 float8, v2 float8, v3 int, status text)
metrics_tstz(... same, with ts timestamptz instead of day)
```

Both are hypertables partitioned `by_range(<time col>, interval :chunk_interval)`
and compressed with `timescaledb.compress_segmentby = 'device_id'`; the orderby
is left at the default unless `--orderby` is given, so T4 measures the default
heuristic.

The twins receive exactly the same rows: each day is generated once into a
staging table and inserted into both, with `ts = day::timestamptz` (midnight
UTC). Insert throughput is therefore measured on the same workload for both.

`v1` is a smooth per-device series,
`round(sin((day_index + r/rows_per_day)/30)*100 + device_id + random()*0.1, 3)`,
so it is temporally correlated inside a day as well as across days and batch
ordering has something to recover. (The brief suggests
`sin(day_index/30)*100 + device_id + random()`; the intra-day ramp and the
smaller noise term were added so the orderby tiebreaker of T4 can show an
effect at all.) `v2` is random noise, `v3` a small int, `status` one of three
strings, `seq` a running counter in generation order.

## Scales

| scale | days | devices | rows/device/day | rows | wall time on 4 cores |
|---|---|---|---|---|---|
| `smoke` | 20 | 20 | 4 | 1.6 k | ~1 min, for checking the harness itself |
| `small` (default) | 400 | 200 | 24 | 1.92 M | ~7 min |
| `customer` (T6 only) | 1095 | 2000 | 24 | 52.6 M | hours, not run here |

The data always ends today (`--start-date` defaults to `today - days + 1`), so
the `now()`-based queries select the most recent 30 days of real data. Pass
`--start-date` to pin a range and make a run comparable to an older one.

**The `customer` row is still the brief's placeholder.** Replace `DAYS`,
`DEVICES` and `RPD` in `run.sh` with the customer's real numbers as soon as
they are known, and note them here.

## Variants

Selected by flags, never by editing SQL. The variant name is both the result
file prefix and a preset; explicit flags win over the preset.

| variant | what changes | flags it presets |
|---|---|---|
| `baseline` | defaults | none |
| `reorder` | column order `day, device_id, region_id, v3, seq, v1, v2, status` | `--reorder` |
| `tiebreaker` | deterministic order inside a batch | `--orderby 'day DESC, seq DESC'` |
| `interval-1d` | chunk interval | `--chunk-interval '1 day'` |
| `interval-30d` | chunk interval | `--chunk-interval '30 days'` |
| `no-index` | no default indexes | `--no-index` |

`--orderby` is written against `metrics_date`; the harness renames the word
`day` to `ts` for the twin. Other flags: `--db NAME`, `--keep` (leave the
cluster up), `--start-date`.

## Query set

| id | shape | why |
|---|---|---|
| Q1 | `WHERE <col> >= now() - interval '30 days'` | cross-type shape; no exclusion on DATE today |
| Q2 | `>= current_date - 30` / `>= date_trunc('day', now()) - interval '30 days'` | same-type stable bound, runtime exclusion only |
| Q3 | `>= d1 AND < d2`, 31 days in the middle | immutable literals, plan-time exclusion baseline |
| Q4 | `time_bucket('7 days', col), device_id, avg(v1), max(v2)` over the Q3 window | bucketing plus vectorized aggregation |
| Q5 | `device_id = 17 AND <col> = d` | point lookup, segmentby hit |
| Q6 | daily continuous aggregate over `v1`, refreshed over the whole range | cagg path on DATE |

Q1 to Q5 run three times each under `EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON)`;
the plans are stored in `probe_plans` and the reported number is the median of
the three. Q6 records refresh wall time only.

To add a query: give it an id, add a `probe_explain(...)` call built with
`format()` in `sql/queries.sql` exactly like the others, and add a row to the
table above. Nothing else needs to change; the metric extraction, CSVs and
summary pick it up automatically.

## Metrics

Extracted from the stored plan JSON in SQL (view `probe_query_metrics`), never
by grepping text. The plan tree is walked by `probe_plan_nodes()`, a recursive
CTE that yields every node exactly once; `jsonb_path_query(plan, '$.**')` is
not used, because in lax mode recursive descent returns each node twice (once
inside its `Plans` array and once unwrapped) and every sum over nodes doubles.

| column | how |
|---|---|
| `planning_ms`, `exec_ms` | `Planning Time`, `Execution Time`; CSV keeps all three runs, the summary reports the median |
| `shared_hit`, `shared_read` | `Shared Hit/Read Blocks` of the top node (cumulative over children) |
| `chunks_in_plan` | DISTINCT relation names matching `_hyper_<n>_<n>_chunk` |
| `compressed_chunks_in_plan` | DISTINCT relation names matching `compress_hyper_%` |
| `chunk_scan_nodes` | raw count of scan nodes on either, the brief's literal wording |
| `chunks_excluded_startup` | sum of `Chunks excluded during startup` over the plan, 0 when absent |
| `vectorized_filter` | any node carries a `Vectorized Filter` key |
| `rows` | actual rows of the top node (1 for the aggregate queries) |
| `scan_rows` | rows summed over the chunk scan nodes, i.e. how much data was really touched; `Actual Rows` is multiplied by `Actual Loops`, because EXPLAIN reports it per loop and the DATE twin often gets parallel workers |
| `workers_launched` | parallel workers the plan actually launched |

`chunks_in_plan` deviates from the brief's wording on purpose: with compression
every scanned chunk contributes two scan nodes (the chunk and its compressed
twin), so counting nodes doubles the chunk count. The literal count is kept as
`chunk_scan_nodes`.

## Result files

`run.sh` writes three files per variant, named `<variant>-<short sha>-*`:

- `*-queries.csv` — one row per (table, query, run) with the metrics above and
  the exact query text.
- `*-storage.csv` — one row per (table, column). Rows whose column name is
  parenthesized are physical table-level bytes from the size functions:
  `(heap)`, `(index)`, `(toast)`, `(total)` before and after compression;
  `(columns)` is the sum of the per-column logical bytes, which is smaller than
  `(heap)` because it excludes tuple headers and alignment padding. Per-column
  bytes are `sum(pg_column_size(col))` over the table before compression and
  over the compressed chunks after it, with `batches` and `avg_meta_count`
  (batch fill) per table.
- `*-summary.md` — the same numbers as markdown tables.

`repro.sh` writes `repro-<short sha>.txt`: Q1 on both twins under
`EXPLAIN (ANALYZE, BUFFERS, COSTS OFF, TIMING OFF, SUMMARY OFF)`, plus the same
predicate written with the column's own type for contrast.

Everything is also kept in the database (`probe_run`, `probe_timing`,
`probe_plans`, `probe_snapshot`, `probe_compstats`, `probe_storage`), so a run
can be re-analysed without repeating it: start the cluster and query
`probe_query_metrics` or `probe_query_median`.

## Caveats

- 2.31 does not register the compressed relation as a chunk:
  `_timescaledb_catalog.chunk` has no `compressed_chunk_id` column any more and
  `compression_chunk_size.compressed_chunk_id` is 0. The only link left is the
  naming convention `"<chunk table>_compressed"` in the chunk's schema
  (`tsl/src/compression/create.c`), which is what the per-column collection
  uses; it raises an error rather than reporting empty columns if a compressed
  chunk has no such relation.
- For the same reason the compressed relation shows up in plans as
  `_hyper_<n>_<n>_chunk_compressed`, not `compress_hyper_%`. The chunk-count
  patterns are anchored accordingly.
- `pg_column_size()` on a compressed column returns the stored (toasted) size
  of the batch datum, which is what "bytes per column after compression" means
  here.
- Results are timing measurements on a shared container. Compare medians of
  runs made back to back on the same machine, not absolute numbers between
  sessions.
