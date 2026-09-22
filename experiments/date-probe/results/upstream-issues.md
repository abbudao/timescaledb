# Upstream issue drafts

Drafts only. **No issue and no pull request has been opened.** Each draft
follows the fields of the repository's GitHub issue forms
(`.github/ISSUE_TEMPLATE/enhancement.yml`, `.github/ISSUE_TEMPLATE/bug_report.yml`)
and is short enough to paste into the form as is.

All numbers below are measured on this fork, TimescaleDB 2.31.0-dev on
PostgreSQL 16.15 (Ubuntu 24.04, 4 cores), by the DATE probe harness
(`experiments/date-probe/harness/run.sh`). The runs they come from are named
in each draft and their raw files are under `experiments/date-probe/results/`.

---

## Draft 1 - Enhancement: DATE dimensions get no plan-time and only partial runtime chunk exclusion

Form: `Enhancement`. Title:

> [Enhancement]: DATE hypertable dimensions get no plan-time and only partial runtime chunk exclusion for clock-derived and TIMESTAMPTZ bounds

**What type of enhancement is this?** Performance

**What subsystems and features will be improved?** Query planner, Partitioning

**What does the enhancement do?**

On a hypertable whose open dimension is a `DATE` column, the single most
common time predicate

```sql
WHERE day >= now() - interval '30 days'
```

gets neither plan-time chunk exclusion nor complete runtime exclusion, and its
filter is not vectorized. The identical table keyed by `TIMESTAMPTZ` gets all
three. Two independent gaps cause it:

1. `ts_transform_cross_datatype_comparison()`
   (`src/nodes/chunk_append/transform.c`) rewrites a `DATE` versus
   `TIMESTAMPTZ` comparison into a `DATE` versus `DATE` one only for `d > T`
   and `d <= T` (and their mirrored spellings `T < d` and `T >= d`), because
   casting the `TIMESTAMPTZ` side down to `DATE` truncates to midnight and
   only those two stay equivalent under truncation - the code says so in a
   comment. `d >= T`, `d < T` and `d = T` fall through unrewritten, so
   ChunkAppend's startup
   and runtime exclusion (`do_startup_exclusion`, `can_exclude_chunk`) and
   `find_vectorized_quals()` in the columnar scan planner see a cross-type
   expression they cannot use. `>=` is the operator nearly every "last N days"
   query is written with.
2. `constify_now()` (`src/planner/constify_now.c`) only accepts dimensions of
   type `TIMESTAMPTZ` (`is_valid_now_expr()` requires
   `F_TIMESTAMPTZ_GT`/`F_TIMESTAMPTZ_GE`), so a `DATE` dimension never gets a
   plan-time bound. The planner therefore costs and plans every chunk of the
   hypertable, and picks a parallel plan whose only job is to get through
   chunks that hold no matching rows.

**Reproducer** (self-contained, no extension changes; `experiments/date-probe/harness/repro.sh`
in the fork prints the same thing side by side against a `TIMESTAMPTZ` twin):

```sql
CREATE TABLE metrics_date(day date NOT NULL, device_id int, v1 float8);
SELECT create_hypertable('metrics_date', by_range('day', INTERVAL '7 days'));
CREATE TABLE metrics_tstz(ts timestamptz NOT NULL, device_id int, v1 float8);
SELECT create_hypertable('metrics_tstz', by_range('ts', INTERVAL '7 days'));

INSERT INTO metrics_date
SELECT (current_date - d)::date, g, random()
FROM generate_series(0, 399) d, generate_series(1, 200) g;
INSERT INTO metrics_tstz
SELECT (current_date - d)::timestamptz, g, random()
FROM generate_series(0, 399) d, generate_series(1, 200) g;

ALTER TABLE metrics_date SET (timescaledb.compress, timescaledb.compress_segmentby='device_id');
ALTER TABLE metrics_tstz SET (timescaledb.compress, timescaledb.compress_segmentby='device_id');
SELECT compress_chunk(c) FROM show_chunks('metrics_date') c;
SELECT compress_chunk(c) FROM show_chunks('metrics_tstz') c;

-- 58 chunks planned, "Chunks excluded during startup: 0", plain Filter:
EXPLAIN (ANALYZE, BUFFERS) SELECT count(*), avg(v1) FROM metrics_date
 WHERE day >= now() - interval '30 days';

-- 5 chunks planned, Vectorized Filter:
EXPLAIN (ANALYZE, BUFFERS) SELECT count(*), avg(v1) FROM metrics_tstz
 WHERE ts  >= now() - interval '30 days';

-- and the same DATE table with a DATE-typed bound does get exclusion,
-- which shows the machinery works and only the cross-type path is missing:
EXPLAIN (ANALYZE, BUFFERS) SELECT count(*), avg(v1) FROM metrics_date
 WHERE day >= current_date - 30;
```

