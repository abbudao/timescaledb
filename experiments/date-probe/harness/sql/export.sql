-- Write the two CSVs of a run. Client-side \copy, so the files land next to
-- the harness and not in the server's data directory.
--
-- Variables: run_id queries_csv storage_csv
\set ON_ERROR_STOP on

\copy (SELECT r.run_id, r.variant, r.git_sha, m.tbl, m.query_id, m.run, m.planning_ms, m.exec_ms, m.shared_hit, m.shared_read, m.chunks_in_plan, m.compressed_chunks_in_plan, m.chunk_scan_nodes, m.chunks_excluded_startup, m.vectorized_filter, m.rows, m.scan_rows, m.query_text FROM probe_query_metrics m JOIN probe_run r USING (run_id) WHERE m.run_id = :'run_id' ORDER BY m.tbl, m.query_id, m.run) TO :'queries_csv' CSV HEADER

\copy (SELECT r.run_id, r.variant, r.git_sha, s.tbl, s.colname, s.coltype, s.uncompressed_bytes, s.compressed_bytes, round(s.uncompressed_bytes::numeric / NULLIF(n.nrows, 0), 3) AS uncompressed_bytes_per_row, round(s.compressed_bytes::numeric / NULLIF(n.nrows, 0), 3) AS compressed_bytes_per_row, round(s.uncompressed_bytes::numeric / NULLIF(s.compressed_bytes, 0), 3) AS ratio, s.batches, s.avg_meta_count FROM probe_storage s JOIN probe_run r USING (run_id) JOIN probe_snapshot n ON n.run_id = s.run_id AND n.tbl = s.tbl WHERE s.run_id = :'run_id' ORDER BY s.tbl, (s.colname LIKE '(%'), s.colname) TO :'storage_csv' CSV HEADER
