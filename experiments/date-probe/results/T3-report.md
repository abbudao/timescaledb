## Report: T3 on probe/a2-constify-date @ 2085ee2

Commits on top of T2's final head `ef03bde` (merged in `1e53e03`): `eb24762`
(WIP checkpoint made by the orchestrator while the session was paused),
`2085ee2` (the change, tests and expected outputs), plus this report and the
harness results. `src/planner/date_bounds.[ch]` are byte-identical to T2's.

### What was built

`src/planner/constify_now.c` now accepts, for a hypertable whose open
dimension is a `DATE`, the lower-bound shapes

| shape | operators involved | constant ANDed in |
|---|---|---|
| `d >\|>= now() [+\|- interval_const]`, also spelled `CURRENT_TIMESTAMP` | `date >\|>= timestamptz` (`F_DATE_GT_TIMESTAMPTZ`, `F_DATE_GE_TIMESTAMPTZ`) | `d >= F` |
| `d >\|>= (now() [+\|- interval_const])::date`, `now()::date` | `date >\|>= date` with the `timestamptz -> date` cast (`F_DATE_TIMESTAMPTZ`) on the right | `d OP F - 1`, operator kept |
| `d >\|>= CURRENT_DATE [+\|- int_const]` | `date >\|>= date` with `SQLValueFunction(SVFOP_CURRENT_DATE)`, `date_pli`, `date_mii` | `d OP F - 1 (+\|- n)`, operator kept |

where `F` is the **UTC calendar date of the plan-time clock value** with the
interval applied. The clock comes from `ts_get_mock_time_or_current_time()`
(transaction start in Release builds); the interval is applied exactly as for
`TIMESTAMPTZ` dimensions, including the existing 4 hour / 7 day safety buffers
for intervals with day / month components; `F` is read with `timestamp_date`
on the raw int64 (the `ts_pg_unix_microseconds_to_date` trick), so no session
timezone is consulted. The added clause carries `PLANNER_LOCATION_MAGIC` and
is removed again by `constraint_cleanup.c` after `hypertable_restrict_info`
has used it, so EXPLAIN shows only the original expression; the effect is the
number of chunks in the plan. Upper bounds, `CURRENT_TIMESTAMP(n)`,
`CURRENT_DATE - interval`, `LOCALTIMESTAMP`, `int + CURRENT_DATE`, non-dimension
columns, OR branches and JOIN conditions are left alone. The switch is
`timescaledb.enable_now_constify`; no second GUC was added (see the bound
analysis below).

**Safety argument, timezone-independent.** Two things can change between
planning and execution: the clock (only forward) and the session timezone
(anything). Every timezone offset PostgreSQL accepts is shorter than one day,
so for any instant the local date in any timezone is within one day of the UTC
date. With `T` the plan-time clock value after the interval and `F = UTC date
of T`:

- `d OP T`, cross-type: PostgreSQL evaluates `d::timestamptz OP T`, the cast
  giving the local midnight of `d`. For every `D < F` the local midnight of
  `D` is below `(D+1) 00:00 UTC <= F 00:00 UTC <= T`, so `d > T` and `d >= T`
  both imply `d >= F`. The added clause is `d >= F` for both operators.
- `d OP T::date`: the cast is the local date of `T`, at least `F - 1`.
- `d OP CURRENT_DATE +- n`: `CURRENT_DATE` is the local date of the clock, at
  least `F - 1`; the offset is applied to the bound.

