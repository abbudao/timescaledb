# T5: chunking and default-index measurement for DATE hypertables

Branch `probe/c1-defaults-measurement` @ `1dc07b9` (harness additions) on a
worktree that is otherwise unmodified `main` (`3af0667` plus
`experiments/`). TimescaleDB 2.31.0-dev, PostgreSQL 16.15, 4 cores, harness
cluster on port 5436.

Six harness runs, all with `--scale small` (400 days x 200 devices x 24 rows =
1.92 M rows per twin), `--start-date 2025-08-19` pinned so every cell sees the
same data and the same `now()`-relative window, `segmentby = device_id`,
default `compress_orderby`, every chunk compressed:

```bash
experiments/date-probe/bin/locked.sh bash -c \
  'make -C build install && experiments/date-probe/harness/run.sh \
     --variant defaults-<1d|7d|30d>-<index|noindex> --scale small --port 5436 \
     --chunk-interval "<1 day|7 days|30 days>" <--index|--no-index> \
     --start-date 2025-08-19 --parallel-off-pass'
```

Raw files: `defaults-{1d,7d,30d}-{index,noindex}-1dc07b9-{queries.csv,storage.csv,summary.md}`.

The brief's matrix is 3 chunk intervals x {index on, index off} = 6 harness
runs; each run measures both twins, so the twelve cells of the done criteria
are read as 6 configurations x {`metrics_date`, `metrics_tstz`}. Both twins
are reported below; the analysis is about `metrics_date`.

## Matrix, `metrics_date`

Storage and ingest. "idx share" is index bytes over total bytes before
compression. Batch fill is `avg(_ts_meta_count)` over all compressed batches.

| cell | interval | default index | chunks | insert rows/s | heap B/row | index B/row | idx share | total B/row (pre) | batches | avg batch rows | compressed total B/row | compress s |
|---|---|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| 1d-index | 1 day | on | 400 | 406 600 | 89.907 | 10.240 | 10.1% | 101.854 | 80 000 | 24.0 | 66.560 | 6.56 |
| 1d-noindex | 1 day | off | 400 | 746 250 | 89.835 | 0.000 | 0.0% | 91.541 | 80 000 | 24.0 | 66.560 | 4.84 |
| 7d-index | 7 days | on | 58 | 502 129 | 83.140 | 7.322 | 8.1% | 90.709 | 11 600 | 165.5 | 28.706 | 2.05 |
| 7d-noindex | 7 days | off | 58 | 924 640 | 83.140 | 0.000 | 0.0% | 83.388 | 11 600 | 165.5 | 28.693 | 2.00 |
| 30d-index | 30 days | on | 14 | 519 268 | 82.219 | 6.946 | 7.8% | 89.225 | 2 800 | 685.7 | 19.793 | 1.34 |
| 30d-noindex | 30 days | off | 14 | 1 036 756 | 82.223 | 0.000 | 0.0% | 82.283 | 2 800 | 685.7 | 19.780 | 1.33 |

Compressed bytes split (per row, `metrics_date`): the index share after
compression is the same with and without the default index, because
compression leaves the default index empty (1 page per chunk) and builds its
own index on the segmentby column.

| cell | comp heap | comp index | comp toast | comp total | ratio pre/post |
|---|---:|---:|---:|---:|---:|
| 1d-index | 61.440 | 3.413 | 1.707 | 66.560 | 1.53 |
| 1d-noindex | 61.440 | 3.413 | 1.707 | 66.560 | 1.38 |
| 7d-index | 3.209 | 0.495 | 25.003 | 28.706 | 3.16 |
| 7d-noindex | 3.209 | 0.495 | 24.990 | 28.693 | 2.91 |
| 30d-index | 0.717 | 0.119 | 18.957 | 19.793 | 4.51 |
| 30d-noindex | 0.717 | 0.119 | 18.944 | 19.780 | 4.16 |

Queries, median of three `EXPLAIN (ANALYZE, BUFFERS)` runs. "exec ms (serial)"
is the same query with `max_parallel_workers_per_gather = 0`, stored by the
harness as `Q1-np`..`Q5-np` (see below).

