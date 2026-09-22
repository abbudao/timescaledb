-- Twin hypertables for the DATE probe: metrics_date keyed by DATE,
-- metrics_tstz keyed by TIMESTAMPTZ, identical in every other respect.
--
-- Variables (all set by run.sh):
--   run_id variant scale git_sha days devices rpd
--   chunk_interval  text, e.g. '7 days'
--   with_index      true|false   -> create_default_indexes
--   reorder         true|false   -> padding-free column order
--   has_orderby     true|false
--   orderby_date    compress_orderby for metrics_date, e.g. 'day DESC, seq DESC'
--   orderby_tstz    same with the time column renamed to ts
--   start_date end_date
\set ON_ERROR_STOP on

DROP MATERIALIZED VIEW IF EXISTS cagg_date CASCADE;
DROP MATERIALIZED VIEW IF EXISTS cagg_tstz CASCADE;
DROP TABLE IF EXISTS metrics_date CASCADE;
DROP TABLE IF EXISTS metrics_tstz CASCADE;

\if :reorder
-- variant "reorder": 4-byte columns grouped so nothing pads to 8-byte alignment
CREATE TABLE metrics_date (
    day        date   NOT NULL,
    device_id  int    NOT NULL,
    region_id  int    NOT NULL,
    v3         int,
    seq        bigint NOT NULL,
    v1         float8,
    v2         float8,
    status     text
);
\else
CREATE TABLE metrics_date (
    day        date   NOT NULL,
    device_id  int    NOT NULL,
    region_id  int    NOT NULL,
    seq        bigint NOT NULL,   -- ingest order, used only by the tiebreaker variant
    v1         float8,            -- smooth per-device series: ordering matters
    v2         float8,            -- random
    v3         int,
    status     text               -- three distinct values
);
\endif

CREATE TABLE metrics_tstz (LIKE metrics_date INCLUDING ALL);
ALTER TABLE metrics_tstz DROP COLUMN day, ADD COLUMN ts timestamptz NOT NULL;

SELECT create_hypertable('metrics_date', by_range('day', interval :'chunk_interval'),
                         create_default_indexes => :with_index);
SELECT create_hypertable('metrics_tstz', by_range('ts', interval :'chunk_interval'),
                         create_default_indexes => :with_index);

\if :has_orderby
ALTER TABLE metrics_date SET (timescaledb.compress,
                              timescaledb.compress_segmentby = 'device_id',
                              timescaledb.compress_orderby = :'orderby_date');
ALTER TABLE metrics_tstz SET (timescaledb.compress,
                              timescaledb.compress_segmentby = 'device_id',
                              timescaledb.compress_orderby = :'orderby_tstz');
\else
-- no compress_orderby: the default heuristic is what gets measured
ALTER TABLE metrics_date SET (timescaledb.compress,
                              timescaledb.compress_segmentby = 'device_id');
ALTER TABLE metrics_tstz SET (timescaledb.compress,
                              timescaledb.compress_segmentby = 'device_id');
\endif

INSERT INTO probe_run (run_id, variant, scale, git_sha, days, devices, rows_per_device_day,
                       chunk_interval, with_index, orderby_date, orderby_tstz, column_order,
                       start_date, end_date, extversion, pg_version)
VALUES (:'run_id', :'variant', :'scale', :'git_sha', :days, :devices, :rpd,
        :'chunk_interval', :with_index,
        NULLIF(:'orderby_date', ''), NULLIF(:'orderby_tstz', ''),
        CASE WHEN :reorder THEN 'reorder' ELSE 'default' END,
        :'start_date', :'end_date',
        (SELECT extversion FROM pg_extension WHERE extname = 'timescaledb'),
        current_setting('server_version'));

-- What the planner will see for the two tables.
SELECT hypertable_name, column_name, column_type, time_interval
FROM timescaledb_information.dimensions
ORDER BY hypertable_name;

SELECT hypertable_name, segmentby_column_name, orderby_column_name,
       orderby_asc, orderby_nullsfirst
FROM timescaledb_information.compression_settings
ORDER BY hypertable_name, orderby_column_index NULLS FIRST;
