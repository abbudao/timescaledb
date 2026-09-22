## Report: T4 orderby tiebreaker on probe/b1-orderby-tiebreaker @ ad228b1

### Commands run: build, install, tests

```bash
git checkout -B probe/b1-orderby-tiebreaker claude/hypertable-date-time-dimension-ms75bt

BUILD_FORCE_REMOVE=true ./bootstrap -DCMAKE_BUILD_TYPE=Debug -DREGRESS_CHECKS=ON >/dev/null && make -C build -j2

experiments/date-probe/bin/locked.sh env CLAUDE_CODE_REMOTE=true \
  CLAUDE_PROJECT_DIR=/home/user/timescaledb/.claude/worktrees/agent-ae51a0b346288402f \
  .claude/hooks/session-start.sh

experiments/date-probe/bin/locked.sh bash -c \
  'make -C build install && SUITE=tsl experiments/date-probe/bin/regress.sh compression_defaults'

# after each edit
make -C build -j2
experiments/date-probe/bin/locked.sh bash -c \
  'make -C build install >/dev/null && SUITE=tsl experiments/date-probe/bin/regress.sh \
     compression_defaults compression_ddl compression_settings'

# collateral-damage sweep over the other tsl tests that mix DATE with compression
experiments/date-probe/bin/locked.sh bash -c \
  'make -C build install >/dev/null && SUITE=tsl experiments/date-probe/bin/regress.sh \
     chunk_column_stats chunk_utils_compression compress_bloom_sparse_debug \
     compress_composite_bloom_debug compression_qualpushdown skip_scan_bugs vector_qual_default'

# measurement, with probe/harness @ b1593f7 merged locally and never committed
experiments/date-probe/bin/locked.sh bash -c \
  'make -C build install >/dev/null && experiments/date-probe/harness/run.sh \
     --variant baseline --scale small --db probe_t4_baseline'      # base-branch SQL installed
experiments/date-probe/bin/locked.sh bash -c \
  'make -C build install >/dev/null && experiments/date-probe/harness/run.sh \
     --variant heuristic --scale small --db probe_t4_heuristic'
experiments/date-probe/bin/locked.sh bash <scratch>/t4_run3.sh   # tiebreaker variant + extraction
git merge --abort
```

`git checkout -B ... claude/hypertable-date-time-dimension-ms75bt` instead of
`git checkout -b` from HEAD: the worktree was created at upstream `3af0667`,
which has no `experiments/date-probe`. The coordinator confirmed this mid-task.

### Tests

- `compression_defaults` **pass**
- `compression_ddl` **pass**
- `compression_settings` **pass**
- sweep, all **pass**: `chunk_column_stats`, `chunk_utils_compression`,
  `compress_bloom_sparse_debug`, `compress_composite_bloom_debug`,
  `compression_qualpushdown`, `vector_qual_default`
  (`skip_scan_bugs` is not part of the tsl schedule and did not run)

Diffs: none remain. The only diff produced during development was the new
`compression_defaults` block, which is **purely additive**: `git diff --numstat`
on the expected file is `175 0` — 175 lines added, 0 removed, so every existing
case still produces byte-identical output.

### Expected outputs touched

- `tsl/test/expected/compression_defaults.out` — 175 added lines, 0 changed, 0 removed.

Outputs needing CI regeneration: **none**. `compression_defaults` has a single
version-independent expected file; no `*.sql.in` template and no
`expected/<name>-16.out` are involved, so PostgreSQL 16 is the only version this
test has an expected file for.

### The change

`_timescaledb_functions.get_orderby_defaults` in `sql/compression_defaults.sql`
only. After `_orderby_names` is fully built, if its first element is an *open*
dimension (`interval_length IS NOT NULL`) whose `column_type` is
`'date'::regtype`, one tiebreaker is appended as `<col> DESC`:

1. a column of any unique index not already in segmentby or orderby;
2. otherwise a `bigint` / `int` / `timestamptz` / `timestamp` column whose name
   matches `seq`, `id`, `ts`, `time`, `created_at` or `updated_at` on a `_`
   word boundary, preferring an exact name match and then the list order;
3. otherwise, when `pg_stats` has inherited rows for the table, the non-segmentby
   column with the most distinct values;
4. otherwise no change.

Rules 2 and 3 lower `confidence` by one and add a `message` key. Rule 1 leaves
both untouched. The JSON shape is unchanged, and no `message` key is emitted on
any path that did not already have one, so every non-DATE case is byte-identical.