**Before and after**, 1.92 M rows per table (400 days x 200 devices x 24
rows/day), 7-day chunks, all chunks compressed, `segmentby = device_id`,
medians of three runs on the same machine on the same day. "serial" is
`max_parallel_workers_per_gather = 0`; runs `int-baseline` (unpatched) and
`int-after` (both fixes), files
`experiments/date-probe/results/int-{baseline,after}-ac62b98-summary.md`.

| metric, `day >= now() - interval '30 days'` | before | after |
|---|---:|---:|
| execution, serial | 14.84 ms | **6.33 ms** |
| execution, parallel allowed | 22.52 ms | **6.16 ms** |
| planning | 3.69 ms | **0.63 ms** |
| planning buffers (shared hit) | 526 | **49** |
| chunks in the plan | 58 of 58 | **5** |
| vectorized filter | no | **yes** |
| parallel workers launched | 2 | **0** |
| buffers hit at execution | 6319 | 6025 |
| rows scanned | 144 000 | 144 000 |

After the change the `DATE` table matches its `TIMESTAMPTZ` twin exactly
(twin: 5.82 ms serial, 0.46 ms planning, 5 chunks, 6025 buffers).

**The effect grows with the number of chunks**, because the unconstified plan
carries every chunk in the hypertable. The same before/after at 52.56 M rows
and 157 chunks (1095 days x 2000 devices x 24 rows/day; runs
`int-baseline-customer` and `int-after-customer`):

| metric, `day >= now() - interval '30 days'`, 157 chunks | before | after |
|---|---:|---:|
| execution, serial | 531.61 ms | **61.92 ms** (8.6x) |
| execution, parallel allowed | 442.67 ms | **39.31 ms** (11.3x) |
| planning | 12.76 ms | **0.58 ms** |
| planning buffers | 1731 | **61** |
| chunks in the plan | 157 of 157 | **5** |
| vectorized filter | no | **yes** |

The `TIMESTAMPTZ` twin needs 63.25 ms serial for the same query at that scale,
so the 8.4x `DATE` penalty becomes 1.008x. No query in the set regressed:
`Q3` 52.91 → 49.46 ms and `Q4` 258.15 → 235.42 ms serial, both *faster*,
because the planner no longer carries 152 superfluous chunk relations.
Storage is untouched to the third decimal (23.265 → 23.264 bytes per row), and
so are load and compression throughput.

The same holds as chunks get smaller: with a 1-day chunk interval over the
small data set, planning goes from 36.53 ms to 2.27 ms and serial execution
from 61.30 ms to 13.52 ms (runs `defaults-1d-index-1dc07b9` and
`int-after-1d-ac62b98`).

**Implementation challenges**

Suggested as **two PRs**, which is how the prototype is split in the fork
(branches `probe/a1-runtime-transform` and `probe/a2-constify-date`):

*PR 1, runtime and vectorized exclusion.* Extend
`ts_transform_cross_datatype_comparison()` to all five operators by building
`DATE` bounds out of PostgreSQL's own functions:

```
floor(T) = date(T)
ceil(T)  = CASE WHEN timestamptz(date(T)) = T THEN date(T) ELSE date_pli(date(T), 1) END

d >  T  ->  d >  floor(T)        d <= T  ->  d <= floor(T)
d >= T  ->  d >= ceil(T)         d <  T  ->  d <  ceil(T)
d =  T  ->  d >= ceil(T) AND d <= floor(T)
```

All five rewrites are exact, not merely necessary conditions. That matters:
`find_vectorized_quals()` *replaces* the executed qual with the rewritten one
on compressed chunks, so a necessary-only rewrite of `=` would return wrong
rows. The range form of `=` is also two `Var op runtime-constant` conjuncts,
so it vectorizes, which a `d = T::date AND midnight(T)` form would not.

