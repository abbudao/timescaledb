-- Q1..Q5 against one table, three runs each, plans stored in probe_plans.
--
-- The query text is built with format() and executed through probe_explain(),
-- so the same file serves both twins and every variant: only the psql
-- variables change.
--
-- Variables:
--   run_id variant
--   tbl      metrics_date | metrics_tstz
--   col      day | ts
--   q2bound  same-type stable bound, e.g. current_date - 30
--   d1 d2    31-day literal window in the middle of the data
--   dpoint   single day in the middle of the data
--
-- To add a query: give it an id, build its text with format() the same way,
-- and add it to the list in harness/README.md.
\set ON_ERROR_STOP on

-- Q1: cross-type shape. now() is TIMESTAMPTZ; on a DATE dimension this is
-- exactly the comparison that gets neither plan-time nor runtime exclusion.
SELECT probe_explain(:'run_id', :'variant', :'tbl', 'Q1', r, format(
    'SELECT count(*) AS n, avg(v1) AS avg_v1 FROM %I WHERE %I >= now() - interval ''30 days''',
    :'tbl', :'col'))
FROM generate_series(1, 3) AS r;

-- Q2: same-type stable bound, runtime (startup) exclusion only.
SELECT probe_explain(:'run_id', :'variant', :'tbl', 'Q2', r, format(
    'SELECT count(*) AS n, avg(v1) AS avg_v1 FROM %I WHERE %I >= %s',
    :'tbl', :'col', :'q2bound'))
FROM generate_series(1, 3) AS r;

-- Q3: immutable literals, plan-time exclusion baseline.
SELECT probe_explain(:'run_id', :'variant', :'tbl', 'Q3', r, format(
    'SELECT count(*) AS n, avg(v1) AS avg_v1 FROM %I WHERE %I >= %L AND %I < %L',
    :'tbl', :'col', :'d1', :'col', :'d2'))
FROM generate_series(1, 3) AS r;

-- Q4: bucketing plus vectorized aggregation over the Q3 window.
SELECT probe_explain(:'run_id', :'variant', :'tbl', 'Q4', r, format(
    'SELECT time_bucket(interval ''7 days'', %I) AS bucket, device_id, avg(v1) AS avg_v1, max(v2) AS max_v2 '
    'FROM %I WHERE %I >= %L AND %I < %L GROUP BY 1, 2',
    :'col', :'tbl', :'col', :'d1', :'col', :'d2'))
FROM generate_series(1, 3) AS r;

-- Q5: point lookup, equality on the time column, segmentby hit.
SELECT probe_explain(:'run_id', :'variant', :'tbl', 'Q5', r, format(
    'SELECT * FROM %I WHERE device_id = 17 AND %I = %L',
    :'tbl', :'col', :'dpoint'))
FROM generate_series(1, 3) AS r;

SELECT query_id,
       round(exec_ms_median::numeric, 2)  AS exec_ms,
       round(planning_ms_median::numeric, 2) AS plan_ms,
       chunks_in_plan,
       chunks_excluded_startup,
       vectorized_filter,
       scan_rows
FROM probe_query_median
WHERE run_id = :'run_id' AND tbl = :'tbl'
ORDER BY query_id;
