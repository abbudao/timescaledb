-- This file and its contents are licensed under the Apache License 2.0.
-- Please see the included NOTICE for copyright information and
-- LICENSE-APACHE for a copy of the license.

-- Plan-time constification of clock-derived lower bounds on a DATE
-- dimension (src/planner/constify_now.c).
--
-- The added constant is derived from the UTC date of the plan-time clock and
-- never depends on the session timezone, so the set of chunks in the plan is
-- the same in every timezone while the rows returned still follow the
-- original, timezone-dependent expression. As for TIMESTAMPTZ dimensions the
-- constant is removed from the plan again after chunk exclusion, so EXPLAIN
-- shows the original expression only and the effect is visible as the number
-- of chunks left in the plan.
--
-- timescaledb.current_timestamp_mock drives now() (through ts_now_mock()) and
-- the plan-time constant, but not PostgreSQL's CURRENT_DATE and
-- CURRENT_TIMESTAMP. Row counts for those spellings therefore use data in
-- years 1000 and 3000 only, so they are independent of the wall clock.

\set PREFIX 'EXPLAIN (BUFFERS OFF, COSTS OFF, SUMMARY OFF, TIMING OFF)'
SET timescaledb.enable_chunk_append TO false;
SET timescaledb.enable_constraint_aware_append TO false;
SET timescaledb.current_timestamp_mock TO '2000-01-15 12:00:00+00';
SET timezone TO 'UTC';

-- Any query with a constified lower bound has 1 chunk in the plan, the
-- others have 2. No indexes, so every plan is a list of Seq Scans.
CREATE TABLE const_date(day date NOT NULL, day2 date, device_id int, value float);
SELECT table_name FROM create_hypertable('const_date', 'day', create_default_indexes => false);
INSERT INTO const_date VALUES ('1000-01-01', '1000-01-01', 1, 0.5);
INSERT INTO const_date VALUES ('1000-01-01', '1000-01-01', 2, 0.5);
INSERT INTO const_date VALUES ('3000-01-01', '3000-01-01', 1, 0.5);
INSERT INTO const_date VALUES ('3000-01-01', '3000-01-01', 2, 0.5);

-- Number of chunks a query has in its plan, for the timezone matrix below.
CREATE FUNCTION chunks_in_plan(query text) RETURNS int LANGUAGE plpgsql AS $$
DECLARE
  n int := 0;
  line text;
BEGIN
  FOR line IN EXECUTE 'EXPLAIN (BUFFERS OFF, COSTS OFF, SUMMARY OFF, TIMING OFF) ' || query LOOP
    IF line LIKE '%Scan on _hyper%' THEN
      n := n + 1;
    END IF;
  END LOOP;
  RETURN n;
END $$;

-- The shapes that are constified, all lower bounds.
-- CURRENT_DATE, with and without an integer offset
:PREFIX SELECT FROM const_date WHERE day > CURRENT_DATE;
:PREFIX SELECT FROM const_date WHERE day >= CURRENT_DATE;
:PREFIX SELECT FROM const_date WHERE day >= CURRENT_DATE - 30;
:PREFIX SELECT FROM const_date WHERE day > CURRENT_DATE + 30;
:PREFIX SELECT FROM const_date WHERE day >= current_date - 1;
-- now() and CURRENT_TIMESTAMP through the cross-type DATE/TIMESTAMPTZ operators
:PREFIX SELECT FROM const_date WHERE day > now();
:PREFIX SELECT FROM const_date WHERE day >= now();
:PREFIX SELECT FROM const_date WHERE day >= now() - interval '30 days';
:PREFIX SELECT FROM const_date WHERE day > now() + interval '10 minutes';
:PREFIX SELECT FROM const_date WHERE day >= now() - interval '1 month';
:PREFIX SELECT FROM const_date WHERE day > CURRENT_TIMESTAMP;
:PREFIX SELECT FROM const_date WHERE day >= CURRENT_TIMESTAMP - interval '30 days';
-- the same with the cast applied
:PREFIX SELECT FROM const_date WHERE day > now()::date;
:PREFIX SELECT FROM const_date WHERE day >= (now() - interval '30 days')::date;
:PREFIX SELECT FROM const_date WHERE day >= (CURRENT_TIMESTAMP - interval '1 week')::date;
-- multiple constraints
:PREFIX SELECT FROM const_date WHERE day >= CURRENT_DATE - 30 AND device_id = 2;
:PREFIX SELECT FROM const_date WHERE day >= now() - interval '30 days' AND day >= CURRENT_DATE - 30;

