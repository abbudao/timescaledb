# T1: Reproducer and benchmark harness

Branch: `probe/harness` (from the base branch). No engine code changes.

## Goal

One repeatable harness that every other task is measured with. It loads twin
hypertables, one keyed by `DATE` and one by `TIMESTAMPTZ`, shaped like the
customer's data, runs a fixed query set, compresses, and emits CSVs with the
numbers the scorecard needs. Plus a one-command reproducer that prints the
chunk-exclusion gap side by side.

## Allowed paths

- `experiments/date-probe/harness/**`
- `experiments/date-probe/results/**`
- `experiments/date-probe/bin/**` (only if a shared helper is needed)

Forbidden: everything else. In particular no changes under `src/`, `tsl/`,
`sql/`, `test/`.

## Design

### Cluster

The regression runner's temporary instance is not suitable for benchmarks.
Provide `harness/pg/start.sh` and `harness/pg/stop.sh` that, as the `postgres`
OS user, `initdb` a dedicated cluster in `experiments/date-probe/.pgdata`
(gitignored), on port 5433, with:

```
shared_preload_libraries = 'timescaledb'
timescaledb.telemetry_level = off
shared_buffers = 2GB
work_mem = 64MB
maintenance_work_mem = 512MB
max_worker_processes = 16
timezone = 'UTC'
log_directory = 'log'
```

`start.sh` is idempotent: it initializes only when `.pgdata` is missing and
starts only when not running. All SQL runs as `psql -X -p 5433 -U postgres`.

### Schema

Parameterized by psql variables so variants are just different invocations:
`:days`, `:devices`, `:rows_per_device_day`, `:chunk_interval` (text like
`'7 days'`), `:with_index` (`true|false`), `:orderby` (text, empty for the
default).

```sql
CREATE TABLE metrics_date (
    day        date        NOT NULL,
    device_id  int         NOT NULL,
    region_id  int         NOT NULL,
    seq        bigint      NOT NULL,   -- ingest order, used only by the tiebreaker variant
    v1         float8,                 -- smooth per-device series: ordering matters for compression
    v2         float8,                 -- random
    v3         int,
    status     text                    -- three distinct values
);
CREATE TABLE metrics_tstz (LIKE metrics_date INCLUDING ALL);
ALTER TABLE metrics_tstz DROP COLUMN day, ADD COLUMN ts timestamptz NOT NULL;
```

Create both as hypertables with `by_range(<col>, interval :chunk_interval)`
and `create_default_indexes => :with_index`. Enable compression with
`timescaledb.compress_segmentby = 'device_id'` and, when `:orderby` is
non-empty, `timescaledb.compress_orderby = :orderby`. When empty, leave the
default so T4's heuristic is what gets measured.

Replace the defaults below with the customer's real numbers as soon as they
are known and record them in `harness/README.md`.

| Scale | days | devices | rows per device per day | rows |
|---|---|---|---|---|
| `small` (default, minutes) | 400 | 200 | 24 | 1.92 M |
| `customer` (T6 only) | 1095 | 2000 | 24 | 52.6 M |

### Load

Generate rows with `generate_series` in batches of one day per transaction so
memory stays flat. `v1` must be temporally correlated per device, for example
`sin(day_index / 30.0) * 100 + device_id + random()`, so that batch ordering
has a measurable effect on compression. `seq` is a running counter in
generation order. The `TIMESTAMPTZ` twin receives identical rows with
`ts = day::timestamptz` at midnight UTC, so the two tables carry the same
information and differ only in the column type. Record insert throughput as
rows per second per table.

### Compression

Compress every chunk of both tables, then `VACUUM ANALYZE`. Record wall time.

### Queries

Six queries, run against both tables with the time column and literal types
adjusted. Use psql variables `:tbl` and `:col`.