| cell | query | exec ms | exec ms (serial) | plan ms | chunks in plan | excluded at startup | vectorized | rows scanned | workers | shared hit |
|---|---|---:|---:|---:|---:|---:|---|---:|---:|---:|
| 1d-index | Q1 | 108.63 | 61.30 | 36.53 | 400 | 0 | no | 144 000 | 2 | 9 200 |
| 1d-index | Q2 | 13.81 | 13.08 | 37.15 | 31 | 369 | yes | 148 800 | 0 | 713 |
| 1d-index | Q3 | 8.23 | 8.28 | 1.34 | 31 | 0 | no | 148 800 | 0 | 713 |
| 1d-index | Q4 | 33.21 | 31.99 | 1.99 | 31 | 0 | no | 148 800 | 0 | 713 |
| 1d-index | Q5 | 0.04 | 0.03 | 0.24 | 1 | 0 | yes | 24 | 0 | 2 |
| 1d-noindex | Q1 | 97.82 | 56.71 | 31.93 | 400 | 0 | no | 144 000 | 2 | 9 200 |
| 1d-noindex | Q2 | 12.87 | 12.75 | 32.06 | 31 | 369 | yes | 148 800 | 0 | 713 |
| 1d-noindex | Q3 | 7.63 | 7.71 | 1.22 | 31 | 0 | no | 148 800 | 0 | 713 |
| 1d-noindex | Q4 | 31.93 | 31.97 | 1.54 | 31 | 0 | no | 148 800 | 0 | 713 |
| 1d-noindex | Q5 | 0.02 | 0.03 | 0.16 | 1 | 0 | yes | 24 | 0 | 2 |
| 7d-index | Q1 | 21.22 | 15.36 | 3.76 | 58 | 0 | no | 144 000 | 2 | 6 360 |
| 7d-index | Q2 | 15.61 | 5.59 | 3.51 | 5 | 53 | yes | 148 800 | 2 | 6 025 |
| 7d-index | Q3 | 4.50 | 4.68 | 0.35 | 5 | 0 | yes | 148 800 | 0 | 4 225 |
| 7d-index | Q4 | 22.02 | 21.07 | 0.59 | 5 | 0 | yes | 148 800 | 0 | 9 025 |
| 7d-index | Q5 | 0.04 | 0.04 | 0.15 | 1 | 0 | yes | 24 | 0 | 23 |
| 7d-noindex | Q1 | 21.27 | 17.20 | 3.86 | 58 | 0 | no | 144 000 | 2 | 6 401 |
| 7d-noindex | Q2 | 15.58 | 5.94 | 3.58 | 5 | 53 | yes | 148 800 | 2 | 6 025 |
| 7d-noindex | Q3 | 4.79 | 4.55 | 0.46 | 5 | 0 | yes | 148 800 | 0 | 4 225 |
| 7d-noindex | Q4 | 21.53 | 20.88 | 0.50 | 5 | 0 | yes | 148 800 | 0 | 9 025 |
| 7d-noindex | Q5 | 0.04 | 0.04 | 0.16 | 1 | 0 | yes | 24 | 0 | 23 |
| 30d-index | Q1 | 12.01 | 13.43 | 1.03 | 14 | 0 | no | 144 000 | 2 | 2 689 |
| 30d-index | Q2 | 7.90 | 4.73 | 0.83 | 2 | 12 | yes | 148 800 | 2 | 2 530 |
| 30d-index | Q3 | 5.83 | 6.37 | 0.28 | 2 | 0 | yes | 148 800 | 0 | 2 608 |
| 30d-index | Q4 | 21.67 | 21.59 | 0.43 | 2 | 0 | yes | 148 800 | 0 | 3 992 |
| 30d-index | Q5 | 0.06 | 0.07 | 0.16 | 1 | 0 | yes | 24 | 0 | 25 |
| 30d-noindex | Q1 | 23.27 | 13.03 | 1.02 | 14 | 0 | no | 144 000 | 2 | 2 691 |
| 30d-noindex | Q2 | 20.55 | 4.85 | 0.97 | 2 | 12 | yes | 148 800 | 2 | 2 532 |
| 30d-noindex | Q3 | 6.41 | 5.89 | 0.28 | 2 | 0 | yes | 148 800 | 0 | 2 613 |
| 30d-noindex | Q4 | 21.53 | 21.53 | 0.33 | 2 | 0 | yes | 148 800 | 0 | 4 000 |
| 30d-noindex | Q5 | 0.06 | 0.06 | 0.14 | 1 | 0 | yes | 24 | 0 | 24 |

`rows scanned` is `Actual Rows x Actual Loops` summed over the chunk scan
nodes, so it counts rows after the vectorized filter, not chunks touched;
it is identical across intervals for Q2-Q4 by construction (same window).

