-- Index usage on the chunks of both twins at one point in time.
--
-- Called by run.sh right before and right after the query set, so the
-- difference answers "did any of Q1..Q5 use a chunk index at all". Each call
-- is its own psql session, which matters: the session that ran the queries
-- flushes its pending statistics when it exits, so by the time this runs the
-- counters are in shared memory.
--
-- Variables: run_id phase
\set ON_ERROR_STOP on

CALL probe_collect_idxstat(:'run_id', 'metrics_date', :'phase');
CALL probe_collect_idxstat(:'run_id', 'metrics_tstz', :'phase');

SELECT tbl, scope, indexes, idx_scan, idx_tup_read, index_bytes
FROM probe_idxstat
WHERE run_id = :'run_id' AND phase = :'phase'
ORDER BY tbl, scope;
