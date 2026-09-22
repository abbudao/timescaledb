\pset border 2
\echo '### planning buffers (median of three runs), per query'
SELECT tbl, query_id,
       round(percentile_cont(0.5) WITHIN GROUP (
           ORDER BY (plan -> 0 -> 'Planning' ->> 'Shared Hit Blocks')::bigint)::numeric, 0) AS plan_buf_median,
       min((plan -> 0 -> 'Planning' ->> 'Shared Hit Blocks')::bigint) AS plan_buf_min,
       max((plan -> 0 -> 'Planning' ->> 'Shared Hit Blocks')::bigint) AS plan_buf_max
FROM probe_plans
GROUP BY tbl, query_id
ORDER BY tbl, query_id;
