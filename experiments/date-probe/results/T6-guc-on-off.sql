\pset border 2
\echo '### results with the two GUCs on and off (must be identical row by row)'

CREATE TEMP TABLE guc_probe(constify bool, runtime bool, q text, n bigint, avg_v1 numeric);

DO $$
DECLARE
    c bool; r bool;
    qs text[] := ARRAY[
      'Q1  day >= now() - 30d',
      'Q1lt day < now() - 300d',
      'Q1gt day > now() - 30d',
      'Q1eq day = now()::date::timestamptz',
      'Q2  day >= current_date - 30',
      'Q3  literal window',
      'Q4c cast bound (now()-30d)::date'];
    sqls text[] := ARRAY[
      'SELECT count(*), round(avg(v1)::numeric,10) FROM metrics_date WHERE day >= now() - interval ''30 days''',
      'SELECT count(*), round(avg(v1)::numeric,10) FROM metrics_date WHERE day < now() - interval ''300 days''',
      'SELECT count(*), round(avg(v1)::numeric,10) FROM metrics_date WHERE day > now() - interval ''30 days''',
      'SELECT count(*), round(avg(v1)::numeric,10) FROM metrics_date WHERE day = (now()::date)::timestamptz',
      'SELECT count(*), round(avg(v1)::numeric,10) FROM metrics_date WHERE day >= current_date - 30',
      'SELECT count(*), round(avg(v1)::numeric,10) FROM metrics_date WHERE day >= ''2026-02-20'' AND day < ''2026-03-23''',
      'SELECT count(*), round(avg(v1)::numeric,10) FROM metrics_date WHERE day >= (now() - interval ''30 days'')::date'];
    i int; nn bigint; aa numeric;
BEGIN
    FOREACH c IN ARRAY ARRAY[true, false] LOOP
      FOREACH r IN ARRAY ARRAY[true, false] LOOP
        PERFORM set_config('timescaledb.enable_now_constify', c::text, false);
        PERFORM set_config('timescaledb.enable_runtime_exclusion', r::text, false);
        FOR i IN 1 .. array_length(qs, 1) LOOP
            EXECUTE sqls[i] INTO nn, aa;
            INSERT INTO guc_probe VALUES (c, r, qs[i], nn, aa);
        END LOOP;
      END LOOP;
    END LOOP;
    RESET timescaledb.enable_now_constify;
    RESET timescaledb.enable_runtime_exclusion;
END $$;

SELECT q,
       count(DISTINCT (n, avg_v1))                AS distinct_results,
       min(n)                                     AS n,
       min(avg_v1)                                AS avg_v1
FROM guc_probe GROUP BY q ORDER BY q;

\echo '### number of query shapes whose result depends on a GUC (must be 0)'
SELECT count(*) AS shapes_disagreeing
FROM (SELECT q FROM guc_probe GROUP BY q HAVING count(DISTINCT (n, avg_v1)) > 1) d;
