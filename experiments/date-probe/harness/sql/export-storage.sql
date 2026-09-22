-- One CSV row per (table, column), plus the parenthesized table-level rows
-- (heap), (index), (toast), (total) and the per-column sum (columns).
-- Written to stdout, so run.sh redirects it into the result file.
--
-- Variables: run_id
\set ON_ERROR_STOP on

COPY (
    SELECT r.run_id, r.variant, r.git_sha, s.tbl, s.colname, s.coltype,
           s.uncompressed_bytes, s.compressed_bytes,
           round(s.uncompressed_bytes::numeric / NULLIF(n.nrows, 0), 3) AS uncompressed_bytes_per_row,
           round(s.compressed_bytes::numeric / NULLIF(n.nrows, 0), 3)   AS compressed_bytes_per_row,
           round(s.uncompressed_bytes::numeric / NULLIF(s.compressed_bytes, 0), 3) AS ratio,
           s.batches, s.avg_meta_count
    FROM probe_storage s
    JOIN probe_run r USING (run_id)
    JOIN probe_snapshot n ON n.run_id = s.run_id AND n.tbl = s.tbl
    WHERE s.run_id = :'run_id'
    ORDER BY s.tbl, (s.colname LIKE '(%'), s.colname
) TO STDOUT WITH (FORMAT csv, HEADER);