-- Shapes that are not constified: upper bounds, offsets that are not a
-- constant integer or interval, spellings with a precision, the operand
-- order PostgreSQL does not normalize, non-dimension columns, and OR.
:PREFIX SELECT FROM const_date WHERE day < CURRENT_DATE;
:PREFIX SELECT FROM const_date WHERE day <= now();
:PREFIX SELECT FROM const_date WHERE day < (now() - interval '30 days')::date;
:PREFIX SELECT FROM const_date WHERE day >= CURRENT_DATE - interval '1 day';
:PREFIX SELECT FROM const_date WHERE day >= CURRENT_TIMESTAMP(0);
:PREFIX SELECT FROM const_date WHERE day > 30 + CURRENT_DATE;
:PREFIX SELECT FROM const_date WHERE day >= LOCALTIMESTAMP;
:PREFIX SELECT FROM const_date WHERE day >= now()::timestamp;
:PREFIX SELECT FROM const_date WHERE day2 >= CURRENT_DATE;
:PREFIX SELECT FROM const_date WHERE day >= CURRENT_DATE OR device_id = 1;
:PREFIX SELECT FROM const_date WHERE device_id = 2 OR (day > now() AND day > CURRENT_DATE);

-- Views and subqueries: the dimension is found through the range table of
-- the subquery.
CREATE VIEW const_date_view AS SELECT day, device_id, avg(value) FROM const_date GROUP BY 1, 2;
:PREFIX SELECT * FROM const_date_view WHERE day >= CURRENT_DATE - 30;
:PREFIX SELECT * FROM (SELECT * FROM const_date) sub WHERE day >= now() - interval '30 days';
-- only WHERE clauses are constified, not JOIN conditions
:PREFIX SELECT FROM const_date m1 INNER JOIN const_date m2 ON (m1.day >= CURRENT_DATE);
:PREFIX SELECT FROM const_date m1 INNER JOIN const_date m2 ON (m1.day >= CURRENT_DATE) WHERE m2.day >= CURRENT_DATE;

-- UPDATE and DELETE
:PREFIX UPDATE const_date SET value = 1 WHERE day >= CURRENT_DATE - 30;
:PREFIX DELETE FROM const_date WHERE day > now() - interval '30 days';

-- The constant does not depend on the session timezone: the same number
-- of chunks stays in the plan in every timezone, for every shape.
CREATE FUNCTION const_date_matrix(tz text) RETURNS TABLE(timezone text, shape text, chunks int)
LANGUAGE plpgsql AS $$
DECLARE
  shapes text[] := ARRAY[
    'day > CURRENT_DATE',
    'day >= CURRENT_DATE - 30',
    'day > CURRENT_DATE + 30',
    'day >= now() - interval ''30 days''',
    'day > now()',
    'day >= CURRENT_TIMESTAMP - interval ''1 month''',
    'day >= (now() - interval ''30 days'')::date',
    'day > now()::date',
    'day <= now()',
    'day < CURRENT_DATE - 30'];
  s text;
BEGIN
  PERFORM set_config('timezone', tz, true);
  FOREACH s IN ARRAY shapes LOOP
    timezone := tz;
    shape := s;
    chunks := chunks_in_plan('SELECT FROM const_date WHERE ' || s);
    RETURN NEXT;
  END LOOP;
END $$;

SELECT * FROM const_date_matrix('UTC');
SELECT * FROM const_date_matrix('Asia/Tokyo');
SELECT * FROM const_date_matrix('America/Los_Angeles');
SELECT * FROM const_date_matrix('Pacific/Kiritimati');
SELECT * FROM const_date_matrix('Etc/GMT+12');
SET timezone TO 'UTC';

