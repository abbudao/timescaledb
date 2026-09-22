# T4 measurement: orderby tiebreaker for a DATE dimension

Branch `probe/b1-orderby-tiebreaker` @ `ad228b1`, harness `probe/harness` @ `b1593f7`
merged locally (never committed), scale `small`
(400 days x 200 devices x 24 rows = 1.92 M rows, chunk interval 7 days,
`compress_segmentby = 'device_id'`, default indexes on).

Only `metrics_date` is reported; `metrics_tstz` is unaffected by this change.

## Variants

| variant | database | orderby on `metrics_date` | how it was produced |
|---|---|---|---|
| `baseline` | `probe_t4_baseline` | `day DESC` | `sql/compression_defaults.sql` restored to the base branch's version, rebuilt, installed |
| `heuristic` | `probe_t4_heuristic` | `day DESC, seq DESC` | this branch's `get_orderby_defaults`, no `--orderby` flag |
| `tiebreaker` | `probe_t4_tiebreaker` | `day DESC, seq DESC` | explicit `--orderby 'day DESC, seq DESC'` |

The heuristic picks `seq` through rule 2 (no unique index exists and the table is
empty at `ALTER TABLE ... SET (timescaledb.compress ...)` time, so there are no
statistics either):

```
{"clauses": ["day DESC", "seq DESC"],
 "message": "Column \"seq\" was appended to the default order by as a tiebreaker
             for the date dimension \"day\". ...",
 "confidence": 4}
```

`heuristic` and `tiebreaker` therefore compress the table identically; the
difference between their numbers is run-to-run variance (the generator uses
`random()` for `v2`, `v3` and `status`), which is useful as a noise floor.

## Compressed bytes per column (`metrics_date`, sum of `pg_column_size` over the compressed chunks)

| column | baseline | heuristic | tiebreaker | heuristic vs baseline |
|---|---:|---:|---:|---:|
| `day` | 1,059,400 | 1,059,400 | 1,059,400 | 0 |
| `device_id` | 46,400 | 46,400 | 46,400 | 0 |
| `region_id` | 594,120 | 594,120 | 594,120 | 0 |
| `seq` | 2,322,376 | 2,200,920 | 2,200,920 | **-121,456 (-5.2%)** |
| `status` | 1,314,600 | 1,314,600 | 1,314,600 | 0 |
| `v1` (smooth series) | 13,349,512 | 13,281,624 | 13,281,088 | **-67,888 (-0.51%)** |
| `v2` (random noise) | 14,838,912 | 14,837,184 | 14,835,736 | -1,728 (-0.01%) |
| `v3` (random int) | 2,657,896 | 2,658,976 | 2,658,648 | +1,080 (+0.04%) |
| **value columns** | **36,183,216** | **35,993,224** | **35,990,912** | **-189,992 (-0.53%)** |

## Per-batch metadata columns

| column | baseline | heuristic | tiebreaker |
|---|---:|---:|---:|
| `_ts_meta_count` | 46,400 | 46,400 | 46,400 |
| `_ts_meta_min_1` / `_ts_meta_max_1` (`day`) | 92,800 | 92,800 | 92,800 |
| `_ts_meta_min_2` / `_ts_meta_max_2` (`seq`) | - | 185,600 | 185,600 |
| `_ts_meta_v2_first_day` / `_ts_meta_v2_last_day` | 92,800 | 92,800 | 92,800 |
| `_ts_meta_v2_first_seq` / `_ts_meta_v2_last_seq` | - | 185,600 | 185,600 |
| **metadata columns** | **232,000** | **603,200** | **603,200** |
| **all columns** | **36,415,216** | **36,596,424** | **36,594,112** |

A second orderby column adds four metadata columns (min/max and first/last of
`seq`), **+371,200 bytes**, which is 1.95x the 189,992 bytes the value columns save.
On this accounting the tiebreaker makes the table **0.50% larger**.

## Physical bytes, batch fill and wall time

| metric | baseline | heuristic | tiebreaker |
|---|---:|---:|---:|
| batches | 11,600 | 11,600 | 11,600 |
| avg rows per batch | 165.5 | 165.5 | 165.5 |
| heap after compression | 6,160,384 | 6,160,384 | 6,160,384 |
| index after compression | 950,272 | 1,900,544 | 1,900,544 |
| toast after compression | 47,947,776 | 46,080,000 | 46,211,072 |
| **total after compression** | **55,058,432** | **54,140,928** | **54,272,000** |
| total before compression | 174,153,728 | 174,170,112 | 174,178,304 |
| compression ratio | 3.16 | 3.22 | 3.21 |
| compress wall time (s) | 2.18 | 2.13 | 2.14 |
| load wall time (s) | 4.34 | 3.72 | 3.79 |

Batch fill is unchanged: the orderby does not move batch boundaries, which are
set by segmentby (200 devices) and the chunk interval (7 days x 24 rows = 168
rows per device per chunk).

Compression wall time does not regress (2.18 s -> 2.13/2.14 s, within noise).

## Reading the two accountings

The two measures disagree in sign and both are reported on purpose:

- **Per-column datum bytes** (`pg_column_size` over the compressed chunks) say
  the change costs 181,208 bytes, because the four new metadata columns cost
  about twice what the value columns save.
- **Physical bytes** say the change saves 917,504 bytes (-1.67%): the compressed
  chunks' index grows by 950,272 bytes but toast shrinks by 1,867,776 bytes. The
  toast drop is an order of magnitude larger than the datum saving, so most of it
  is toast chunking and page packing, not better compression. The `tiebreaker`
  run, which is the same configuration as `heuristic`, lands 131,072 bytes away
  from it, so the run-to-run noise floor on the total is about 0.24%.

Either way the effect is far below the bar the brief sets.

## Verdict

**No.** The value-column saving (189,992 bytes, 0.53% of the value columns and
0.52% of all compressed column bytes) does not exceed the metadata cost
(371,200 bytes), let alone by a tenth of the total compressed bytes, which would
require about 3.6 MB. The largest single win, `seq` at -5.2%, is the tiebreaker
column compressing itself better once it is sorted; the one column that is
genuinely temporally correlated inside a day, `v1`, gains 0.51%.

The heuristic is therefore not worth turning on as a *default*. It is cheap and
safe as an opt-in, and the picture could change for a table whose batches are
much wider than 168 rows (fewer segmentby values, or a chunk interval large
enough to reach the 1000-row batch limit) and whose value columns are all
temporally correlated. This measurement should be repeated at `customer` scale
before the design is ruled out entirely.
