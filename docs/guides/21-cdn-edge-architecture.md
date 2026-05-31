# CDN & Edge 아키텍처 전략

## 1. 개요

CDN(Content Delivery Network)은 정적 파일을 빠르게 전달하는 캐시 계층을 넘어, 대규모 트래픽을 흡수하고 오리진(origin)을 보호하는 핵심 아키텍처 계층입니다. 게임 회사, 영상 스트리밍 회사, 글로벌 SaaS처럼 트래픽이 특정 이벤트나 지역에 몰리는 서비스는 CDN 설계를 별도 아키텍처 주제로 다뤄야 합니다.

```text
User
  │
  ▼
CDN Edge
  │  cache hit
  ├──────────────▶ Response
  │
  │ cache miss
  ▼
Origin Shield / Regional Edge
  │
  ▼
Origin ALB / S3 / Media Origin
  │
  ▼
App / Storage / DB
```

핵심 목표는 다음과 같습니다.

| 목표 | 설명 |
|------|------|
| Latency 감소 | 사용자와 가까운 edge에서 응답 |
| Origin 보호 | cache hit, request collapsing, shield로 원본 부하 감소 |
| 비용 최적화 | origin egress, compute, DB read 부하 감소 |
| 글로벌 확장 | 지역별 edge POP을 활용한 트래픽 분산 |
| 보안 강화 | WAF, bot control, signed URL/cookie, DDoS 완화 |

## 2. CDN을 반드시 고려해야 하는 서비스

| 서비스 유형 | CDN 필요 이유 |
|-------------|---------------|
| 게임 | 패치 파일, 런처 리소스, 이벤트 배너, 이미지, replay asset 대량 다운로드 |
| 영상 서비스 | HLS/DASH segment, thumbnail, subtitle, manifest 전달 |
| 이커머스 | 상품 이미지, 검색/프로모션 트래픽 급증 흡수 |
| 글로벌 SaaS | 정적 asset, frontend bundle, API edge protection |
| 교육/라이브 서비스 | VOD, 교재 asset, 라이브 이벤트 트래픽 분산 |

## 3. 기본 아키텍처 패턴

### 3.1 S3 Origin 기반 정적 콘텐츠

```text
User
  │
  ▼
CloudFront
  │
  ▼
S3 Origin
```

적합한 경우:

- 이미지, JS/CSS, 다운로드 파일
- 게임 런처 리소스
- 패치 manifest
- 영상 thumbnail/subtitle

주요 설정:

- S3 public access 차단
- Origin Access Control(OAC) 사용
- cache policy와 origin request policy 분리
- versioned object path 사용
- invalidation 최소화

### 3.2 ALB Origin 기반 동적 API 보호

```text
User
  │
  ▼
CloudFront + WAF
  │
  ▼
ALB
  │
  ▼
ECS/EKS/EC2 App
  │
  ▼
RDS/Cache
```

적합한 경우:

- API 앞단 보호
- Bot/abuse 제어
- TLS/WAF 중앙화
- region edge cache가 가능한 GET API

주의:

- 인증/개인화 응답은 cache key 설계가 중요함
- `Authorization`, `Cookie`, query string forwarding을 무조건 켜면 cache hit ratio가 급감함
- API cache는 TTL을 짧게 두고 stale 정책을 명확히 해야 함

### 3.3 Origin Shield 패턴

```text
Edge POPs
  │
  ▼
Origin Shield
  │
  ▼
Origin
```

여러 edge location에서 동일 object를 동시에 요청할 때 origin miss storm을 줄이는 패턴입니다.

적합한 경우:

- 글로벌 사용자가 같은 파일을 동시에 다운로드
- 게임 대규모 패치 배포
- 영상 인기 콘텐츠 segment 요청 집중
- origin이 S3가 아니라 ALB/EC2/Nginx처럼 비용/부하에 민감한 경우

## 4. 게임 회사 CDN 아키텍처

게임 서비스는 “패치 배포”와 “실시간 API”를 분리해야 합니다.

```text
Game Client
  │
  ├── Patch/Asset Download ─▶ CDN ─▶ S3 Origin
  │
  ├── Login/API ───────────▶ CDN/WAF 또는 ALB ─▶ API Service ─▶ DB/Cache
  │
  └── Realtime Game Traffic ─▶ NLB/UDP/TCP ─▶ Game Server
```

### 4.1 패치/에셋 다운로드

권장:

- object path에 version 포함: `/patch/v2026.05.31/...`
- manifest는 짧은 TTL, 대용량 chunk는 긴 TTL
- chunk 파일은 immutable 처리
- 사전 warming은 제한적으로 사용
- origin shield 사용
- regional rollout로 한 번에 모든 유저가 같은 파일을 받지 않도록 제어

예시 TTL:

| 콘텐츠 | TTL |
|--------|-----|
| patch chunk | 7일~1년 |
| manifest | 30초~5분 |
| launcher config | 1분~10분 |
| event banner | 5분~1시간 |

### 4.2 게임 API

권장:

- 로그인, 결제, 인벤토리 API는 캐시하지 않음
- 공지, 이벤트, 점검 정보는 짧은 TTL 캐시 가능
- WAF rate-based rule로 abuse 방어
- CloudFront Function 또는 Lambda@Edge로 header normalization
- API origin은 ALB/EKS 앞단에서 autoscaling

### 4.3 실시간 게임 트래픽

CDN은 실시간 UDP/TCP 게임 세션 자체를 처리하는 계층이 아닙니다. 실시간 게임 트래픽은 보통 Global Accelerator, NLB, Anycast/전용 네트워크, 지역별 game server placement로 설계합니다.

