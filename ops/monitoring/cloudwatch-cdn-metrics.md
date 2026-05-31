# CDN CloudWatch Metrics

## 1. 핵심 지표

| 지표 | 의미 | 경보 기준 예시 |
|------|------|----------------|
| `Requests` | 전체 요청 수 | 평소 대비 3배 이상 |
| `BytesDownloaded` | 사용자에게 전송한 바이트 | 패치/영상 이벤트 기준 확인 |
| `4xxErrorRate` | 클라이언트 오류율 | 5분 평균 5% 이상 |
| `5xxErrorRate` | 서버/edge 오류율 | 5분 평균 1% 이상 |
| `TotalErrorRate` | 전체 오류율 | 서비스 SLO 기준 |
| `CacheHitRate` | 캐시 적중률 | 정적 asset 90% 미만 |
| `OriginLatency` | origin 응답 지연 | p95 급증 |

## 2. 게임 서비스 기준

| 콘텐츠 | 핵심 지표 |
|--------|-----------|
| patch chunk | `CacheHitRate`, `BytesDownloaded`, top object |
| manifest | `Requests`, `4xxErrorRate`, `OriginLatency` |
| launcher config | `CacheHitRate`, invalidation count |
| 이벤트 이미지 | `CacheHitRate`, regional latency |

## 3. 영상 서비스 기준

| 콘텐츠 | 핵심 지표 |
|--------|-----------|
| VOD segment | `CacheHitRate`, `BytesDownloaded`, `OriginLatency` |
| live playlist | `OriginLatency`, `5xxErrorRate`, p95 time taken |
| thumbnail | `CacheHitRate`, `4xxErrorRate` |
| DRM license API | `4xxErrorRate`, application latency |

## 4. 알람 설계

| 알람 | 조건 | 대응 |
|------|------|------|
| CDN hit ratio drop | 10분 평균 기준선 대비 20%p 하락 | cache policy 변경 확인 |
| Origin 5xx spike | 5분 평균 1% 이상 | origin runbook 전환 |
| Signed URL 403 spike | 5분 평균 5% 이상 | token TTL/clock skew 확인 |
| Patch egress surge | 이벤트 기준치 초과 | staged rollout, origin shield 확인 |
| Segment latency spike | p95 time taken 급증 | edge/region/origin 분리 |
