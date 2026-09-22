## Report: T2 on probe/a1-runtime-transform @ 5baede3

Commits on top of the base `72c3c27`: `27cdd38` (helper, transform, test
sources), `7c8a54d` (expected outputs), `5baede3` (version-independent
InitPlan section, harness results), plus this report.

### Background verified before writing code

1. **Volatility.** `pg_operator` joined to `pg_proc` on PostgreSQL 16.15: all six
   `date OP timestamptz` and `timestamptz OP date` operators are implemented by
   `date_*_timestamptz` / `timestamptz_*_date` with `provolatile = 's'`
   (STABLE); all `date OP timestamp` and `timestamp OP date` operators are
   `provolatile = 'i'` (IMMUTABLE). Casts the helper uses: `timestamptz -> date`
   is `date(timestamptz)` oid 1178 (STABLE, assignment), `date -> timestamptz` is
   `timestamptz(date)` oid 1174 (STABLE, implicit), `date + int4` is `date_pli`
   oid 1141 (IMMUTABLE), `timestamptz = timestamptz` is operator 1320 /
   `timestamptz_eq` 1152 (IMMUTABLE).
2. **Where the transformed clause is consumed.** Four callers of
   `ts_transform_cross_datatype_comparison`:
   - `src/nodes/chunk_append/planner.c:245`: at plan time every restriction
     clause is transformed and stored per child in `custom_private`
     (`chunk_ri_clauses`); the child scan's own `qual` is left alone, so the
     executed filter stays the original `day >= T` (the `Filter:` lines in every
     plan of the new test show the cross-type operator). `exec.c`
     `do_startup_exclusion` folds the stored clauses with
     `estimate_expression_value` and feeds them to `can_exclude_chunk`
     (`predicate_refuted_by` plus a constant-FALSE/NULL check); runtime exclusion
     reuses them for parameters. Exclusion only.
   - `src/nodes/chunk_append/exec.c:1032`: same, for the extra clauses derived
     from parameterised `time_bucket` comparisons. Exclusion only.
   - `src/nodes/constraint_aware_append/constraint_aware_append.c:483`: same
     shape, consumed through `relation_excluded_by_constraints` in
     `ca_append_begin`. Exclusion only.
   - `tsl/src/nodes/columnar_scan/planner.c:963` (`find_vectorized_quals`): the
     transformed clause goes to `vector_qual_make`, and when that succeeds the
     **vectorized clause replaces the executed qual** for the batch; the original
     is kept only when vectorization fails. For compressed chunks the rewrite is
     therefore the executed filter, and a merely necessary condition for `=`
     would return wrong rows. Consequence: the `=` rewrite must be exactly
     equivalent.
3. **Startup folding.** `estimate_expression_value` runs
   `eval_const_expressions_mutator` with `estimate = true`, which folds STABLE
   functions and external Params; ChunkAppend calls it from
   `ts_constify_restrictinfos` with a skeleton `PlannerInfo` that carries
   `es_param_list_info`. Confirmed by the new test: a literal `timestamptz`
   constant (already a Const, but behind a STABLE cross-type operator) and a
   `$1` of a generic prepared plan both give `Chunks excluded during startup: N > 0`
   for every operator.

### The rewrite

`src/planner/date_bounds.[ch]` (Apache header, clang-format 17 clean) builds
DATE-typed bounds only from PostgreSQL's own functions, found through
`ts_get_cast_func` / `ts_get_operator` and `F_DATE_PLI`:

```
floor(T) = date(T)
ceil(T)  = CASE WHEN timestamptz(date(T)) = T THEN date(T) ELSE date_pli(date(T), 1) END
```

| original | rewritten | exact |
|---|---|---|
| `d > T`  | `d > floor(T)`  (same nodes as before) | yes |
| `d <= T` | `d <= floor(T)` (same nodes as before) | yes |
| `d >= T` | `d >= ceil(T)` | yes |
| `d < T`  | `d < ceil(T)` | yes |
| `d = T`  | `d = floor(T) AND timestamptz(floor(T)) = T` | yes |

Mirrored `T OP d` keeps the argument order and commutes the strategy.
`ts_make_date_bound_expr(tstz_expr, strategy, &exact)` returns floor for
`>`/`<=`, ceil for `>=`/`<`, and floor with `*exact = false` for `=`;
`ts_make_date_floor_expr`, `ts_make_date_ceil_expr` and
`ts_make_date_is_midnight_expr` are exported separately for T3.