*Timezone safety.* The rewrite is evaluated at execution with the session's
timezone, exactly as PostgreSQL evaluates the original cross-type operator
(`date_ge_timestamptz` and friends are STABLE, the `timestamptz -> date` cast
is STABLE), so it cannot disagree with the unrewritten predicate. The
prototype was checked outside TimescaleDB with a PL/pgSQL sweep over UTC,
Asia/Tokyo, America/Los_Angeles, America/New_York, Europe/London,
America/Santiago (including the 2019-09-08 midnight gap and the 2019-04-07
ambiguous midnight), America/Sao_Paulo, Asia/Beirut, America/Havana and
Pacific/Apia, at 15-minute steps across the transition days plus microsecond
neighbours of midnight, for all five operators: 0 mismatches.

*PR 2, plan-time constification.* Accept `DATE` dimensions in
`constify_now()` for the lower-bound shapes `d >|>= now() [+|- interval]`,
`d >|>= (now() [+|- interval])::date` and `d >|>= CURRENT_DATE [+|- int]`, and
AND in a `DATE` constant computed from `ts_get_mock_time_or_current_time()`.

*Timezone safety, plan time.* A plan-time constant must not depend on the
session timezone, because `SET timezone` can happen between planning and
execution of a generic plan. Use the **UTC** calendar date `F` of the
plan-time clock, never `CURRENT_DATE`: every offset PostgreSQL accepts is
under one day, so any timezone's local date for that instant is within one day
of `F`, and the bound stays conservative in all of them. `d > T` and `d >= T`
both imply `d >= F`; the `::date` and `CURRENT_DATE` spellings get `F - 1`
with the operator kept. The existing 4-hour and 7-day buffers for interval
constants with day and month components apply unchanged. The price is at most
one extra chunk in the plan on 1 clock-day in 7 at a 7-day interval (measured
over a full cycle), and that chunk is then removed by startup exclusion
through PR 1. An exact bound would need the session timezone at plan time and
is not safe; do not add it.

*Expected outputs CI must regenerate* (the prototype regenerated only the
PostgreSQL 16 files, which is the only version its container had):

- PR 1: `test/expected/append-17.out`, `append-18.out`, `append-19.out` -
  the same 3-line change as `append-16.out` (query 152 of
  `test/sql/include/append_query.sql`, the `::timestamptz` variant, now
  excludes 3 chunks instead of 2 like its `::date` and `::timestamp`
  siblings; row counts unchanged).
- PR 2: `test/expected/plan_expand_hypertable-17.out`, `-18.out`, `-19.out` -
  the same 66-line hunk added after the "time_bucket exclusion with date"
  section.
- New tests, single version-independent expected file each, nothing to
  regenerate: `test/expected/chunk_append_date_tstz.out` (90-cell operator x
  timezone matrix, GUC on versus off versus ChunkAppend disabled,
  0 mismatches) and `test/expected/constify_date.out` (28 accepted and
  rejected shapes, a 10-shape x 5-timezone matrix including Pacific/Kiritimati
  UTC+14 and Etc/GMT+12, generic prepared plans re-executed after the mock
  clock advances and after `SET timezone`).
- `tsl/test/expected/decompress_vector_qual.out` gains a DATE-versus-TIMESTAMPTZ
  section under `timescaledb.debug_require_vector_qual = 'require'`; single
  expected file.

---

## Draft 2 - Bug: CURRENT_TIMESTAMP is never constified, because `is_valid_now_func()` compares the wrong struct field

Form: `Bug report`. Title:

> [Bug]: CURRENT_TIMESTAMP is never constified for TIMESTAMPTZ dimensions (is_valid_now_func compares SQLValueFunction->type instead of ->op)

**What type of bug is this?** Performance issue

**What subsystems and features are affected?** Query planner

**TimescaleDB version affected:** 2.31.0-dev (the code is unchanged as far
back as the field has existed; every released version with `constify_now.c`
is affected)

**PostgreSQL version used:** 16.15

**What operating system did you use?** Ubuntu 24.04 x64

**What installation method did you use?** Source

**What platform did you run on?** On prem/Self-hosted

**What happened?**

