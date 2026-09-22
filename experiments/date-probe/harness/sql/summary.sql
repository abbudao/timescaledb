-- Human-readable summary of a run, as markdown on stdout.
-- Run with: psql -X -q -A -t -v run_id=... -f summary.sql > <variant>-<sha>-summary.md
--
-- Variables: run_id
\set ON_ERROR_STOP on

SELECT format('# DATE probe: variant `%s` @ %s', variant, git_sha) FROM probe_run WHERE run_id = :'run_id';
SELECT '';
SELECT format('run_id `%s`, scale `%s`, TimescaleDB %s on PostgreSQL %s, started %s UTC',
              run_id, scale, extversion, pg_version, to_char(started_at AT TIME ZONE 'UTC', 'YYYY-MM-DD HH24:MI'))
FROM probe_run WHERE run_id = :'run_id';
SELECT '';
SELECT format('| days | devices | rows/device/day | rows | chunk interval | default indexes | compress_orderby | column order | date range |');
SELECT '|---|---|---|---|---|---|---|---|---|';
SELECT format('| %s | %s | %s | %s | %s | %s | %s | %s | %s .. %s |',
              days, devices, rows_per_device_day,
              days::bigint * devices * rows_per_device_day,
              chunk_interval, with_index, COALESCE(orderby_date, '(default)'),
              column_order, start_date, end_date)
FROM probe_run WHERE run_id = :'run_id';

SELECT '';
SELECT '## Queries, median of three runs';
SELECT '';
SELECT '| query | table | exec ms | plan ms | chunks in plan | excluded at startup | vectorized filter | top rows | rows scanned | shared hit | shared read |';
SELECT '|---|---|---:|---:|---:|---:|---|---:|---:|---:|---:|';
SELECT format('| %s | %s | %s | %s | %s | %s | %s | %s | %s | %s | %s |',
              query_id, tbl,
              round(exec_ms_median::numeric, 2), round(planning_ms_median::numeric, 2),
              chunks_in_plan, chunks_excluded_startup, vectorized_filter,
              round(rows::numeric, 0), round(scan_rows::numeric, 0),
              round(shared_hit_median::numeric, 0), round(shared_read_median::numeric, 0))
FROM probe_query_median WHERE run_id = :'run_id' ORDER BY query_id, tbl;

SELECT '';
SELECT '## Load, compression and continuous aggregate';
SELECT '';
SELECT '| table | phase | seconds | rows | rows/sec |';
SELECT '|---|---|---:|---:|---:|';
SELECT format('| %s | %s | %s | %s | %s |', tbl, phase, round(seconds::numeric, 2), nrows,
              CASE WHEN seconds > 0 AND nrows IS NOT NULL
                   THEN round((nrows / seconds)::numeric, 0) END)
FROM probe_timing WHERE run_id = :'run_id' ORDER BY phase, tbl;

SELECT '';
SELECT '## Storage, whole table';
SELECT '';
SELECT '| table | rows | heap before | index before | total before | bytes/row before | total after | bytes/row after | ratio |';
SELECT '|---|---:|---:|---:|---:|---:|---:|---:|---:|';
SELECT format('| %s | %s | %s | %s | %s | %s | %s | %s | %s |',
              s.tbl, s.nrows,
              pg_size_pretty(s.heap_bytes), pg_size_pretty(s.index_bytes),
              pg_size_pretty(s.total_bytes),
              round(s.total_bytes::numeric / NULLIF(s.nrows, 0), 2),
              pg_size_pretty(c.after_total),
              round(c.after_total::numeric / NULLIF(s.nrows, 0), 2),
              round(c.before_total::numeric / NULLIF(c.after_total, 0), 2))
FROM probe_snapshot s JOIN probe_compstats c USING (run_id, tbl)
WHERE s.run_id = :'run_id' ORDER BY s.tbl;

SELECT '';
SELECT '## Storage per column';
SELECT '';
SELECT '| table | column | type | uncompressed bytes | bytes/row | compressed bytes | bytes/row | ratio | batches | avg batch rows |';
SELECT '|---|---|---|---:|---:|---:|---:|---:|---:|---:|';
SELECT format('| %s | %s | %s | %s | %s | %s | %s | %s | %s | %s |',
              st.tbl, st.colname, COALESCE(st.coltype, ''),
              st.uncompressed_bytes,
              round(st.uncompressed_bytes::numeric / NULLIF(n.nrows, 0), 3),
              st.compressed_bytes,
              round(st.compressed_bytes::numeric / NULLIF(n.nrows, 0), 3),
              round(st.uncompressed_bytes::numeric / NULLIF(st.compressed_bytes, 0), 2),
              COALESCE(st.batches::text, ''),
              COALESCE(round(st.avg_meta_count::numeric, 1)::text, ''))
FROM probe_storage st JOIN probe_snapshot n USING (run_id, tbl)
WHERE st.run_id = :'run_id'
ORDER BY st.tbl, (st.colname LIKE '(%'), st.colname;

SELECT '';
SELECT '## Query texts';
SELECT '';
SELECT format('- **%s** on `%s`: `%s`', query_id, tbl, query_text)
FROM probe_query_median WHERE run_id = :'run_id' ORDER BY query_id, tbl;
