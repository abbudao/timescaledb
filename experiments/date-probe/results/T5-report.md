## Report: T5 (chunking and default-index measurement) on probe/c1-defaults-measurement @ 1dc07b9

### Commands run

Branch set up from the finished harness, then built without the lock:

```bash
git checkout -B probe/c1-defaults-measurement probe/harness
BUILD_FORCE_REMOVE=true ./bootstrap -DCMAKE_BUILD_TYPE=Debug -DREGRESS_CHECKS=ON >/dev/null \
  && make -C build -j2
```

Bootstrap hook, under the install lock:

```bash
experiments/date-probe/bin/locked.sh env CLAUDE_CODE_REMOTE=true \
  CLAUDE_PROJECT_DIR=/home/user/timescaledb/.claude/worktrees/agent-aecb12a36b1cc3870 \
  .claude/hooks/session-start.sh
```

Harness check of the two additions (smoke scale, result files deleted again):

```bash
experiments/date-probe/bin/locked.sh bash -c \
  'make -C build install && experiments/date-probe/harness/run.sh \
     --variant smoketest --scale smoke --port 5436 --parallel-off-pass'
```

The six matrix cells, each as one locked command, `make install` first:

```bash
experiments/date-probe/bin/locked.sh bash -c \
  'make -C build install && experiments/date-probe/harness/run.sh \
     --variant defaults-<1d|7d|30d>-<index|noindex> --scale small --port 5436 \
     --chunk-interval "<1 day|7 days|30 days>" <--index|--no-index> \
     --start-date 2025-08-19 --parallel-off-pass'
```

Wall time 22-50 s per cell; the cluster is stopped by run.sh's EXIT trap after
each. `--start-date` was pinned so all six cells see identical data and an
identical `now()`-relative window. Variant names are custom (not the
`interval-1d` / `no-index` presets) because the presets cannot be combined
without colliding on the result-file prefix; the flags they preset were passed
explicitly, which the harness documents as equivalent.

### Tests

None run. T5 changes no engine code and no SQL under `sql/`: the only edits are
under `experiments/date-probe/harness/` and `experiments/date-probe/results/`.
The regression suite was last exercised on this build by T1 (`insert_single`,
pass) and the extension installed here is byte-identical to `main` at 3af0667.

### Expected outputs touched

None. Nothing outside `experiments/` was modified, so no expected output needs
CI regeneration on any PostgreSQL version.

### Harness numbers

Full matrix, all metrics and the three analysis answers:
`experiments/date-probe/results/T5-defaults-1dc07b9.md`. Raw files:
`defaults-{1d,7d,30d}-{index,noindex}-1dc07b9-{queries.csv,storage.csv,summary.md}`.

`metrics_date`, `--scale small` (400 days x 200 devices x 24 rows = 1.92 M
rows), `segmentby = device_id`, all chunks compressed:

| cell | chunks | insert rows/s | index B/row | idx share | avg batch rows | compressed B/row | Q1 plan ms | Q1 exec ms | Q1 exec ms serial | chunk idx_scan delta |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| 1 day, index on | 400 | 406 600 | 10.240 | 10.1% | 24.0 | 66.560 | 36.53 | 108.63 | 61.30 | **0** |
| 1 day, index off | 400 | 746 250 | 0 | 0% | 24.0 | 66.560 | 31.93 | 97.82 | 56.71 | n/a |
| 7 days, index on | 58 | 502 129 | 7.322 | 8.1% | 165.5 | 28.706 | 3.76 | 21.22 | 15.36 | **0** |
| 7 days, index off | 58 | 924 640 | 0 | 0% | 165.5 | 28.693 | 3.86 | 21.27 | 17.20 | n/a |
| 30 days, index on | 14 | 519 268 | 6.946 | 7.8% | 685.7 | 19.793 | 1.03 | 12.01 | 13.43 | **0** |
| 30 days, index off | 14 | 1 036 756 | 0 | 0% | 685.7 | 19.780 | 1.02 | 23.27 | 13.03 | n/a |

Q2 to Q5 and the `metrics_tstz` half of the twelve cells are in the results
file. Headlines:

1. **The default time index is never used.** The `idx_scan` delta over Q1..Q5
   on the chunk indexes is 0 in every cell, in both the parallel and the
   serial pass. The only index the query set touches is the one compression
   builds on `device_id` (Q5, delta 3 = three runs on one chunk). Sanity
   check: a forced index scan moved the same counter from 0 to 3.
2. **It costs 45-50% of insert throughput** at every interval (406 600 vs
   746 250 rows/s at 1 day; 519 268 vs 1 036 756 at 30 days) and 6.9-10.2
   bytes per row, 7.8-10.1% of the pre-compression total. The byte cost is
   transient (compression empties the index to one page per chunk); the write
   cost is not.
3. **Batch fill is `rows_per_device_day x days_in_chunk`, capped at 1000.**
   Measured 24.0 / 165.5 / 685.7 against a model predicting 24 / 168 / 686.
   For this shape fill first reaches 900 at 38 days and peaks at 41 (984); at
   42 days it halves to 504, because 1008 rows need two batches. The
   customer's device count does not move this at all -- `segmentby` gives each
   device its own batch stream -- only their rows per device per day does.
