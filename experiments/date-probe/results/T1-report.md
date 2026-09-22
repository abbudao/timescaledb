## Report: T1 (reproducer and benchmark harness) on probe/harness @ 2551fd8

### Commands run

Build (no lock needed):

```bash
BUILD_FORCE_REMOVE=true ./bootstrap -DCMAKE_BUILD_TYPE=Debug -DREGRESS_CHECKS=ON >/dev/null && make -C build -j2
```

Bootstrap and verification, under the install lock:

```bash
experiments/date-probe/bin/locked.sh env CLAUDE_CODE_REMOTE=true \
  CLAUDE_PROJECT_DIR=/home/user/timescaledb/.claude/worktrees/agent-a8ab9036b84b948b7 \
  .claude/hooks/session-start.sh

experiments/date-probe/bin/locked.sh bash -c \
  'make -C build install && experiments/date-probe/bin/regress.sh insert_single'
```

Baseline and reproducer (one locked command, `make install` first, as the
README requires):

```bash
experiments/date-probe/bin/locked.sh bash -c \
  'make -C build install && experiments/date-probe/harness/run.sh --variant baseline --scale small
   && experiments/date-probe/harness/repro.sh'
```

Run time for `--variant baseline --scale small` on 4 cores: **30 s**
(load 8.9 s for 2 x 1.92 M rows, compress 4.1 s, queries and cagg ~4 s), well
inside the 20 minute budget. Both scripts stop the cluster from an EXIT trap,
so nothing is left running; `ps -C postgres` is empty and port 5433 free
afterwards.

Push: `git push -u origin probe/harness` was attempted once and **failed with
403**: "Claude doesn't have GitHub access to abbudao/timescaledb for your
organization ... an org admin can install the Claude GitHub App". Not retried
and not worked around, as instructed. The seven commits of this task exist only
in this worktree's `probe/harness`.

### Tests

- `insert_single` (core suite): **pass**. No other suite was run: T1 changes no
  engine code, only files under `experiments/`.
- No diffs, so nothing to explain.

### Expected outputs touched

None. No file outside `experiments/` was modified, so nothing needs CI
regeneration on other PostgreSQL versions.

### Harness numbers

Baseline, `--scale small`: 400 days x 200 devices x 24 rows = 1.92 M rows per
table, 58 chunks of 7 days each, all compressed, `segmentby = device_id`,
default orderby, default indexes, data ending today. TimescaleDB 2.31.0-dev on
PostgreSQL 16.15. Median of three runs.

| query | table | exec ms | plan ms | chunks in plan | excluded at startup | vectorized filter | rows scanned | workers | shared hit |
|---|---|---:|---:|---:|---:|---|---:|---:|---:|
| Q1 `>= now() - 30 days` | metrics_date | **30.96** | 4.01 | **58 of 58** | **0** | **no** | 144000 | 2 | 6360 |
| Q1 `>= now() - 30 days` | metrics_tstz | **5.82** | 0.46 | **5 of 58** | 0 | yes | 144000 | 0 | 6025 |
| Q2 same-type stable bound | metrics_date | 21.13 | 3.35 | 5 | **53** | yes | 148800 | 2 | 6025 |
| Q2 same-type stable bound | metrics_tstz | 20.16 | 4.49 | 5 | **53** | yes | 148800 | 2 | 6025 |
| Q3 literal 31-day window | metrics_date | 4.60 | 0.37 | 5 | 0 | yes | 148800 | 0 | 4225 |
| Q3 literal 31-day window | metrics_tstz | 4.69 | 0.36 | 5 | 0 | yes | 148800 | 0 | 4225 |
| Q4 time_bucket + avg | metrics_date | 21.09 | 0.45 | 5 | 0 | yes | 148800 | 0 | 9025 |
| Q4 time_bucket + avg | metrics_tstz | 17.37 | 0.58 | 5 | 0 | yes | 148800 | 0 | 9025 |
| Q5 point lookup | metrics_date | 0.04 | 0.16 | 1 | 0 | yes | 24 | 0 | 23 |
| Q5 point lookup | metrics_tstz | 0.04 | 0.17 | 1 | 0 | yes | 24 | 0 | 23 |