-- With the GUC off nothing is constified.
SET timescaledb.enable_now_constify TO off;
:PREFIX SELECT FROM const_date WHERE day >= CURRENT_DATE - 30;
:PREFIX SELECT FROM const_date WHERE day >= now() - interval '30 days';
RESET timescaledb.enable_now_constify;

-- Chunks actually get excluded. now() follows the mock clock at execution,
-- so these row counts are deterministic.
-- clock in the far future: all chunks are excluded at plan time
SET timescaledb.current_timestamp_mock TO '3010-01-01';
:PREFIX SELECT * FROM const_date WHERE day > now();
SELECT * FROM const_date WHERE day > now();
-- clock a day before the last row: only the last chunk stays
SET timescaledb.current_timestamp_mock TO '2999-12-31 12:00:00+00';
:PREFIX SELECT * FROM const_date WHERE day > now();
SELECT * FROM const_date WHERE day > now();
SET timescaledb.current_timestamp_mock TO '2000-01-15 12:00:00+00';

-- Where exactly the bound lands. One chunk per day, so the chunks left in
-- the plan show the constant: the UTC date of the clock value with the
-- interval applied (F) for the cross-type comparisons, F - 1 with the
-- operator kept for the DATE-typed spellings.
CREATE TABLE const_date_days(day date NOT NULL, v int);
SELECT table_name FROM create_hypertable('const_date_days', 'day', chunk_time_interval => interval '1 day', create_default_indexes => false);
INSERT INTO const_date_days SELECT d, 1 FROM generate_series('2000-01-10'::date, '2000-01-20'::date, interval '1 day') d;
SELECT count(*) FROM show_chunks('const_date_days');

-- clock 2000-01-15 20:00 UTC, which is already 2000-01-16 in Asia/Tokyo
SET timescaledb.current_timestamp_mock TO '2000-01-15 20:00:00+00';

-- day > now() - '2 days': T = 2000-01-13 20:00 UTC, F = 2000-01-13, the plan
-- keeps 2000-01-13 and later in every timezone
:PREFIX SELECT * FROM const_date_days WHERE day > now() - interval '2 days';
-- day >= now() - '2 days': the same chunks
:PREFIX SELECT * FROM const_date_days WHERE day >= now() - interval '2 days';
-- day >= (now() - '2 days')::date: F - 1 = 2000-01-12 with >= kept
:PREFIX SELECT * FROM const_date_days WHERE day >= (now() - interval '2 days')::date;
-- day > (now() - '2 days')::date: F - 1 with > kept, so from 2000-01-13
:PREFIX SELECT * FROM const_date_days WHERE day > (now() - interval '2 days')::date;
-- day intervals get the 4 hour DST safety buffer: the clock at 02:00 UTC
-- minus 4 hours is on the previous day
SET timescaledb.current_timestamp_mock TO '2000-01-15 02:00:00+00';
:PREFIX SELECT * FROM const_date_days WHERE day >= now() - interval '2 days';
:PREFIX SELECT * FROM const_date_days WHERE day >= now() - interval '48 hours';
SET timescaledb.current_timestamp_mock TO '2000-01-15 20:00:00+00';

-- The plan is the same in every timezone while the rows follow the
-- timezone-dependent original expression. With the clock at 20:00 UTC the
-- exact bound for day >= now() - '2 days' is 2000-01-14 in UTC and
-- America/Los_Angeles, but 2000-01-15 in Asia/Tokyo, where T is already
-- 2000-01-14 05:00 local. The reference count is PostgreSQL's own evaluation
-- of the same predicate with the mock clock spelled out as ts_now_mock(),
-- which is neither constified nor excluded. (With the GUC off now() is not
-- redirected to the mock clock, so that comparison is made below on data
-- whose counts do not depend on the clock.)
CREATE FUNCTION const_date_days_check(tz text, q text)
RETURNS TABLE(timezone text, chunks int, rows_constified int, rows_reference int) LANGUAGE plpgsql AS $$
BEGIN
  PERFORM set_config('timezone', tz, true);
  timezone := tz;
  chunks := chunks_in_plan(q);
  EXECUTE q INTO rows_constified;
  EXECUTE replace(q, 'now()', 'ts_now_mock()') INTO rows_reference;
  RETURN NEXT;
