# T6: Integration branch, combined measurement, scorecard

Branch: `probe/integration`, created from the base branch. Orchestration
task: merges, measurements and writing. No new engine code.

## Goal

Combine the engine changes that earned a go, measure them together on the
finished harness, and produce the scorecard and the upstream issue drafts
from the five task reports.

## Inputs

Read all of these before doing anything else:

- `results/T1-report.md` on `probe/harness`: baseline numbers and metric
  definitions
- `results/T2-report.md` on `probe/a1-runtime-transform`
- `results/T3-report.md` on `probe/a2-constify-date`
- `results/T4-report.md` on `probe/b1-orderby-tiebreaker`
- `results/T5-report.md` and `results/T5-defaults-1dc07b9.md` on
  `probe/c1-defaults-measurement`

Read them with `git show <branch>:experiments/date-probe/results/<file>`
before merging, so the merge cannot change what you read.

## Allowed paths

- merges of the branches listed below into `probe/integration`
- `experiments/date-probe/results/**`
- `experiments/date-probe/README.md`, scorecard section only

Forbidden: any edit to `src/`, `tsl/`, `sql/`, `test/` beyond what the merges
bring in. If a merge conflicts in those paths, stop and report the conflict
instead of resolving it by hand.

## Integration branch

1. `git checkout -B probe/integration claude/hypertable-date-time-dimension-ms75bt`
2. `git merge --no-edit probe/c1-defaults-measurement` (brings the harness
   with T5's parallel-off pass and index sampling)
3. `git merge --no-edit probe/a2-constify-date` (brings T2 and T3)
4. Do not merge `probe/b1-orderby-tiebreaker`. T4's verdict is no-go as a
   default; it stays a separately measured opt-in.
5. Build without the lock, then one locked command for
   `make -C build install` plus this test list:
   core `constify_date plan_expand_hypertable chunk_append_date_tstz append insert_single`,
   shared `constify_now constify_timestamptz_op_interval`,
   tsl `decompress_vector_qual`. Set `LANG=C.UTF-8 LC_ALL=C.UTF-8` and
   `TS_BUILD_DIR` to your worktree's build. All must pass; a failure is a
   finding, not something to fix here.

## Measurements

All harness runs are one locked command each, starting with
`make -C build install`, on `PGPORT=5437`, with `--parallel-off-pass` so
serial numbers exist, and with `--start-date` pinned to the value T5 used so
cells are comparable.

| run | branch installed | flags | purpose |
|---|---|---|---|
| `int-baseline` | base branch build, from a `git archive` of the base branch in a scratch directory | `--scale small` | control on the same day and machine |
| `int-after` | `probe/integration` | `--scale small` | the two planner changes together |
| `int-after-1d` | `probe/integration` | `--scale small --chunk-interval '1 day'` | T5's open question: how much of the 1-day penalty was planning |
| `int-after-customer` | `probe/integration` | `--scale customer` | headline at scale, only if the small runs took under a minute each and disk allows; skip and say so otherwise |

Report for every run: Q1 to Q5 execution and planning time, serial and
parallel, chunks in plan, chunks excluded at startup, vectorized filter, plan
buffers, and the per-table compressed bytes per row. Quote serial numbers
when comparing configurations, as T5 recommends.

## Scorecard

Write `results/T6-scorecard.md` with:

1. One table, one row per design, columns: measured gain on Q1 and Q2 serial
   versus the control, bytes per row effect, tests added and passing, expected
   outputs needing CI regeneration, effort as files and lines changed from
   `git diff --stat` against the base, go or no-go.
2. The go or no-go rule applied uniformly: go when the design improves the
   customer shape Q1 or Q2 by at least a fifth with no regression on Q3 to Q5
   and identical results with its GUC on and off; no-go otherwise, with the
   number that failed.
3. The three findings that were not designs: the compression prior correction
   from T1, the dead time index and batch-fill formula from T5, and the
   upstream `CURRENT_TIMESTAMP` constification bug from T3.
4. Open questions carried forward, deduplicated from the five reports, with
   who answers each: customer numbers the user must supply, decisions for the
   maintainers, follow-up designs.

Fill the scorecard table in `README.md` with the same go or no-go values.

## Upstream issue drafts

Write `results/upstream-issues.md` with one draft per issue, following the
repository's Enhancement issue template fields, each short enough to paste:

- Track A, planner: DATE dimensions get no plan-time or complete runtime
  exclusion for clock-derived and timestamptz-typed bounds. Reproducer from
  the harness, before and after numbers, the two-PR shape from T2 and T3, the
  timezone safety argument, the list of expected outputs CI must regenerate.
- Bug: `CURRENT_TIMESTAMP` is never constified for TIMESTAMPTZ dimensions
  because `is_valid_now_func` compares the wrong field. Include the saved
  diff and the affected expected outputs.
- Track C, documentation and a create-time hint for DATE dimensions with
  one-day chunks and the default time index, with T5's numbers.

Do not open issues or pull requests. Drafts only.

## Done criteria

- `probe/integration` exists, builds warning-free, passes the test list.
- All runs in the table exist under `results/` with the harness's CSVs and
  summaries, or are explicitly marked skipped with the reason.
- `results/T6-scorecard.md`, `results/upstream-issues.md`, and the README
  scorecard are committed on `probe/integration`.
- One push attempt, result recorded.

## Report

Template in `experiments/date-probe/README.md`, plus the scorecard table
inline in the final message.
