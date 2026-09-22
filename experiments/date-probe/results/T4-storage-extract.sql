\set ON_ERROR_STOP on
\pset pager off
CREATE TEMP TABLE colbytes(colname text, bytes bigint);
CREATE TEMP TABLE batchinfo(nbatch bigint, metasum float8);
DO $$
DECLARE cc record; c record; v bigint; nb bigint; ms float8;
BEGIN
  FOR cc IN
    SELECT cl.oid AS rel
    FROM _timescaledb_catalog.chunk ch
    JOIN _timescaledb_catalog.hypertable h ON h.id = ch.hypertable_id
    JOIN pg_class ocl ON ocl.oid = ch.relid
    JOIN pg_class cl ON cl.relname = ocl.relname || '_compressed'
                    AND cl.relnamespace = ocl.relnamespace
    WHERE h.schema_name = 'public' AND h.table_name = 'metrics_date'
  LOOP
    EXECUTE format('SELECT count(*)::bigint, COALESCE(sum(_ts_meta_count),0)::float8 FROM %s', cc.rel::regclass) INTO nb, ms;
    INSERT INTO batchinfo VALUES (nb, ms);
    FOR c IN SELECT a.attname::text AS colname FROM pg_attribute a
             WHERE a.attrelid = cc.rel AND a.attnum > 0 AND NOT a.attisdropped
    LOOP
      EXECUTE format('SELECT COALESCE(sum(pg_column_size(%I))::bigint,0) FROM %s', c.colname, cc.rel::regclass) INTO v;
      INSERT INTO colbytes VALUES (c.colname, v);
    END LOOP;
  END LOOP;
END $$;
\echo '=== per column compressed bytes (metrics_date) ==='
SELECT colname, sum(bytes) AS bytes FROM colbytes GROUP BY 1 ORDER BY (colname LIKE '\_ts\_meta%'), colname;
\echo '=== totals ==='
SELECT sum(bytes) FILTER (WHERE colname NOT LIKE '\_ts\_meta%') AS value_col_bytes,
       sum(bytes) FILTER (WHERE colname LIKE '\_ts\_meta%')     AS meta_col_bytes,
       sum(bytes)                                               AS all_col_bytes
FROM colbytes;
\echo '=== batches ==='
SELECT sum(nbatch) AS batches, round((sum(metasum)/NULLIF(sum(nbatch),0))::numeric,1) AS avg_batch_rows FROM batchinfo;
\echo '=== physical bytes ==='
SELECT colname, uncompressed_bytes, compressed_bytes FROM probe_storage
 WHERE tbl='metrics_date' AND colname LIKE '(%' ORDER BY colname;
SELECT pg_size_pretty(hypertable_size('metrics_date')) AS hypertable_size_now, hypertable_size('metrics_date') AS bytes_now;
\echo '=== timings ==='
SELECT phase, round(seconds::numeric,2) AS seconds FROM probe_timing WHERE tbl='metrics_date' ORDER BY phase;
\echo '=== orderby actually used ==='
SELECT DISTINCT segmentby, orderby FROM timescaledb_information.chunk_compression_settings WHERE hypertable='metrics_date'::regclass;
\echo '=== default orderby the installed function would return for metrics_date ==='
SELECT _timescaledb_functions.get_orderby_defaults('public.metrics_date', ARRAY['device_id']);