END $$;

SELECT * FROM const_date_days_check('UTC', 'SELECT count(*) FROM const_date_days WHERE day >= now() - interval ''2 days''');
SELECT * FROM const_date_days_check('Asia/Tokyo', 'SELECT count(*) FROM const_date_days WHERE day >= now() - interval ''2 days''');
SELECT * FROM const_date_days_check('America/Los_Angeles', 'SELECT count(*) FROM const_date_days WHERE day >= now() - interval ''2 days''');
SELECT * FROM const_date_days_check('UTC', 'SELECT count(*) FROM const_date_days WHERE day > now() - interval ''2 days''');
SELECT * FROM const_date_days_check('Asia/Tokyo', 'SELECT count(*) FROM const_date_days WHERE day > now() - interval ''2 days''');
SELECT * FROM const_date_days_check('America/Los_Angeles', 'SELECT count(*) FROM const_date_days WHERE day > now() - interval ''2 days''');
-- at a local midnight: 2000-01-13 20:00 UTC is 2000-01-14 00:00 in Etc/GMT-4,
-- so day >= T keeps that day while day > T does not
SELECT * FROM const_date_days_check('Etc/GMT-4', 'SELECT count(*) FROM const_date_days WHERE day >= now() - interval ''2 days''');
SELECT * FROM const_date_days_check('Etc/GMT-4', 'SELECT count(*) FROM const_date_days WHERE day > now() - interval ''2 days''');
SET timezone TO 'UTC';

-- With ChunkAppend the chunks the constant could not exclude are still
-- excluded at startup by the original expression.
SET timescaledb.enable_chunk_append TO true;
SET timescaledb.enable_constraint_aware_append TO true;
EXPLAIN (ANALYZE, BUFFERS OFF, COSTS OFF, SUMMARY OFF, TIMING OFF) SELECT * FROM const_date_days WHERE day >= now() - interval '2 days';
SET timezone TO 'Asia/Tokyo';
EXPLAIN (ANALYZE, BUFFERS OFF, COSTS OFF, SUMMARY OFF, TIMING OFF) SELECT * FROM const_date_days WHERE day >= now() - interval '2 days';
SET timezone TO 'UTC';
SET timescaledb.enable_chunk_append TO false;
SET timescaledb.enable_constraint_aware_append TO false;

-- Prepared statements. The constant is baked into the generic plan, so the
-- chunks excluded when it was built stay excluded; that is safe because the
-- clock only moves forward and the bound holds in every timezone. Each
-- prepared statement is executed six times to reach the generic plan, then
-- the clock is advanced by 40 days and the timezone is changed. The counts
-- must match the same statement prepared with the GUC off, which is planned
-- at its first EXECUTE. Data in years 1000 and 3000, so the counts do not
-- depend on the clock.
SET timescaledb.current_timestamp_mock TO '2000-01-15 12:00:00+00';
PREPARE p AS SELECT count(*) FROM const_date WHERE day >= CURRENT_DATE - 30;
SET timescaledb.enable_now_constify TO off;
PREPARE p_off AS SELECT count(*) FROM const_date WHERE day >= CURRENT_DATE - 30;
EXECUTE p_off;
:PREFIX EXECUTE p_off;
RESET timescaledb.enable_now_constify;
EXECUTE p; EXECUTE p; EXECUTE p; EXECUTE p; EXECUTE p;
:PREFIX EXECUTE p;
EXECUTE p;
EXECUTE p_off;
SET timescaledb.current_timestamp_mock TO '2000-02-24 12:00:00+00';
:PREFIX EXECUTE p;
EXECUTE p;
EXECUTE p_off;
SET timezone TO 'Asia/Tokyo';
EXECUTE p;
EXECUTE p_off;
SET timezone TO 'America/Los_Angeles';
EXECUTE p;
EXECUTE p_off;
SET timezone TO 'Pacific/Kiritimati';
EXECUTE p;
EXECUTE p_off;
SET timezone TO 'Etc/GMT+12';
EXECUTE p;
EXECUTE p_off;
SET timezone TO 'UTC';
DEALLOCATE p;
DEALLOCATE p_off;