`sql/CMakeLists.txt` confirmation, as the brief asks: `compression_defaults.sql`
is listed in `SOURCE_FILES` (`cmake/ScriptFiles.cmake:60`), and
`sql/CMakeLists.txt` concatenates `${SOURCE_FILES_VERSIONED}` into **both** the
`CREATE EXTENSION` script and every `timescaledb--<old>--<new>.sql` update script
(the `cat_files(...)` calls inside the `foreach(transition_mod_file ...)` loop).
The function body is therefore re-applied on every `ALTER EXTENSION ... UPDATE`,
and since the signature does not change, **no update script is needed**.

### Harness numbers

Full tables in `experiments/date-probe/results/T4-orderby-ad228b1.md`, raw psql
output in `T4-orderby-ad228b1-raw.txt`, extraction query in
`T4-storage-extract.sql`. Scale `small`: 400 days x 200 devices x 24 rows =
1.92 M rows, 7-day chunks, `compress_segmentby = 'device_id'`. Only
`metrics_date` is affected.

Compressed bytes per column of `metrics_date`:

| column | baseline (`day DESC`) | heuristic (`day DESC, seq DESC`) | tiebreaker (explicit, same orderby) | heuristic - baseline |
|---|---:|---:|---:|---:|
| `day` | 1,059,400 | 1,059,400 | 1,059,400 | 0 |
| `device_id` | 46,400 | 46,400 | 46,400 | 0 |
| `region_id` | 594,120 | 594,120 | 594,120 | 0 |
| `seq` | 2,322,376 | 2,200,920 | 2,200,920 | -121,456 (-5.2%) |
| `status` | 1,314,600 | 1,314,600 | 1,314,600 | 0 |
| `v1` (smooth) | 13,349,512 | 13,281,624 | 13,281,088 | -67,888 (-0.51%) |
| `v2` (noise) | 14,838,912 | 14,837,184 | 14,835,736 | -1,728 |
| `v3` (noise) | 2,657,896 | 2,658,976 | 2,658,648 | +1,080 |
| **value columns** | **36,183,216** | **35,993,224** | **35,990,912** | **-189,992 (-0.53%)** |
| metadata columns | 232,000 | 603,200 | 603,200 | **+371,200** |
| **all columns** | **36,415,216** | **36,596,424** | **36,594,112** | **+181,208 (+0.50%)** |

The metadata cost is four new columns: `_ts_meta_min_2`, `_ts_meta_max_2`,
`_ts_meta_v2_first_seq`, `_ts_meta_v2_last_seq`, 92,800 bytes each.

Batch fill, wall time and physical size:

| metric | baseline | heuristic | tiebreaker |
|---|---:|---:|---:|
| batches | 11,600 | 11,600 | 11,600 |
| avg rows per batch | 165.5 | 165.5 | 165.5 |
| heap / index / toast after | 6,160,384 / 950,272 / 47,947,776 | 6,160,384 / 1,900,544 / 46,080,000 | 6,160,384 / 1,900,544 / 46,211,072 |
| **total after compression** | **55,058,432** | **54,140,928** | **54,272,000** |
| compression ratio | 3.16 | 3.22 | 3.21 |
| compress wall time (s) | 2.18 | 2.13 | 2.14 |

Batch fill is unchanged — the orderby does not move batch boundaries, which come
from segmentby (200 devices) and the chunk interval (7 x 24 = 168 rows per device
per chunk). Compression wall time does not regress.

`heuristic` and `tiebreaker` are the same configuration (the heuristic picks
exactly `seq`), so the 131,072-byte gap between their totals is the run-to-run
noise floor, about 0.24%.

**Verdict: no.** The value-column saving (189,992 bytes, 0.52% of all compressed
column bytes) does not exceed the metadata cost (371,200 bytes), let alone by a
tenth of total compressed bytes, which would need about 3.6 MB. Physical bytes
tell a milder story (-917,504, -1.67%, from a 1.87 MB toast drop against a
0.95 MB index growth), but a toast drop ten times larger than the datum saving is
mostly toast chunking, not compression. Not worth defaulting on; cheap and safe
as an opt-in, and worth re-measuring at `customer` scale with wider batches.

### Deviations from the brief

1. **Branch base.** Created with `git checkout -B probe/b1-orderby-tiebreaker
   claude/hypertable-date-time-dimension-ms75bt` rather than from the worktree's
   HEAD (`3af0667`, upstream main), which has no `experiments/date-probe`. The
   coordinator confirmed this while the task was running.
