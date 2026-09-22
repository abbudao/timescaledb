-- Q6: daily continuous aggregate over v1, refreshed across the whole range.
-- Only the refresh wall time is recorded.
--
-- Variables: run_id tbl col cagg
\set ON_ERROR_STOP on

DROP MATERIALIZED VIEW IF EXISTS :cagg;

CREATE MATERIALIZED VIEW :cagg WITH (timescaledb.continuous) AS
SELECT time_bucket(interval '1 day', :col) AS bucket,
       device_id,
       avg(v1) AS avg_v1,
       count(*) AS n
FROM :tbl
GROUP BY 1, 2
WITH NO DATA;

SELECT set_config('probe.t0', clock_timestamp()::text, false);

CALL refresh_continuous_aggregate(:'cagg', NULL, NULL);

INSERT INTO probe_timing (run_id, tbl, phase, seconds, nrows)
SELECT :'run_id', :'tbl', 'cagg_refresh',
       extract(epoch FROM clock_timestamp() - current_setting('probe.t0')::timestamptz),
       (SELECT count(*) FROM :cagg)
ON CONFLICT (run_id, tbl, phase) DO UPDATE
   SET seconds = excluded.seconds, nrows = excluded.nrows;

SELECT tbl, round(seconds::numeric, 2) AS cagg_refresh_seconds, nrows AS buckets
FROM probe_timing WHERE run_id = :'run_id' AND tbl = :'tbl' AND phase = 'cagg_refresh';
