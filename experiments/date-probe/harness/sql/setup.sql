-- Bookkeeping tables and helper routines for the DATE probe harness.
--
-- Everything the harness measures is stored in the benchmark database
-- itself, so metrics are extracted with SQL (jsonb path queries over the
-- stored plans) instead of by parsing text output.
--
-- Variables: none. Run once per database, before schema.sql.
\set ON_ERROR_STOP on

CREATE EXTENSION IF NOT EXISTS timescaledb;

-- One row per harness invocation.
CREATE TABLE IF NOT EXISTS probe_run (
    run_id              text PRIMARY KEY,
    variant             text NOT NULL,
    scale               text NOT NULL,
    git_sha             text NOT NULL,
    days                int  NOT NULL,
    devices             int  NOT NULL,
    rows_per_device_day int  NOT NULL,
    chunk_interval      text NOT NULL,
    with_index          boolean NOT NULL,
    orderby_date        text,
    orderby_tstz        text,
    column_order        text NOT NULL,
    start_date          date NOT NULL,
    end_date            date NOT NULL,
    extversion          text,
    pg_version          text,
    started_at          timestamptz NOT NULL DEFAULT now()
);

-- Wall times: load per table, compress per table, cagg refresh per table.
CREATE TABLE IF NOT EXISTS probe_timing (
    run_id  text NOT NULL,
    tbl     text NOT NULL,
    phase   text NOT NULL,
    seconds float8 NOT NULL,
    nrows   bigint,
    PRIMARY KEY (run_id, tbl, phase)
);

-- Raw EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON) output, one row per execution.
CREATE TABLE IF NOT EXISTS probe_plans (
    run_id     text NOT NULL,
    variant    text NOT NULL,
    tbl        text NOT NULL,
    query_id   text NOT NULL,
    run        int  NOT NULL,
    query_text text NOT NULL,
    plan       jsonb NOT NULL,
    PRIMARY KEY (run_id, tbl, query_id, run)
);

-- Physical size of each table before compression.
CREATE TABLE IF NOT EXISTS probe_snapshot (
    run_id      text NOT NULL,
    tbl         text NOT NULL,
    nrows       bigint NOT NULL,
    heap_bytes  bigint NOT NULL,
    index_bytes bigint NOT NULL,
    toast_bytes bigint NOT NULL,
    total_bytes bigint NOT NULL,
    PRIMARY KEY (run_id, tbl)
);

-- Physical size of each table after compression, from chunk_compression_stats.
CREATE TABLE IF NOT EXISTS probe_compstats (
    run_id            text NOT NULL,
    tbl               text NOT NULL,
    chunks            bigint,
    before_heap       bigint,
    before_index      bigint,
    before_toast      bigint,
    before_total      bigint,
    after_heap        bigint,
    after_index       bigint,
    after_toast       bigint,
    after_total       bigint,
    numrows_pre       bigint,
    numrows_post      bigint,
    PRIMARY KEY (run_id, tbl)
);

-- Per-column bytes. Rows whose colname is parenthesized -- (heap), (index),
-- (toast), (total) -- are physical table-level numbers from the size
-- functions; all other rows are logical datum bytes, summed with
-- pg_column_size() over the uncompressed table before compression and over
-- the compressed chunks after it.
CREATE TABLE IF NOT EXISTS probe_storage (
    run_id             text NOT NULL,
    tbl                text NOT NULL,
    colname            text NOT NULL,
    coltype            text,
    uncompressed_bytes bigint,
    compressed_bytes   bigint,
    batches            bigint,
    avg_meta_count     float8,
    PRIMARY KEY (run_id, tbl, colname)
);

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

-- Run one query under EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON) and store the
-- plan. Dynamic SQL, so every execution is planned from scratch.
CREATE OR REPLACE FUNCTION probe_explain(p_run_id text, p_variant text, p_tbl text,
                                         p_qid text, p_run int, p_sql text)
RETURNS void LANGUAGE plpgsql AS $fn$
DECLARE
    j json;
BEGIN
    EXECUTE 'EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON) ' || p_sql INTO j;
    INSERT INTO probe_plans(run_id, variant, tbl, query_id, run, query_text, plan)
    VALUES (p_run_id, p_variant, p_tbl, p_qid, p_run, p_sql, j::jsonb);
END
$fn$;

-- Load both twins with identical rows, one day per transaction so memory
-- stays flat. A per-day staging table holds the generated rows, which are
-- then inserted into each twin separately: the two tables receive exactly the
-- same values and their insert throughput is measured on the same workload.
CREATE OR REPLACE PROCEDURE probe_load(p_run_id text, p_days int, p_devices int,
                                       p_rpd int, p_start date)
LANGUAGE plpgsql AS $pr$
DECLARE
    i        int;
    t0       timestamptz;
    date_s   float8 := 0;
    tstz_s   float8 := 0;
    base     bigint;
    n        bigint := p_days::bigint * p_devices * p_rpd;
