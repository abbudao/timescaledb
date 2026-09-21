# T2: Runtime cross-type transform for all five operators

Branch: `probe/a1-runtime-transform` (from the base branch). Track A, planner.

## Goal

Today `ts_transform_cross_datatype_comparison` in
`src/nodes/chunk_append/transform.c` rewrites `date_col OP timestamptz_expr`
into a date-versus-date comparison only for `>` and `<=`, because a plain cast
to `date` floors the value and is only equivalent for those two operators.
Extend it to `>=`, `<`, and `=` with exact bound expressions so ChunkAppend
startup exclusion covers every comparison shape on a `DATE` dimension.

Put the bound construction in a small shared helper that T3 will reuse for
plan-time constification.

## Allowed paths

- `src/nodes/chunk_append/transform.c`
- new: `src/planner/date_bounds.c`, `src/planner/date_bounds.h`, and the
  matching line in `src/planner/CMakeLists.txt`
- tests: new `test/sql/chunk_append_date_tstz.sql` plus its registration in
  `test/sql/CMakeLists.txt` and `test/expected/chunk_append_date_tstz.out`;
  additions to `tsl/test/sql/decompress_vector_qual.sql` and its expected file

Forbidden: `src/planner/constify_now.c`, `src/hypertable_restrict_info.c`,
anything under `tsl/src/`, `sql/`, catalog code, `.unreleased/`.

## Background you should verify first

1. Cross-type `date OP timestamptz` operators are STABLE in PostgreSQL because
   they depend on the session timezone. `date OP timestamp` operators are
   IMMUTABLE, which is why the existing code leaves them alone.
2. Find where the transformed clause is consumed. Start at the callers of
   `ts_transform_cross_datatype_comparison` under `src/nodes/chunk_append/`.
   Establish whether the rewritten clause replaces the executed filter or is
   used only to decide exclusion. Write the answer in your report; it decides
   whether a merely necessary condition is acceptable for `=`.
3. `estimate_expression_value` folds STABLE expressions at executor startup,
   which is what makes the rewritten clause usable for startup exclusion.

## Semantics

Let `d` be the DATE column, `T` the timestamptz expression, and let casts use
the session timezone as PostgreSQL does. Define:

```
floor(T) = T::date
ceil(T)  = CASE WHEN (T::date)::timestamptz = T THEN T::date ELSE T::date + 1 END
```

PostgreSQL evaluates `d OP T` as `local_midnight(d) OP T`. Since
`local_midnight` is monotonic in `d`:

| original | rewritten | status |
|---|---|---|
| `d > T` | `d > floor(T)` | existing |
| `d <= T` | `d <= floor(T)` | existing |
| `d >= T` | `d >= ceil(T)` | new |
| `d < T` | `d < ceil(T)` | new |
| `d = T` | `d = T::date AND (T::date)::timestamptz = T` | new, exact |

Mirrored forms `T OP d` swap the strategy the way the existing code already
does. For `=`, if the clause is used only for exclusion, `d = T::date` alone is
a safe necessary condition; state which one you implemented and why.

DST is the trap: on transition days `local_midnight(d)` may not exist or may be
ambiguous, and PostgreSQL resolves it inside `date2timestamptz`. Do not
reimplement that logic. Build the bound out of PostgreSQL's own cast functions
so the resolution is identical by construction.

## Implementation guidance

- `date_bounds.h` exposes something like
  `Expr *ts_make_date_bound_expr(Expr *tstz_expr, StrategyNumber strategy, bool *exact)`
  returning a DATE-typed expression. Build it from `FuncExpr` and `CaseExpr`
  nodes using the cast functions found with `ts_get_cast_func` and the `+ 1`
  through `F_DATE_PLI`. Apache license header, `clang-format`.
- Keep the existing behaviour for `>` and `<=` byte-for-byte identical in
  EXPLAIN output, so existing expected files do not churn.
- Do not add a GUC. The existing `timescaledb.enable_runtime_exclusion`
  already gates this path.

## Tests

New core test `test/sql/chunk_append_date_tstz.sql`:

- table `date_ca(day date, v int)` as a hypertable with 1-day chunks holding
  ten consecutive days;
- `SET timezone` to `UTC`, `Asia/Tokyo`, `America/Los_Angeles`, and one DST
  transition day for `America/New_York` (2020-03-08) and `Europe/London`
  (2020-03-29);
- for each operator in `> >= < <= =` and for a bound at local midnight and at
  12:00, run `EXPLAIN (COSTS OFF, TIMING OFF, SUMMARY OFF)` and check
  `Chunks excluded during startup`, then compare `SELECT count(*)` with
  `timescaledb.enable_runtime_exclusion` on and off. Counts must match in
  every cell.
- use literal `timestamptz` constants, not `now()`, so the output is
  deterministic. A literal folded to a Const still goes through a STABLE
  operator and is therefore handled at startup, which is the path under test.

Add DATE-versus-TIMESTAMPTZ cases to `tsl/test/sql/decompress_vector_qual.sql`
and record in the report whether the filter on compressed chunks is shown as
`Vectorized Filter`. If it is not, explain why (the constant is folded only at
startup, so the planner still sees a cross-type expression). That gap is T3's.

Register the new test in `test/sql/CMakeLists.txt`. Only PostgreSQL 16 output
can be generated here; if the plan text turns out to vary by version, convert
the test into a `.sql.in` template and say so in the report.

## Commands

Install and test sequences go through `experiments/date-probe/bin/locked.sh`
as one command, see "Working in a worktree" in the README. Unlocked:

```bash
make -C build -j"$(nproc)" && make -C build install
clang-format -i src/nodes/chunk_append/transform.c src/planner/date_bounds.[ch]
experiments/date-probe/bin/regress.sh chunk_append_date_tstz append plan_expand_hypertable
SUITE=tsl    experiments/date-probe/bin/regress.sh decompress_vector_qual
SUITE=shared experiments/date-probe/bin/regress.sh constify_now constify_timestamptz_op_interval
```

Then, with the harness from `probe/harness` merged into your worktree locally
(do not commit the merge), run `harness/run.sh --variant baseline --scale small`
and compare Q1 on `metrics_date` against the baseline result files.

## Done criteria

- Build clean with warnings as errors, formatter clean.
- All tests in the command list pass on PostgreSQL 16; no existing expected
  output changed except where a new case was added.
- Every cell of the operator by timezone matrix shows identical counts with
  runtime exclusion on and off.
- Harness Q1 on `metrics_date` reports `chunks_excluded_startup > 0` and a
  buffer count comparable to Q1 on `metrics_tstz`.

## Report

Template in `experiments/date-probe/README.md`. Add: the answer to background
item 2, the exact expression chosen for `=`, and the Q1 before and after
numbers.
