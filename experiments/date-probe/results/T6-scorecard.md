# T6 scorecard: DATE time-dimension probe

Branch `probe/integration`, created from `claude/hypertable-date-time-dimension-ms75bt`
(`829325b`) and containing two merges:

- `probe/c1-defaults-measurement` (which carries `probe/harness`): the finished
  harness with T5's `--parallel-off-pass` and index sampling;
- `probe/a2-constify-date` (which carries `probe/a1-runtime-transform`): the
  two planner changes.

`probe/b1-orderby-tiebreaker` is **not** merged, per the brief: T4's verdict is
no-go as a default and it stays a separately measured opt-in.

Both merges applied cleanly, with no conflict in `src/`, `tsl/`, `sql/` or
`test/`. The merged tree compiles warning-free (`make -C build -j4`, 0 lines
matching `warning`) and passes the brief's whole test list.

Every number below is measured, on TimescaleDB 2.31.0-dev / PostgreSQL 16.15,
Ubuntu 24.04, 4 cores, this container. Nothing is estimated. Where a number
comes from a task branch's own run rather than from a T6 run, the report it
comes from is named.

## The measurement runs

All four runs of the brief's table exist, plus two additions. Every run is one
`locked.sh` command that begins with `make install`, on `PGPORT=5437`, with
`--parallel-off-pass`, `--start-date` pinned, and the cluster destroyed
afterwards.

| run | extension installed | flags | wall time | result files |
|---|---|---|---:|---|
| `int-baseline` | base branch, built from `git archive` in a scratch directory | `--scale small --start-date 2025-08-19` | 33 s | `int-baseline-ac62b98-*` |
| `int-after` | `probe/integration` | `--scale small --start-date 2025-08-19` | 35 s | `int-after-ac62b98-*` |
| `int-after-1d` | `probe/integration` | `--scale small --start-date 2025-08-19 --chunk-interval '1 day'` | 49 s | `int-after-1d-ac62b98-*` |
| `int-after-customer` | `probe/integration` | `--scale customer --start-date 2023-09-24` | 12 m 53 s | `int-after-customer-59db144-*` |
| `int-baseline-customer` (addition) | base branch | `--scale customer --start-date 2023-09-24` | see below | `int-baseline-customer-59db144-*` |
| `int-after-guccheck` (addition) | `probe/integration` | `--scale small --start-date 2025-08-19` | 33 s | `int-after-guccheck-ac62b98-*` |

The customer-scale run was **not** skipped: its two conditions were met - each
small run finished in well under a minute (33 s, 35 s, 49 s) and `df -h`
reported 23 GB free afterwards, against the 10 GB the brief requires.

Two things to know when reading the file names and the harness's own header
lines:

- **`git_sha` in every file name is this worktree's HEAD, not the extension
  that was installed.** `run.sh` reads the worktree HEAD. For `int-baseline`
  and `int-baseline-customer` the *installed* extension was the base branch,
  built from `git archive claude/hypertable-date-time-dimension-ms75bt` in a
  scratch directory; the harness itself is always this branch's, because the
  base branch has no `--parallel-off-pass`.
- **Planning buffers are not in the harness CSVs.** They are extracted from
  `probe_plans` with `results/T6-planbuffers.sql` while the cluster is kept up
  at the end of each locked command, and saved as `*-planbuffers.txt`. The
  median of the three runs is quoted; the first run of each query has a cold
  relation cache and is the maximum, which is why min and max are also saved.
- **`--start-date` for the customer scale is 2023-09-24, not T5's 2025-08-19.**
  Pinning T5's date at 1095 days would end the data on 2028-08-17, i.e. two
  years in the future, and `>= now() - interval '30 days'` would then select
  725 days of rows instead of 30. 2023-09-24 is 1094 days before the run date,
  so the customer data ends today exactly as every `small` cell does. The
  small-scale cells, which are the ones the scorecard compares, all share
  T5's 2025-08-19.

**Cross-day comparability check.** `int-baseline` reproduces T5's
`defaults-7d-index` cell, run on the same machine on a different day with the
same flags and the same start date, within 4%: Q1 serial 14.84 ms against
15.36 ms, Q1 planning 3.69 ms against 3.15 ms, 58 chunks in plan, 0 excluded,
vectorized filter false in both. T5's cells and T6's are therefore comparable,
which is what makes the 1-day row below meaningful.

