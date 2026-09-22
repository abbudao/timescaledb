## Report: T6 (integration, combined measurement, scorecard) on probe/integration @ 6f3297b

Commits on top of the base `829325b`: `c952d26` (merge of
`probe/c1-defaults-measurement`), `ac62b98` (merge of `probe/a2-constify-date`),
`59db144` (small-scale runs), `2d8cf81` (customer-scale run, scorecard, issue
drafts), `06d2c96` (planning-noise note, exact base operator set), `6f3297b`
(customer-scale control), plus this report.

`probe/b1-orderby-tiebreaker` is deliberately **not** merged: T4's verdict is
no-go as a default and the brief keeps it a separately measured opt-in.

Both merges applied with **no conflict anywhere**, so nothing under `src/`,
`tsl/`, `sql/` or `test/` was hand-edited; the only files this task wrote are
under `experiments/date-probe/results/` plus the scorecard section of
`experiments/date-probe/README.md`.

### Commands run

Branch and merges:

```bash
git checkout -B probe/integration claude/hypertable-date-time-dimension-ms75bt   # 829325b
git merge --no-edit probe/c1-defaults-measurement                                # c952d26
git merge --no-edit probe/a2-constify-date                                       # ac62b98
```

Build, without the lock, 0 lines of the log matching `warning`:

```bash
BUILD_FORCE_REMOVE=true ./bootstrap -DCMAKE_BUILD_TYPE=Debug -DREGRESS_CHECKS=ON >/dev/null && make -C build -j4
```

Bootstrap hook, under the install lock:

```bash
experiments/date-probe/bin/locked.sh env CLAUDE_CODE_REMOTE=true \
  CLAUDE_PROJECT_DIR=/home/user/timescaledb/.claude/worktrees/agent-ae04e9b1b12d47e21 \
  .claude/hooks/session-start.sh
```

Tests, one locked command starting with `make install`, with
`LANG=LC_ALL=C.UTF-8` and `TS_BUILD_DIR` pointing at this worktree's `build/`
(run twice: once after the merges, once after the last commit, same result):

```bash
export LANG=C.UTF-8 LC_ALL=C.UTF-8 \
  TS_BUILD_DIR=/home/user/timescaledb/.claude/worktrees/agent-ae04e9b1b12d47e21/build
experiments/date-probe/bin/locked.sh <script>   # make -C build install && the three suites:
  experiments/date-probe/bin/regress.sh constify_date plan_expand_hypertable \
      chunk_append_date_tstz append insert_single
  SUITE=shared experiments/date-probe/bin/regress.sh constify_now constify_timestamptz_op_interval
  SUITE=tsl    experiments/date-probe/bin/regress.sh decompress_vector_qual
```

Control build, for the two `int-baseline` runs:

```bash
git archive claude/hypertable-date-time-dimension-ms75bt -o <scratch>/base.tar
tar -xf <scratch>/base.tar -C <scratch>/base-src
cd <scratch>/base-src && BUILD_FORCE_REMOVE=true ./bootstrap -DCMAKE_BUILD_TYPE=Debug -DREGRESS_CHECKS=ON >/dev/null && make -C build -j4
```

The six harness runs, each one locked command beginning with `make install`,
each on `PGPORT=5437`, each destroying its cluster afterwards:

```bash
experiments/date-probe/bin/locked.sh <scratch>/run-int-baseline.sh
  # make -C <scratch>/base-src/build install
  #   && harness/run.sh --variant int-baseline --scale small --port 5437 \
  #        --start-date 2025-08-19 --parallel-off-pass --keep
  #   && psql -f results/T6-planbuffers.sql && harness/pg/stop.sh --destroy

experiments/date-probe/bin/locked.sh <scratch>/run-int.sh int-after           --scale small    --start-date 2025-08-19
experiments/date-probe/bin/locked.sh <scratch>/run-int.sh int-after-1d        --scale small    --start-date 2025-08-19 --chunk-interval '1 day'
experiments/date-probe/bin/locked.sh <scratch>/run-int.sh int-after-customer  --scale customer --start-date 2023-09-24
experiments/date-probe/bin/locked.sh <scratch>/run-guc.sh                     # small + results/T6-guc-on-off.sql
experiments/date-probe/bin/locked.sh <scratch>/run-base.sh int-baseline-customer --scale customer --start-date 2023-09-24
```

