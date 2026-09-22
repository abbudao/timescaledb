# DATE time-dimension probe

Experiments on this fork to find out whether TimescaleDB leaves performance
on the table for hypertables partitioned on a `DATE` column, and to prototype
the fixes before proposing them upstream.

Nothing under `experiments/` is meant to be merged upstream. The engine
changes prototyped here are, once they have numbers behind them.

## What we already know

Established by reading the code on `main` (see the briefs for line references):

- A `DATE` dimension is **not** converted to `timestamptz`. It becomes a
  timezone-free midnight `timestamp`, then an `int64` of microseconds since
  the Unix epoch. Chunk constraints are emitted as `::date` literals.
  `timescaledb_information.chunks` renders every time-like range through
  `to_timestamp(bigint)`, which is where the `timestamptz` impression comes
  from.
- `DATE` gets correctness coverage everywhere but no performance work:
  `now()` constification is `TIMESTAMPTZ`-only (`src/planner/constify_now.c`),
  the runtime cross-type transform rewrites only `>` and `<=`
  (`src/nodes/chunk_append/transform.c`), and vectorized predicates exist
  only for date-versus-date. `day >= now() - interval '30 days'` therefore
  gets no plan-time exclusion, incomplete runtime exclusion, and no
  vectorized filter.
- Before compression, `DATE` saves bytes only when the next column does not
  need 8-byte alignment; in the harness schema the 4 bytes go to padding
  ahead of `seq` and the heap rows are byte-identical. After compression the
  stream format is the same for both types, but the delta magnitudes are
  not: day-to-day steps are small integers for `DATE` and 86.4 billion
  microseconds for a midnight `timestamptz`, so the `DATE` column compresses
  about three times smaller. Measured by T1 at small scale: 0.55 versus 1.55
  bytes per row for the time column, 28.8 versus 30.4 bytes per row for the
  whole table. Real, but about five percent, not half.
- Rows are sorted for compression by segmentby plus orderby with no
  tiebreaker. A `DATE` orderby leaves rows within a day in arbitrary order
  inside each batch of 1000, which hurts every other column's compression.

## Tracks and branches

| Task | Track | Branch | Brief |
|---|---|---|---|
| T0 | environment | `claude/hypertable-date-time-dimension-ms75bt` (this branch, base for all) | this file |
| T1 | evidence | `probe/harness` | `briefs/T1-harness.md` |
| T2 | planner | `probe/a1-runtime-transform` | `briefs/T2-runtime-transform.md` |
| T3 | planner | `probe/a2-constify-date` | `briefs/T3-constify-date.md` |
| T4 | compression | `probe/b1-orderby-tiebreaker` | `briefs/T4-orderby-tiebreaker.md` |
| T5 | defaults | `probe/c1-defaults-measurement` | `briefs/T5-defaults-measurement.md` |
| T6 | integration | `probe/integration` | orchestrator only |

Every task branch starts from the base branch. T3 additionally needs the
helper T2 introduces, so it branches from `probe/a1-runtime-transform` once
that exists.

## Environment

`.claude/hooks/session-start.sh` runs at the start of every remote session and
leaves the container able to build and test:

- installs `postgresql-server-dev-16`, `clang-format-17`, `tzdata-legacy`
  (the tests use `US/Pacific` and `PST8PDT`, which Ubuntu 24.04 moved to the
  legacy package);
- configures `build/` as a Debug build with regression checks;
- compiles and installs the extension into the system PostgreSQL 16;
- makes `build/`, `test/`, `tsl/test/` and `tsl/test/shared/` writable for
  the `postgres` OS user, because PostgreSQL refuses to run as root and the
  test runner writes a schedule file into the source test directories.

Manual equivalents:

```bash
make -C build -j"$(nproc)" && make -C build install     # after editing C or SQL
experiments/date-probe/bin/regress.sh insert_single      # core suite, test/
SUITE=tsl    experiments/date-probe/bin/regress.sh decompress_vector_qual
SUITE=shared experiments/date-probe/bin/regress.sh constify_now
clang-format -i <changed .c/.h files>                    # style check uses clang-format 17
```

Failed test diffs land in `build/test/regression.diffs`,
`build/tsl/test/regression.diffs` and `build/tsl/test/shared/regression.diffs`;
actual outputs in the matching `results/` directories.

Only PostgreSQL 16 exists in this container. Tests whose expected output is
per-version (`*.sql.in` templates, `expected/<name>-16.out`) can only be
regenerated for 16 here. Never edit or add expected outputs for other versions;
list them in the report and let the fork's GitHub Actions produce them.

`timescaledb.current_timestamp_mock` is available in Debug builds and drives
the clock TimescaleDB uses internally (constification, policies). It does not
change PostgreSQL's own `now()` or `current_date`.

## Working in a worktree

Task agents run in their own git worktree with their own `build/`. The
system PostgreSQL is shared, so two rules apply on top of the hook:

1. Bootstrap the worktree once, under the install lock, so its build is
   configured, compiled and installed and its test directories are writable
   for `postgres`:

   ```bash
   experiments/date-probe/bin/locked.sh env CLAUDE_CODE_REMOTE=true CLAUDE_PROJECT_DIR="$(pwd)" .claude/hooks/session-start.sh
   ```

2. Every later sequence that installs or exercises the extension runs as one
   locked command, starting with `make install` from your own build so the
   installed extension is yours for the whole run:

   ```bash
   experiments/date-probe/bin/locked.sh bash -c 'make -C build -j"$(nproc)" install && experiments/date-probe/bin/regress.sh <tests>'
   experiments/date-probe/bin/locked.sh bash -c 'make -C build install && harness/run.sh --variant baseline --scale small'
   ```

   Never run `make install`, `regress.sh` or `harness/run.sh` outside the
   lock. Editing and compiling need no lock.

## Working rules for agents

1. Work only inside the paths your brief allows. If the fix needs a file
   outside them, stop and say so in the report instead of editing it.
2. Commit early and often. The container is ephemeral. Push with
   `git push -u origin <your-branch>`.
3. Never push to `main`, never force-push, never open a pull request.
4. Do not touch `.unreleased/`, `CHANGELOG.md`, `sql/updates/` or anything
   under `sql/pre_install/`.
5. C files get the license header of their directory (`src/` Apache,
   `tsl/` Timescale) and `clang-format` before every commit.
6. New tests must be registered in the directory's `CMakeLists.txt`, or CI's
   unreferenced-file check fails.
7. Never make an unrelated failing test pass by editing its expected output.
   Report it.
8. Results, CSVs and plan dumps go under `experiments/date-probe/results/`,
   never next to the code they measure.
9. A change whose results differ between GUC on and GUC off is a bug, not a
   speedup. Report it and stop.

## Report template

End every task with this, in the final message and as
`experiments/date-probe/results/<task>-report.md` on your branch:

```
## Report: <task> on <branch> @ <short sha>
Commands run: build, install, tests (exact command lines)
Tests: <name> pass|fail, ... ; diffs explained line by line if any
Expected outputs touched: <files>; outputs needing CI regeneration: <files>
Harness numbers: <table, one row per query or per column>
Deviations from the brief:
Open questions for the orchestrator:
```

## Scorecard

Filled by T6 from measured numbers. Until then the ranking is the prior from
the probe plan: T2+T3 first, T4 second, T5 as a decision input.

| Design | Gain on customer queries | Bytes per row | Effort | Go / no-go |
|---|---|---|---|---|
| runtime transform, all operators | | | | |
| constify DATE bounds | | | | |
| orderby tiebreaker | | | | |
| chunking and index defaults | | | | |
