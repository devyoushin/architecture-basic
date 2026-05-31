# RDS Parameter 변경 체크리스트

## 1. 공통 원칙

| 항목 | 확인 내용 |
|------|-----------|
| 적용 방식 | dynamic인지 static인지 확인 |
| 재부팅 필요 여부 | static parameter는 reboot 필요 |
| rollback 값 | 변경 전 값을 기록 |
| peak time 회피 | 재부팅/성능 영향이 있으면 maintenance window 사용 |
| Performance Insights | 변경 전후 DB Load, top SQL 비교 |

## 2. MySQL/Aurora MySQL

| 파라미터 | 목적 | 주의 |
|----------|------|------|
| `max_connections` | connection 상한 | pool 총합과 메모리 사용량 함께 계산 |
| `innodb_buffer_pool_size` | data/index cache | RDS managed 기본값 우선 검토 |
| `innodb_log_file_size` | write burst 완화 | 변경 영향 검토 필요 |
| `slow_query_log` | slow query 수집 | 로그 비용/용량 확인 |
| `long_query_time` | slow query 기준 | 운영에서는 0.5~2초부터 검토 |
| `tmp_table_size` | memory temp table | 너무 크게 잡으면 메모리 압박 |
| `max_allowed_packet` | large payload 처리 | 애플리케이션 payload도 함께 점검 |

## 3. PostgreSQL/Aurora PostgreSQL

| 파라미터 | 목적 | 주의 |
|----------|------|------|
| `max_connections` | connection 상한 | pgbouncer 등 pooler 우선 검토 |
| `shared_buffers` | shared cache | RDS 기본값과 workload 기준 검토 |
| `work_mem` | sort/hash memory | connection 수와 곱해 메모리 폭증 가능 |
| `maintenance_work_mem` | index/vacuum 작업 | DDL/maintenance 시점 고려 |
| `log_min_duration_statement` | slow query logging | 로그량 증가 주의 |
| `autovacuum_max_workers` | vacuum 병렬성 | write-heavy workload에서 중요 |
| `max_wal_size` | checkpoint 빈도 | storage와 recovery time 고려 |

## 4. 변경 전후 검증

```bash
# AWS CLI 예시
aws rds describe-db-parameters \
  --db-parameter-group-name <PARAMETER_GROUP> \
  --region ap-northeast-2

aws rds describe-db-instances \
  --db-instance-identifier <DB_INSTANCE> \
  --query 'DBInstances[0].DBParameterGroups'
```

## 5. 변경 기록 템플릿

| 항목 | 값 |
|------|----|
| 변경 일시 | `<YYYY-MM-DD HH:mm>` |
| 대상 DB | `<DB_IDENTIFIER>` |
| 변경 파라미터 | `<PARAMETER>` |
| 변경 전 | `<OLD_VALUE>` |
| 변경 후 | `<NEW_VALUE>` |
| 적용 방식 | `immediate` 또는 `pending-reboot` |
| rollback 방법 | `<ROLLBACK_PLAN>` |