`run-int.sh` and `run-base.sh` are three-line wrappers that do
`make -C <build> install`, then `harness/run.sh --port 5437 --parallel-off-pass
--keep <flags>`, then the planning-buffer extraction, then
`pg/stop.sh --destroy`; `run-base.sh` reinstalls this worktree's build at the
end. They exist only because this session's sandbox refuses
`locked.sh bash -c '...'`; each is still exactly one locked command that starts
with `make install`, as the README requires.

Push: `git push -u origin probe/integration` was attempted **once** and refused
with **HTTP 403**: "Claude doesn't have GitHub access to abbudao/timescaledb for
your organization. An org admin can install the Claude GitHub App ...". Not
retried and not worked around, as instructed. The branch exists only in this
worktree, `/home/user/timescaledb/.claude/worktrees/agent-ae04e9b1b12d47e21`.
Every task branch hit the same 403.

### Tests

The brief's whole list, all **pass**, twice (after the merges and after the
last commit), PostgreSQL 16.15, Debug build, `LANG=C.UTF-8`:

- core: `constify_date` **pass**, `plan_expand_hypertable-16` **pass**,
  `chunk_append_date_tstz` **pass**, `append-16` **pass**, `insert_single`
  **pass**
- shared: `constify_now-16` **pass**, `constify_timestamptz_op_interval-16`
  **pass**
- tsl: `decompress_vector_qual` **pass**

No diffs, so there is nothing to explain line by line. Two notes on the runs
themselves, neither a failure: `pg_regress` prints
`mkdir: cannot create directory '.../sql/dump': Permission denied` in each
suite, which is the `postgres` user failing to create an unused scratch
directory in the source tree and is present on every branch; and
`decompress_vector_qual` needs `LANG=C.UTF-8`, without which `pg_regress`
initialises its temp instance as `SQL_ASCII` and that test's pre-existing
`text_table` section fails, as T2 documented.

The build is warning-free: `make -C build -j4` produced 0 lines matching
`warning`.

### Expected outputs touched

None by T6 - this task edited nothing under `src/`, `tsl/`, `sql/` or `test/`.
What the merges bring in, and what CI must regenerate for the other PostgreSQL
versions:

| file | state | who |
|---|---|---|
| `test/expected/chunk_append_date_tstz.out` | new, version-independent | T2 |
| `test/expected/constify_date.out` | new, version-independent | T3 |
| `test/expected/append-16.out` | +1 / -3 lines | T2 |
| `test/expected/plan_expand_hypertable-16.out` | +66 lines | T3 |
| `tsl/test/expected/decompress_vector_qual.out` | +73 / -7 lines | T2 |

Outputs needing CI regeneration, none of which exists in this container:
`test/expected/append-17.out`, `append-18.out`, `append-19.out` (T2, the same
3-line change) and `test/expected/plan_expand_hypertable-17.out`, `-18.out`,
`-19.out` (T3, the same 66-line hunk). If the `CURRENT_TIMESTAMP` fix of
draft 2 is also taken, add `tsl/test/shared/expected/constify_now-16.out`
through `-19.out`.

### Harness numbers