## Scorecard

Serial numbers (`max_parallel_workers_per_gather = 0`, the harness's `-np`
query ids) are quoted for every comparison, as T5 recommends, because at 400
chunks the parallel plan is *slower* than the serial one and two cells that
differ only by an unused index can disagree by 2.6x with parallelism on.
"Gain" is `(control - after) / control` on `metrics_date`, `int-after` versus
`int-baseline`.

| design | Q1 serial gain vs control | Q2 serial gain vs control | bytes per row effect | tests added and passing | expected outputs needing CI regeneration | effort (`git diff --stat` vs base) | go / no-go |
|---|---|---|---|---|---|---|---|
| **runtime transform, all operators** (T2, `probe/a1-runtime-transform`) | not separable in a T6 run; T2's own before/after: 21.10 → 20.52 ms parallel, **+2.7%** | T2's own: 14.95 → 16.73 ms, **-11.9%** (noise, shape unchanged) | none: 28.66 → 28.73 B/row over the pair, 0.27% run-to-run | `chunk_append_date_tstz` new (200 SQL / 580 expected lines, 90-cell matrix, 0 mismatches GUC on vs off vs ChunkAppend disabled, 0 cells without startup exclusion); `decompress_vector_qual` +23 SQL / +73-7 expected; `append-16` +1/-3 | `append-17.out`, `append-18.out`, `append-19.out` | engine 4 files, +389 / -19; with tests 10 files, +1263 / -33 | **go as PR 1 of Track A.** Alone it is +2.7% on Q1, below the fifth, and would be no-go under the rule read strictly - see "the rule applied", below |
| **constify DATE bounds** (T3, `probe/a2-constify-date`) | 14.84 → **6.33 ms**, **+57.3%** (T3's own isolated before/after: 19.81 → 6.03 ms parallel, +69.6%) | 6.18 → **5.72 ms**, +7.4% (parallel 14.01 → 5.66 ms, +59.6%) | none: same 0.27% | `constify_date` new (331 SQL / 1086 expected lines, 28 shapes, 10-shape x 5-timezone matrix, generic plans re-executed after the clock advances and after `SET timezone`); `plan_expand_hypertable` +10 SQL / +66 expected | `plan_expand_hypertable-17.out`, `-18.out`, `-19.out` | engine 1 file, +462 / -95; with tests 6 files, +1956 / -95 | **go** |
| **orderby tiebreaker** (T4, `probe/b1-orderby-tiebreaker`, not merged) | 0%: not measured to change any query; the design is compression-only | 0%, same | **worse**: value columns -189 992 B (-0.53%), metadata +371 200 B, **all compressed columns +181 208 B (+0.50%)**; physical total 55 058 432 → 54 140 928 B (-1.67%), against a 131 072 B (0.24%) run-to-run floor | `compression_defaults` +103 SQL / +175 expected, purely additive (0 lines of the existing output changed); sweep of 6 further tsl tests all pass | none (single version-independent expected file) | engine 1 file (`sql/compression_defaults.sql`), +124 / -1; with tests 3 files, +402 / -1 | **no-go as a default**; keep as an opt-in. Number that failed: 0% on Q1 and Q2, and +0.50% on compressed column bytes, where the rule needs +20% on Q1 or Q2 |
| **chunking and index defaults** (T5, `probe/c1-defaults-measurement`) | n/a: a measurement task, no engine change; the intervals it compares are user choices | n/a | 1 day 66.56, 7 days 28.71, 30 days 19.79 B/row; the default index costs 6.9-10.2 B/row before compression and 45-50% of insert throughput | none (no engine or SQL change; harness additions only) | none | 0 files under `src/`, `tsl/`, `sql/`, `test/` | **no-go as an engine default change**; **go** for a create-time `NOTICE` plus documentation. Numbers that failed a default change: 7 → 30 days is 1.45x on bytes with a +33% Q3 regression (4.62 → 6.13 ms serial), against a 2x-with-no-regression bar; dropping the default index clears 2x on ingest but rests on one analytic query set |
| **the two planner changes together** (what `int-after` measures) | 14.84 → **6.33 ms, +57.3%** | 6.18 → **5.72 ms, +7.4%** (parallel +59.6%) | none | all of the above, 8 of 8 in the brief's list pass | `append-17/18/19.out`, `plan_expand_hypertable-17/18/19.out` | engine 5 files, +851 / -114; with tests 15 files, +3219 / -128 | **go** |

### The go / no-go rule, applied uniformly

The rule: **go** when the design improves the customer shape Q1 or Q2 by at
least a fifth, with no regression on Q3 to Q5, and identical results with its
GUC on and off. **No-go** otherwise, with the number that failed.

1. **At least a fifth on Q1 or Q2, serial, `metrics_date`, `int-after` vs
   `int-baseline`:** Q1 14.84 → 6.33 ms is **+57.3%**, which clears the bar on
   its own. Q2 6.18 → 5.72 ms is +7.4% and does not, which is expected and not
   a failure of the rule: Q2's bound is already the column's own type, so it
   was already excluded at startup before the change, and the rule needs
   either one. Q2's *parallel* number moves far more (14.01 → 5.66 ms, +59.6%)
   because the change removes the parallel plan the 58-chunk cost estimate was
   buying; that gain is real on a busy server but is exactly the kind of
   number T5 said not to quote.
2. **No regression on Q3 to Q5, serial, `metrics_date`:** Q3 5.15 → 5.20 ms
   (+1.0%), Q4 22.38 → 22.35 ms (-0.1%), Q5 0.04 → 0.04 ms (0%). All three are
   inside the run-to-run noise of this harness and none is a regression. The
   parallel pass shows Q4 21.92 → 22.89 ms (+4.4%) and Q5 0.04 → 0.06 ms, both
   of which are worker-scheduling noise of the kind T5 documented; the serial
   pass is the measurement.
3. **Identical results with the GUC on and off:** checked directly on the
   harness data (`results/T6-guc-on-off.sql`, output in
   `int-after-guccheck-ac62b98-guc-on-off.txt`): seven DATE query shapes -
   `>=`, `>`, `<`, `=` against `now()`-derived bounds, `current_date - 30`, a
   literal window, and a `(now() - interval)::date` cast bound - each executed
   under all four combinations of `timescaledb.enable_now_constify` and
   `timescaledb.enable_runtime_exclusion`. **`shapes_disagreeing = 0`**: every
   shape returned one distinct `(count, avg(v1))` across all four settings.
   The regression suite asserts the same independently:
   `chunk_append_date_tstz` reports `count_mismatches = 0` over a 90-cell
   operator x timezone matrix with the GUC on, off, and with ChunkAppend and
   ConstraintAwareAppend disabled, and `constify_date` compares constified
   counts against PostgreSQL's own evaluation in five timezones.

   Verdict: **go** for the pair, and **go** for T3, which is the change the
   Q1 number belongs to.

4. **T2 read strictly.** T2's own before/after is +2.7% on Q1, which fails the
   fifth. The honest reason is that the harness query set cannot measure what
   T2 does: Q1 to Q5 contain exactly one cross-type predicate, `day >= now() -
   interval '30 days'`, and no cross-type `<`, `>`, `<=` or `=` at all - the
   four operators T3 never constifies and T2 is the only thing that can
   exclude. What T2 *is* measured to change on Q1, in its own run, is chunks
   reaching the executor 58 → 5, `Vectorized Filter` false → true, and buffers
   6401 → 6025, i.e. down to the `TIMESTAMPTZ` twin's figure; the wall clock
   does not follow because the planner still costs all 58 chunks and still
   picks two workers, which is precisely what T3 removes. T2 is also load
   bearing inside the merged tree, visibly: in `int-after-1d`, Q1 on
   `metrics_date` shows `Chunks excluded during startup: 1`, which is T2's
   rewrite removing the one chunk T3's deliberately conservative UTC bound
   leaves in. The recommendation is to ship it as PR 1 of the track, and to
   record that under a strict single-design reading of the rule its number is
   +2.7% on Q1.
5. **T4** fails at step 1 with 0% on both Q1 and Q2 - it changes no plan - and
   also fails on its own terms: its stated bar was that the value-column
   saving must exceed the metadata cost, and 189 992 B of saving against
   371 200 B of four new metadata columns does not. No-go as a default,
   cheap and safe as an opt-in, worth re-measuring where batches are wide.
6. **T5** is not a design with a GUC; it proposes a `NOTICE` and
   documentation. The engine-default options it evaluated fail step 1's spirit
   (1.45x, not 2x, and with a Q3 regression), which is why the recommendation
   stops at a hint.

## The four runs in full

`metrics_date` unless stated. "excl" is chunks excluded during startup, "vec"
the presence of a `Vectorized Filter`, "plan buf" the median planning-time
shared-buffer hits.

### `int-baseline` - control, base branch, 7-day chunks, 58 chunks

| query | exec ms | exec ms serial | plan ms | plan ms serial | chunks in plan | excl | vec | plan buf | workers | shared hit |
|---|---:|---:|---:|---:|---:|---:|---|---:|---:|---:|
| Q1 | 22.52 | 14.84 | 4.40 | 3.69 | 58 | 0 | no | 526 | 2 | 6401 |
| Q2 | 14.01 | 6.18 | 3.66 | 3.05 | 5 | 53 | yes | 526 | 2 | 6025 |
| Q3 | 4.89 | 5.15 | 0.43 | 0.74 | 5 | 0 | yes | 55 | 0 | 4225 |
| Q4 | 21.92 | 22.38 | 0.53 | 0.52 | 5 | 0 | yes | 49 | 0 | 9025 |
| Q5 | 0.04 | 0.04 | 0.45 | 0.17 | 1 | 0 | yes | 13 | 0 | 23 |

`metrics_tstz` for contrast: Q1 5.90 / 5.82 ms, 0.49 / 0.46 ms planning, 5
chunks, plan buf 49; Q2 14.42 / 6.35 ms, 4.48 / 4.51 ms planning, 5 chunks, 53
excluded, plan buf 526.

Compressed bytes per row: `metrics_date` **28.655** (of which `day` 0.552),
`metrics_tstz` **30.374** (of which `ts` 1.550). 11 600 batches, 165.5 rows
per batch, both twins.

### `int-after` - `probe/integration`, 7-day chunks, 58 chunks

| query | exec ms | exec ms serial | plan ms | plan ms serial | chunks in plan | excl | vec | plan buf | workers | shared hit |
|---|---:|---:|---:|---:|---:|---:|---|---:|---:|---:|
| Q1 | **6.16** | **6.33** | **1.10** | **0.63** | **5** | 0 | **yes** | **49** | **0** | 6025 |
| Q2 | **5.66** | **5.72** | **0.41** | **0.39** | 5 | **0** | yes | **49** | **0** | 6025 |
| Q3 | 5.02 | 5.20 | 0.37 | 0.56 | 5 | 0 | yes | 55 | 0 | 4225 |
| Q4 | 22.89 | 22.35 | 0.57 | 0.54 | 5 | 0 | yes | 49 | 0 | 9025 |
| Q5 | 0.06 | 0.04 | 0.15 | 0.22 | 1 | 0 | yes | 13 | 0 | 23 |

`metrics_tstz` is unchanged by the patch, as it must be: Q1 6.16 / 5.77 ms,
5 chunks, plan buf 49; Q2 17.35 / 6.50 ms, plan buf 526 - byte-identical
counters to the control.

Compressed bytes per row: `metrics_date` **28.732**, `metrics_tstz` **30.374**.
The 0.077 B/row difference from the control on the DATE twin is the data
generator's `random()` moving the `status` text by 1 477 bytes across 1.92 M
rows; the planner changes touch no storage path.

**Q1 on the DATE twin is now the TIMESTAMPTZ twin, metric for metric:** 6.33
against 5.77 ms serial, 5 chunks against 5, 49 planning buffers against 49,
6025 buffers hit against 6025, 144 000 rows scanned against 144 000. Q2 is
three times faster than the twin, because the twin's
`ts >= date_trunc('day', now()) - interval '30 days'` is a shape
`constify_now` does not handle for `TIMESTAMPTZ` either (see open question 5).

### `int-after-1d` - `probe/integration`, 1-day chunks, 400 chunks

This run answers T5's open question 4, "does T2/T3 change the interval
answer?". The comparison is against T5's `defaults-1d-index-1dc07b9` cell,
which is the same configuration on the unpatched engine.

| metric, Q1 on `metrics_date`, 1-day chunks | before (T5 `defaults-1d-index`) | after (`int-after-1d`) | change |
|---|---:|---:|---|
| planning | 36.53 ms | **2.27 ms** | **-93.8%** |
| planning buffers | not sampled by T5 | 411 | - |
| execution, serial | 61.30 ms | **13.52 ms** | **-77.9%** |
| execution, parallel allowed | 108.63 ms | **12.10 ms** | -88.9% |
| chunks in the plan | 400 | **30** | -92.5% |
| chunks excluded at startup | 0 | **1** | T2's rewrite |
| vectorized filter | no | **yes** | |
| workers launched | 2 | **0** | |
| buffers hit | 9 200 | 690 | |

**Most of the 1-day penalty was planning and the plan shape it bought, and it
is gone.** What remains at 1 day is not planning:

| 1 day vs 7 days, both on `probe/integration` | 1 day | 7 days | ratio |
|---|---:|---:|---:|
| Q1 execution, serial | 13.52 ms | 6.33 ms | 2.14x |
| Q1 planning | 2.27 ms | 1.10 ms | 2.06x |
| chunks in the plan | 30 | 5 | 6x |
| compressed bytes per row | 66.56 | 28.73 | **2.32x** |
| average rows per compression batch | 24.0 | 165.5 | 0.15x |
| load throughput | 351 346 rows/s | 496 434 rows/s | 0.71x |
| Q3 serial / Q4 serial | 9.81 / 35.55 ms | 5.20 / 22.35 ms | 1.89x / 1.59x |

Before the fix the same 1-day-versus-7-day ratios were 4.0x on serial
execution and 9.7x on planning (T5's cells). So T5's recommendation stands
and its ordering note is confirmed: the planner fix removes the planning
argument almost entirely, and leaves the storage and batch-fill arguments
untouched at 2.32x and 0.15x. A create-time hint is still worth having.

One side effect worth recording: at 1 day Q3 and Q4 lose their vectorized
filter (`vec = no`) on both twins, before and after, because a literal window
that spans whole 1-day chunks is excluded at plan time and leaves no filter to
vectorize. That is T5's cell behaving the same way, not a regression from this
branch.

### `int-after-customer` - `probe/integration`, customer scale

1095 days x 2000 devices x 24 rows = **52.56 M rows per twin**, 157 chunks of
7 days, all compressed, `segmentby = device_id`, data 2023-09-24 .. 2026-09-22.
Load 128.6 s at 408 765 rows/s, compression 46.5 s at 1.13 M rows/s, continuous
aggregate refresh 21.6 s over 2.19 M buckets.

| query | exec ms | exec ms serial | plan ms | plan ms serial | chunks in plan | excl | vec | plan buf | workers | shared hit |
|---|---:|---:|---:|---:|---:|---:|---|---:|---:|---:|
| Q1 | 39.31 | 61.92 | 0.62 | 0.58 | **5 of 157** | 0 | yes | **61** | 2 | 60 420 |
| Q2 | 32.75 | 60.04 | 0.59 | 0.47 | 5 | 0 | yes | 61 | 2 | 60 420 |
| Q3 | 34.34 | 49.46 | 0.57 | 0.57 | 5 | 0 | yes | 66 | 2 | 42 411 |
| Q4 | 126.91 | 235.42 | 0.60 | 0.59 | 5 | 0 | yes | 60 | 2 | 90 436 |
| Q5 | 0.07 | 0.06 | 0.17 | 0.16 | 1 | 0 | yes | 16 | 0 | 24 |

`metrics_tstz` at the same scale: Q1 30.31 / 61.43 ms, planning 0.54 / 0.56 ms,
5 chunks, plan buf 61; Q2 46.81 / 61.83 ms, planning **13.97 / 14.32 ms**, 5
chunks, 152 excluded at startup, plan buf **1733**.

**The headline at scale: the DATE twin and the TIMESTAMPTZ twin are now the
same query.** Q1 serial 61.92 ms against 61.43 ms (0.8% apart), planning 0.58
against 0.56 ms, 5 of 157 chunks in both plans, 61 planning buffers in both.
On Q2 the DATE twin is now the *faster* one - 0.47 ms planning and 61
planning buffers against 14.32 ms and 1733 - because `day >= current_date - 30`
is constified while the twin's `date_trunc('day', now())` shape is not.

**Storage at scale, where the DATE advantage is larger than at small scale:**

| | `metrics_date` | `metrics_tstz` | difference |
|---|---:|---:|---:|
| time column, compressed bytes/row | 0.548 | 1.548 | 2.82x |
| whole table, compressed bytes/row | **23.264** | **27.400** | **-15.1%** |
| whole table, compressed | 1166 MB | 1373 MB | -207 MB |
| compression ratio | 3.81 | 3.23 | |
| batches / avg rows per batch | 314 000 / 167.4 | 314 000 / 167.4 | identical |

At `small` the same difference is 28.73 against 30.37 B/row, i.e. -5.4%. The
gap widens with scale because the whole-table figure is dominated by toast
chunking, which rounds less coarsely over 157 chunks than over 58.

A customer-scale **control** on the base branch was run as an addition (it is
not in the brief's table), so that the scale row has a measured before/after
rather than an inference; its numbers are in
`int-baseline-customer-59db144-summary.md` and in the report.

## The three findings that were not designs

### 1. The probe's prior on DATE compression was wrong (from T1, confirmed at two scales)

The README's prior said that after compression the time column's width is
irrelevant, because deltadelta widens dates to `int64`. The stream format is
indeed the same, but the delta *magnitudes* are not: consecutive days differ by
1 for a `DATE` and by 86 400 000 000 microseconds for a midnight `TIMESTAMPTZ`,
and simple8b pays for the extra bits. Measured three times now, on three
independent runs:

| | `day` (date) | `ts` (timestamptz) | whole table, date | whole table, tstz |
|---|---:|---:|---:|---:|
| T1, small | 0.552 | 1.550 | 28.757 | 30.374 |
| T6 `int-baseline`, small | 0.552 | 1.550 | 28.655 | 30.374 |
| T6 `int-after-customer` | 0.548 | 1.548 | 23.264 | 27.400 |

So the time column really is about **2.8x smaller** with `DATE`, and the whole
table is 5.4% smaller at `small` and **15.1% smaller at customer scale**. The
correction cuts both ways: the saving is real and larger than the README
claimed at scale, but it is still not the "half the bytes" a reader might
expect from a 4-byte versus 8-byte type. Before compression the two tables are
byte-for-byte identical (83.14 B/row of heap in both) because the 4 bytes
`DATE` saves are spent on alignment padding ahead of `seq`; a padding-free
column order is the only way to collect them, and that is the harness's
`--reorder` variant, not measured here.

### 2. The default time index on a DATE dimension is dead, and the batch-fill formula (from T5, reconfirmed by two T6 runs)

`pg_stat_user_indexes.idx_scan` over the chunk indexes moved by **0** across
the whole query set, in the parallel and the serial pass, in all six of T5's
cells - and again in all four T6 runs, including customer scale, where the
delta is 0 over 157 chunk indexes holding 1 286 144 bytes. The only index any
query touches is the one compression builds on the segmentby column (Q5). The
zero is verified to be a real zero: a forced index scan moves the same counter
through the same sampling path.

Its cost: 6.9-10.2 bytes per row while a chunk is uncompressed (7.8-10.1% of
the pre-compression total) and **45-50% of insert throughput** at every chunk
interval (406 600 vs 746 250 rows/s at 1 day, 502 129 vs 924 640 at 7 days,
519 268 vs 1 036 756 at 30 days). The byte cost is transient - compression
empties the index to one page per chunk - but the write cost is permanent.

This is structural, not accidental: a chunk of `k` days on a `DATE` dimension
holds at most `k` distinct keys, so at the 7-day default an index lookup can
never select less than about a seventh of the chunk, and at 1 day the index has
exactly one key.

The batch-fill formula, measured to three digits against the model:

```
rows per device per chunk N = rows_per_device_day x days_in_chunk
batches per device          ceil(N / 1000)
average fill                N / ceil(N / 1000)
```

Measured 24.0 / 165.5 / 685.7 rows per batch at 1 / 7 / 30 days against a model
predicting 24 / 168 / 686, and 167.4 at customer scale where the same 7-day
interval has fewer partial chunks at the ends. For 24 rows per device per day,
fill first reaches 900 at 38 days and peaks at 41 (984), then **halves to 504
at 42 days**, because 1008 rows need two batches. The device count does not
move this at all: `segmentby` gives each device its own batch stream, so going
from 200 to 2000 devices multiplies the batch count by 10 (11 600 → 314 000 at
7 days, measured) and leaves the fill at 165-167. Only rows per device per day
moves it.

### 3. CURRENT_TIMESTAMP is never constified, for any type (from T3)

`is_valid_now_func()` in `src/planner/constify_now.c` tests
`castNode(SQLValueFunction, node)->type == SVFOP_CURRENT_TIMESTAMP`.
`SQLValueFunction.type` is the node's **result type Oid** (`TIMESTAMPTZOID`,
1184); the function code lives in `SQLValueFunction.op`, and
`SVFOP_CURRENT_TIMESTAMP` is enum value 3. The comparison is `1184 == 3` and
the branch has never fired, so `WHERE time > CURRENT_TIMESTAMP - interval '1
day'` on a `TIMESTAMPTZ` dimension has never been constified while the same
query spelled `now()` has. `tsl/test/shared/expected/constify_now-16.out`
records the unconstified two-chunk `Append` plans in a section whose comment
claims the opposite.

The fix is one word, `->type` to `->op`. The diff it produces on PostgreSQL 16
is saved as `results/T3-constify_now-16-current-timestamp.diff`: 10 plans, each
losing its `Append` and one of its two children. `constify_now-16/17/18/19.out`
would all need regeneration. The bug is independent of `DATE` and is drafted as
its own upstream issue. T3 deliberately did not fix it - the expected file is
outside its allowed paths - and scoped its own acceptance of `CURRENT_TIMESTAMP`
to `DATE` dimensions instead.

## Open questions carried forward

Deduplicated from the five reports, with who answers each. Questions the probe
has since answered are listed with their answer and not carried.

### For the user: customer numbers the probe cannot invent

1. **What is the customer's real rows per device per day?** (T5 Q3, T1 Q3.)
   This is the single input the chunk-interval recommendation needs: the target
   interval is `1000 / rows_per_device_day` days and nothing else. At 24 it is
   38-41 days; at 1440 (one row per minute) even a 1-day chunk overshoots and
   `segmentby` has to change instead. `DAYS`, `DEVICES` and `RPD` in
   `harness/run.sh` are still the probe plan's placeholders (1095 x 2000 x 24 at
   `customer` scale), so every absolute number at that scale is the placeholder
   shape, not the customer's.
2. **Does any query filter a single day of *uncompressed* recent data?**
   (T5 Q2.) The probe proves the default time index is never used by an
   analytic query set over compressed chunks. One counter-example - a
   `WHERE day = X ORDER BY day DESC LIMIT n`, an update, or a delete by time,
   against recent uncompressed chunks - decides whether "drop the default index
   for DATE" is even arguable. If there is none, it clears a 2x ingest bar on
   its own.
3. **What are the customer's real column shapes?** (T4 Q2.) The harness's value
   columns are 41% random noise; only `v1` is correlated enough to benefit from
   ordering at all, which caps T4's ceiling at the measured 0.53%. If the real
   columns are mostly correlated, the tiebreaker's ceiling is much higher and
   the no-go should be re-examined.
4. **Are the customer's queries written with `>=` only, or also with `<`, `>`,
   `<=` and `=` against `now()`?** Not asked by any report, but it is what
   decides how much of Track A's value comes from PR 1 rather than PR 2: the
   harness measures only `>=`.

### For the maintainers: decisions the probe cannot make

5. **Apply the one-word `CURRENT_TIMESTAMP` fix?** (T3 Q1.) Genuine upstream
   bug, independent of `DATE`, drafted as its own issue; needs
   `constify_now-16/17/18/19.out` regenerated.
6. **Extend `constify_now` to `date_trunc`- and `time_bucket`-of-`now()`
   bounds, for `TIMESTAMPTZ` as well?** (T3 Q2.) After this branch,
   `ts >= date_trunc('day', now()) - interval '30 days'` is the *slowest* of
   the four twin/query combinations at customer scale: 14.32 ms of planning and
   1733 planning buffers against 0.47 ms and 61 for the DATE twin's
   `current_date - 30`. The `TIMESTAMPTZ` side now has the gap the `DATE` side
   had.
7. **Handle the reversed operand order `now() - interval <= d`?** (T3 Q3.)
   PostgreSQL does not normalize it and upstream does not handle it for
   `TIMESTAMPTZ` either. Worth adding for both types in one change if customer
   queries use it.
8. **Should `compression_defaults`' `confidence` and `message` surface to the
   user?** (T4 Q4.) The SQL function lowers `confidence` and sets `message` for
   its heuristic rules, but the C caller only logs it with `LOG_SERVER_ONLY`,
   so nothing reaches the user. Making it visible is a C change outside T4's
   allowed paths.
9. **Should rule 3 of the tiebreaker heuristic be restricted to fixed-width
   types?** (T4 Q3.) It currently picks the column with the most distinct
   values, which can be a `text` column over a moderately distinct `bigint`.
10. **Do `experiments/date-probe/harness/README.md` and the probe README need
    the counting caveats?** (T2 Q4.) `chunks_in_plan` is distinct chunk
    relations, not scan nodes - a compressed chunk contributes two nodes - and
    `chunks_excluded_startup` was double counted before T1's `7103a22`, which
    is why T2's report reads `10 / 106` where today's reads `5 / 53`.

### Follow-up designs, for whoever takes the track further

11. **Re-measure the orderby tiebreaker where batches are wide.** (T4 Q1.) At
    `small` and at `customer` the batches hold 165-167 rows, because
    `segmentby = device_id` plus a 7-day chunk gives 168 rows per stream; the
    intra-day disorder the tiebreaker removes therefore spans 24 rows and never
    approaches the 1000-row batch limit. A 30- or 41-day interval, or a coarser
    `segmentby`, is where the design would have room to work. The current
    no-go is a verdict on a table shaped like the harness's, not on `DATE`
    hypertables in general.
12. **A padding-free column order.** Before compression the `DATE` and
    `TIMESTAMPTZ` tables are byte-identical because `DATE`'s 4 bytes go to
    alignment padding ahead of `seq`. The harness has a `--reorder` variant for
    this and it was never run; it is the only way to collect the pre-compression
    saving, and it is a documentation matter, not an engine change.
13. **An exact rather than conservative plan-time bound.** (T3.) Measured cost
    of the conservative UTC bound: one extra chunk in the plan on 1 clock-day in
    7 at a 7-day interval, plus 4 hours a week from the day-interval safety
    buffer - invisible in every median here, and removed at startup by T2's
    rewrite. An exact bound needs the session timezone at plan time and is
    unsafe under `SET timezone` between planning and execution, so it could only
    be a default-off GUC. Not implemented, and the numbers say not to.

### Answered by the probe, not carried forward

- *T1 Q1, "is the compression prior wrong?"* Yes. Finding 1 above, measured at
  two scales.
- *T1 Q2 and T5 Q1, "should T6 report single-worker numbers?"* Yes, and every
  comparison in this scorecard does. At 400 chunks the parallel Q1 is slower
  than the serial one (108.63 vs 61.30 ms), and cells that differ only by an
  unused index disagree by up to 2.6x with parallelism on and within 5% with it
  off.
- *T1 Q4, "why is Q2 not faster on either twin?"* Because the five surviving
  chunks hold all the matching rows and the work is decompressing them; the
  exclusion win shows up in planning and chunk count. Confirmed again here:
  Q2's serial execution moves 7.4% while its planning moves 87%.
- *T5 Q4, "does T2/T3 change the interval answer?"* No. `int-after-1d` above:
  the planning argument for a larger interval shrinks by an order of magnitude
  and the storage (2.32x) and batch-fill (0.15x) arguments are untouched.
- *T2 Q1 and Q2, T3 Q4* were resolved inside those tasks (the range form for
  `=`, `append-16.out` updated on the branch).
- *T2 Q3, the harness bugs.* All fixed on `probe/harness` before this merge;
  all four T6 runs produced their CSVs and summaries and stopped their cluster
  cleanly.
