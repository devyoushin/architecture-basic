-- MySQL high-load diagnostic queries.
-- Run with: mysql -h <DB_ENDPOINT> -u <USER> -p

-- Connection usage.
SHOW VARIABLES LIKE 'max_connections';
SHOW STATUS LIKE 'Threads_connected';
SHOW STATUS LIKE 'Threads_running';
SHOW STATUS LIKE 'Max_used_connections';

-- Current sessions.
SHOW FULL PROCESSLIST;

-- InnoDB status including latest deadlock and lock waits.
SHOW ENGINE INNODB STATUS\G

-- Top tables by size.
SELECT table_schema,
       table_name,
       ROUND((data_length + index_length) / 1024 / 1024, 2) AS size_mb,
       table_rows
FROM information_schema.tables
WHERE table_schema NOT IN ('mysql', 'performance_schema', 'information_schema', 'sys')
ORDER BY size_mb DESC
LIMIT 20;

-- Missing index candidates from full table scans.
SELECT object_schema,
       object_name,
       count_read,
       count_fetch,
       sum_timer_wait
FROM performance_schema.table_io_waits_summary_by_table
ORDER BY count_read DESC
LIMIT 20;

-- Statement digest by total latency.
SELECT digest_text,
       count_star,
       ROUND(sum_timer_wait / 1000000000000, 2) AS total_sec,
       ROUND(avg_timer_wait / 1000000000000, 4) AS avg_sec,
       sum_rows_examined,
       sum_rows_sent
FROM performance_schema.events_statements_summary_by_digest
ORDER BY sum_timer_wait DESC
LIMIT 20;

-- Lock waits.
SELECT *
FROM sys.innodb_lock_waits
LIMIT 20;

-- Buffer pool efficiency.
SHOW STATUS LIKE 'Innodb_buffer_pool_read%';

-- Temporary table pressure.
SHOW STATUS LIKE 'Created_tmp%';