Six runs, all on `PGPORT=5437` with `--parallel-off-pass` and a pinned
`--start-date`, cluster destroyed after each. Serial numbers
(`max_parallel_workers_per_gather = 0`, the harness's `-np` ids) are quoted for
every comparison, as T5 recommends. Full tables, per-column storage and the
raw CSVs are in `results/T6-scorecard.md` and
`results/int-{baseline,after}*-{queries,storage}.csv` / `-summary.md` /
`-planbuffers.txt`.

**`metrics_date`, `--scale small`, 7-day chunks, 58 chunks, 1.92 M rows.**

| query | control exec ms (serial) | after exec ms (serial) | control plan ms | after plan ms | control plan buf | after plan buf | chunks in plan | vectorized |
|---|---:|---:|---:|---:|---:|---:|---|---|
| Q1 | 14.84 | **6.33** | 3.69 | **0.63** | 526 | **49** | 58 → **5** | no → **yes** |
| Q2 | 6.18 | **5.72** | 3.05 | **0.39** | 526 | **49** | 5 → 5 | yes → yes |
| Q3 | 5.15 | 5.20 | 0.74 | 0.56 | 55 | 55 | 5 → 5 | yes → yes |
| Q4 | 22.38 | 22.35 | 0.52 | 0.54 | 49 | 49 | 5 → 5 | yes → yes |
| Q5 | 0.04 | 0.04 | 0.17 | 0.22 | 13 | 13 | 1 → 1 | yes → yes |

Q1 gains **57.3%**, Q2 7.4% serial (59.6% parallel, because the change also
removes the two-worker plan the 58-chunk cost estimate was buying). Q3 to Q5
move by at most 1% and none is a regression. After the change Q1 on the `DATE`
twin is metric-for-metric the `TIMESTAMPTZ` twin: 6.33 vs 5.77 ms serial,
5 chunks vs 5, 49 planning buffers vs 49, 6025 buffers hit vs 6025, 144 000
rows scanned vs 144 000.

**`metrics_date`, `--scale customer`, 7-day chunks, 157 chunks, 52.56 M rows.**

| query | control exec ms (serial) | after exec ms (serial) | change | control plan ms | after plan ms | control plan buf | after plan buf |
|---|---:|---:|---|---:|---:|---:|---:|
| Q1 | 531.61 | **61.92** | **-88.4%, 8.6x** | 12.76 | **0.58** | 1731 | **61** |
| Q2 | 65.85 | 60.04 | -8.8% | 11.23 | **0.47** | 1731 | **61** |
| Q3 | 52.91 | 49.46 | -6.5% | 0.67 | 0.57 | 66 | 66 |
| Q4 | 258.15 | 235.42 | -8.8% | 0.68 | 0.59 | 60 | 60 |
| Q5 | 0.06 | 0.06 | 0% | 0.24 | 0.16 | 16 | 16 |

Chunks in the Q1 plan 157 → 5, vectorized filter no → yes, buffers hit
67 479 → 60 225, rows scanned 1 440 000 either way. **The gain grows with the
chunk count** - 57.3% over 58 chunks, 88.4% over 157 - which is the mechanism:
the unconstified plan carries every chunk in the hypertable. The `TIMESTAMPTZ`
twin needs 63.25 ms for the same query, so the 8.4x `DATE` penalty becomes
1.008x. **Nothing regressed at this scale**, in either pass.

**`metrics_date`, `--scale small --chunk-interval '1 day'`, 400 chunks**, the
run that answers T5's open question 4. Compared with T5's
`defaults-1d-index-1dc07b9` cell, the same configuration unpatched:

| Q1 metric, 1-day chunks | before | after | change |
|---|---:|---:|---|
| planning (parallel pass median) | 36.53 ms | **2.27 ms** | -93.8% |
| execution, serial | 61.30 ms | **13.52 ms** | -77.9% |
| execution, parallel allowed | 108.63 ms | **12.10 ms** | -88.9% |
| chunks in the plan | 400 | **30** | -92.5% |
| chunks excluded at startup | 0 | **1** | T2's rewrite |
| vectorized filter | no | **yes** | |

Most of the 1-day penalty was planning and the plan shape its cost bought, and
it is gone. What survives is not planning: compressed storage is still
66.56 B/row against 28.73 at 7 days (**2.32x**), batch fill still 24.0 rows
against 165.5, load still 351 346 rows/s against 496 434. T5's create-time
hint therefore stands unchanged, and its ordering note is confirmed.

**Storage.** The planner changes touch no storage path, and the runs say so to
the third decimal at customer scale: `metrics_date` 23.265 B/row before and
23.264 after, `metrics_tstz` 27.401 and 27.400, 314 000 batches and 167.4 rows
per batch in both. At `small` the same pair is 28.655 and 28.732, a 0.27%
difference that is the data generator's `random()` moving the `status` text by
1 477 bytes across 1.92 M rows.

The `DATE`-versus-`TIMESTAMPTZ` storage advantage, measured a third time and
larger at scale than the probe had seen: the time column is 0.548 against
1.548 B/row (**2.82x**) and the whole table 23.264 against 27.400 B/row
(**-15.1%**) at customer scale, against -5.4% at `small`.

**GUC on and off.** `results/T6-guc-on-off.sql` runs seven `DATE` query shapes
(`>=`, `>`, `<` and `=` against `now()`-derived bounds, `current_date - 30`, a
literal window, and a `(now() - interval)::date` cast bound) under all four
combinations of `timescaledb.enable_now_constify` and
`timescaledb.enable_runtime_exclusion`. **`shapes_disagreeing = 0`**: every
shape returns one distinct `(count, avg(v1))` across all four settings.
Output in `int-after-guccheck-ac62b98-guc-on-off.txt`.

### Scorecard

`results/T6-scorecard.md` and the README table. Summary:

| Design | Q1 / Q2 serial gain vs control | Bytes per row | Effort (vs base) | Go / no-go |
|---|---|---|---|---|
| runtime transform, all operators (T2) | T2's own run: Q1 +2.7%, Q2 -11.9%; measured on Q1: chunks reaching the executor 58 → 5, vectorized no → yes, buffers 6401 → 6025 | none | engine 4 files, +389/-19; with tests 10 files, +1263/-33 | **go** as PR 1 of Track A; alone it misses the fifth at +2.7% |
| constify DATE bounds (T3) | small **Q1 +57.3%**, Q2 +7.4%; customer **Q1 +88.4%**, Q2 +8.8%; planning 12.76 → 0.58 ms, plan buffers 1731 → 61 | none (23.265 → 23.264) | engine 1 file, +462/-95; with tests 6 files, +1956/-95 | **go** |
| orderby tiebreaker (T4, not merged) | 0% on both: changes no plan | **worse**: value columns -0.53%, metadata +371 200 B, all compressed columns **+0.50%**; physical total -1.67% vs a 0.24% noise floor | engine 1 file, +124/-1; with tests 3 files, +402/-1 | **no-go** as a default; keep as an opt-in |
| chunking and index defaults (T5) | n/a, a measurement task | 1 day 66.56, 7 days 28.71, 30 days 19.79 B/row; the default time index costs 6.9-10.2 B/row and 45-50% of insert throughput, and is never scanned | 0 files under `src/`, `tsl/`, `sql/`, `test/` | **no-go** as an engine default; **go** for a create-time `NOTICE` plus docs |

The rule - go when the design improves Q1 or Q2 by at least a fifth, with no
regression on Q3 to Q5 and identical results with the GUC on and off - is
applied design by design in the scorecard's own section, including the number
that failed for each no-go and the strict reading under which T2 alone would
also be a no-go.

Three findings that were not designs, all in the scorecard: the compression
prior correction from T1 (confirmed at two scales, and larger at customer
scale than the README claimed); the dead default time index and the
`rows_per_device_day x days_in_chunk` batch-fill formula from T5 (the index's
`idx_scan` delta is 0 in all four T6 runs as well, including over 157 chunk
indexes at customer scale); and the upstream `CURRENT_TIMESTAMP` constification
bug from T3.

`results/upstream-issues.md` holds the three drafts the brief asks for, in the
fields of `.github/ISSUE_TEMPLATE/enhancement.yml` and `bug_report.yml`.
**No issue and no pull request was opened.**

### Deviations from the brief

1. **`--start-date` at customer scale is 2023-09-24, not T5's 2025-08-19.**
   The brief says to pin T5's value "so cells are comparable". At 1095 days
   T5's date would end the data on 2028-08-17, two years in the future, and
   `day >= now() - interval '30 days'` would then select 725 days of rows
   instead of 30 - a different query, not a comparable cell. 2023-09-24 is
   1094 days before the run date, so the customer data ends today exactly as
   every `small` cell does. All four `small` cells keep T5's 2025-08-19.
2. **A sixth run was added: `int-baseline-customer`,** a customer-scale control
   on the base branch. The brief's table has no control at that scale, which
   would have left the headline row with no measured before/after. Both of the
   brief's conditions for the customer scale were met first (every small run
   under a minute: 33, 35 and 49 s; 23 GB free afterwards against the 10 GB
   required), so the customer run was **not** skipped.