| 트래픽 | 권장 경로 |
|--------|-----------|
| 패치/asset | CDN + S3 |
| 공지/이벤트 API | CDN short TTL + ALB |
| 로그인/결제/API | WAF + ALB |
| 실시간 게임 세션 | Global Accelerator/NLB/Game Server |

## 5. 영상 서비스 CDN 아키텍처

영상 서비스는 encoding/transcoding, origin storage, segment delivery, DRM, player telemetry를 분리해야 합니다.

```text
Upload
  │
  ▼
Transcoding Pipeline
  │
  ▼
S3 Media Origin
  │
  ▼
CDN
  │
  ▼
Player
```

### 5.1 HLS/DASH 전달

영상은 보통 작은 segment 파일을 연속적으로 요청합니다.

| 파일 | 특성 | TTL |
|------|------|-----|
| master manifest | bitrate 목록 | 짧음 |
| media playlist | segment 목록 | live는 매우 짧음, VOD는 김 |
| segment `.ts`/`.m4s` | 실제 미디어 조각 | VOD는 길게 |
| thumbnail | 정적 이미지 | 길게 |
| subtitle | 정적 텍스트 | 길게 |

VOD는 cache hit ratio를 높이기 쉽지만, live는 manifest가 자주 바뀌므로 TTL 설계가 더 중요합니다.

### 5.2 VOD와 Live 차이

| 항목 | VOD | Live |
|------|-----|------|
| 콘텐츠 변경 | 거의 없음 | 계속 변경 |
| segment TTL | 길게 | 짧게 |
| manifest TTL | 중간~길게 | 매우 짧게 |
| latency 목표 | 수 초~수십 초 허용 | low latency 요구 가능 |
| origin 부하 | 인기 콘텐츠 편중 | 이벤트 시간 집중 |

### 5.3 DRM/Signed URL

권장:

- premium 영상은 signed URL 또는 signed cookie 사용
- token TTL은 재생 세션 기준으로 제한
- DRM license API는 캐시하지 않음
- manifest/segment 접근 권한과 license 권한을 분리
- hotlink 방지를 위해 referer만 믿지 않음

## 6. Cache Key 설계

CDN 성능의 대부분은 cache key 설계에서 결정됩니다.

| 요소 | 권장 |
|------|------|
| Host | 서비스별 domain 분리 |
| Path | versioned path 사용 |
| Query string | 필요한 key만 whitelist |
| Header | cache에 필요한 header만 forward |
| Cookie | 정적 콘텐츠에서는 forward 금지 |
| Authorization | 개인화 API가 아니면 forward 금지 |
| Accept-Encoding | gzip/br 분기만 허용 |

잘못된 예:

```text
Cache Key = path + all query strings + all headers + all cookies
```

이 구조는 사용자마다 다른 cache object를 만들기 때문에 hit ratio가 급락합니다.

좋은 예:

```text
Cache Key = host + normalized path + allowed query keys + accept-encoding
```

## 7. Origin 보호 전략

| 전략 | 설명 |
|------|------|
| Origin Shield | 여러 edge miss를 한 지역으로 수렴 |
| Request Collapsing | 동일 object 동시 miss를 하나의 origin request로 축소 |
| Stale-if-error | origin 장애 시 stale object 반환 |
| Stale-while-revalidate | 사용자에게 stale 응답 후 백그라운드 갱신 |
| Rate Limit | 비정상 요청 origin 도달 전 차단 |
| Negative Caching | 404/403도 짧게 캐시해 반복 miss 방지 |
| Compression | edge에서 gzip/br 적용 |

## 8. 모니터링 지표

| 계층 | 지표 |
|------|------|
| CDN | cache hit ratio, origin latency, 4xx/5xx, bytes downloaded, request count |
| Origin ALB | TargetResponseTime, TargetConnectionErrorCount, HTTPCode_Target_5XX |
| Nginx | request_time, upstream_response_time, active/waiting connections |
| S3 Origin | 4xx/5xx, FirstByteLatency, TotalRequestLatency |
| DB | CPU, connection, slow query, lock wait, read/write latency |

CDN을 쓰더라도 origin과 DB 모니터링은 반드시 유지해야 합니다. CDN cache hit이 낮아지는 순간 origin과 DB가 직접 부하를 받습니다.

## 9. 장애 패턴

| 장애 | 원인 | 대응 |
|------|------|------|
| cache hit ratio 급락 | cache key 변경, query/header forwarding 증가 | cache policy rollback |
| origin 5xx 급증 | cache miss storm, origin scale 부족 | origin shield, scale-out, stale-if-error |
| 게임 패치 중 origin egress 폭증 | manifest TTL 짧음, chunk versioning 미흡 | chunk immutable, staged rollout |
| 영상 재생 중 buffering 증가 | segment latency, origin saturation | popular object cache, multi-CDN 검토 |
| signed URL 오류 증가 | clock skew, token TTL 과소 | TTL/clock sync 확인 |
| 특정 국가 latency 증가 | edge/ISP 문제 | geo routing, multi-CDN, Regional Edge 분석 |

## 10. 관련 운영 자산

- `../../ops/runbooks/nginx-overload-response.md`
- `../../ops/runbooks/db-overload-response.md`
- `../../ops/runbooks/cdn-origin-overload-response.md`
- `../../ops/monitoring/cdn-log-insights-queries.md`
- `../../ops/nginx/nginx-tuning.conf`
