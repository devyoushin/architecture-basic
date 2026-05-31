# DB 고부하 대응 Runbook

## 1. 목적

RDS/MySQL/PostgreSQL에서 CPU, I/O, connection, lock, slow query로 인한 장애가 발생했을 때 병목을 분리하고 완화하는 절차입니다.

## 2. 빠른 판단 기준

| 증상 | 우선 의심 지점 | 확인 지표 |
|------|----------------|-----------|
| CPU 90% 이상 | query CPU, sort/hash, 함수 연산 | Performance Insights DB Load by SQL |
| FreeableMemory 급감 | buffer/cache 부족, temp table, connection 증가 | FreeableMemory, swap |
| DatabaseConnections 급증 | connection pool 누수, 트래픽 폭주 | max connections 대비 사용률 |
| ReadLatency/WriteLatency 증가 | EBS/스토리지 IOPS 병목 | ReadIOPS, WriteIOPS, DiskQueueDepth |
| Lock wait 증가 | 장기 트랜잭션, DDL, hot row | lock wait, blocking session |
| ReplicaLag 증가 | read replica 처리 지연 | ReplicaLag, write volume |

## 3. 1차 진단 순서

1. CloudWatch에서 CPU, Memory, IOPS, Latency, Connections 동시 확인
2. Performance Insights에서 DB Load 기준 top SQL 확인
3. connection pool active/idle/waiting 확인
4. slow query, lock wait, deadlock 확인
5. 최근 배포, 배치, 리포트성 쿼리, 인덱스 변경 여부 확인

## 4. MySQL 진단

```bash
mysql -h <DB_ENDPOINT> -u <USER> -p
```

```sql
-- 현재 실행 중인 쿼리
SHOW FULL PROCESSLIST;

-- InnoDB lock/deadlock 상태
SHOW ENGINE INNODB STATUS\G

-- connection 한도와 현재 사용량
SHOW VARIABLES LIKE 'max_connections';
SHOW STATUS LIKE 'Threads_connected';
SHOW STATUS LIKE 'Threads_running';

-- slow query 설정
SHOW VARIABLES LIKE 'slow_query_log';
SHOW VARIABLES LIKE 'long_query_time';
```

상세 쿼리: `../database/mysql-high-load-queries.sql`

## 5. PostgreSQL 진단

```bash
psql "host=<DB_ENDPOINT> user=<USER> dbname=<DB_NAME> sslmode=require"
```

```sql
-- 실행 중인 쿼리
SELECT pid, usename, state, wait_event_type, wait_event, now() - query_start AS runtime, query
FROM pg_stat_activity
WHERE state <> 'idle'
ORDER BY runtime DESC;

-- blocking session 확인
SELECT blocked_locks.pid AS blocked_pid,
       blocking_locks.pid AS blocking_pid,
       blocked_activity.query AS blocked_query,
       blocking_activity.query AS blocking_query
FROM pg_catalog.pg_locks blocked_locks
JOIN pg_catalog.pg_stat_activity blocked_activity ON blocked_activity.pid = blocked_locks.pid
JOIN pg_catalog.pg_locks blocking_locks
  ON blocking_locks.locktype = blocked_locks.locktype
 AND blocking_locks.database IS NOT DISTINCT FROM blocked_locks.database
 AND blocking_locks.relation IS NOT DISTINCT FROM blocked_locks.relation
 AND blocking_locks.pid != blocked_locks.pid
JOIN pg_catalog.pg_stat_activity blocking_activity ON blocking_activity.pid = blocking_locks.pid
WHERE NOT blocked_locks.granted;
```

상세 쿼리: `../database/postgres-high-load-queries.sql`

## 6. 즉시 완화 조치

| 조치 | 적용 상황 | 주의 |
|------|-----------|------|
| 문제 쿼리 kill | 특정 장기 쿼리가 전체 lock 유발 | 업무 영향 확인 |
| connection pool 상한 하향 | DB connection 고갈 | App request queue 증가 가능 |
| read replica로 read 분산 | read-heavy workload | replica lag 확인 |
| cache 적용 | 반복 read query 많음 | cache invalidation 정책 필요 |
| instance scale-up | CPU/Memory 지속 포화 | 비용과 재시작 영향 확인 |
| storage IOPS 상향 | I/O latency 지속 증가 | gp3/io2 설정과 비용 확인 |
| slow query 인덱스 추가 | 특정 SQL 반복 병목 | write overhead 확인 |

## 7. 금지해야 할 즉흥 조치

- 원인 분리 없이 `max_connections`만 크게 증가
- lock 유발 세션 확인 없이 DB 재시작
- 운영 피크 중 검증되지 않은 인덱스 대량 생성
- replica lag가 큰 상태에서 read traffic을 무조건 replica로 전환
- connection pool timeout을 과도하게 늘려 장애 감지를 늦춤

## 8. 사후 개선

- slow query 상위 20개를 정기 리뷰
- connection pool active/idle/waiting 지표 대시보드화
- CPU bound, I/O bound, lock bound를 구분하는 알람 설계
- 배치 작업과 API workload 분리
- read/write split 기준 명확화
- 장애 시 degraded mode 또는 read-only mode 전환 절차 정의