3. **A seventh run was added: `int-after-guccheck`,** a `small` run whose only
   purpose is the GUC on/off equality check that the scorecard rule requires.
   It writes its own result files rather than overwriting `int-after`'s.
4. **Planning buffers are extracted by hand.** The brief asks for plan buffers
   per run; the harness's CSVs do not carry them (`probe_query_metrics` reads
   `Planning Time` but not the `Planning` object's `Shared Hit Blocks`). They
   are read from `probe_plans` with `results/T6-planbuffers.sql` inside the
   same locked command, with `--keep`, and saved as `*-planbuffers.txt`. The
   harness itself was not modified.
5. **`locked.sh bash -c '...'` is refused by this session's sandbox**, so each
   install-plus-run sequence is a small executable script in the scratchpad
   invoked as `locked.sh <script>`. Every sequence is still one locked command
   that begins with `make install` from this worktree's build (or, for the two
   control runs, from the base-branch build, which is what the brief asks for);
   `run-base.sh` reinstalls this worktree's build before exiting.
6. **`experiments/date-probe/bin/locked.sh` is not modified in this worktree.**
   The `9>&-` fix the earlier tasks carried uncommitted is already committed on
   the base branch (`0173dd1`), so there was nothing to leave out.
7. **`git_sha` in every result file name is this worktree's HEAD, not the
   installed extension.** `run.sh` reads the worktree HEAD, so
   `int-baseline-ac62b98-*` and `int-baseline-customer-59db144-*` are labelled
   with an integration sha although the extension installed for them was the
   base branch, built from `git archive` in a scratch directory. Stated in the
   scorecard too.
