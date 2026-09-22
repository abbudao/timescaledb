# Resuming the probe in another session

Pushing from the remote session is blocked until the Claude GitHub App is
linked to `abbudao/timescaledb` at the claude.ai organization level. Until
then, work moves between sessions as patch series.

## Producing a hand-off

From the base worktree:

```bash
experiments/date-probe/bin/export-patches.sh /tmp/probe-patches
```

Send the whole directory. `MANIFEST.md` lists every branch, its head and the
apply order, and names worktrees that still held uncommitted changes, which
the export does not capture.

## Resuming from a hand-off

On a clone of upstream `main` (`git clone https://github.com/timescale/timescaledb`
or the fork):

```bash
git checkout -b claude/hypertable-date-time-dimension-ms75bt origin/main
git am base/*.patch
# Then, in the manifest's order, each series on top of its parent branch:
#   git checkout -b probe/<name> <parent branch from the manifest>
#   git am probe-<name>/*.patch
# Series cut from the base list the base branch as parent; T3 lists
# probe/a1-runtime-transform and T5 lists probe/harness.
git checkout claude/hypertable-date-time-dimension-ms75bt
```

Then run the SessionStart hook once if this is a fresh remote container
(`CLAUDE_CODE_REMOTE=true CLAUDE_PROJECT_DIR="$(pwd)" .claude/hooks/session-start.sh`)
and continue from the task table in `README.md`. Each task's latest report is
`results/<task>-report.md` on its branch.

## Pause history

The probe was paused mid-wave-two at the user's request and resumed the next
day by resuming the same two agents from their transcripts. T5 has since
finished. The notes below describe the state at the pause and remain the
resume instructions for T3 should it be interrupted again:

- **T3** on `probe/a2-constify-date`: the branch is T2's earlier head plus a
  `WIP` commit holding an unbuilt, untested edit to
  `src/planner/constify_now.c`. First `git merge probe/a1-runtime-transform`
  to pick up T2's final head (equality range form, `append-16.out`), then
  continue from `briefs/T3-constify-date.md`; the WIP diff shows how far the
  shape detection got. Everything in the brief still applies, including the
  timezone-independent conservative bound.
- **T5** on `probe/c1-defaults-measurement`: the harness gained a
  parallel-off query pass and chunk-index usage sampling (commit `1dc07b9`),
  and all six matrix cells ran; their raw CSVs and summaries are committed
  under `results/defaults-*`. What is missing is the analysis:
  `results/T5-defaults-<sha>.md` with the matrix table, the three answers
  from the brief, the recommendation, and `results/T5-report.md`. No rerun
  should be needed unless a CSV is incomplete.
- **T6** has not started. Inputs are ready for T1, T2 and T4; T3 and T5
  finish first.

## Task state

Kept current by the orchestrator at every hand-off.

| task | branch | state |
|---|---|---|
| T0 | base | done |
| T1 | probe/harness | done at bf46778; baseline: Q1 5.3x slower on DATE (58 chunks planned vs 5, no vectorized filter); harness bugs fixed; report in results/T1-report.md |
| T2 | probe/a1-runtime-transform | done at ef03bde; all five operators rewritten exactly, 90-cell matrix and DST sweep zero mismatches, all five vectorized on compressed chunks; Q1 chunks in plan 116 to 10; append-17/18/19.out need CI regeneration; report in results/T2-report.md |
| T3 | probe/a2-constify-date | not started, waits for T2 |
| T4 | probe/b1-orderby-tiebreaker | done at a7ee096; tests pass; verdict no-go as default at small scale (value columns -0.53%, metadata +371 KB); re-measure at customer scale in T6; report in results/T4-report.md |
| T5 | probe/c1-defaults-measurement | done at 2b8f0b9; time index never used by Q1-Q5 and costs 45-50% insert throughput; batch fill = rows per device per day x days in chunk, capped at 1000; 30-day chunks cut planning 96% vs 1 day; recommendation: create-time NOTICE for DATE with chunk interval <= 1 day plus docs, not a default change; report in results/T5-report.md |
| T6 | probe/integration | not started |
