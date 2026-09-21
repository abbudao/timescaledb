# T3: Plan-time constification of DATE lower bounds

Branch: `probe/a2-constify-date`, created from `probe/a1-runtime-transform`
once T2 has landed its helper. Track A, planner. Starts after T2.

## Goal

`src/planner/constify_now.c` turns `col > now() - interval` into
`col > <const> AND col > now() - interval` so plan-time chunk exclusion can use
the constant, and it refuses any dimension whose type is not `TIMESTAMPTZ`
(see the type check near the dimension lookup). Extend it to `DATE`
dimensions for the lower-bound shapes below, reusing the bound helper from T2.
Once the added constant is a `DATE`, `hypertable_restrict_info` excludes
chunks at plan time unchanged, and the date-versus-date vectorized predicate
applies on compressed chunks.

## Allowed paths

- `src/planner/constify_now.c`
- `src/planner/date_bounds.[ch]` only for additions T2 did not need
- tests: `test/sql/include/plan_expand_hypertable_query.sql` and the
  PostgreSQL 16 expected output of that template; new
  `test/sql/constify_date.sql` plus registration and expected file

Forbidden: `src/nodes/chunk_append/`, `src/hypertable_restrict_info.c`,
`tsl/src/`, `sql/`, `.unreleased/`.

## Shapes to accept, lower bounds only

| shape | bound to add |
|---|---|
| `d >|>= current_date` | `current_date` evaluated at plan time |
| `d >|>= current_date ± int_const` | same, with the arithmetic applied |
| `d >|>= now() ± interval_const` and the `CURRENT_TIMESTAMP` spelling | a DATE bound derived from the timestamptz value, see below |
| `d >|>= (now() ± interval_const)::date` and `now()::date` | cast applied at plan time |

Upper bounds (`<`, `<=`) stay out, for the same reason the existing code
excludes them: a bound derived from the clock moves forward, so an added upper
bound could wrongly exclude rows in a cached plan.

## The safety argument, and the timezone twist

The existing argument: the added qual is a lower bound computed from the plan
time clock, the original qual stays, and since the clock only moves forward
the real bound at execution is never lower than the added one. Prepared and
cached plans stay correct.

For `DATE` there is a second variable: the session timezone. Both
`current_date` and the ceiling of a timestamptz depend on it, and a session
can `SET timezone` between plan and execution. An exact bound computed in one
timezone can be one day too strict in another.

Implement the timezone-independent conservative bound first:

```
bound = (T at UTC)::date - 1 day          for now()-derived shapes
bound = current_date_at_plan_time - 1 day for current_date shapes
```

Any timezone's ceiling date is within one day of the UTC date, so this bound is
safe under every timezone and still excludes all but at most one extra day of
chunks. Measure the exclusion it achieves in the harness. Only if the lost day
is material, add the exact bound behind a separate boolean GUC that defaults
to off, and document the timezone caveat next to it.

Reuse `timescaledb.enable_now_constify` as the switch. Do not add a second
knob unless the exact-bound variant is implemented.

## Implementation guidance

- Extend the dimension type check to accept `DATEOID` and branch on the
  shape. `is_valid_now_func` needs to accept `SQLValueFunction` with
  `SVFOP_CURRENT_DATE` for DATE dimensions.
- Compute the constant in C with `DirectFunctionCall` on PostgreSQL's own
  functions. Apply the interval with `timestamptz_mi_interval` or
  `timestamptz_pl_interval`. To get the UTC date without touching the session
  timezone GUC, pass the timestamptz value straight to `timestamp_date`: the
  two types share the int64 representation, and `timestamp_date` reads it as
  a timezone-free value, which is exactly the UTC date. This is the same trick
  `ts_pg_unix_microseconds_to_date` in `src/utils.c` relies on. Then subtract
  one day with `date_mii`. Take the clock from
  `ts_get_mock_time_or_current_time` so tests are deterministic.
- Keep the PG18 `RTE_GROUP` handling that already exists in the file working.

## Tests

`test/sql/include/plan_expand_hypertable_query.sql` already has a
`metrics_date` table. Add Q1 and Q2 shaped predicates there and regenerate the
PostgreSQL 16 output only.

New core test `test/sql/constify_date.sql` modelled on
`tsl/test/shared/sql/constify_now.sql.in`:

- `SET timescaledb.current_timestamp_mock TO '2000-01-15 12:00:00+00'`;
- data in years 1000 and 3000 so row counts are independent of the wall
  clock, exactly as the existing test does;
- for each shape, `EXPLAIN (COSTS OFF, TIMING OFF, SUMMARY OFF)` showing the
  constified filter, under `UTC`, `Asia/Tokyo` and `America/Los_Angeles`;
- a prepared statement: `PREPARE p AS SELECT count(*) ... WHERE day >= current_date - 30`,
  executed six times to reach a generic plan, then the mock clock advanced by
  40 days and executed again; compare against the same query with
  `timescaledb.enable_now_constify = off`;
- the same prepared statement with `SET timezone` changed between executions.

## Commands

Install and test sequences go through `experiments/date-probe/bin/locked.sh`
as one command, see "Working in a worktree" in the README. Unlocked:

```bash
make -C build -j"$(nproc)" && make -C build install
clang-format -i src/planner/constify_now.c src/planner/date_bounds.[ch]
experiments/date-probe/bin/regress.sh constify_date plan_expand_hypertable chunk_append_date_tstz
SUITE=shared experiments/date-probe/bin/regress.sh constify_now constify_timestamptz_op_interval
```

Then run the harness locally: Q1 and Q2 on `metrics_date` must show fewer
`chunks_in_plan` than the baseline, not just startup exclusion.

## Done criteria

- Tests above pass on PostgreSQL 16; the report lists every `.sql.in`
  expected file that needs regeneration by CI for other versions.
- Identical results with the GUC on and off in every test, including the
  prepared-statement and timezone-change cases.
- Harness: `chunks_in_plan` for Q1 and Q2 on `metrics_date` drops to the same
  order as Q3, and `vectorized_filter` becomes true on compressed chunks.

## Report

Template in `experiments/date-probe/README.md`. Add: how many chunk-days the
conservative bound leaves on the table versus an exact bound at the harness
scale, and whether that justifies the exact-bound variant.