8. Two commit messages tripped the repository's commit-message hook (subject
   length, body wrapping); the hook only warns, and one was amended.

### Open questions for the orchestrator

The full deduplicated list, with who answers each, is the last section of
`results/T6-scorecard.md`. The four that block a decision:

1. **The customer's real rows per device per day** (T5 Q3, T1 Q3). The whole
   chunk-interval recommendation is `1000 / rows_per_device_day` days and
   nothing else; `DAYS`, `DEVICES` and `RPD` in `harness/run.sh` are still the
   probe plan's placeholders, so every absolute number at `customer` scale is
   the placeholder shape, not the customer's.
2. **Does any query filter a single day of uncompressed recent data?** (T5 Q2.)
   If not, "drop the default time index for `DATE`" clears a 2x ingest bar on
   its own; the probe cannot rule it in or out from an analytic query set.
3. **Are the customer's predicates only `>=`, or also `<`, `>`, `<=` and `=`
   against `now()`?** This is what decides how much of Track A's value comes
   from PR 1 rather than PR 2. The harness measures only `>=`, which is why
   T2's standalone number looks small: Q1 to Q5 contain no cross-type `<`,
   `>`, `<=` or `=` at all, and those four operators are exactly what T2 - and
   only T2 - can exclude.
4. **Apply the one-word `CURRENT_TIMESTAMP` fix?** (T3 Q1.) Genuine upstream
   bug, independent of `DATE`, drafted as its own issue; it needs
   `constify_now-16/17/18/19.out` regenerated and nothing else.

Two more worth flagging because this branch created them:

5. **`TIMESTAMPTZ` now has the gap `DATE` had** for the
   `ts >= date_trunc('day', now()) - interval '30 days'` shape: at customer
   scale it costs 14.32 ms of planning and 1733 planning buffers against
   0.47 ms and 61 for the `DATE` twin's `current_date - 30`. Extending
   `constify_now` to `date_trunc`- and `time_bucket`-of-`now()` bounds would
   close it for both types.
6. **T4 should be re-measured where batches are wide.** At both scales the
   batches hold 165-167 rows, because `segmentby = device_id` plus a 7-day
   chunk gives 168 rows per stream, so the intra-day disorder the tiebreaker
   removes spans 24 rows and never approaches the 1000-row limit. The current
   no-go is a verdict on a table shaped like the harness's.
