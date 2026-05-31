# CloudWatch Logs Insights Queries

## 1. Nginx 5xx 상위 URI

```sql
fields @timestamp, status, request_uri, request_time, upstream_response_time, upstream_status
| filter status >= 500
| stats count(*) as errors,
        pct(request_time, 50) as p50,
        pct(request_time, 95) as p95,
        pct(request_time, 99) as p99
  by request_uri, upstream_status
| sort errors desc
| limit 30
```

## 2. Nginx 499 증가 원인 분석

```sql
fields @timestamp, status, request_uri, request_time, upstream_response_time
| filter status = 499
| stats count(*) as client_closed,
        avg(request_time) as avg_request_time,
        pct(request_time, 95) as p95_request_time
  by request_uri
| sort client_closed desc
| limit 30
```

## 3. Upstream 지연 상위 URI

```sql
fields @timestamp, request_uri, upstream_response_time, request_time, upstream_status
| filter upstream_response_time != "-"
| stats count(*) as requests,
        pct(upstream_response_time, 95) as upstream_p95,
        pct(request_time, 95) as request_p95
  by request_uri
| sort upstream_p95 desc
| limit 30
```

## 4. RDS 에러 로그 키워드

```sql
fields @timestamp, @message
| filter @message like /deadlock|timeout|Too many connections|Lock wait|could not serialize|remaining connection slots/
| sort @timestamp desc
| limit 100
```

## 5. 배포 시점 전후 오류 비교

```sql
fields @timestamp, status, request_uri
| filter @timestamp >= ago(2h)
| stats count(*) as count by bin(5m), status
| sort bin(5m) asc
```