BEGIN
    CREATE TEMP TABLE IF NOT EXISTS probe_stage (
        day       date   NOT NULL,
        device_id int    NOT NULL,
        region_id int    NOT NULL,
        seq       bigint NOT NULL,
        v1        float8,
        v2        float8,
        v3        int,
        status    text
    ) ON COMMIT PRESERVE ROWS;

    FOR i IN 0 .. p_days - 1 LOOP
        base := i::bigint * p_devices * p_rpd;
        TRUNCATE probe_stage;
        INSERT INTO probe_stage (day, device_id, region_id, seq, v1, v2, v3, status)
        SELECT p_start + i,
               dev,
               dev % 10,
               base + dev::bigint * p_rpd + r,
               -- smooth per-device series: one slow sine over ~30 days plus a
               -- ramp inside the day, so row order within a batch matters
               round((sin((i + r::float8 / p_rpd) / 30.0) * 100 + dev
                      + random() * 0.1)::numeric, 3)::float8,
               round((random() * 1000)::numeric, 3)::float8,
               (random() * 100)::int,
               (ARRAY['ok', 'warn', 'error'])[1 + floor(random() * 3)::int]
        FROM generate_series(0, p_devices - 1) AS dev,
             generate_series(0, p_rpd - 1) AS r;

        t0 := clock_timestamp();
        INSERT INTO metrics_date (day, device_id, region_id, seq, v1, v2, v3, status)
        SELECT day, device_id, region_id, seq, v1, v2, v3, status
        FROM probe_stage ORDER BY seq;
        date_s := date_s + extract(epoch FROM clock_timestamp() - t0);

        t0 := clock_timestamp();
        INSERT INTO metrics_tstz (ts, device_id, region_id, seq, v1, v2, v3, status)
        SELECT day::timestamptz, device_id, region_id, seq, v1, v2, v3, status
        FROM probe_stage ORDER BY seq;
        tstz_s := tstz_s + extract(epoch FROM clock_timestamp() - t0);

        COMMIT;
    END LOOP;

    INSERT INTO probe_timing(run_id, tbl, phase, seconds, nrows)
    VALUES (p_run_id, 'metrics_date', 'load', date_s, n),
           (p_run_id, 'metrics_tstz', 'load', tstz_s, n)
    ON CONFLICT (run_id, tbl, phase) DO UPDATE
       SET seconds = excluded.seconds, nrows = excluded.nrows;
END
$pr$;

-- Logical bytes per column of the uncompressed table, before compression.
CREATE OR REPLACE PROCEDURE probe_collect_uncompressed(p_run_id text, p_tbl text)
LANGUAGE plpgsql AS $pr$
DECLARE
    c    record;
    v    bigint;
BEGIN
    FOR c IN
        SELECT a.attname::text AS colname, format_type(a.atttypid, a.atttypmod) AS coltype
        FROM pg_attribute a
        WHERE a.attrelid = p_tbl::regclass AND a.attnum > 0 AND NOT a.attisdropped
        ORDER BY a.attnum
    LOOP
        EXECUTE format('SELECT COALESCE(sum(pg_column_size(%I))::bigint, 0) FROM %s',
                       c.colname, p_tbl)
        INTO v;
        INSERT INTO probe_storage(run_id, tbl, colname, coltype, uncompressed_bytes)
        VALUES (p_run_id, p_tbl, c.colname, c.coltype, v)
        ON CONFLICT (run_id, tbl, colname) DO UPDATE
           SET uncompressed_bytes = excluded.uncompressed_bytes,
               coltype = excluded.coltype;
    END LOOP;
END
$pr$;

-- Bytes per column in the compressed chunks, plus batch count and average
-- batch fill. The compressed chunk of a chunk is found through
-- _timescaledb_catalog.compression_chunk_size (2.31 no longer keeps
-- compressed_chunk_id on _timescaledb_catalog.chunk).
CREATE OR REPLACE PROCEDURE probe_collect_compressed(p_run_id text, p_tbl text)
LANGUAGE plpgsql AS $pr$
DECLARE
    cc       record;
    c        record;
    v        bigint;
    nbatch   bigint;
    metasum  float8;
    totals     jsonb := '{}'::jsonb;
    v_batches  bigint := 0;
    v_meta_acc float8 := 0;
