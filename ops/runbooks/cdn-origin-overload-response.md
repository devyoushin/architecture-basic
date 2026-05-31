# CDN Origin 부하 대응 Runbook

## 1. 목적

CDN을 사용 중인데도 origin ALB/Nginx/App/DB에 부하가 급증할 때 cache hit ratio, cache key, TTL, origin shield, 배포 이벤트를 기준으로 원인을 분리합니다.

## 2. 빠른 판단 기준

| 증상 | 우선 의심 | 확인 지표 |
|------|-----------|-----------|
| CDN hit ratio 급락 | cache policy 변경, query/header/cookie forwarding 증가 | CacheHitRate, MissRate |
| origin 5xx 증가 | miss storm, origin capacity 부족 | OriginLatency, Origin5xx, ALB 5xx |
| 특정 object 요청 폭증 | 게임 패치, 영상 인기 콘텐츠 | top URI, bytes downloaded |
| 403 증가 | signed URL/cookie 만료, OAC/OAI 정책 | Edge 403, origin 403 |
| 404 증가 | 잘못된 manifest, 배포 누락 | negative cache, top 404 URI |
| DB 부하 증가 | API cache bypass, personalization cache key 폭증 | DB CPU, connection, slow query |

## 3. 1차 진단 순서

1. CDN cache hit ratio가 언제부터 떨어졌는지 확인
2. 배포, cache policy, origin request policy 변경 여부 확인
3. top URI, top query string, top user-agent 확인
4. origin ALB/Nginx의 `upstream_response_time` 확인
5. App/DB까지 부하가 전파됐는지 확인
6. stale-if-error, origin shield, rate limit 적용 가능성 판단

## 4. 게임 패치 트래픽 대응

```text
Game Launcher
  │
  ├── manifest.json      짧은 TTL
  └── patch chunks       긴 TTL + immutable
```

즉시 조치:

- manifest TTL이 너무 짧아 반복 miss가 발생하는지 확인
- patch chunk path가 versioned path인지 확인
- 동일 chunk가 query string 때문에 여러 cache object로 분리되는지 확인
- origin shield 활성화 여부 확인
- 지역/비율 기반 staged rollout으로 동시 다운로드를 분산

## 5. 영상 트래픽 대응

```text
Player
  │
  ├── master manifest
  ├── media playlist
  └── segments
```

즉시 조치:

- VOD segment TTL이 충분히 긴지 확인
- live manifest TTL이 latency 목표보다 과도하게 짧지 않은지 확인
- popular segment가 cache hit되는지 확인
- DRM license API가 cache 대상에 잘못 포함되지 않았는지 확인
- 특정 ISP/region edge 문제인지 국가/ASN별로 분리

## 6. Origin 보호 조치

| 조치 | 적용 상황 | 주의 |
|------|-----------|------|
| Origin Shield 활성화 | 글로벌 edge miss가 origin으로 몰림 | shield region 선택 중요 |
| stale-if-error | origin 5xx 발생 시 정적 콘텐츠 보호 | 오래된 콘텐츠 허용 범위 필요 |
| stale-while-revalidate | 갱신 중 사용자 latency 완화 | 최신성 요구 낮은 콘텐츠에 적합 |
| negative caching | 반복 404/403 miss 차단 | 잘못된 404 캐시 TTL 과도 금지 |
| WAF rate limit | bot/abuse가 origin까지 도달 | 정상 peak와 구분 필요 |
| cache key 축소 | query/header/cookie 분산 과도 | 개인화 응답 캐시 금지 |

## 7. 에스컬레이션 기준

- hit ratio 회복 후에도 origin latency가 높으면 Nginx/App/DB runbook으로 전환
- CDN 5xx와 origin 5xx가 다르면 edge/origin 연결, TLS, DNS 확인
- 특정 지역만 문제면 multi-CDN, geo routing, ISP 이슈로 분리
- DB 부하가 함께 증가하면 API cache bypass 또는 cache key 폭증 가능성 우선 확인