**Exact expression chosen for `=`:** `d = T::date AND (T::date)::timestamptz = T`,
the brief's exact form, because consumer 4 above executes the rewritten clause,
so the necessary-only `d = T::date` is not acceptable. A value that is not a
local midnight folds to constant FALSE at startup, which `can_exclude_chunk`
turns into "all chunks excluded" (10 of 10 in the test); a midnight value folds
to `d = '2020-03-08'::date` and excludes all but one chunk.

DST correctness was checked outside TimescaleDB first (scratch PostgreSQL 16,
no extension): a PL/pgSQL sweep over UTC, Asia/Tokyo, America/Los_Angeles,
America/New_York (both transitions), Europe/London (both), America/Santiago
(midnight gap 2019-09-08, ambiguous midnight 2019-04-07), America/Sao_Paulo,
Asia/Beirut, America/Havana and Pacific/Apia (skipped day), with instants every
15 minutes across the transition days plus microsecond neighbours of midnight
and 01:00, and every date within +-4 days, comparing PostgreSQL's `d OP T`
against the rewritten forms for all five operators: 0 mismatches (the range
form `d >= ceil(T) AND d <= floor(T)` for `=` was included and also had 0).

**Vectorized Filter on compressed chunks:** yes for `>`, `<=`, `>=`, `<`
(literal and `now()`-derived bounds alike), because `vector_qual_make` accepts
any Var-free, non-volatile right-hand side as a runtime constant, so the CASE
bound qualifies; `decompress_vector_qual` shows
`Vectorized Filter: (ts >= CASE WHEN (timestamptz(date('...')) = '...') THEN date('...') ELSE date_pli(date('...'), 1) END)`
and the harness reports `vectorized_filter = t` for Q1 on `metrics_date`. The
gap the brief expected does not exist for the inequalities. `=` is **not**
vectorized: its second conjunct has no Var, `vector_qual_make` rejects that
argument and therefore the whole AND, and the original cross-type `Filter:`
runs row by row (still correct, just not vectorized).

Commands run:

```
git checkout -B probe/a1-runtime-transform claude/hypertable-date-time-dimension-ms75bt   # 72c3c27
BUILD_FORCE_REMOVE=true ./bootstrap -DCMAKE_BUILD_TYPE=Debug -DREGRESS_CHECKS=ON >/dev/null && make -C build -j2
experiments/date-probe/bin/locked.sh env CLAUDE_CODE_REMOTE=true CLAUDE_PROJECT_DIR="$(pwd)" .claude/hooks/session-start.sh
experiments/date-probe/bin/locked.sh bash -c 'make -C build install && experiments/date-probe/bin/regress.sh insert_single'
clang-format -i src/nodes/chunk_append/transform.c src/planner/date_bounds.c src/planner/date_bounds.h   # 17.0.6
make -C build -j2                                                                                       # 0 warnings
export LANG=C.UTF-8 LC_ALL=C.UTF-8   # see Tests
experiments/date-probe/bin/locked.sh bash -c 'make -C build install && experiments/date-probe/bin/regress.sh chunk_append_date_tstz append plan_expand_hypertable; SUITE=tsl experiments/date-probe/bin/regress.sh decompress_vector_qual; SUITE=shared experiments/date-probe/bin/regress.sh constify_now constify_timestamptz_op_interval'
experiments/date-probe/bin/locked.sh bash -c 'make -C build install && experiments/date-probe/bin/regress.sh chunk_append_date_tstz'   # regeneration after the InitPlan edit
git merge --no-commit --no-ff probe/harness   # b1593f7, aborted afterwards
PGPORT=5434 experiments/date-probe/bin/locked.sh bash -c 'make -C build install && experiments/date-probe/harness/run.sh --variant t2-after --scale small'
PGPORT=5434 experiments/date-probe/bin/locked.sh bash -c 'make -C <72c3c27 build> install && experiments/date-probe/harness/run.sh --variant t2-before --scale small && make -C build install'
git merge --abort
```

Tests:

- `chunk_append_date_tstz` (new) pass. 90-cell matrix (5 operators x midnight/noon
  x UTC, Asia/Tokyo, America/Los_Angeles, America/New_York 2020-03-08,
  Europe/London 2020-03-29, America/Santiago 2019-09-08 and 2019-04-07, plus
  mirrored forms for UTC and New_York): `count_mismatches = 0` between
  `timescaledb.enable_runtime_exclusion` on, off, and ChunkAppend plus
  ConstraintAwareAppend disabled (plain PostgreSQL evaluation);
  `cells_without_startup_exclusion = 0`. Every operator shows
  `Chunks excluded during startup` in EXPLAIN, for literals, `$1` of a generic
  prepared plan, and through ConstraintAwareAppend; the InitPlan case shows
  `Chunks excluded during runtime: 5` with the GUC on and nothing with it off,
  same count.