`WHERE time > CURRENT_TIMESTAMP - interval '1 day'` on a `TIMESTAMPTZ`
hypertable dimension is never constified, so no chunk is excluded at plan
time. The same query written with `now()` is constified. `CURRENT_TIMESTAMP`
and `now()` are the same value, and the planner is meant to treat them alike:
`src/planner/constify_now.c` has an explicit branch for `CURRENT_TIMESTAMP`
and the shared test `tsl/test/shared/sql/constify_now.sql` has a section for
it. The branch is dead code.

`src/planner/constify_now.c`:

```c
	if (IsA(node, SQLValueFunction) &&
		castNode(SQLValueFunction, node)->type == SVFOP_CURRENT_TIMESTAMP)
```

`SQLValueFunction.type` is the node's **result type Oid**
(`TIMESTAMPTZOID`, 1184); the function code is `SQLValueFunction.op`.
`SVFOP_CURRENT_TIMESTAMP` is enum value 3, so the comparison is 1184 == 3 and
can never be true. The fix is one word, `->type` to `->op`.

The expected output currently records the bug as if it were correct
behaviour: `tsl/test/shared/expected/constify_now-16.out` contains
two-chunk `Append` plans in a section whose comment says the opposite.

**How can we reproduce the bug?**

```sql
CREATE TABLE const_now(time timestamptz NOT NULL, device int, value float);
SELECT create_hypertable('const_now', by_range('time'));
INSERT INTO const_now
SELECT '3000-01-01'::timestamptz + (i || 'day')::interval, i, i FROM generate_series(1, 10) i;
INSERT INTO const_now
SELECT '1000-01-01'::timestamptz + (i || 'day')::interval, i, i FROM generate_series(1, 10) i;

-- one chunk: constified
EXPLAIN (COSTS OFF) SELECT FROM const_now WHERE time > now();
-- two chunks under an Append: not constified, but should be identical
EXPLAIN (COSTS OFF) SELECT FROM const_now WHERE time > CURRENT_TIMESTAMP;
EXPLAIN (COSTS OFF) SELECT FROM const_now WHERE time > CURRENT_TIMESTAMP - '24h'::interval;
```

**Relevant log output and stack trace**

The diff the one-word fix produces on `constify_now-16.out` is saved in the
fork as `experiments/date-probe/results/T3-constify_now-16-current-timestamp.diff`.
It is 10 plans, each losing its `Append` and one of its two
`Index Only Scan` children, for example:

```diff
 :PREFIX SELECT FROM const_now WHERE time > CURRENT_TIMESTAMP;
 --- QUERY PLAN ---
- Append
-   ->  Index Only Scan using _hyper_X_X_chunk_const_now_time_idx on _hyper_X_X_chunk
-         Index Cond: ("time" > CURRENT_TIMESTAMP)
-   ->  Index Only Scan using _hyper_X_X_chunk_const_now_time_idx on _hyper_X_X_chunk
-         Index Cond: ("time" > CURRENT_TIMESTAMP)
+ Index Only Scan using _hyper_X_X_chunk_const_now_time_idx on _hyper_X_X_chunk
+   Index Cond: ("time" > CURRENT_TIMESTAMP)
```

Affected expected outputs, all of which CI must regenerate with the fix:
`tsl/test/shared/expected/constify_now-16.out`, `constify_now-17.out`,
`constify_now-18.out`, `constify_now-19.out`. Nothing else in the suite
changes. The fix is independent of the `DATE` work in draft 1 and can go in on
its own.

---

## Draft 3 - Enhancement: warn at create time, and document, when a DATE dimension gets one-day chunks

Form: `Enhancement`. Title:

> [Enhancement]: NOTICE and documentation for DATE dimensions with a chunk interval of one day or less

**What type of enhancement is this?** User experience, Configuration

**What subsystems and features will be improved?** Partitioning, Compression,
Data ingestion

**What does the enhancement do?**

A `DATE` dimension with a chunk interval of one day is a degenerate
configuration: the partition granularity equals the type's granularity, so
every chunk holds exactly one distinct time value. It is easy to reach by
accident ("one day per chunk" reads sensible for a daily table) and it is
expensive. `create_hypertable()` / `by_range()` should emit a `NOTICE` when a
`DATE` dimension is given an interval of one day or less, and the
documentation should carry the three measurements below, which a `NOTICE`
cannot.