## Matrix, `metrics_tstz` (the other six cells)

| cell | insert rows/s | total B/row (pre) | compressed B/row | avg batch rows | Q1 exec ms | Q1 exec ms (serial) | Q1 plan ms | Q1 chunks in plan |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| 1d-index | 340 606 | 101.854 | 66.560 | 24.0 | 12.02 | 12.35 | 1.85 | 31 |
| 1d-noindex | 567 817 | 91.541 | 66.560 | 24.0 | 11.95 | 12.36 | 1.84 | 31 |
| 7d-index | 403 380 | 90.709 | 30.374 | 165.5 | 6.64 | 6.65 | 0.43 | 5 |
| 7d-noindex | 630 544 | 83.388 | 30.374 | 165.5 | 6.94 | 5.97 | 0.42 | 5 |
| 30d-index | 411 767 | 89.225 | 20.962 | 685.7 | 7.06 | 5.34 | 0.29 | 2 |
| 30d-noindex | 695 279 | 82.283 | 20.962 | 685.7 | 15.44 | 5.03 | 0.31 | 2 |

`metrics_tstz` is shown for contrast only. Two things carry over from T1 and
get worse as chunks get smaller: `DATE` Q1 plans every chunk while
`TIMESTAMPTZ` Q1 is constified at plan time (400 vs 31 chunks at 1 day), and
the `DATE` twin compresses the time column better (19.79 vs 20.96 B/row total
at 30 days).

The `DATE`/`TIMESTAMPTZ` Q1 gap depends strongly on the chunk interval:

| interval | Q1 date / Q1 tstz (parallel) | Q1 date / Q1 tstz (serial) |
|---|---:|---:|
| 1 day | 9.0x | 5.0x |
| 7 days | 3.2x | 2.3x |
| 30 days | 1.7x | 2.5x |

## Chunk index usage over Q1..Q5

`pg_stat_user_indexes.idx_scan` summed over the indexes of the chunks,
sampled before the query set, after it, and after the serial pass. Scope
`chunk` is the uncompressed chunks, which is where the default time index
lives; scope `compressed` is the index compression builds on the compressed
relation.

| cell | table | scope | indexes | index bytes | idx_scan before | after Q1-Q5 | delta | after serial pass | delta |
|---|---|---|---:|---:|---:|---:|---:|---:|---:|
| 1d-index | metrics_date | chunk | 400 | 3 276 800 | 273 | 273 | **0** | 273 | **0** |
| 1d-index | metrics_date | compressed | 400 | 6 553 600 | 0 | 3 | 3 | 6 | 3 |
| 1d-index | metrics_tstz | chunk | 400 | 3 276 800 | 274 | 274 | **0** | 274 | **0** |
| 1d-index | metrics_tstz | compressed | 400 | 6 553 600 | 0 | 6 | 6 | 12 | 6 |
| 1d-noindex | metrics_date | chunk | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| 1d-noindex | metrics_date | compressed | 400 | 6 553 600 | 0 | 3 | 3 | 6 | 3 |
| 1d-noindex | metrics_tstz | chunk | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| 1d-noindex | metrics_tstz | compressed | 400 | 6 553 600 | 0 | 6 | 6 | 12 | 6 |
| 7d-index | metrics_date | chunk | 58 | 475 136 | 119 | 119 | **0** | 119 | **0** |
| 7d-index | metrics_date | compressed | 58 | 950 272 | 0 | 3 | 3 | 6 | 3 |
| 7d-index | metrics_tstz | chunk | 58 | 475 136 | 119 | 119 | **0** | 119 | **0** |
| 7d-index | metrics_tstz | compressed | 58 | 950 272 | 0 | 3 | 3 | 6 | 3 |
| 7d-noindex | metrics_date | chunk | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| 7d-noindex | metrics_date | compressed | 58 | 950 272 | 0 | 3 | 3 | 6 | 3 |
| 7d-noindex | metrics_tstz | chunk | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| 7d-noindex | metrics_tstz | compressed | 58 | 950 272 | 0 | 3 | 3 | 6 | 3 |
| 30d-index | metrics_date | chunk | 14 | 114 688 | 31 | 31 | **0** | 31 | **0** |
| 30d-index | metrics_date | compressed | 14 | 229 376 | 0 | 3 | 3 | 6 | 3 |
| 30d-index | metrics_tstz | chunk | 14 | 114 688 | 31 | 31 | **0** | 31 | **0** |
| 30d-index | metrics_tstz | compressed | 14 | 229 376 | 0 | 3 | 3 | 6 | 3 |
| 30d-noindex | metrics_date | chunk | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| 30d-noindex | metrics_date | compressed | 14 | 229 376 | 0 | 3 | 3 | 6 | 3 |
| 30d-noindex | metrics_tstz | chunk | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| 30d-noindex | metrics_tstz | compressed | 14 | 229 376 | 0 | 3 | 3 | 6 | 3 |

