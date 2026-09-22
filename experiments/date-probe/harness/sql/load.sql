-- Load both twins, one day per transaction. See probe_load() in setup.sql.
--
-- Variables: run_id days devices rpd start_date
\set ON_ERROR_STOP on

CALL probe_load(:'run_id', :days, :devices, :rpd, :'start_date');

SELECT tbl,
       nrows,
       round(seconds::numeric, 2)              AS seconds,
       round((nrows / seconds)::numeric, 0)    AS rows_per_sec
FROM probe_timing
WHERE run_id = :'run_id' AND phase = 'load'
ORDER BY tbl;
