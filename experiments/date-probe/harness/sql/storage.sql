-- Per-column compressed bytes, batch count and batch fill, plus the
-- table-level physical rows.
--
-- Rows whose colname is parenthesized are physical bytes from the size
-- functions: (heap), (index), (toast), (total). The (columns) row is the sum
-- of the per-column logical datum bytes, which is smaller than (heap)
-- because it excludes tuple headers and alignment padding.
--
-- Variables: run_id
\set ON_ERROR_STOP on

CALL probe_collect_compressed(:'run_id', 'metrics_date');
CALL probe_collect_compressed(:'run_id', 'metrics_tstz');

INSERT INTO probe_storage (run_id, tbl, colname, coltype, uncompressed_bytes, compressed_bytes)
SELECT run_id, tbl, v.colname, NULL,
       CASE v.colname WHEN '(heap)'  THEN before_heap
                      WHEN '(index)' THEN before_index
                      WHEN '(toast)' THEN before_toast
                      ELSE before_total END,
       CASE v.colname WHEN '(heap)'  THEN after_heap
                      WHEN '(index)' THEN after_index
                      WHEN '(toast)' THEN after_toast
                      ELSE after_total END
FROM probe_compstats,
     (VALUES ('(heap)'), ('(index)'), ('(toast)'), ('(total)')) AS v(colname)
WHERE run_id = :'run_id'
ON CONFLICT (run_id, tbl, colname) DO UPDATE
   SET uncompressed_bytes = excluded.uncompressed_bytes,
       compressed_bytes = excluded.compressed_bytes;

INSERT INTO probe_storage (run_id, tbl, colname, coltype, uncompressed_bytes, compressed_bytes)
SELECT run_id, tbl, '(columns)', NULL,
       sum(uncompressed_bytes), sum(compressed_bytes)
FROM probe_storage
WHERE run_id = :'run_id' AND colname NOT LIKE '(%'
GROUP BY run_id, tbl
ON CONFLICT (run_id, tbl, colname) DO UPDATE
   SET uncompressed_bytes = excluded.uncompressed_bytes,
       compressed_bytes = excluded.compressed_bytes;

SELECT tbl, colname, coltype,
       uncompressed_bytes, compressed_bytes,
       round(uncompressed_bytes::numeric / NULLIF(compressed_bytes, 0), 2) AS ratio,
       batches, round(avg_meta_count::numeric, 1) AS avg_batch_rows
FROM probe_storage
WHERE run_id = :'run_id' AND tbl = 'metrics_date'
ORDER BY (colname LIKE '(%'), colname;