BEGIN
    FOR cc IN
        SELECT comp.relid AS comp_relid
        FROM _timescaledb_catalog.chunk ch
        JOIN _timescaledb_catalog.hypertable h ON h.id = ch.hypertable_id
        JOIN _timescaledb_catalog.compression_chunk_size ccs ON ccs.chunk_id = ch.id
        JOIN _timescaledb_catalog.chunk comp ON comp.id = ccs.compressed_chunk_id
        WHERE format('%I.%I', h.schema_name, h.table_name)::regclass = p_tbl::regclass
    LOOP
        EXECUTE format('SELECT count(*)::bigint, COALESCE(sum(_ts_meta_count), 0)::float8 FROM %s',
                       cc.comp_relid)
        INTO nbatch, metasum;
        v_batches := v_batches + nbatch;
        v_meta_acc := v_meta_acc + metasum;

        FOR c IN
            SELECT a.attname::text AS colname
            FROM pg_attribute a
            WHERE a.attrelid = p_tbl::regclass AND a.attnum > 0 AND NOT a.attisdropped
        LOOP
            EXECUTE format('SELECT COALESCE(sum(pg_column_size(%I))::bigint, 0) FROM %s',
                           c.colname, cc.comp_relid)
            INTO v;
            totals := jsonb_set(totals, ARRAY[c.colname],
                                to_jsonb(COALESCE((totals ->> c.colname)::bigint, 0) + v));
        END LOOP;
    END LOOP;

    FOR c IN SELECT key, value::text::bigint AS bytes FROM jsonb_each(totals) LOOP
        INSERT INTO probe_storage(run_id, tbl, colname, compressed_bytes)
        VALUES (p_run_id, p_tbl, c.key, c.bytes)
        ON CONFLICT (run_id, tbl, colname) DO UPDATE
           SET compressed_bytes = excluded.compressed_bytes;
    END LOOP;

    UPDATE probe_storage
       SET batches = v_batches,
           avg_meta_count = CASE WHEN v_batches > 0 THEN v_meta_acc / v_batches END
     WHERE run_id = p_run_id AND tbl = p_tbl;
END
$pr$;

-- ---------------------------------------------------------------------------
-- Metric extraction: one row per stored plan.
-- ---------------------------------------------------------------------------
-- chunks_in_plan counts DISTINCT chunk relations of the hypertable in the
-- plan. With compression each scanned chunk contributes two scan nodes (the
-- chunk and its compressed twin), so the raw node count of the brief is kept
-- separately as chunk_scan_nodes.
CREATE OR REPLACE VIEW probe_query_metrics AS
SELECT p.run_id,
       p.variant,
       p.tbl,
       p.query_id,
       p.run,
       (p.plan -> 0 ->> 'Planning Time')::float8                       AS planning_ms,
       (p.plan -> 0 ->> 'Execution Time')::float8                      AS exec_ms,
       (p.plan -> 0 -> 'Plan' ->> 'Shared Hit Blocks')::bigint         AS shared_hit,
       (p.plan -> 0 -> 'Plan' ->> 'Shared Read Blocks')::bigint        AS shared_read,
       (p.plan -> 0 -> 'Plan' ->> 'Actual Rows')::float8               AS rows,
       (SELECT count(DISTINCT rn #>> '{}')
          FROM jsonb_path_query(p.plan, '$.**."Relation Name"') rn
         WHERE rn #>> '{}' ~ '^_hyper_[0-9]+_[0-9]+_chunk')            AS chunks_in_plan,
       (SELECT count(DISTINCT rn #>> '{}')
          FROM jsonb_path_query(p.plan, '$.**."Relation Name"') rn
         WHERE rn #>> '{}' ~ '^compress_hyper_')                       AS compressed_chunks_in_plan,
       (SELECT count(*)
          FROM jsonb_path_query(p.plan, '$.**."Relation Name"') rn
         WHERE rn #>> '{}' ~ '^(_hyper_|compress_hyper_)')             AS chunk_scan_nodes,
       COALESCE((SELECT sum((v #>> '{}')::bigint)
                   FROM jsonb_path_query(p.plan,
                        '$.**."Chunks excluded during startup"') v), 0) AS chunks_excluded_startup,
       EXISTS (SELECT 1 FROM jsonb_path_query(p.plan, '$.**."Vectorized Filter"') v)
                                                                       AS vectorized_filter,
       COALESCE((SELECT sum((n ->> 'Actual Rows')::float8)
                   FROM jsonb_path_query(p.plan,
                        '$.**?(@."Relation Name" like_regex "^_hyper_[0-9]+_[0-9]+_chunk")') n),
                0)                                                     AS scan_rows,
       p.query_text
FROM probe_plans p;

-- Median of the three runs, the number the scorecard quotes.
CREATE OR REPLACE VIEW probe_query_median AS
SELECT run_id, variant, tbl, query_id,
       percentile_cont(0.5) WITHIN GROUP (ORDER BY exec_ms)      AS exec_ms_median,
       percentile_cont(0.5) WITHIN GROUP (ORDER BY planning_ms)  AS planning_ms_median,
       min(exec_ms)                                              AS exec_ms_min,
       max(exec_ms)                                              AS exec_ms_max,
       max(chunks_in_plan)                                       AS chunks_in_plan,
       max(compressed_chunks_in_plan)                            AS compressed_chunks_in_plan,
       max(chunk_scan_nodes)                                     AS chunk_scan_nodes,
       max(chunks_excluded_startup)                              AS chunks_excluded_startup,
       bool_or(vectorized_filter)                                AS vectorized_filter,
       max(rows)                                                 AS rows,
       max(scan_rows)                                            AS scan_rows,
       percentile_cont(0.5) WITHIN GROUP (ORDER BY shared_hit)   AS shared_hit_median,
       percentile_cont(0.5) WITHIN GROUP (ORDER BY shared_read)  AS shared_read_median,
       min(query_text)                                           AS query_text
FROM probe_query_metrics
GROUP BY run_id, variant, tbl, query_id;
