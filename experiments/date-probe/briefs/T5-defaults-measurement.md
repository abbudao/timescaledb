# T5: Chunking and default-index measurement for DATE tables

Branch: `probe/c1-defaults-measurement` (from `probe/harness` once T1 has
landed). Track C, defaults. No engine code, no SQL changes; measurement only.

## Goal

Decide with numbers whether daily-granularity `DATE` hypertables are hurt by
the defaults: a 7-day chunk interval and a btree index on the time column.
The hypotheses from the analysis:

- With one distinct key per day per chunk, the default time index is almost
  pure overhead for inserts and storage, and btree deduplication may or may
  not rescue it.
- Small chunks plus a segmentby leave compression batches far below the
  1000-row target, inflating per-row overhead.
- Fewer, larger chunks cut planning time and catalog scans without hurting
  exclusion for 30-day windows.

## Allowed paths

- `experiments/date-probe/results/**`
- `experiments/date-probe/harness/**` only for flags the matrix needs and the
  harness does not yet have

Forbidden: everything else.

## Matrix

Run every harness invocation through `experiments/date-probe/bin/locked.sh`
preceded by `make -C build install` from your worktree, see "Working in a
worktree" in the README. Your worktree must be unmodified `main` apart from
`experiments/`.

Run the harness on `metrics_date` at `small` scale for every cell:

| chunk interval | default index |
|---|---|
| 1 day | on, off |
| 7 days | on, off |
| 30 days | on, off |

For each cell record:

- insert rows per second
- heap bytes per row and index bytes per row before compression, and index
  share of the total
- number of chunks
- average rows per compressed batch (`_ts_meta_count`)
- compressed bytes per row, total
- Q1 to Q5 planning time and execution time medians
- whether any of Q1 to Q5 used the time index at all: read
  `pg_stat_user_indexes.idx_scan` on the chunk indexes before and after the
  query set

If time allows, repeat the two most interesting cells at `customer` scale.

## Analysis

Answer these in the results file:

1. At which chunk interval does batch fill reach at least 900 rows for this
   shape, and how does that change with the customer's real device count?
2. Does any query use the time index? If none does, what is the index's cost
   in bytes and insert throughput?
3. How much planning time does a 30-day interval save over 1 day, and does
   Q3's exclusion get worse?

## Deliverable

`results/T5-defaults-<short sha>.md` with the full matrix as a table and one
of three recommendations, each with the threshold that justifies it:

- engine change: a `DATE`-specific default interval or index policy;
- create-time hint: a `NOTICE` when a `DATE` dimension gets a one-day interval
  with default indexes;
- documentation only.

## Done criteria

- All twelve cells measured and committed.
- Recommendation stated with the numbers that support it.
- No changes outside the allowed paths.

## Report

Template in `experiments/date-probe/README.md`.