2. **Rule 1 includes a unique index's INCLUDE columns**, not only its key columns.
   Reason: with only key columns the rule is nearly unreachable and, worse,
   untestable deterministically — reaching it needs two unique indexes, and which
   one the function's existing `... where indisunique and indrelid = relation
   limit 1` picks is unordered, so the expected output would be unstable. A
   single `CREATE UNIQUE INDEX ... (day) INCLUDE (seq)` makes the rule both
   reachable and deterministic, and an INCLUDE column is still a column of a
   unique index.
3. **Rule 3 normalises `n_distinct` before comparing.** A negative `n_distinct` is
   a negated fraction of the row count, so "highest `n_distinct`" taken literally
   would rank a column with 50 distinct values above a fully unique one (-1). The
   implementation compares
   `CASE WHEN n_distinct < 0 THEN -n_distinct * rows ELSE n_distinct END`
   and requires the result to be > 1, so a constant column is never chosen.
4. **`tiebreaker` variant run with this branch's build installed**, not the base
   build. The variant passes `--orderby` explicitly, which bypasses the default
   function entirely, so the installed version cannot affect it. This saved one
   rebuild.
5. **Per-column compressed bytes were extracted with my own query**, not the
   harness's, because the harness's collector is broken on this version (below).
   The query is committed as `results/T4-storage-extract.sql`.

### Problems found in the harness (`probe/harness` @ b1593f7), for T1

Neither is caused by this task's change; both are reproducible on `baseline`.

1. **`sql/export.sql` fails on every run.** psql does not interpolate `:'run_id'`
   inside a `\copy (...)` query; it re-lexes the text and emits `: 'run_id'`.
   Every run dies there with `ERROR: syntax error at or near ":"`, so
   `*-queries.csv`, `*-storage.csv` and `*-summary.md` are **never written** and,
   because `run.sh` has `set -e`, the cluster is left running. Fix: run the two
   queries through `\set` + a server-side `COPY (...) TO PROGRAM`/temp view, or
   build the whole `\copy` line with `\gset`/`\o`, or pass the run id into a temp
   table first and reference that instead of a psql variable.
2. **`probe_collect_compressed` in `sql/setup.sql` finds nothing on 2.31.** It
   joins `_timescaledb_catalog.compression_chunk_size.compressed_chunk_id` to
   `_timescaledb_catalog.chunk.id`, but on this version `compressed_chunk_id` is
   **0** for every row and `hypertable.compressed_hypertable_id` is NULL. There is
   no `compress_hyper_%` relation at all; the compressed chunk is
   `_timescaledb_internal.<chunk name>_compressed`. Consequence: every per-column
   `compressed_bytes` is NULL and `batches` is 0 in `probe_storage`, so the
   README's headline metric is empty. Working lookup (used in
   `results/T4-storage-extract.sql`):

   ```sql
   JOIN pg_class ocl ON ocl.oid = ch.relid
   JOIN pg_class cl  ON cl.relname = ocl.relname || '_compressed'
                    AND cl.relnamespace = ocl.relnamespace
   ```

   The harness's `(heap)/(index)/(toast)/(total)` rows are unaffected; they come
   from `chunk_compression_stats()` and are correct.

Also observed twice, and fixed by the coordinator in
`experiments/date-probe/bin/locked.sh` (`"$@" 9>&-`): the harness postmaster
inherited the lock file descriptor from `locked.sh` and held the install lock
while idle, blocking every other agent. My worktree carries that fix as an
**uncommitted** working-tree change, as instructed.

### Push

`git push -u origin probe/b1-orderby-tiebreaker` was attempted once and refused:

```
remote: Claude doesn't have GitHub access to abbudao/timescaledb for your organization.
fatal: unable to access 'https://github.com/abbudao/timescaledb/': The requested URL returned error: 403
```

Not retried and not worked around. The four commits
(`a71c7ea`, `3b2aeb1`, `ad228b1`, `c17552e` plus this amendment) exist only in
this worktree; the branch needs to be pushed by someone with access, or the
container kept alive until it is.

### Open questions for the orchestrator

1. The `small` scale gives batches of only ~168 rows (200 segmentby values x
   7-day chunks x 24 rows/day), so the intra-day disorder the tiebreaker removes
   spans 24 rows at a time and never approaches the 1000-row batch limit. Should
   T4 be re-measured at `customer` scale, or with `interval-30d`, before the
   design is scored? The current numbers argue "no-go" for a table shaped like
   the harness's, not for DATE hypertables in general.
2. The harness's value columns are 41% random noise (`v2`) plus `v3` and
   `status`; only `v1` can benefit from ordering at all. If the customer's real
   columns are mostly correlated, the ceiling is much higher than 0.53%. Are the
   real column shapes known yet?
3. Rule 3 currently ignores column type. A `text` column with the most distinct
   values would be chosen over a moderately distinct `bigint`, which sorts more
   cheaply. Worth restricting to fixed-width types, or is "most distinct" the
   intent?
4. `confidence` is lowered for rules 2 and 3 but the C caller only logs the
   message with `LOG_SERVER_ONLY`; nothing surfaces to the user. If the message
   is meant to be seen, that is a C change outside this brief's allowed paths.