Reading the counters:

- The `chunk` delta is **0 in every cell**. None of Q1 to Q5 used the default
  time index, in either pass, at any chunk interval.
- The non-zero "before" values (273 at 1 day, 119 at 7 days, 31 at 30 days)
  come from the load and `compress_chunk` phases, not from the query set, and
  do not scale with the chunk count. They are exactly why the sample is taken
  before *and* after instead of being read once at the end: read once, they
  would look like query-side index usage.
- The `compressed` delta of 3 on `metrics_date` is Q5, three runs, one chunk:
  the point lookup uses the index compression builds on `device_id`, not the
  time index. The serial pass adds another 3.
- Sanity check that a zero delta is a real zero: on the smoke database, a
  forced `SET enable_seqscan = off; SELECT count(*) FROM metrics_date WHERE
  device_id = 5` moved the `compressed` counter from 0 to 3 through the same
  sampling path.
- `index bytes` here is measured after compression, where the default index
  has been emptied down to one page per chunk (400 x 8 kB). The index cost
  that matters is the pre-compression one in the first table (6.9-10.2 bytes
  per row).

## Analysis

### 1. At which chunk interval does batch fill reach 900 rows?

Measured fill: **24.0** rows/batch at 1 day, **165.5** at 7 days, **685.7** at
30 days. None of the three reaches 900.

The fill follows a simple model, which the measurements confirm to three
digits: with `segmentby = device_id`, each chunk is cut into one batch stream
per device, so

```
rows per device per chunk  N = rows_per_device_day x days_in_chunk
batches per device         ceil(N / 1000)
average fill               N / ceil(N / 1000)
```

For this shape (`rows_per_device_day = 24`): 1 day -> N = 24 (measured 24.0);
7 days -> N = 168, and the partial chunks at the ends of the range pull the
average to the measured 165.5; 30 days -> the 400-day range is covered by 14
aligned chunks, i.e. 28.6 days each -> N = 686 (measured 685.7).

So fill first reaches 900 at **38 days** (N = 912) and peaks at **41 days**
(N = 984). It then *falls off a cliff*: 42 days gives N = 1008, which is two
batches, i.e. an average fill of 504. The target is the largest interval with
`rows_per_device_day x days <= 1000`, not simply "as large as possible".

**The customer's device count does not change this.** Fill depends on rows per
device per chunk; adding devices adds batch streams, not rows per stream. Going
from 200 to 2000 devices at the same 24 rows/device/day multiplies the batch
count by 10 (80 000 -> 800 000 batches at 1 day) and leaves the fill at 24.
What changes the answer is the customer's real *rows per device per day*: at
1440 rows/device/day (one per minute) even a 1-day chunk overshoots
(N = 1440 -> 2 batches -> 720), and the right interval is then well under a
day, or `segmentby` has to change.

### 2. Does any query use the time index, and what does it cost?

No. The `idx_scan` delta on the chunk indexes is 0 for all of Q1 to Q5, in all
six cells, in both the parallel and the serial pass. The only index the query
set touches is the one compression builds on the segmentby column (Q5).

This is structural rather than accidental: a `DATE` dimension has one distinct
value per day, so a chunk of `k` days holds at most `k` distinct keys. At the
default 7 days an index lookup can never select less than about 1/7 of the
chunk, and at 1 day the index has exactly one key: it cannot be selective
inside a chunk at all. Chunk exclusion already does the coarse filtering, and
after compression the chunk's own heap is empty, so the index is unused by
construction.

Its cost, `metrics_date`:

| interval | index B/row (pre-compression) | share of pre-compression total | insert rows/s with index | without | index cost |
|---|---:|---:|---:|---:|---:|
| 1 day | 10.240 | 10.1% | 406 600 | 746 250 | **-45.5%** |
| 7 days | 7.322 | 8.1% | 502 129 | 924 640 | **-45.7%** |
| 30 days | 6.946 | 7.8% | 519 268 | 1 036 756 | **-49.9%** |

