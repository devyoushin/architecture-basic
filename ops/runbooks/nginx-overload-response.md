# Nginx 고부하 대응 Runbook

## 1. 목적

Nginx 또는 Web tier에서 5xx, latency, connection backlog, CPU saturation이 발생했을 때 원인을 분리하고 안전하게 완화하는 절차입니다.

## 2. 빠른 판단 기준

| 증상 | 우선 의심 지점 | 확인 지표 |
|------|----------------|-----------|
| 499 증가 | 클라이언트 timeout 또는 응답 지연 | `request_time`, ALB TargetResponseTime |
| 502 증가 | upstream 연결 실패 | `upstream_status`, `upstream_connect_time` |
| 503 증가 | Nginx worker/connection 포화 또는 upstream unavailable | `active`, `waiting`, `worker_connections` |
| 504 증가 | upstream 처리 지연 | `upstream_response_time`, DB slow query |
| CPU 90% 이상 | TLS, gzip, log, Lua/WAF, 정적 압축 부하 | `top`, `perf`, Nginx worker CPU |
| connection reset | backlog, conntrack, upstream keepalive 부족 | `ss -s`, `conntrack -S` |

## 3. 1차 진단

```bash
# Nginx 프로세스와 worker 상태
ps -eo pid,ppid,cmd,%cpu,%mem --sort=-%cpu | grep nginx

# 연결 상태 요약
ss -s
ss -ant state established '( sport = :80 or sport = :443 )' | wc -l
ss -ant state time-wait | wc -l

# listen backlog 확인
ss -lntp | grep -E ':80|:443'

# 파일 디스크립터 한도 확인
pid=$(pgrep -o nginx)
cat /proc "$pid" /limits 2>/dev/null || cat /proc/$pid/limits

# 커널 큐/드롭 확인
netstat -s | grep -Ei 'listen|overflow|reset|retransmit'

# conntrack 사용률
sysctl net.netfilter.nf_conntrack_count net.netfilter.nf_conntrack_max
```

## 4. 로그 기반 원인 분리

Nginx access log에 `request_time`, `upstream_response_time`, `upstream_status`가 있어야 정확히 분리할 수 있습니다.

| 패턴 | 해석 |
|------|------|
| `request_time` 높고 `upstream_response_time` 낮음 | 클라이언트 전송 지연, Nginx buffering, 네트워크 문제 가능성 |
| `upstream_response_time` 높음 | App 또는 DB 병목 가능성 |
| `upstream_connect_time` 높음 | upstream connection pool, SYN backlog, target 포화 |
| `upstream_status=502` | upstream reset/refused, App crash, health check 실패 |
| `status=499` | 클라이언트가 먼저 연결 종료. 실제 원인은 서버 지연일 수 있음 |

## 5. 즉시 완화 조치

| 조치 | 적용 상황 | 주의 |
|------|-----------|------|
| Auto Scaling scale-out | CPU/connection 포화 | warm-up 시간 고려 |
| upstream keepalive 증가 | upstream connect time 증가 | App connection limit 확인 |
| `limit_req` 적용 | 특정 URI/API 폭주 | 정상 트래픽 차단 위험 |
| 캐시 활성화 | 반복 GET 요청 많음 | stale data 허용 범위 확인 |
| gzip 비활성/레벨 하향 | CPU 압박 | 대역폭 증가 가능 |
| access log sampling/buffer | 디스크 I/O 병목 | 감사 요구사항 확인 |
| ALB target deregistration delay 조정 | 배포 중 502/504 | 장기 연결 영향 확인 |

## 6. 설정 변경 후보

관련 예시:

- `../nginx/nginx-tuning.conf`
- `../nginx/sysctl-nginx.conf`
- `../nginx/systemd-nginx-override.conf`
- `../nginx/log-format-json.conf`

## 7. 검증

```bash
# 설정 문법 확인
nginx -t

# reload 후 에러 확인
systemctl reload nginx
journalctl -u nginx -n 100 --no-pager

# 부하 테스트 전후 비교
../load-test/wrk-nginx.sh https://example.com/
```

## 8. 에스컬레이션 기준

- Nginx worker를 늘려도 `upstream_response_time`이 계속 높으면 App/DB 병목으로 전환
- DB CPU, connection, slow query가 동시에 증가하면 `db-overload-response.md`로 전환
- ALB 5xx와 Nginx 5xx가 불일치하면 ALB target health, security group, network ACL 확인
