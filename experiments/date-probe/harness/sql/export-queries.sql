-- One CSV row per (table, query, run). Written to stdout, so run.sh redirects
-- it into the result file. (\copy is not used: it does not expand psql
-- variables inside the query.)
--
-- Variables: run_id
\set ON_ERROR_STOP on

COPY (
    SELECT r.run_id, r.variant, r.git_sha, m.tbl, m.query_id, m.run,
           m.planning_ms, m.exec_ms, m.shared_hit, m.shared_read,
           m.chunks_in_plan, m.compressed_chunks_in_plan, m.chunk_scan_nodes,
           m.chunks_excluded_startup, m.vectorized_filter, m.rows, m.scan_rows,
           m.workers_launched, m.query_text
    FROM probe_query_metrics m
    JOIN probe_run r USING (run_id)
    WHERE m.run_id = :'run_id'
    ORDER BY m.tbl, m.query_id, m.run
) TO STDOUT WITH (FORMAT csv, HEADER);