4. **Planning scales with chunk count for `now()` queries on DATE.** Q1..Q5
   planning totals 77.25 ms at 1 day, 8.36 at 7 days, 2.73 at 30 days: 30 days
   saves 96% over 1 day and 67% over the default. At 1 day, planning Q1
   (36.5 ms) costs three times what executing the `TIMESTAMPTZ` twin does.
5. **Q3's exclusion gets slightly worse at 30 days:** 4.62 -> 6.13 ms serial
   (+33%), still 1.9 ms faster than at 1 day; Q4 over the same window shows no
   penalty. Buffer hits fall (4 225 -> 2 608) because the data compresses
   better.
6. **Small chunks amplify the T2/T3 defect.** `DATE`/`TIMESTAMPTZ` Q1 is 9.0x
   at 1 day, 3.2x at 7 days, 1.7x at 30 days, purely from how many chunks the
   unconstified plan carries.

**Recommendation: create-time hint, not an engine default change.** Emit a
`NOTICE` from `create_hypertable()` when a `DATE` dimension gets a chunk
interval of **one day or less**, mentioning the default index, plus
documentation. Thresholds: a silent default change needs >=2x with no
regression, and 7 -> 30 days is 1.45x on compressed bytes with a 33% Q3
regression, while the optimal interval (`1000 / rows_per_device_day` days) is
not knowable at create time; dropping the default index for `DATE` would clear
a 2x ingest bar but cannot be proven safe from an analytic query set alone,
and `create_default_indexes => false` already exists. A 1-day `DATE` interval
is the one decidable cliff: 2.32x the compressed bytes of the default, batch
fill at 2.4% of target, 9.7x the planning time, and one distinct time value
per chunk by construction.

### Deviations from the brief

1. **Twelve cells.** The brief's matrix is 3 intervals x {index on, off} = 6
   harness runs; the done criteria say twelve cells. Each run measures both
   twins, so twelve is read as 6 configurations x {`metrics_date`,
   `metrics_tstz`}, and both are reported.
2. **Two harness additions** (commit 1dc07b9), the coordinator's requests:
   `--parallel-off-pass` / `PROBE_PARALLEL_OFF_PASS=true` reruns Q1..Q5 per
   table with `max_parallel_workers_per_gather = 0` under the query ids
   `Q1-np`..`Q5-np`; `sql/idxstat.sql` samples
   `pg_stat_user_indexes.idx_scan` over the chunk indexes into
   `probe_idxstat` before the query set, after it and after the serial pass,
   and the summary prints the deltas. Both are documented in
   `harness/README.md`. No other harness behaviour changed.
3. **Custom variant names** instead of the `interval-1d` / `interval-30d` /
   `no-index` presets, because the presets cannot be combined (the variant
   name is also the result-file prefix, so `interval-1d` with `--no-index`
   would overwrite `interval-1d` with the index). The flags the presets set
   were passed explicitly.
4. **`customer` scale not run.** The brief makes it conditional; the session
   was interrupted after the six `small` cells and resumed for analysis only.
5. **`experiments/date-probe/bin/locked.sh`** carries the orchestrator's
   uncommitted descriptor fix in this worktree and was deliberately left out
   of every commit.
6. Commits 1dc07b9 and 601ca23 trip the repository's commit-message hook
   (subject length, body wrapping). The hook only warns.

### Push

`git push -u origin probe/c1-defaults-measurement` was attempted once and
failed with **403**: "Claude doesn't have GitHub access to abbudao/timescaledb
for your organization". Not retried, as instructed. The branch exists only in
this worktree.

### Open questions for the orchestrator

1. **T1's open question 2 is answered, and the answer is inconvenient.** The
   parallel workers are not just free speed for `DATE`: at 400 chunks the
   parallel Q1 is *slower* than the serial one (108.63 vs 61.30 ms). Two cells
   that differ only by an unused index also disagree by up to 2.6x with
   parallelism on and agree within 5% with it off. The scorecard should quote
   serial numbers for configuration comparisons.
2. **Does anything in the customer's workload need the time index?** The
   recommendation stops short of dropping it by default only because this
   query set is entirely analytic over compressed chunks. One example of a
   selective time lookup against uncompressed recent data would settle it; if
   there is none, "drop the default index for `DATE`" clears a 2x ingest bar
   on its own.
3. **What is the customer's real rows per device per day?** The interval
   recommendation is `1000 / rpd` days and nothing else; at 24 it is 41 days,
   at 1440 it is under a day. `DAYS`, `DEVICES` and `RPD` in `run.sh` are
   still T1's placeholders.
4. **Does T2/T3 change the interval answer?** Planning cost is what makes
   small chunks expensive on `DATE` today, and constification removes most of
   it. The storage and batch-fill arguments survive; the planning argument may
   shrink by an order of magnitude, so T6 should re-measure the 1-day cell
   after T2/T3 land.
