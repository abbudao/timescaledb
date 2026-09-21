# T4: Orderby tiebreaker for low-cardinality time columns

Branch: `probe/b1-orderby-tiebreaker` (from the base branch). Track B,
compression. SQL only in this iteration.

## Goal

Compression sorts rows by segmentby plus orderby with no tiebreaker
(`compression_create_tuplesort_state` in `tsl/src/compression/compression.c`).
When the orderby is a `DATE` column and a segment has many rows per day, rows
within a day land in each batch of 1000 in arbitrary order, and the value
columns lose the temporal locality that `deltadelta` and `gorilla` depend on.

The default orderby is computed by the PL/pgSQL function
`_timescaledb_functions.get_orderby_defaults` in `sql/compression_defaults.sql`,
selected through the GUC `timescaledb.compression_orderby_default_function`.
Change that function so a `DATE` dimension gets a tiebreaker column appended,
and measure what it buys.

## Allowed paths

- `sql/compression_defaults.sql`, function `get_orderby_defaults` only
- `tsl/test/sql/compression_defaults.sql` and its expected file
- `experiments/date-probe/results/**`

Forbidden: any C file, `sql/updates/`, `sql/pre_install/`, other SQL files,
`.unreleased/`.

## Current logic to preserve

Read the function first. It builds `_orderby_names` from the columns of a
unique index not covered by segmentby, appends the dimension columns, and
returns `{"clauses": [...], "message": ..., "confidence": 5|8}`. Keep the
JSON shape and the existing outputs for every non-`DATE` case untouched in
this iteration, so the existing expected file changes only by the cases you
add.

## Heuristic

After `_orderby_names` is built, if the first orderby column is an open
dimension whose `column_type` in `_timescaledb_catalog.dimension` is
`'date'::regtype`, append one tiebreaker chosen in this order:

1. a column of any unique index on the table not already in segmentby or
   orderby;
2. otherwise a non-segmentby column of type `bigint`, `int`, `timestamptz` or
   `timestamp` whose name matches `seq`, `id`, `ts`, `time`, `created_at` or
   `updated_at`;
3. otherwise, when `pg_stats` has rows for the table, the non-segmentby
   column with the highest `n_distinct`;
4. otherwise no change.

Emit the tiebreaker as `<col> DESC` to match the dimension's direction. Lower
`confidence` by one when a tiebreaker was added through rules 2 or 3 and
mention it in `message`.

The function body is re-applied on extension update, so no update script is
needed as long as the signature does not change. Confirm in `sql/CMakeLists.txt`
that `compression_defaults.sql` is in the set that is re-run and note it in
the report.

## Tests

Extend `tsl/test/sql/compression_defaults.sql` with `DATE` dimension tables
covering each rule: with a unique index, with a `seq bigint` column and no
index, with statistics only, and with nothing applicable. Show the returned
JSON and the resulting `compression_settings`.

```bash
make -C build -j"$(nproc)" && make -C build install
SUITE=tsl experiments/date-probe/bin/regress.sh compression_defaults compression_ddl compression_settings
```

## Measurement

With the harness from `probe/harness` merged locally, at `small` scale:

| variant | orderby |
|---|---|
| `baseline` | default on unmodified `main` |
| `heuristic` | default with your change |
| `tiebreaker` | explicit `--orderby 'day DESC, seq DESC'` |

Report per-column compressed bytes and totals for `metrics_date`, batch fill,
and compression wall time. Note that a second orderby column adds per-batch
min and max metadata columns; include their bytes in the total so the trade
is visible.

## Done criteria

- Existing `compression_defaults` cases produce identical output; new `DATE`
  cases show the tiebreaker.
- The measurement table exists in `results/T4-orderby-<short sha>.md` with all
  three variants.
- No file outside the allowed paths changed.

## Report

Template in `experiments/date-probe/README.md`. Add the measurement table and
a one-line verdict: does the value-column saving exceed the metadata cost by
at least a tenth of total compressed bytes.
