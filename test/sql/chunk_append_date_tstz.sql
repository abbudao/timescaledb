-- This file and its contents are licensed under the Apache License 2.0.
-- Please see the included NOTICE for copyright information and
-- LICENSE-APACHE for a copy of the license.

-- Chunk exclusion for a DATE dimension compared against a TIMESTAMPTZ value.
--
-- The cross-type DATE/TIMESTAMPTZ operators are STABLE (they depend on the
-- session timezone), so neither plan-time exclusion nor predicate_refuted_by
-- can use them directly. ChunkAppend rewrites such clauses into DATE-versus-
-- DATE comparisons with a bound derived from the TIMESTAMPTZ value through
-- PostgreSQL's own cast functions (src/planner/date_bounds.c) and folds the
-- bound at executor startup. This test checks that every operator gets
-- startup exclusion and that the row counts never differ from the plain
-- PostgreSQL evaluation, across timezones and DST transition days.

\set PREFIX 'EXPLAIN (ANALYZE, BUFFERS OFF, COSTS OFF, TIMING OFF, SUMMARY OFF)'

CREATE TABLE date_ca(day date NOT NULL, v int);
SELECT table_name FROM create_hypertable('date_ca', 'day', chunk_time_interval => INTERVAL '1 day', create_default_indexes => false);

-- Load ten consecutive days into date_ca, one chunk per day, replacing any
-- previous contents. Returns the number of chunks.
CREATE FUNCTION date_ca_load(start date) RETURNS int LANGUAGE plpgsql AS $$
BEGIN
  TRUNCATE date_ca;
  INSERT INTO date_ca SELECT d::date, 1 FROM generate_series(start, start + 9, '1 day') d;
  RETURN (SELECT count(*) FROM show_chunks('date_ca'));
END $$;

-- Every result row of the operator by timezone matrix gets recorded here so
-- the end of the test can summarize it.
CREATE TABLE date_ca_results(timezone text, bound text, op text, excluded int, cnt int, cnt_no_runtime_excl int, cnt_no_excl int, ok bool);