- `plan_expand_hypertable-16` pass, `constify_now-16` pass,
  `constify_timestamptz_op_interval-16` pass, `insert_single` pass.
- `decompress_vector_qual` pass with `LANG=C.UTF-8`. With `LANG` unset (this
  container's default) pg_regress initialises the temp instance as `SQL_ASCII`
  and the pre-existing `text_table` section of that test fails
  (`sum(length(a))` 134551 bytes instead of 118551 characters, then the
  non-ASCII `LIKE` patterns error); unrelated to this change and not touched.
- `append-16` **fail**, 3-line diff, saved as `results/T2-append-16.diff`:
  ```
  -   Chunks excluded during startup: 2
  +   Chunks excluded during startup: 3
  -   ->  Index Scan Backward using _hyper_3_11_chunk_metrics_date_time_idx on _hyper_3_11_chunk (actual rows=0.00 loops=1)
  -         Index Cond: (("time" > 'Sat Jan 15 00:00:00 2000 PST'::timestamp with time zone) AND ("time" < 'Fri Jan 21 00:00:00 2000 PST'::timestamp with time zone))
  ```
  Query 152 of `test/sql/include/append_query.sql`,
  `metrics_date WHERE time > '2000-01-15'::timestamptz AND time < '2000-01-21'::timestamptz`,
  annotated in the test as "should all have 2 chunks": the `::date` and
  `::timestamp` variants already excluded 3 chunks, and the `::timestamptz`
  variant now does too because `<` is rewritten (`ceil` of a local midnight is
  that date). Rows unchanged (1440). This is the intended effect, not a
  regression, but `test/expected/append-16.out` is outside the paths this brief
  allows, so it was not edited.

Expected outputs touched: `test/expected/chunk_append_date_tstz.out` (new,
generated on PostgreSQL 16, version-independent by construction: no InitPlan
headers, `BUFFERS OFF`, Seq Scans only), `tsl/test/expected/decompress_vector_qual.out`
(DATE section only). Outputs needing CI regeneration: none for the files in this
branch. Pending for whoever applies `results/T2-append-16.diff`:
`test/expected/append-17.out`, `append-18.out`, `append-19.out` (same 3 lines).

Harness numbers: `harness/run.sh --scale small` (400 days x 200 devices x 24
rows, 58 chunks of 7 days per twin, compressed, segmentby `device_id`), median
of three runs, PostgreSQL 16.15. "before" is the unmodified base `72c3c27`,
"after" is this branch. Files: `results/T2-harness-{before,after}-small.txt`,
`-queries.csv`, `T2-harness-after-Q1-plans.txt`. Another worktree's harness
cluster was running on the same 4 cores during both runs, so the millisecond
columns are indicative (a first "after" run measured Q1 on `metrics_date` at
17.37 ms and Q4 at 21.29 ms).

| query | table | variant | exec ms | plan ms | chunks in plan | excluded at startup | vectorized filter | rows scanned | shared hit |
|---|---|---|---:|---:|---:|---:|---|---:|---:|
| Q1 `>= now() - 30d` | metrics_date | before | 21.10 | 3.79 | 116 | 0 | f | 260934 | 6401 |
| Q1 | metrics_date | **after** | 20.52 | 5.40 | 10 | 106 | t | 290000 | 6025 |
| Q1 | metrics_tstz | before | 5.93 | 0.44 | 10 | 0 | t | 290000 | 6025 |
| Q1 | metrics_tstz | after | 6.16 | 0.62 | 10 | 0 | t | 290000 | 6025 |
| Q2 `>= current_date - 30` | metrics_date | before | 14.95 | 3.58 | 10 | 106 | t | 299600 | 6025 |
| Q2 | metrics_date | after | 16.73 | 4.33 | 10 | 106 | t | 299600 | 6025 |
| Q2 | metrics_tstz | before | 16.14 | 4.11 | 10 | 106 | t | 299600 | 6025 |
| Q2 | metrics_tstz | after | 15.50 | 4.47 | 10 | 106 | t | 299600 | 6025 |
| Q3 literals | metrics_date | before / after | 4.57 / 4.82 | 0.34 / 0.48 | 10 | 0 | t | 299600 | 4225 |
| Q3 | metrics_tstz | before / after | 4.66 / 4.74 | 0.33 / 0.43 | 10 | 0 | t | 299600 | 4225 |
| Q4 bucket + agg | metrics_date | before / after | 21.08 / 29.40 | 0.37 / 0.72 | 10 | 0 | t | 299600 | 9025 |
| Q4 | metrics_tstz | before / after | 15.95 / 16.53 | 0.36 / 0.47 | 10 | 0 | t | 299600 | 9025 |
| Q5 point `= d` | metrics_date | before / after | 0.04 / 0.07 | 0.14 / 0.16 | 2 | 0 | t | 26 | 23 |
| Q5 | metrics_tstz | before / after | 0.04 / 0.05 | 0.14 / 0.20 | 2 | 0 | t | 26 | 23 |

Q1 on `metrics_date`, before and after: `chunks_excluded_startup` 0 -> 53 per
ChunkAppend (the harness reports 106, it sums two counters), chunks in the plan
116 -> 10, `Vectorized Filter` f -> t, shared buffers 6401 -> 6025, which is
exactly the `metrics_tstz` figure; rows scanned and buffers are now identical
to the TIMESTAMPTZ twin. Row count and `avg(v1)` are identical with
`timescaledb.enable_runtime_exclusion` on and off (144000 rows,
124.78049004166667). The remaining execution-time gap to `metrics_tstz`
(about 20 ms versus 6 ms) is plan shape, not I/O: the planner still costs all
58 chunks for the DATE twin, chooses `Gather` with two workers and a parallel
ChunkAppend, and spends 5.4 ms and 13846 planning buffers versus 0.6 ms and
1898 for the twin whose chunks `constify_now` already removed at plan time.
That is the part T3 addresses. Q2 to Q5 are unchanged in shape, as expected
(same-type or immutable bounds).

Deviations from the brief:

1. Branch created from the probe base `72c3c27` (`claude/hypertable-date-time-dimension-ms75bt`),
   not from the worktree's HEAD `3af0667`, which lacked `experiments/` and the
   hook; confirmed by the coordinator.
2. The two InitPlan EXPLAINs in the new test print only the
   `Chunks excluded during ...` counters (through a small plpgsql helper) instead
   of the full plan, because PostgreSQL 17+ prints `InitPlan 1` where 16 prints
   `InitPlan 1 (returns $0)`. The brief's fallback was a `.sql.in` template; a
   single version-independent output avoids three expected files CI would have
   to regenerate.
3. `test/expected/append-16.out` not updated (outside allowed paths); the
   `append` test fails on this branch until the 3-line patch is applied.
4. `experiments/date-probe/bin/locked.sh` carries the coordinator's `9>&-` fix
   in the worktree and is deliberately left out of every commit.
5. Harness ran on `PGPORT=5434` because another worktree's harness cluster held
   5433, and the CSVs / plan text under `results/T2-harness-*` were extracted
   with my own psql queries against the probe tables, because the harness's
   `export.sql` cannot write its CSVs (see open questions). The "before" run is
   labelled `git_sha 7c8a54d` by `run.sh` (it reads the worktree HEAD) although
   the installed extension was `72c3c27`, built from `git archive 72c3c27` in
   the scratchpad.

Push: `git push -u origin probe/a1-runtime-transform` was attempted once and
refused with HTTP 403 ("Claude doesn't have GitHub access to
abbudao/timescaledb for your organization"); not retried. The branch exists
only in this worktree: `/home/user/timescaledb/.claude/worktrees/agent-a60925aa01f171cca`.

Open questions for the orchestrator:

1. `=` could be rewritten as `d >= ceil(T) AND d <= floor(T)` instead: equally
   exact (0 mismatches in the sweep), identical exclusion, and both conjuncts are
   `Var op runtime-constant`, so `=` would also get a Vectorized Filter. Only
   `transform.c` would change. Worth switching, or keep the brief's form?
2. Who applies `results/T2-append-16.diff` and triggers the `append-17/18/19`
   regeneration: T6, or should T2's allowed paths be widened?
3. Harness (T1) bugs found while measuring: (a) `sql/export.sql` uses
   `:'run_id'` / `:'queries_csv'` inside `\copy`, and psql performs no variable
   interpolation in `\copy` arguments, so every run ends with
   `syntax error at or near ":"`, exit 3, no CSV and no summary, plus an empty
   file literally named `:` in the cwd (psql opens the target before the server
   rejects the query); (b) because of (a) `run.sh` never reaches
   `pg/stop.sh`, so the cluster stays up on 5433 and collides with the next
   worktree's run (`could not bind IPv4 address`), and under the pre-fix
   `locked.sh` it also kept the install lock; (c) `run.sh --scale small` takes
   about 40 s here, not the documented 7 minutes.
4. `chunks_excluded_startup` in the harness sums two ChunkAppend counters per
   query (106 = 2 x 53 for 58 chunks minus the 5 needed) and `chunks_in_plan`
   counts two scan nodes per chunk; fine for comparisons, but the README should
   say so.