The same on `metrics_tstz`: -40.0%, -36.0%, -40.8%. Deduplication does rescue
part of the byte cost -- 7 bytes per row rather than the 8 the key alone would
need, because a posting list still needs a 6-byte TID per row -- but it cannot
rescue the write cost.

Two qualifications the numbers make explicit:

- The byte cost is transient. Compression empties the index (down to 8 kB per
  chunk), so it is paid on the uncompressed, most recent chunks only: 8-10% of
  the hot set, 0% of the archive.
- The write cost is permanent, and it is the larger of the two: the default
  index roughly halves insert throughput for this workload at every interval.

### 3. Planning time saved by 30 days over 1 day, and Q3's exclusion

Medians on `metrics_date`:

| query | 1 day | 7 days | 30 days | saved, 30d vs 1d | saved, 30d vs 7d |
|---|---:|---:|---:|---:|---:|
| Q1 plan ms | 36.53 | 3.76 | 1.03 | **-35.50 (-97%)** | -2.73 (-73%) |
| Q2 plan ms | 37.15 | 3.51 | 0.83 | -36.32 (-98%) | -2.68 (-76%) |
| Q3 plan ms | 1.34 | 0.35 | 0.28 | -1.06 | -0.07 |
| Q4 plan ms | 1.99 | 0.59 | 0.43 | -1.56 | -0.16 |
| Q5 plan ms | 0.24 | 0.15 | 0.16 | -0.08 | +0.01 |
| Q1..Q5 total | 77.25 | 8.36 | 2.73 | **-74.52 (-96%)** | -5.63 (-67%) |

Planning cost tracks the number of chunks the planner has to consider, which
is why Q1 and Q2 dominate: neither gets plan-time exclusion on a `DATE`
column, so both plan all 400 / 58 / 14 chunks. Q3, with immutable literals,
is excluded at plan time and costs about the same everywhere.

At 1 day, planning Q1 (36.5 ms) costs three times as much as executing the
equivalent `TIMESTAMPTZ` query (12.0 ms).

**Q3's exclusion does get slightly worse at 30 days, but by little.** Q3 asks
for a 31-day window. It lands in 31 chunks at 1 day (exact fit), 5 chunks at 7
days (35 days scanned for 31 wanted), 2 chunks at 30 days (up to 57 days
scanned). The over-scan is absorbed by the vectorized filter:

| interval | Q3 exec ms (serial) | shared hit | Q4 exec ms (serial) |
|---|---:|---:|---:|
| 1 day | 8.28 / 7.71 | 713 | 31.99 / 31.97 |
| 7 days | 4.68 / 4.55 | 4 225 | 21.07 / 20.88 |
| 30 days | 6.37 / 5.89 | 2 608 | 21.59 / 21.53 |

Taking the mean of the two index states, Q3 serial costs 4.62 ms at 7 days and
6.13 ms at 30 days: **+1.5 ms, +33%**. It is still 1.9 ms faster than at 1 day
(8.00 ms), where 31 chunks cost more in per-chunk setup than the over-scan
costs at 30 days. Q4, the bucketed aggregate over the same window, shows no
penalty at all (21.6 vs 21.0 ms). Buffer hits go *down* at 30 days (2 608 vs
4 225) because the data is better compressed.

### What the serial pass bought

The serial numbers (`max_parallel_workers_per_gather = 0`) were added after
T1's open question 2, and they change the reading of two cells:

- **The `DATE` Q1 plan is slower with parallel workers at small chunk
  intervals.** At 1 day: 108.63 ms with 2 workers, 61.30 ms serial. Scanning
  400 chunks through a parallel append costs more in per-worker chunk setup
  than the workers return.
- **Cells that should be identical only agree when parallelism is off.** The
  default index changes nothing about reads, so 30d-index and 30d-noindex
  should give the same query times. With parallelism: Q1 12.01 vs 23.27 ms,
  Q2 7.90 vs 20.55 ms (up to 2.6x apart, pure worker-scheduling noise). Serial:
  13.43 vs 13.03 and 4.73 vs 4.85, within 5%. Across all 6 cells and Q1..Q5,
  index-on versus index-off serial times agree within 10% with no systematic
  direction, which is the measurement that actually establishes "the default
  index does not help any of these queries".

The scorecard should therefore quote serial numbers when comparing
configurations, and quote both when comparing `DATE` against `TIMESTAMPTZ`.

## Recommendation: create-time hint, not an engine default change