-- The same for the cross-type shape.
SET timescaledb.current_timestamp_mock TO '2000-01-15 12:00:00+00';
PREPARE p2 AS SELECT count(*) FROM const_date WHERE day >= now() - interval '30 days';
SET timescaledb.enable_now_constify TO off;
PREPARE p2_off AS SELECT count(*) FROM const_date WHERE day >= now() - interval '30 days';
EXECUTE p2_off;
RESET timescaledb.enable_now_constify;
EXECUTE p2; EXECUTE p2; EXECUTE p2; EXECUTE p2; EXECUTE p2;
:PREFIX EXECUTE p2;
EXECUTE p2;
EXECUTE p2_off;
SET timescaledb.current_timestamp_mock TO '2000-02-24 12:00:00+00';
EXECUTE p2;
EXECUTE p2_off;
SET timezone TO 'Asia/Tokyo';
EXECUTE p2;
EXECUTE p2_off;
SET timezone TO 'America/Los_Angeles';
EXECUTE p2;
EXECUTE p2_off;
SET timezone TO 'UTC';
DEALLOCATE p2;
DEALLOCATE p2_off;

-- A now()-derived bound on the one-chunk-per-day table, where the mock clock
-- also drives the rows returned, against the ts_now_mock() reference. The
-- generic plan is built with the clock at 2000-01-15 20:00 UTC and keeps the
-- chunks from 2000-01-13 on; executed with the clock 4 days later the exact
-- bound is 2000-01-18 in UTC and America/Los_Angeles (3 rows) and 2000-01-19
-- in Asia/Tokyo (2 rows).
SET timescaledb.current_timestamp_mock TO '2000-01-15 20:00:00+00';
PREPARE p3 AS SELECT count(*) FROM const_date_days WHERE day >= now() - interval '2 days';
PREPARE p3_ref AS SELECT count(*) FROM const_date_days WHERE day >= ts_now_mock() - interval '2 days';
EXECUTE p3; EXECUTE p3; EXECUTE p3; EXECUTE p3; EXECUTE p3;
:PREFIX EXECUTE p3;
EXECUTE p3;
EXECUTE p3_ref;
SET timescaledb.current_timestamp_mock TO '2000-01-19 20:00:00+00';
:PREFIX EXECUTE p3;
EXECUTE p3;
EXECUTE p3_ref;
SET timezone TO 'Asia/Tokyo';
EXECUTE p3;
EXECUTE p3_ref;
SET timezone TO 'America/Los_Angeles';
EXECUTE p3;
EXECUTE p3_ref;
SET timezone TO 'UTC';
DEALLOCATE p3;
DEALLOCATE p3_ref;

-- ChunkAppend on top of the generic plan: startup exclusion removes what
-- the constant left in, results unchanged.
SET timescaledb.enable_chunk_append TO true;
SET timescaledb.enable_constraint_aware_append TO true;
SET timescaledb.current_timestamp_mock TO '2000-01-15 20:00:00+00';
PREPARE p4 AS SELECT count(*) FROM const_date_days WHERE day >= now() - interval '2 days';
EXECUTE p4; EXECUTE p4; EXECUTE p4; EXECUTE p4; EXECUTE p4;
SET timescaledb.current_timestamp_mock TO '2000-01-19 20:00:00+00';
EXPLAIN (ANALYZE, BUFFERS OFF, COSTS OFF, SUMMARY OFF, TIMING OFF) EXECUTE p4;
EXECUTE p4;
SET timezone TO 'Asia/Tokyo';
EXPLAIN (ANALYZE, BUFFERS OFF, COSTS OFF, SUMMARY OFF, TIMING OFF) EXECUTE p4;
EXECUTE p4;
SET timezone TO 'UTC';
DEALLOCATE p4;

DROP TABLE const_date_days;
DROP TABLE const_date CASCADE;