Q6, continuous aggregate refresh over the whole range: 0.77 s on
`metrics_date`, 0.78 s on `metrics_tstz` (80 000 buckets each). Load:
485 k rows/s on `metrics_date`, 392 k rows/s on `metrics_tstz`. Compression:
2.04 s and 2.06 s.

**The gap.** Q1 is the customer's shape. On the `TIMESTAMPTZ` twin the bound is
constified at plan time and the plan holds 5 chunks; on the `DATE` twin nothing
is constified, nothing is excluded at startup, all 58 chunks are planned and
scanned, the filter is not vectorized, and the query needs 2 parallel workers
to stay within 5x of the serial `TIMESTAMPTZ` query. **Q1 is 5.3x slower on
DATE** (30.96 ms vs 5.82 ms), same rows, same data.

Q2 shows the same query written with the column's own type
(`day >= current_date - 30`): 53 of 58 chunks excluded during startup and a
vectorized filter. The exclusion machinery works for DATE; it is the
cross-type `now()` comparison that falls through.

Per-column storage, `metrics_date`, after compression. Parenthesized rows are
physical bytes from the size functions; the others are logical datum bytes
(`pg_column_size`), summed over the table before compression and over the
compressed relations after.

| column | type | uncompressed bytes | bytes/row | compressed bytes | bytes/row | ratio | batches | avg batch rows |
|---|---|---:|---:|---:|---:|---:|---:|---:|
| day | date | 7680000 | 4.000 | 1059400 | 0.552 | 7.25 | 11600 | 165.5 |
| device_id | integer | 7680000 | 4.000 | 46400 | 0.024 | 165.52 | 11600 | 165.5 |
| region_id | integer | 7680000 | 4.000 | 594120 | 0.309 | 12.93 | 11600 | 165.5 |
| seq | bigint | 15360000 | 8.000 | 2322376 | 1.210 | 6.61 | 11600 | 165.5 |
| status | text | 8960056 | 4.667 | 1314600 | 0.685 | 6.82 | 11600 | 165.5 |
| v1 | double precision | 15360000 | 8.000 | 13351304 | 6.954 | 1.15 | 11600 | 165.5 |
| v2 | double precision | 15360000 | 8.000 | 14839688 | 7.729 | 1.04 | 11600 | 165.5 |
| v3 | integer | 7680000 | 4.000 | 2658576 | 1.385 | 2.89 | 11600 | 165.5 |
| (columns) | | 85760056 | 44.667 | 36186464 | 18.847 | 2.37 | | |
| (heap) | | 159653888 | 83.153 | 6160384 | 3.209 | 25.92 | | |
| (index) | | 14057472 | 7.322 | 950272 | 0.495 | 14.79 | | |
| (toast) | | 475136 | 0.247 | 48103424 | 25.054 | 0.01 | | |
| (total) | | 174186496 | 90.722 | 55214080 | 28.757 | 3.15 | | |

For contrast, the `TIMESTAMPTZ` twin: `ts` costs 2976200 compressed bytes
(1.550 per row) against 1059400 (0.552) for `day`, and the whole table is
58318848 bytes against 55214080, i.e. **30.37 vs 28.76 bytes per row**. Before
compression the two tables are byte-for-byte the same size (83.153 bytes per
row of heap), because the 4 bytes DATE saves are spent on alignment padding
ahead of `seq`.

### Deviations from the brief

1. **`chunks_in_plan`.** The brief counts scan nodes matching `_hyper_%` or
   `compress_hyper_%`. In 2.31 a compressed chunk is scanned through two nodes
   (the chunk and `<chunk>_compressed`), so that count is twice the chunk
   count. `chunks_in_plan` is therefore distinct chunk relations under an
   anchored pattern, and the brief's literal count is kept beside it as
   `chunk_scan_nodes`. Extra columns `compressed_chunks_in_plan`, `scan_rows`
   and `workers_launched` were added.
2. **Plan walking.** Metrics come from the plan JSON in SQL, but not from
   `jsonb_path_query(plan, '$.**')`: in lax mode recursive descent yields every
   node twice, which doubles every sum (rows scanned, chunks excluded).
   `probe_plan_nodes()`, a recursive CTE, yields each node once.
3. **Rows scanned are per loop.** The DATE twin gets parallel workers because
   it scans every chunk; `Actual Rows` is per loop, so `scan_rows` multiplies
   by `Actual Loops`. Without that the DATE side looks like it read *less*
   data than the TIMESTAMPTZ one.