-- For each operator and for a bound at local midnight and at 12:00 of
-- bound_day in timezone tz: the number of chunks ChunkAppend excluded during
-- startup, the row count, the row count with timescaledb.enable_runtime_exclusion
-- off, and the row count with ChunkAppend and ConstraintAwareAppend disabled
-- (plain Append, no chunk exclusion at all, i.e. PostgreSQL's own evaluation).
-- All three counts must agree in every cell.
CREATE FUNCTION date_ca_matrix(tz text, bound_day date, mirrored bool DEFAULT false)
RETURNS TABLE(timezone text, bound text, op text, excluded int, cnt int, cnt_no_runtime_excl int, cnt_no_excl int, ok bool)
LANGUAGE plpgsql AS $$
DECLARE
  ops text[] := ARRAY['>', '>=', '<', '<=', '='];
  times text[] := ARRAY['00:00:00', '12:00:00'];
  t text;
  o text;
  q text;
  line text;
BEGIN
  PERFORM set_config('timezone', tz, true);
  FOREACH t IN ARRAY times LOOP
    FOREACH o IN ARRAY ops LOOP
      IF mirrored THEN
        q := format('SELECT count(*) FROM date_ca WHERE %L::timestamptz %s day', bound_day || ' ' || t, o);
        op := 'T ' || o || ' day';
      ELSE
        q := format('SELECT count(*) FROM date_ca WHERE day %s %L::timestamptz', o, bound_day || ' ' || t);
        op := 'day ' || o || ' T';
      END IF;
      timezone := tz;
      bound := bound_day || ' ' || t;
      excluded := NULL;

      PERFORM set_config('timescaledb.enable_runtime_exclusion', 'on', true);
      PERFORM set_config('timescaledb.enable_chunk_append', 'on', true);
      PERFORM set_config('timescaledb.enable_constraint_aware_append', 'on', true);
      FOR line IN EXECUTE 'EXPLAIN (ANALYZE, BUFFERS OFF, COSTS OFF, TIMING OFF, SUMMARY OFF) ' || q LOOP
        IF line LIKE '%Chunks excluded during startup%' THEN
          excluded := substring(line FROM '\d+')::int;
        END IF;
      END LOOP;
      EXECUTE q INTO cnt;

      PERFORM set_config('timescaledb.enable_runtime_exclusion', 'off', true);
      EXECUTE q INTO cnt_no_runtime_excl;
      PERFORM set_config('timescaledb.enable_runtime_exclusion', 'on', true);

      PERFORM set_config('timescaledb.enable_chunk_append', 'off', true);
      PERFORM set_config('timescaledb.enable_constraint_aware_append', 'off', true);
      EXECUTE q INTO cnt_no_excl;
      PERFORM set_config('timescaledb.enable_chunk_append', 'on', true);
      PERFORM set_config('timescaledb.enable_constraint_aware_append', 'on', true);

      ok := cnt = cnt_no_runtime_excl AND cnt = cnt_no_excl;
      INSERT INTO date_ca_results VALUES (timezone, bound, op, excluded, cnt, cnt_no_runtime_excl, cnt_no_excl, ok);
      RETURN NEXT;
    END LOOP;
  END LOOP;
END $$;

SELECT date_ca_load('2020-03-04');

---------------------------------------------------------------------------
-- Plans in UTC: every operator, bound at midnight and at noon.
---------------------------------------------------------------------------
SET timezone TO 'UTC';

-- ">" and "<=" cast the bound down to the date (existing behaviour)
:PREFIX SELECT count(*) FROM date_ca WHERE day > '2020-03-08 12:00:00'::timestamptz;
:PREFIX SELECT count(*) FROM date_ca WHERE day <= '2020-03-08 12:00:00'::timestamptz;

-- ">=" and "<" need the bound rounded up unless it is a midnight
:PREFIX SELECT count(*) FROM date_ca WHERE day >= '2020-03-08 00:00:00'::timestamptz;
:PREFIX SELECT count(*) FROM date_ca WHERE day >= '2020-03-08 12:00:00'::timestamptz;
:PREFIX SELECT count(*) FROM date_ca WHERE day < '2020-03-08 00:00:00'::timestamptz;
:PREFIX SELECT count(*) FROM date_ca WHERE day < '2020-03-08 12:00:00'::timestamptz;

-- "=" matches one chunk at midnight and nothing otherwise
:PREFIX SELECT count(*) FROM date_ca WHERE day = '2020-03-08 00:00:00'::timestamptz;
:PREFIX SELECT count(*) FROM date_ca WHERE day = '2020-03-08 12:00:00'::timestamptz;

-- mirrored forms
:PREFIX SELECT count(*) FROM date_ca WHERE '2020-03-08 12:00:00'::timestamptz <= day;
:PREFIX SELECT count(*) FROM date_ca WHERE '2020-03-08 12:00:00'::timestamptz > day;
:PREFIX SELECT count(*) FROM date_ca WHERE '2020-03-08 00:00:00'::timestamptz = day;

-- the ConstraintAwareAppend path uses the same rewrite
SET timescaledb.enable_chunk_append TO off;
:PREFIX SELECT count(*) FROM date_ca WHERE day >= '2020-03-08 12:00:00'::timestamptz;
:PREFIX SELECT count(*) FROM date_ca WHERE day = '2020-03-08 12:00:00'::timestamptz;
RESET timescaledb.enable_chunk_append;

-- external parameters of a generic plan are folded at startup as well
SET plan_cache_mode TO force_generic_plan;
PREPARE p_ge(timestamptz) AS SELECT count(*) FROM date_ca WHERE day >= $1;
PREPARE p_eq(timestamptz) AS SELECT count(*) FROM date_ca WHERE day = $1;
:PREFIX EXECUTE p_ge('2020-03-08 12:00:00');
EXECUTE p_ge('2020-03-08 12:00:00');
EXECUTE p_ge('2020-03-08 00:00:00');
:PREFIX EXECUTE p_eq('2020-03-08 00:00:00');
EXECUTE p_eq('2020-03-08 00:00:00');
EXECUTE p_eq('2020-03-08 12:00:00');
DEALLOCATE p_ge;
DEALLOCATE p_eq;
RESET plan_cache_mode;

-- an InitPlan parameter is only known at runtime; this is the path that
-- timescaledb.enable_runtime_exclusion switches off
:PREFIX SELECT count(*) FROM date_ca WHERE day < (SELECT '2020-03-08 12:00:00'::timestamptz);
SELECT count(*) FROM date_ca WHERE day < (SELECT '2020-03-08 12:00:00'::timestamptz);
SET timescaledb.enable_runtime_exclusion TO off;
:PREFIX SELECT count(*) FROM date_ca WHERE day < (SELECT '2020-03-08 12:00:00'::timestamptz);
SELECT count(*) FROM date_ca WHERE day < (SELECT '2020-03-08 12:00:00'::timestamptz);
RESET timescaledb.enable_runtime_exclusion;

---------------------------------------------------------------------------
-- DST transition day in America/New_York: the plan shape is the same, the
-- bound is resolved in the session timezone.
---------------------------------------------------------------------------
SET timezone TO 'America/New_York';
:PREFIX SELECT count(*) FROM date_ca WHERE day >= '2020-03-08 00:00:00'::timestamptz;
:PREFIX SELECT count(*) FROM date_ca WHERE day >= '2020-03-08 12:00:00'::timestamptz;
:PREFIX SELECT count(*) FROM date_ca WHERE day = '2020-03-08 00:00:00'::timestamptz;
RESET timezone;

---------------------------------------------------------------------------
-- Operator by timezone matrix. Data: 2020-03-04 .. 2020-03-13.
---------------------------------------------------------------------------
SELECT * FROM date_ca_matrix('UTC', '2020-03-08');
SELECT * FROM date_ca_matrix('Asia/Tokyo', '2020-03-08');
SELECT * FROM date_ca_matrix('America/Los_Angeles', '2020-03-08');
-- DST starts 2020-03-08 02:00 in America/New_York
SELECT * FROM date_ca_matrix('America/New_York', '2020-03-08');
-- mirrored forms
SELECT * FROM date_ca_matrix('UTC', '2020-03-08', true);
SELECT * FROM date_ca_matrix('America/New_York', '2020-03-08', true);

-- DST starts 2020-03-29 01:00 in Europe/London. Data: 2020-03-25 .. 2020-04-03.
SELECT date_ca_load('2020-03-25');
SELECT * FROM date_ca_matrix('Europe/London', '2020-03-29');

-- In America/Santiago the transitions happen at midnight: 2019-09-08 00:00
-- does not exist (clocks jump to 01:00) and 2019-04-07 00:00 happens twice.
-- PostgreSQL resolves both inside the date to timestamptz cast, and the
-- rewrite uses that same cast.
SELECT date_ca_load('2019-09-04');
SELECT * FROM date_ca_matrix('America/Santiago', '2019-09-08');
SELECT date_ca_load('2019-04-03');
SELECT * FROM date_ca_matrix('America/Santiago', '2019-04-07');

-- Every cell must have identical counts in all three modes, and every
-- cell must have excluded chunks at startup.
SELECT count(*) AS cells,
       count(*) FILTER (WHERE NOT ok) AS count_mismatches,
       count(*) FILTER (WHERE excluded IS NULL) AS cells_without_chunk_append,
       count(*) FILTER (WHERE excluded = 0) AS cells_without_startup_exclusion
FROM date_ca_results;
