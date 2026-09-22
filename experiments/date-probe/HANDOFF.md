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
for d in probe-*/; do
  br="${d%/}"; br="${br/probe-/probe/}"
  git checkout -b "${br}" claude/hypertable-date-time-dimension-ms75bt
  git am "${d}"*.patch
done
git checkout claude/hypertable-date-time-dimension-ms75bt
```

Then run the SessionStart hook once if this is a fresh remote container
(`CLAUDE_CODE_REMOTE=true CLAUDE_PROJECT_DIR="$(pwd)" .claude/hooks/session-start.sh`)
and continue from the task table in `README.md`. Each task's latest report is
`results/<task>-report.md` on its branch.

## Task state

Kept current by the orchestrator at every hand-off.

| task | branch | state |
|---|---|---|
| T0 | base | done |
| T1 | probe/harness | in progress, agent running |
| T2 | probe/a1-runtime-transform | in progress, agent running |
| T3 | probe/a2-constify-date | not started, waits for T2 |
| T4 | probe/b1-orderby-tiebreaker | done at a7ee096; tests pass; verdict no-go as default at small scale (value columns -0.53%, metadata +371 KB); re-measure at customer scale in T6; report in results/T4-report.md |
| T5 | probe/c1-defaults-measurement | not started, waits for T1 |
| T6 | probe/integration | not started |