4. **Compressed chunk lookup.** The brief says to find the compressed chunk
   through `_timescaledb_catalog.chunk (compressed_chunk_id)`. That column is
   gone in 2.31 and `compression_chunk_size.compressed_chunk_id` is 0; the
   compressed relation is `<chunk table>_compressed` in the chunk's schema and
   is not registered as a chunk. The harness joins `pg_class` on that name and
   raises an error if a compressed chunk has no such relation, rather than
   reporting empty columns.
5. **`v1` formula.** The brief suggests
   `sin(day_index / 30.0) * 100 + device_id + random()`. The harness uses
   `round(sin((day_index + r/rows_per_day)/30) * 100 + device_id + random()*0.1, 3)`
   so the series also ramps *inside* a day and the noise does not swamp it;
   otherwise the T4 orderby tiebreaker would have nothing to recover.
6. **Startup exclusion on the TIMESTAMPTZ twin.** The done criteria expect Q1
   on `metrics_tstz` to show startup exclusion. It does not, and cannot: the
   bound is constified at *plan* time, so only 5 chunks ever reach the plan and
   `Chunks excluded during startup` is 0. Startup exclusion appears instead in
   the third query of the repro (`day >= current_date - 30`, 53 excluded). The
   repro shows all three, which is the stronger evidence: no exclusion at all
   for DATE + `now()`, plan-time exclusion for TIMESTAMPTZ, startup exclusion
   for DATE with a same-type bound.
7. **A `smoke` scale** (20 days x 20 devices x 4 rows, ~2 s) was added next to
   `small` and `customer`, for checking the harness itself.
8. **`experiments/date-probe/bin/locked.sh`** carries an uncommitted change in
   this worktree: the orchestrator patched it directly (closing fd 9 for the
   child) and asked for it to be left out of my commits. It is the same bug
   class as item 3 under "bugs found", below.

### Bugs found and fixed while building this

1. `\copy` does not expand psql variables inside its query, so every export
   died with `syntax error at or near ":"`, and with `set -e` the run exited
   before stopping the cluster. The exports are now plain
   `COPY ... TO STDOUT` scripts whose output `run.sh` redirects, and both
   scripts stop the cluster from an EXIT trap, so a failure never leaves port
   5433 occupied. The port is `--port` / `PGPORT`.
2. The per-column compressed sizes were silently empty (item 4 above).
3. `pg/start.sh` let the daemonized postmaster inherit `locked.sh`'s lock
   descriptor, so the install lock stayed held for every worktree until the
   cluster was stopped. `start.sh` now closes fd 9 for everything it starts.
4. The harness restarts the cluster at the start of every run: the postmaster
   keeps the `timescaledb` library it preloaded at startup, so a cluster left
   running from an earlier session would otherwise serve another worktree's
   build.

### Open questions for the orchestrator

1. **The prior on DATE compression looks wrong.** The probe README says that
   after compression the time column's width is irrelevant because deltadelta
   widens dates to `int64`. Measured, `day` compresses to 0.552 bytes/row while
   `ts` needs 1.550, and the whole `DATE` table is 1.6 bytes/row smaller (28.76
   vs 30.37). The deltas differ in magnitude (1 day vs 86.4e9 microseconds) and
   simple8b pays for that. Worth confirming before the scorecard quotes the old
   claim.
2. **DATE Q1 goes parallel, TIMESTAMPTZ Q1 does not.** Part of the 5.3x is
   PostgreSQL throwing two workers at the DATE plan. The customer's real gain
   from a fix is therefore larger than the wall-clock ratio suggests on a busy
   server, where those workers are not free. Should T6 also report the
   single-worker number (`max_parallel_workers_per_gather = 0`)?
3. **Customer numbers.** The `customer` scale is still the brief's placeholder
   (1095 days x 2000 devices x 24). Replace `DAYS`, `DEVICES`, `RPD` in
   `run.sh` and the table in `harness/README.md` when the real shape is known.
4. **Q2 is not faster on either twin** (21.13 vs 20.16 ms) even though 53 of 58
   chunks are excluded, because the five surviving chunks hold all the matching
   rows and the work is in decompressing them. The exclusion win shows up in
   planning and in chunk count, not in Q2's wall clock; Q1 is the query that
   pays for the gap.
