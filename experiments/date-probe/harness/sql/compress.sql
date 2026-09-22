-- Compress every chunk of both twins and record the wall time.
--
-- Variables: run_id
\set ON_ERROR_STOP on

SELECT set_config('probe.t0', clock_timestamp()::text, false);
SELECT count(*) AS compressed_chunks
FROM (SELECT compress_chunk(c) FROM show_chunks('metrics_date') c) s;
INSERT INTO probe_timing (run_id, tbl, phase, seconds, nrows)
SELECT :'run_id', 'metrics_date', 'compress',
       extract(epoch FROM clock_timestamp() - current_setting('probe.t0')::timestamptz),
       (SELECT count(*) FROM metrics_date)
ON CONFLICT (run_id, tbl, phase) DO UPDATE
   SET seconds = excluded.seconds, nrows = excluded.nrows;

SELECT set_config('probe.t0', clock_timestamp()::text, false);
SELECT count(*) AS compressed_chunks
FROM (SELECT compress_chunk(c) FROM show_chunks('metrics_tstz') c) s;
INSERT INTO probe_timing (run_id, tbl, phase, seconds, nrows)
SELECT :'run_id', 'metrics_tstz', 'compress',
       extract(epoch FROM clock_timestamp() - current_setting('probe.t0')::timestamptz),
       (SELECT count(*) FROM metrics_tstz)
ON CONFLICT (run_id, tbl, phase) DO UPDATE
   SET seconds = excluded.seconds, nrows = excluded.nrows;

VACUUM (ANALYZE) metrics_date;
VACUUM (ANALYZE) metrics_tstz;

INSERT INTO probe_compstats (run_id, tbl, chunks, before_heap, before_index, before_toast,
                             before_total, after_heap, after_index, after_toast, after_total,
                             numrows_pre, numrows_post)
SELECT :'run_id', t.tbl, s.chunks, s.bh, s.bi, s.bt, s.btot, s.ah, s.ai, s.at, s.atot,
       s.pre, s.post
FROM (VALUES ('metrics_date'), ('metrics_tstz')) AS t(tbl),
LATERAL (
    SELECT count(*)                                       AS chunks,
           COALESCE(sum(before_compression_table_bytes), 0) AS bh,
           COALESCE(sum(before_compression_index_bytes), 0) AS bi,
           COALESCE(sum(before_compression_toast_bytes), 0) AS bt,
           COALESCE(sum(before_compression_total_bytes), 0) AS btot,
           COALESCE(sum(after_compression_table_bytes), 0)  AS ah,
           COALESCE(sum(after_compression_index_bytes), 0)  AS ai,
           COALESCE(sum(after_compression_toast_bytes), 0)  AS at,
           COALESCE(sum(after_compression_total_bytes), 0)  AS atot,
           (SELECT COALESCE(sum(ccs.numrows_pre_compression), 0)
              FROM _timescaledb_catalog.compression_chunk_size ccs
              JOIN _timescaledb_catalog.chunk ch ON ch.id = ccs.chunk_id
              JOIN _timescaledb_catalog.hypertable h ON h.id = ch.hypertable_id
             WHERE h.table_name = t.tbl)                    AS pre,
           (SELECT COALESCE(sum(ccs.numrows_post_compression), 0)
              FROM _timescaledb_catalog.compression_chunk_size ccs
              JOIN _timescaledb_catalog.chunk ch ON ch.id = ccs.chunk_id
              JOIN _timescaledb_catalog.hypertable h ON h.id = ch.hypertable_id
             WHERE h.table_name = t.tbl)                    AS post
    FROM chunk_compression_stats(t.tbl::regclass)
) s
ON CONFLICT (run_id, tbl) DO UPDATE
   SET chunks = excluded.chunks, before_heap = excluded.before_heap,
       before_index = excluded.before_index, before_toast = excluded.before_toast,
       before_total = excluded.before_total, after_heap = excluded.after_heap,
       after_index = excluded.after_index, after_toast = excluded.after_toast,
       after_total = excluded.after_total, numrows_pre = excluded.numrows_pre,
       numrows_post = excluded.numrows_post;

-- The orderby the default heuristic settled on, which is what T4 is about.
SELECT hypertable_name, attname, segmentby_column_index, orderby_column_index,
       orderby_asc, orderby_nullsfirst
FROM timescaledb_information.compression_settings
WHERE hypertable_name IN ('metrics_date', 'metrics_tstz')
ORDER BY hypertable_name, segmentby_column_index NULLS LAST, orderby_column_index;

SELECT tbl, chunks,
       pg_size_pretty(before_total) AS before_total,
       pg_size_pretty(after_total)  AS after_total,
       round(before_total::numeric / NULLIF(after_total, 0), 2) AS ratio,
       (SELECT round(seconds::numeric, 2) FROM probe_timing p
         WHERE p.run_id = c.run_id AND p.tbl = c.tbl AND p.phase = 'compress') AS compress_seconds
FROM probe_compstats c
WHERE run_id = :'run_id'
ORDER BY tbl;
