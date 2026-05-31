# Connection Pool Sizing

## 1. 핵심 원칙

애플리케이션 인스턴스 수가 늘어나면 DB connection pool 총합도 함께 늘어납니다. DB가 병목인 상황에서 App scale-out만 수행하면 DB connection 고갈이 더 빨라질 수 있습니다.

```text
총 DB 연결 수 = App 인스턴스 수 × 인스턴스당 max pool size × DB 접근 프로세스 수
```

## 2. 계산 예시

| 항목 | 값 |
|------|----|
| App instance | 20 |
| max pool size | 30 |
| worker process | 2 |
| 총 connection 가능 수 | 1200 |

DB `max_connections`가 1000이면 이 구조는 scale-out 순간 connection 고갈 가능성이 높습니다.

## 3. 권장 기준

| 상황 | 권장 조치 |
|------|-----------|
| connection 대부분 idle | pool size 축소 |
| active는 낮고 waiting 높음 | App 내부 thread/queue 병목 확인 |
| active 높고 DB CPU 높음 | query tuning/cache/read replica 검토 |
| connection 생성/해제가 많음 | pool reuse, keepalive, pooler 검토 |
| PostgreSQL connection 많음 | pgbouncer transaction pooling 검토 |

## 4. 운영 체크리스트

- App 인스턴스 수와 max pool size를 곱한 총합이 DB 한도보다 낮은지 확인
- 배치/worker도 별도 pool을 갖는지 확인
- HPA 최대 replica 기준으로 connection 총합 계산
- 장애 시 pool timeout이 너무 길어 장애 전파를 늦추지 않는지 확인
- DB scale-up 전에 pool 누수와 idle connection을 먼저 확인