**Emit a `NOTICE` from `create_hypertable()`/`by_range()` when a `DATE`
dimension is given a chunk interval of one day or less, and mention the
default time index in it.** Documentation for everything above that.

The thresholds that justify each option, against the measured numbers:

*Engine default change (a `DATE`-specific interval): no.* The bar for
silently changing a default that every existing deployment inherits is a win
of at least 2x with no query regression. From 7 days to 30 days the win is
28.71 -> 19.79 compressed bytes per row (**1.45x**), planning 8.36 -> 2.73 ms
over Q1..Q5, and it comes with a 33% Q3 regression (4.62 -> 6.13 ms serial)
plus a coarser exclusion granularity for any window query shorter than a
month. 1.45x with a regression is below the bar. The optimum interval is also
not a constant the engine can know: it is `1000 / rows_per_device_day` days
(38-41 days here, under a day at one row per minute), i.e. it depends on the
ingest rate and on `segmentby`, neither of which exists at `create_hypertable`
time.

*Engine default change (drop the default index for `DATE`): no, and this is
the closest call.* The index is never scanned in any cell, costs 6.9-10.2
bytes per row while a chunk is uncompressed and **45-50% of insert
throughput**, which on its own would clear a "2x on ingest" bar. It does not
clear it because this harness only proves the negative for one analytic query
set: a `SELECT ... WHERE day = X ORDER BY day DESC LIMIT n` against
*uncompressed* recent chunks, or an update or delete by time, is exactly the
shape the index exists for, and `create_default_indexes => false` already
exists for users who know they have no such query. Removing an index by
default can make a query 100x slower; keeping it costs 2x on ingest. Wrong
direction for a silent default.

*Create-time hint: yes, at the threshold "`DATE` dimension AND chunk interval
<= 1 day".* One day is where the numbers stop being a trade-off and become a
cliff, and it is decidable from the arguments of `create_hypertable()` alone:

| against 7 days (default) | against 30 days |
|---|---|
| compressed 66.56 vs 28.71 B/row = **2.32x more storage** | **3.36x** |
| batch fill 24 of 1000 rows = **2.4% of the target** | 685.7 |
| Q1 planning 36.53 vs 3.76 ms = **9.7x** | 35.5x |
| Q1 execution (serial) 61.30 vs 15.36 ms = **4.0x** | 4.6x |
| `DATE` vs `TIMESTAMPTZ` Q1 penalty 9.0x vs 3.2x | 1.7x |
| chunks 400 vs 58 for the same 400 days | 14 |

A one-day chunk on a `DATE` column is additionally a degenerate case the
engine can reason about: the partition granularity equals the type's
granularity, so each chunk holds exactly one distinct time value. Every batch
is then one device-day, the default time index has exactly one key per chunk,
and chunk exclusion is as fine as it can ever get while planning cost is at
its maximum. Suggested wording:

> NOTICE: chunk interval of 1 day on DATE column "day" gives one distinct
> value per chunk
> DETAIL: Compression batches will hold one device-day of rows and the
> default time index cannot be selective within a chunk.
> HINT: Consider a larger chunk interval (about 1000 / rows per device per
> day, in days) and create_default_indexes => false if no query filters a
> single day of uncompressed data.

*Documentation: yes, alongside the hint*, for the three findings a `NOTICE`
cannot carry: the `1000 / rows_per_device_day` rule for batch fill and its
cliff just past the optimum; that the default time index costs about half the
insert throughput and is never used by analytic queries on compressed chunks;
and that on a `DATE` column planning cost scales with chunk count for every
`now()`-based query until T2/T3 land, which is what makes small chunks hurt
three times as much on `DATE` as on `TIMESTAMPTZ`.

Ordering note for T6: the defaults interact with the T2/T3 defect rather than
competing with it. Fixing constification removes the 400-chunk plans that make
a 1-day interval catastrophic (`DATE`/`TIMESTAMPTZ` Q1 goes 9.0x -> 3.2x ->
1.7x as chunks grow, purely from how many chunks the unconstified plan has to
carry). T5's recommendation is cheap and independent; it does not change the
ranking.

## Not measured

- `customer` scale (1095 days x 2000 devices x 24 rows). The brief makes it
  conditional ("if time allows"); the session was interrupted after the six
  `small` cells and resumed for analysis only, so no `customer` cell was run.
  The batch-fill model above says what to expect: identical fill, 10x the
  batches and 10x the chunk catalog.
- Any cell at a different `segmentby`, `orderby` or column order. Those are
  T4's matrix.