| id | shape | why |
|---|---|---|
| Q1 | `WHERE :col >= now() - interval '30 days'` | the cross-type shape with no exclusion today on DATE |
| Q2 | `WHERE :col >= current_date - 30` (DATE) / `>= date_trunc('day', now()) - interval '30 days'` (TSTZ) | same-type stable bound, runtime exclusion only |
| Q3 | `WHERE :col >= '<d1>' AND :col < '<d2>'` for a 31-day window in the middle of the data | immutable literals, plan-time exclusion baseline |
| Q4 | `SELECT time_bucket('7 days', :col), device_id, avg(v1) ... WHERE <Q3 range> GROUP BY 1,2` | bucketing plus vectorized aggregation |
| Q5 | `WHERE device_id = 17 AND :col = '<d>'` | point lookup, equality, segmentby hit |
| Q6 | daily continuous aggregate over `v1`, `CALL refresh_continuous_aggregate(...)` over the full range | cagg path on DATE |

Run Q1 to Q5 three times each with
`EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON)` and store the JSON in a table
`probe_plans(run_id, variant, tbl, query_id, run, plan jsonb)` in the same
database. Extract metrics from the JSON with jsonb path queries, never by
grepping text:

- `planning_ms`, `exec_ms` (report the median of three)
- `shared_hit`, `shared_read` summed over the top node
- `chunks_in_plan`: count of scan nodes whose `Relation Name` matches `_hyper_%` or `compress_hyper_%`
- `chunks_excluded_startup`: the `Chunks excluded during startup` field of the ChunkAppend node, 0 if absent
- `vectorized_filter`: whether any node carries a `Vectorized Filter` key
- `rows`: actual rows of the top node

Q6 records refresh wall time only.

### Storage

After compression, for each table:

- `hypertable_detailed_size` and `chunk_compression_stats` totals
- per-column compressed bytes: dynamic SQL over the compressed chunks found
  through `_timescaledb_catalog.chunk` (`compressed_chunk_id`), summing
  `pg_column_size(<col>)` per column, plus `avg(_ts_meta_count)` as batch fill
- heap bytes per row and index bytes per row before compression, taken from a
  snapshot before the compress step

### Outputs

`harness/run.sh --variant <name> --scale small|customer [--chunk-interval ..]
[--no-index] [--orderby ..]` runs everything above and writes:

- `results/<variant>-<short sha>-queries.csv` with one row per
  (tbl, query_id, run) and the metric columns above
- `results/<variant>-<short sha>-storage.csv` with one row per (tbl, column)
  plus one total row per table
- `results/<variant>-<short sha>-summary.md`, a short table for humans

`harness/repro.sh` prints `EXPLAIN (ANALYZE, BUFFERS, COSTS OFF, TIMING OFF,
SUMMARY OFF)` of Q1 for both tables in text form and saves it to
`results/repro-<short sha>.txt`. This file is the evidence attached to the
upstream issue later.

Variants to support from day one, selected by flags, not by editing SQL:

| variant | what changes |
|---|---|
| `baseline` | defaults above |
| `reorder` | column order `day, device_id, region_id, v3, seq, v1, v2, status` to remove alignment padding |
| `tiebreaker` | `--orderby 'day DESC, seq DESC'` |
| `interval-1d`, `interval-30d` | chunk interval |
| `no-index` | `create_default_indexes => false` |

## Steps

1. `harness/pg/start.sh`, `stop.sh`; verify `SELECT extversion FROM pg_extension`.
2. `harness/sql/*.sql` in the order setup, schema, load, snapshot, compress, queries, storage.
3. `harness/run.sh`, `harness/repro.sh`, `harness/README.md` documenting knobs and how to add a query.
4. Run `run.sh --variant baseline --scale small` on unmodified code and commit the three result files plus the repro text.
5. Report.

## Done criteria

- `run.sh --variant baseline --scale small` completes in under 20 minutes on 4 cores and leaves no background process running.
- The repro shows Q1 on `metrics_date` with `chunks_excluded_startup = 0` and every chunk scanned, and Q1 on `metrics_tstz` with startup exclusion.
- Baseline CSVs and the repro are committed under `results/`.
- `git status` shows no changes outside `experiments/`.

## Report

Use the template in `experiments/date-probe/README.md`. Include the baseline
summary table inline and the per-column storage table for `metrics_date`.
