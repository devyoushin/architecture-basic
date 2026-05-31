# Scale-out 의사결정 트리

## 1. 목적

부하 상황에서 무조건 scale-out하기 전에 병목 계층을 분리하고 올바른 완화책을 선택하기 위한 기준입니다.

## 2. 의사결정 흐름

```text
사용자 지연/오류 증가
  │
  ├─ ALB 5xx 증가?
  │   ├─ TargetConnectionError 증가 → target health, SG/NACL, Nginx listen/backlog 확인
  │   └─ TargetResponseTime 증가 → Nginx/App/DB latency 분리
  │
  ├─ Nginx worker/connection 포화?
  │   ├─ 예 → Web tier scale-out, keepalive, worker_connections, rate limit 검토
  │   └─ 아니오
  │
  ├─ App CPU/thread pool 포화?
  │   ├─ 예 → App scale-out, queue, async, pool 조정
  │   └─ 아니오
  │
  └─ DB 병목?
      ├─ CPU bound → query tuning, cache, read replica, scale-up
      ├─ I/O bound → index/query 개선, storage IOPS, batching
      ├─ connection bound → pool 조정, leak 점검, pgbouncer/proxy
      └─ lock bound → blocking transaction 제거, transaction scope 축소
```

## 3. Scale-out이 효과적인 경우

| 병목 | Scale-out 효과 | 조건 |
|------|----------------|------|
| Stateless Web CPU | 높음 | 세션 외부화, ALB target 정상 |
| Stateless App CPU | 높음 | DB가 병목이 아닐 때 |
| Nginx connection | 중간~높음 | upstream keepalive와 OS limit도 함께 조정 |
| Read DB | 중간 | read replica lag 허용 가능 |
| Write DB | 낮음 | 단일 writer 병목이면 query/index/scale-up 우선 |

## 4. Scale-out보다 먼저 봐야 할 것

- DB가 이미 포화면 App scale-out은 DB 부하를 더 키울 수 있음
- Nginx upstream keepalive가 부족하면 target 수 증가 후에도 connect overhead가 커질 수 있음
- connection pool 총합이 DB `max_connections`를 초과하면 scale-out이 장애를 악화시킴
- ALB target slow start, deregistration delay, health check grace period를 함께 확인해야 함

## 5. 검증 지표

| 조치 | 성공 기준 |
|------|-----------|
| Web scale-out | p95 latency 감소, 5xx 감소, CPU 분산 |
| App scale-out | queue depth 감소, thread pool saturation 해소 |
| DB scale-up | DBLoad/CPU/latency 감소 |
| Read replica 추가 | primary read IOPS/CPU 감소, replica lag 안정 |
| Rate limit | 5xx 감소, 정상 사용자 성공률 유지 |