Measured on 1.92 M rows (400 days x 200 devices x 24 rows/day),
`segmentby = device_id`, every chunk compressed, medians of three runs, serial
execution. Runs `defaults-{1d,7d,30d}-{index,noindex}-1dc07b9`, full matrix in
`experiments/date-probe/results/T5-defaults-1dc07b9.md`.

| 1 day versus the 7-day default | |
|---|---|
| compressed storage | 66.56 vs 28.71 bytes/row, **2.32x more** |
| compression batch fill | 24.0 vs 165.5 rows, **2.4% of the 1000-row target** |
| chunks for 400 days | 400 vs 58 |
| planning, `day >= now() - interval '30 days'` | 36.53 vs 3.76 ms, **9.7x** |
| execution, same query, serial | 61.30 vs 15.36 ms, **4.0x** |

Suggested wording:

> NOTICE: chunk interval of 1 day on DATE column "day" gives one distinct
> value per chunk
> DETAIL: Compression batches will hold one device-day of rows and the
> default time index cannot be selective within a chunk.
> HINT: Consider a larger chunk interval (about 1000 / rows per device per
> day, in days) and create_default_indexes => false if no query filters a
> single day of uncompressed data.

Three things for the documentation, all measured:

1. **Batch fill is `rows_per_device_day x days_in_chunk`, capped at 1000**,
   and it has a cliff just past the optimum. Measured 24.0 / 165.5 / 685.7
   rows per batch at 1 / 7 / 30 days against a model predicting 24 / 168 /
   686. For this shape fill first reaches 900 at 38 days and peaks at 41
   (984); at 42 days it *halves* to 504, because 1008 rows need two batches.
   The device count does not move this at all - `segmentby` gives each device
   its own batch stream - only rows per device per day does.
2. **The default time index on a `DATE` dimension is never used by analytic
   queries on compressed chunks, and costs 45-50% of insert throughput.**
   `pg_stat_user_indexes.idx_scan` on the chunk indexes moved by 0 over the
   whole query set in all six configurations, in both the parallel and the
   serial pass (sampled before and after; a forced index scan moves the same
   counter, so the zero is real). Cost: 406 600 vs 746 250 rows/s at 1 day,
   502 129 vs 924 640 at 7 days, 519 268 vs 1 036 756 at 30 days, and 6.9-10.2
   bytes per row while a chunk is uncompressed. This is structural: a chunk of
   `k` days holds at most `k` distinct keys, so at 1 day the index has exactly
   one key and cannot be selective inside a chunk at all.
3. On a `DATE` column, planning cost scales with chunk count for every
   `now()`-based query until draft 1 lands, which is what makes small chunks
   hurt about three times as much on `DATE` as on `TIMESTAMPTZ` (the
   `DATE`/`TIMESTAMPTZ` ratio for that query is 9.0x at 1 day, 3.2x at 7 days,
   1.7x at 30 days).

**Implementation challenges**

A `NOTICE` and documentation only - deliberately **not** a change of any
default:

- Changing the default interval for `DATE` is not justified: 7 to 30 days is
  1.45x on compressed bytes (28.71 to 19.79 per row) and comes with a 33%
  regression on a 31-day literal-window query (4.62 to 6.13 ms serial), below
  any reasonable bar for silently changing a default every existing
  deployment inherits. The optimal interval is `1000 / rows_per_device_day`
  days, which depends on the ingest rate and on `segmentby`, neither of which
  exists at `create_hypertable()` time.
- Dropping the default index for `DATE` would clear a 2x ingest bar, but the
  evidence is one analytic query set; a selective lookup or a delete by time
  against *uncompressed* recent chunks is exactly the shape the index exists
  for, and `create_default_indexes => false` already exists for users who know
  they have none.
- One day or less is decidable from the arguments of `create_hypertable()`
  alone, which is what makes it a good threshold for a hint.

After draft 1 lands, the planning part of this shrinks by an order of
magnitude but the storage and batch-fill parts do not: with both planner
fixes installed, the 1-day cell still costs 66.56 bytes per row against 28.73
at 7 days (2.32x) and still plans 30 chunks against 5, while its planning
falls from 36.53 ms to 2.27 ms and its serial execution from 61.30 ms to
13.52 ms (run `int-after-1d-ac62b98`). The hint is worth having either way.