A later execution has a later clock, and the day/month buffers cover the
timezone dependence of interval arithmetic exactly as upstream does for
`TIMESTAMPTZ`. Price: the bound is one day below the exact one in UTC (none
for `d >= T` when `T` is a local midnight), up to two days below it in
timezones east of UTC; those chunks stay in the plan and are removed by
startup exclusion through the original expression (T2's transform for the
cross-type shape, PostgreSQL's own stable evaluation for the others).

**Not reused from T2:** `ts_make_date_floor_expr` and friends build runtime
expressions whose casts follow the session timezone at *execution*, which is
exactly what a plan-time constant must not depend on. The constant is computed
directly in C instead; nothing had to be added to `date_bounds.[ch]`.

Commands run:

```
git checkout -B probe/a2-constify-date probe/a1-runtime-transform            # ed223fb at the time
BUILD_FORCE_REMOVE=true ./bootstrap -DCMAKE_BUILD_TYPE=Debug -DREGRESS_CHECKS=ON >/dev/null && make -C build -j2
experiments/date-probe/bin/locked.sh env CLAUDE_CODE_REMOTE=true CLAUDE_PROJECT_DIR=/home/user/timescaledb/.claude/worktrees/agent-a93175b355e14ee2f .claude/hooks/session-start.sh
experiments/date-probe/bin/locked.sh bash -c 'make -C build install >/dev/null && experiments/date-probe/bin/regress.sh insert_single'
git merge --no-edit probe/a1-runtime-transform                                # ef03bde -> 1e53e03
clang-format -i src/planner/constify_now.c                                    # 17.0.6
make -C build -j2                                                             # 0 warnings
export LANG=C.UTF-8 LC_ALL=C.UTF-8 TS_BUILD_DIR=/home/user/timescaledb/.claude/worktrees/agent-a93175b355e14ee2f/build   # see deviation 9
experiments/date-probe/bin/locked.sh bash -c 'make -C build install >/dev/null && experiments/date-probe/bin/regress.sh constify_date plan_expand_hypertable chunk_append_date_tstz append; SUITE=shared experiments/date-probe/bin/regress.sh constify_now constify_timestamptz_op_interval; SUITE=tsl experiments/date-probe/bin/regress.sh decompress_vector_qual'
git merge --no-commit --no-ff probe/harness                                   # 8844320, aborted afterwards
experiments/date-probe/bin/locked.sh <scratchpad>/harness_variant.sh t3-before <scratchpad>/before-src/build <out>   # make -C <ef03bde build> install && PGPORT=5435 harness/run.sh --variant t3-before --scale small --keep && psql extraction && pg/stop.sh
experiments/date-probe/bin/locked.sh <scratchpad>/harness_variant.sh t3-after build <out>                             # same with make -C build install
PGPORT=5435 experiments/date-probe/harness/pg/stop.sh --destroy
git merge --abort
```

Tests (all on PostgreSQL 16.15, Debug build, `LANG=C.UTF-8`):

- `constify_date` (new, core, Debug-only because it uses
  `timescaledb.current_timestamp_mock`) **pass**. Contents: 17 constified and
  11 rejected shapes as full EXPLAINs under UTC (1 chunk of 2 in the plan
  versus 2 of 2); views, subqueries, JOIN conditions, UPDATE and DELETE; a
  10-shape x 5-timezone matrix (UTC, Asia/Tokyo, America/Los_Angeles,
  Pacific/Kiritimati, Etc/GMT+12) with identical chunk counts in every
  timezone; GUC off; plan-time exclusion of everything and of all but the
  last chunk with the mock clock in the future; a one-chunk-per-day table
  showing where the bound lands for each shape (F for the cross-type
  comparisons, F - 1 with the operator kept for the DATE-typed spellings, the
  4 hour buffer moving it a day earlier at 02:00 UTC); constified row counts
  equal to PostgreSQL's own evaluation with the mock clock spelled as
  `ts_now_mock()` in UTC, Asia/Tokyo, America/Los_Angeles and Etc/GMT-4 (a
  local midnight, where `>` and `>=` differ); ChunkAppend startup exclusion
  of the day the constant left in; prepared statements with `CURRENT_DATE -
  30` and `now() - interval '30 days'` executed six times, then the mock clock
  advanced 40 days, then `SET timezone` to Asia/Tokyo, America/Los_Angeles,
  Pacific/Kiritimati and Etc/GMT+12, each count equal to the same statement
  prepared with `timescaledb.enable_now_constify = off`; and the same generic
  plan on the per-day table with the clock advanced 4 days, counts equal to
  the `ts_now_mock()` reference in three timezones (3, 2, 3 rows), with and
  without ChunkAppend.
- `plan_expand_hypertable-16` **pass** after regeneration: six new queries on
  `metrics_date` (Q1 and Q2 shapes, the cast shape, `CURRENT_TIMESTAMP`, and
  two upper bounds as negative controls). No mock clock there because the
  core suite also runs on Release builds in CI, so the constified plans are
  `Result / One-Time Filter: false` (data from 2000, clock 2026) and the
  upper bounds show all five chunks.
- `chunk_append_date_tstz` pass, `append-16` pass (with T2's `ef03bde`
  update), `constify_now-16` pass, `constify_timestamptz_op_interval-16`
  pass, `decompress_vector_qual` pass, `insert_single` pass.
- Results identical with the GUC on and off everywhere, including the
  harness: Q1 `144000 / 124.7805429652778`, Q2 `148800 / 123.16737188844088`
  on `metrics_date` with the GUC on, off, and on the `TIMESTAMPTZ` twin.

Expected outputs touched: `test/expected/constify_date.out` (new; generated
on 16, version-independent by construction: Seq Scans only, no InitPlans,
no version-specific text), `test/expected/plan_expand_hypertable-16.out`
(66 added lines). Outputs needing CI regeneration:
`test/expected/plan_expand_hypertable-17.out`, `-18.out`, `-19.out` (the same
66-line hunk after the `time_bucket exclusion with date` section).
`append-17/18/19.out` are T2's and already listed by T2.

Harness numbers: `harness/run.sh --scale small` on `PGPORT=5435`, T1's head
`8844320` merged without committing; 400 days x 200 devices x 24 rows, 58
chunks of 7 days per twin, compressed, segmentby `device_id`, data
2025-08-19 .. 2026-09-22, clock 11:34 UTC. "before" is T2's final head
`ef03bde` built from `git archive` in the scratchpad and installed for that
run (`run.sh` labels both runs `2085ee2`, it reads the worktree HEAD); "after"
is this branch. Median of three, PostgreSQL 16.15. Files:
`results/T3-harness-{before,after}-small.txt` (my psql extraction, incl. the
Q1/Q2 plans), `-queries.csv`, `-storage.csv`, `-summary.md` (the harness's own
export, which works since T1's `7103a22`). Note that T1's fix changed the
counting: `chunks_in_plan` is now distinct chunk relations left after startup
exclusion (was 2 nodes per chunk) and `chunks_excluded_startup` is no longer
doubled, so T2's `10 / 106` correspond to today's `5 / 53`.

| query | table | variant | exec ms | plan ms | plan buffers cold / warm | chunks in plan | excluded at startup | parallel | vectorized filter | rows scanned | shared hit |
|---|---|---|---:|---:|---:|---:|---:|---|---|---:|---:|
| Q1 `>= now() - 30d` | metrics_date | T2 after (`results/T2-*`) | 20.52 | 5.40 | 13846 / n.a. | 10 (old count) | 106 (old count) | Gather, 2 workers | t | 290000 | 6025 |
| Q1 | metrics_date | before (ef03bde, today) | 19.81 | 4.98 | 13615 / 526 | 5 | 53 | Gather, 2 workers | t | 144000 | 6025 |
| Q1 | metrics_date | **after (2085ee2)** | **6.03** | **0.49** | **1851 / 49** | 5 | **0** | **no** | t | 144000 | 6025 |
| Q1 | metrics_tstz | before / after | 5.89 / 6.12 | 0.50 / 0.45 | 1966 / 49 | 5 | 0 | no | t | 144000 | 6025 |
| Q2 `>= current_date - 30` | metrics_date | before | 16.29 | 3.71 | 531 / 526 | 5 | 53 | Gather, 2 workers | t | 148800 | 6085 |
| Q2 | metrics_date | **after** | **5.44** | **0.34** | **54 / 49** | 5 | **0** | **no** | t | 148800 | 6025 |
| Q2 `>= date_trunc('day', now()) - 30d` | metrics_tstz | before / after | 15.01 / 15.78 | 4.31 / 4.61 | 12052 / 526 | 5 | 53 | Gather, 2 workers | t | 148800 | 6025 |
| Q3 literals | metrics_date | before / after | 4.73 / 4.94 | 0.53 / 0.35 | | 5 | 0 | no | t | 148800 | 4225 |
| Q4 bucket + agg | metrics_date | before / after | 21.54 / 22.05 | 0.64 / 0.54 | | 5 | 0 | no | t | 148800 | 9025 |
| Q5 point | metrics_date | before / after | 0.04 / 0.04 | 0.19 / 0.18 | | 1 | 0 | no | t | 24 | 23 |

Q1 and Q2 on `metrics_date` now plan like Q3: 5 chunks costed instead of 58,
planning 5.0 -> 0.5 ms and 3.7 -> 0.3 ms, planning buffers 526 -> 49 warm
(13615 -> 1851 cold), no `Gather`, execution 19.8 -> 6.0 ms and 16.3 -> 5.4 ms,
i.e. identical to the `TIMESTAMPTZ` twin for Q1 and three times faster than
the twin for Q2 (whose `date_trunc('day', now()) - interval` is a shape
`constify_now` does not handle for `TIMESTAMPTZ` either). `vectorized_filter`
stays true on the compressed chunks (T2's result; the constant is gone from
the executed plan). Rows scanned and buffers are unchanged, as expected: T2
had already removed the extra I/O, T3 removes the planning of 53 chunks and
the parallel plan shape that their cost had bought.

**Conservative versus exact bound at harness scale** (7-day chunks aligned
on Thursdays; from the `exact versus conservative` and `whole cycle` tables in
`results/T3-harness-after-small.txt`):

- Today (clock 2026-09-22 11:34 UTC): Q1 exact bound 2026-08-24, conservative
  2026-08-23; Q2 exact 2026-08-23, conservative 2026-08-22; both fall inside
  chunk `[2026-08-20, 2026-08-27)`, so **5 chunks in the plan either way, 0
  lost**.
- Over a full 7-day cycle of clock days, the one-day loss keeps one extra
  chunk in the plan on **1 day in 7** (the day the exact bound is a chunk's
  first day: 2026-09-18 for Q1 midday, 2026-09-19 for Q2), and the 4 hour
  day-interval buffer adds a second such day for Q1 during the 4 hours after
  midnight UTC (2026-09-19 before 04:00 UTC). Expected extra chunks per plan:
  Q2 `1/7 ~ 0.14`, Q1 `1/7 + 1/7 * 4/24 ~ 0.17`. In chunk-days: exactly one
  chunk-day (Q2) or one chunk-day plus four hours (Q1) of exclusion power is
  given up; it materializes as one whole 7-day chunk being costed at plan
  time on those days and excluded at startup, roughly `(526-49)/53 ~ 9`
  planning buffers and `(4.98-0.49)/53 ~ 0.08 ms` for that chunk, then
  removed at startup like before T3. With 1-day chunks the extra chunk would
  be there every day (one chunk of the 30 in the plan); with 30-day chunks
  one day in 30.
- An exact bound would need the session timezone at plan time and is unsafe
  under `SET timezone` between planning and execution (the brief's caveat), so
  it could only ever be a default-off GUC. **Not justified**: the measured
  loss is at most one chunk on one day in seven, invisible in the medians
  above. Not implemented, no second GUC.

Deviations from the brief:

1. **Bound formula.** The brief's `current_date_at_plan_time - 1 day` is not
   safe for every timezone pair: the same instant is two calendar days apart
   in `Pacific/Kiritimati` (UTC+14) and `Etc/GMT+12` (UTC-12), so a plan made
   in the first and executed in the second would be one day too strict. The
   implementation uses the UTC date of the clock for all shapes, which is
   exactly the brief's safety argument ("within one day of the UTC date")
   carried through; both timezones are in the test matrix and the prepared
   statement test. For the cross-type shapes the bound is `F` rather than
   `F - 1` (`d >= F` follows from `d > T` as well as `d >= T`, proof in the
   code comment), one day tighter than the brief's formula and still
   timezone-independent.
2. `date +- days` is done with `pg_add_s32_overflow` / `IS_VALID_DATE` checks
   instead of `DirectFunctionCall2(date_mii)`: out-of-range arithmetic skips
   the optimization rather than raising "date out of range" at plan time for a
   query that would raise it at execution anyway. `timestamp_date` is called
   through `DirectFunctionCall1` as the brief says.
3. **`CURRENT_TIMESTAMP` on `TIMESTAMPTZ` dimensions.** Upstream's
   `is_valid_now_func()` compares `SQLValueFunction->type` (the result type
   Oid) with `SVFOP_CURRENT_TIMESTAMP`, so it never matches and
   `CURRENT_TIMESTAMP` has never been constified; `constify_now-16.out`
   documents the unconstified two-chunk plans while its comment claims the
   opposite. Fixing the field name makes 10 plans in that shared test lose
   their `Append`, and the expected file is outside T3's paths, so the
   acceptance of `CURRENT_TIMESTAMP` is scoped to `DATE` dimensions
   (`is_clock_func()`), the upstream function is left untouched, and the diff
   the fix would produce on 16 is saved as
   `results/T3-constify_now-16-current-timestamp.diff` (17/18/19 would need
   regeneration too).
4. The `plan_expand_hypertable` additions cannot use the mock clock (the core
   suite runs on `RelWithDebInfo` in CI, where the GUC does not exist), so
   they show full plan-time exclusion (`One-Time Filter: false`) rather than
   partial exclusion; the partial cases live in `constify_date`, which is
   registered in the Debug-only block like `constify_now`.
5. "Identical results with the GUC on and off" for the `now()`-derived shapes
   under the mock clock is checked against `ts_now_mock()` spelled out in the
   query, because with the GUC off `planner.c` no longer redirects `now()` to
   the mock and the count would follow the real clock. The GUC on/off
   comparison proper is done on the year-1000/3000 data (counts independent
   of the clock) and on the harness data.
6. EXPLAIN never shows the constant: `ts_planner_constraint_cleanup` removes
   the marked clause before the plan is printed, as for `TIMESTAMPTZ`. The
   tests show it through chunk counts and through one-chunk-per-day tables.
7. `experiments/date-probe/bin/locked.sh` carries the coordinator's `9>&-`
   fix in the worktree and is left out of every commit, as instructed.
8. Harness: `PGPORT=5435`, `--keep` so my extraction could run inside the same
   locked command, cluster stopped and `.pgdata` destroyed before
   `git merge --abort`. The harness's own CSV export now works, so both the
   harness files and my extraction are in `results/`.
9. The session's `TS_BUILD_DIR` pointed at `/home/user/timescaledb/build`
   (the main checkout's hook wrote it), so the first `regress.sh` run tested
   the main repository's tree; every test command since sets `TS_BUILD_DIR`
   to this worktree's `build/` explicitly. Worth a note in the README.

Push: `git push -u origin probe/a2-constify-date` was attempted once after
the final test run and refused with HTTP 403 ("Claude doesn't have GitHub
access to abbudao/timescaledb for your organization"); not retried. The branch
exists only in this worktree,
`/home/user/timescaledb/.claude/worktrees/agent-a93175b355e14ee2f`, head
`27adb4c` plus this amendment.

Open questions for the orchestrator:

1. Apply the one-word `CURRENT_TIMESTAMP` fix (`->type` -> `->op` in
   `is_valid_now_func`, then `is_clock_func` collapses into it) together with
   the saved diff and CI regeneration of `constify_now-17/18/19.out`? It is a
   genuine upstream bug and independent of DATE.
2. Q2 on the `TIMESTAMPTZ` twin (`ts >= date_trunc('day', now()) - interval`)
   is now the slow one (15.8 ms versus 5.4 ms for the DATE twin). Out of T3's
   scope, but a `date_trunc`/`time_bucket`-of-now() shape in `constify_now`
   would give `TIMESTAMPTZ` the same treatment.
3. Operand order `now() - interval <= d` is not handled, same as upstream for
   `TIMESTAMPTZ`; PostgreSQL does not normalize it. Worth adding for both
   types in one go if it shows up in customer queries.
4. `T2-append-16.diff` is applied in `ef03bde`; nothing left from T2's list.
