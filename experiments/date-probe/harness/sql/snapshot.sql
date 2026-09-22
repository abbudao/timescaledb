-- Size of both twins before compression: physical bytes per table (heap,
-- index, toast, which is where DATE alignment padding shows up) and logical
-- bytes per column.
--
-- Variables: run_id
\set ON_ERROR_STOP on

VACUUM (ANALYZE) metrics_date;
VACUUM (ANALYZE) metrics_tstz;

INSERT INTO probe_snapshot (run_id, tbl, nrows, heap_bytes, index_bytes, toast_bytes, total_bytes)
SELECT :'run_id', 'metrics_date', (SELECT count(*) FROM metrics_date),
       COALESCE(table_bytes, 0), COALESCE(index_bytes, 0),
       COALESCE(toast_bytes, 0), COALESCE(total_bytes, 0)
FROM hypertable_detailed_size('metrics_date')
ON CONFLICT (run_id, tbl) DO UPDATE
   SET nrows = excluded.nrows, heap_bytes = excluded.heap_bytes,
       index_bytes = excluded.index_bytes, toast_bytes = excluded.toast_bytes,
       total_bytes = excluded.total_bytes;

INSERT INTO probe_snapshot (run_id, tbl, nrows, heap_bytes, index_bytes, toast_bytes, total_bytes)
SELECT :'run_id', 'metrics_tstz', (SELECT count(*) FROM metrics_tstz),
       COALESCE(table_bytes, 0), COALESCE(index_bytes, 0),
       COALESCE(toast_bytes, 0), COALESCE(total_bytes, 0)
FROM hypertable_detailed_size('metrics_tstz')
ON CONFLICT (run_id, tbl) DO UPDATE
   SET nrows = excluded.nrows, heap_bytes = excluded.heap_bytes,
       index_bytes = excluded.index_bytes, toast_bytes = excluded.toast_bytes,
       total_bytes = excluded.total_bytes;

CALL probe_collect_uncompressed(:'run_id', 'metrics_date');
CALL probe_collect_uncompressed(:'run_id', 'metrics_tstz');

SELECT tbl, nrows,
       pg_size_pretty(heap_bytes)  AS heap,
       pg_size_pretty(index_bytes) AS idx,
       round((heap_bytes::numeric / nrows), 2)  AS heap_bytes_per_row,
       round((index_bytes::numeric / nrows), 2) AS index_bytes_per_row
FROM probe_snapshot WHERE run_id = :'run_id' ORDER BY tbl;
