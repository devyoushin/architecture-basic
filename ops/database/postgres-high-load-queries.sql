-- PostgreSQL high-load diagnostic queries.
-- Run with: psql "host=<DB_ENDPOINT> user=<USER> dbname=<DB_NAME> sslmode=require"

-- Active queries by runtime.
SELECT pid,
       usename,
       application_name,
       client_addr,
       state,
       wait_event_type,
       wait_event,
       now() - query_start AS runtime,
       query
FROM pg_stat_activity
WHERE state <> 'idle'
ORDER BY runtime DESC
LIMIT 30;

-- Blocking sessions.
SELECT blocked.pid AS blocked_pid,
       blocking.pid AS blocking_pid,
       blocked.query AS blocked_query,
       blocking.query AS blocking_query,
       now() - blocked.query_start AS blocked_runtime
FROM pg_stat_activity blocked
JOIN pg_locks blocked_locks ON blocked_locks.pid = blocked.pid
JOIN pg_locks blocking_locks
  ON blocking_locks.locktype = blocked_locks.locktype
 AND blocking_locks.database IS NOT DISTINCT FROM blocked_locks.database
 AND blocking_locks.relation IS NOT DISTINCT FROM blocked_locks.relation
 AND blocking_locks.page IS NOT DISTINCT FROM blocked_locks.page
 AND blocking_locks.tuple IS NOT DISTINCT FROM blocked_locks.tuple
 AND blocking_locks.pid <> blocked_locks.pid
JOIN pg_stat_activity blocking ON blocking.pid = blocking_locks.pid
WHERE NOT blocked_locks.granted;

-- Top SQL by total execution time. Requires pg_stat_statements.
SELECT query,
       calls,
       round(total_exec_time::numeric, 2) AS total_ms,
       round(mean_exec_time::numeric, 2) AS mean_ms,
       rows
FROM pg_stat_statements
ORDER BY total_exec_time DESC
LIMIT 20;

-- Cache hit ratio.
SELECT datname,
       blks_hit,
       blks_read,
       round((blks_hit::numeric / NULLIF(blks_hit + blks_read, 0)) * 100, 2) AS cache_hit_ratio
FROM pg_stat_database
ORDER BY cache_hit_ratio ASC;

-- Table bloat/vacuum candidates.
SELECT schemaname,
       relname,
       n_live_tup,
       n_dead_tup,
       last_vacuum,
       last_autovacuum,
       last_analyze,
       last_autoanalyze
FROM pg_stat_user_tables
ORDER BY n_dead_tup DESC
LIMIT 20;

-- Index usage.
SELECT schemaname,
       relname,
       indexrelname,
       idx_scan,
       idx_tup_read,
       idx_tup_fetch
FROM pg_stat_user_indexes
ORDER BY idx_scan ASC
LIMIT 30;

-- Database connection usage.
SELECT datname,
       count(*) AS connections,
       count(*) FILTER (WHERE state = 'active') AS active,
       count(*) FILTER (WHERE state = 'idle') AS idle,
       count(*) FILTER (WHERE wait_event_type IS NOT NULL) AS waiting
FROM pg_stat_activity
GROUP BY datname
ORDER BY connections DESC;
