# Architecture Ops

아키텍처 운영 상황을 재현하고 대응하기 위한 runbook, 튜닝 예시, 모니터링 쿼리, 부하 테스트 자산을 관리합니다.

## 구조

| 폴더 | 내용 |
|------|------|
| `runbooks/` | Nginx, DB, scale-out 의사결정 등 장애/부하 대응 절차 |
| `nginx/` | Nginx 고부하 대응 설정 예시 |
| `database/` | MySQL/PostgreSQL/RDS 부하 진단 쿼리와 파라미터 체크리스트 |
| `monitoring/` | CloudWatch Logs Insights, Prometheus alert, 대시보드 기준 |
| `load-test/` | `wrk`, `k6`, `sysbench`, `pgbench` 기반 부하 테스트 예시 |

## 우선 적용 순서

1. `runbooks/nginx-overload-response.md`로 Web/Nginx 고부하 원인 분리
2. `runbooks/db-overload-response.md`로 DB 병목 원인 분리
3. `monitoring/log-insights-queries.md`로 로그 기반 지표 확인
4. `nginx/nginx-tuning.conf`와 `nginx/sysctl-nginx.conf`로 설정 후보 검토
5. `database/mysql-high-load-queries.sql`, `database/postgres-high-load-queries.sql`로 DB 내부 상태 확인
6. `load-test/` 스크립트로 변경 전/후 성능 비교

## 운영 원칙

- 설정 변경 전 반드시 현재 병목이 Web, App, DB, Network 중 어디인지 분리합니다.
- 부하 테스트는 운영 트래픽과 분리된 환경에서 먼저 수행합니다.
- DB 파라미터 변경은 즉시 적용 가능 여부와 재부팅 필요 여부를 먼저 확인합니다.
- scale-out, scale-up, rate limit, cache, query tuning 중 어떤 조치가 병목에 맞는지 판단한 뒤 적용합니다.
