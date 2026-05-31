# 13. 모니터링 & 관찰가능성 전략

## 개요

관찰가능성(Observability)은 로그(Logs), 메트릭(Metrics), 트레이스(Traces)
세 가지 신호를 통해 시스템 내부 상태를 외부에서 파악할 수 있는 능력입니다.
멀티 어카운트 환경에서는 이 세 가지 신호를 중앙으로 집계하여
운영팀이 단일 뷰에서 전체 환경을 모니터링할 수 있게 합니다.

---

## 관찰가능성 3요소

| 신호 | AWS 서비스 | 중앙화 방법 |
|------|----------|-----------|
| Logs | CloudWatch Logs | CloudWatch Logs 크로스 어카운트 구독 |
| Metrics | CloudWatch Metrics | CloudWatch 크로스 어카운트 관찰 |
| Traces | AWS X-Ray | X-Ray 크로스 어카운트 집계 |

---

## 중앙 모니터링 아키텍처

```
각 워크로드 계정
  CloudWatch Logs
  CloudWatch Metrics
  X-Ray Traces
        │
   크로스 어카운트 공유
        ▼
Shared Services Account (모니터링 허브)
  Amazon Managed Grafana  ← 통합 대시보드
  Amazon Managed Prometheus ← 메트릭 집계 (컨테이너 환경)
  Amazon OpenSearch Service ← 로그 검색/분석 (선택)
```

---

## 로그 (Logs)

### CloudWatch Logs 크로스 어카운트 구독

각 계정의 로그를 Shared Services 또는 Log Archive 계정으로 중앙 집계합니다.

```
워크로드 계정 CloudWatch Logs
        │
   Subscription Filter
        │
   Kinesis Data Firehose (크로스 어카운트)
        │
  ┌─────┴──────────────┐
S3 (Log Archive)   OpenSearch (실시간 검색)
```

### 로그 분류 및 보존 정책

| 로그 유형 | 보존 기간 (CloudWatch) | 장기 보존 (S3) |
|---------|---------------------|--------------|
| 애플리케이션 로그 | 30일 | 1년 (Intelligent-Tiering) |
| 인프라 로그 (VPC Flow, ALB) | 7일 | 1년 |
| 보안 감사 로그 (CloudTrail) | 90일 | 7년 (Object Lock) |
| 데이터베이스 감사 로그 | 30일 | 1년 |

### 구조화 로그 (Structured Logging) 권장

```json
{
  "timestamp": "2026-04-09T10:00:00Z",
  "level": "ERROR",
  "service": "payment-api",
  "trace_id": "1-xxx-yyy",
  "user_id": "u-123",
  "message": "결제 처리 실패",
  "error_code": "PAYMENT_DECLINED",
  "latency_ms": 234
}
```

- JSON 형식으로 구조화하여 CloudWatch Logs Insights 쿼리 효율화
- `trace_id` 포함으로 X-Ray 트레이스와 연동

---

## 메트릭 (Metrics)

### CloudWatch 크로스 어카운트 관찰

Shared Services 계정의 Grafana에서 다른 계정의 CloudWatch 메트릭을 직접 조회합니다.

```
Shared Services Account (Grafana)
        │ CloudWatch 크로스 어카운트 역할 AssumeRole
        ▼
각 워크로드 계정 CloudWatch Metrics 조회
```

**설정 방법:**
- 각 워크로드 계정에 `monitoring-cross-account-role` 생성
- Grafana에서 해당 역할을 AssumeRole하여 메트릭 쿼리

### 핵심 메트릭 항목

#### 컴퓨팅 (EC2 / ECS / EKS)

| 메트릭 | 임계값 (예시) | 알람 |
|-------|-----------|------|
| CPU Utilization | > 80% (5분 지속) | Warning |
| Memory Utilization | > 85% (5분 지속) | Warning |
| Disk I/O Wait | > 50% | Warning |
| ECS Service Running Count | < Desired Count | Critical |

#### 데이터베이스 (RDS / Aurora)

| 메트릭 | 임계값 | 알람 |
|-------|-------|------|
| CPUUtilization | > 80% | Warning |
| FreeableMemory | < 500MB | Warning |
| DatabaseConnections | > 80% of max | Warning |
| ReplicaLag | > 60초 | Critical |
| FreeStorageSpace | < 10% | Critical |

#### 네트워크

| 메트릭 | 임계값 | 알람 |
|-------|-------|------|
| ALB TargetResponseTime | > 1초 (p99) | Warning |
| ALB HTTPCode_Target_5XX_Count | > 1% of requests | Critical |
| NAT Gateway PacketDropCount | > 0 | Warning |
| TGW BytesDropCountBlackhole | > 0 | Critical |

### Amazon Managed Prometheus (컨테이너 환경)

EKS 클러스터의 메트릭은 Prometheus 형식으로 수집합니다.

```
EKS 클러스터
  Prometheus Operator + node-exporter
  kube-state-metrics
        │ Remote Write
        ▼
Amazon Managed Prometheus (Shared Services Account)
        │
Amazon Managed Grafana
```

---

## 트레이스 (Traces)

### AWS X-Ray 분산 추적

마이크로서비스 간 요청 흐름을 추적하여 지연 원인을 정확히 파악합니다.

```
클라이언트 요청
      │ trace_id 생성
      ▼
API Gateway (세그먼트)
      │
Lambda / ECS (서브세그먼트)
      │
RDS / DynamoDB / External API (서브세그먼트)
      │
X-Ray → Service Map 시각화
```

### 샘플링 전략

전체 트레이스를 수집하면 비용이 증가하므로 샘플링 규칙을 설정합니다.

| 규칙 | 비율 |
|------|------|
| 기본 샘플링 | 5% (초당 최소 1개 보장) |
| 오류 응답 (5xx) | 100% (오류는 전수 수집) |
| 지연 > 2초 | 100% (느린 요청 전수 수집) |
| Health Check 경로 | 0% (불필요한 노이즈 제거) |

---

## 알람 및 대응

### 알람 라우팅 구조

```
CloudWatch Alarm 발생
        │
   SNS Topic
        │
  ┌─────┴────────────────────────────────┐
  │              │                       │
Slack 채널   PagerDuty             Lambda (자동 대응)
(#alerts-info) (On-Call 호출)      (Auto Scaling, 재시작 등)
```

### 알람 심각도 분류

| 심각도 | 조건 | 채널 | 대응 시간 |
|------|------|------|---------|
| Critical | 서비스 중단, 데이터 손실 위험 | PagerDuty + Slack | 즉시 (5분 내) |
| Warning | 성능 저하, 임계값 근접 | Slack | 30분 내 |
| Info | 이상 없음, 참고 사항 | Slack (별도 채널) | 다음 근무일 |

### 알람 피로도(Alert Fatigue) 방지 원칙

- 알람은 **대응이 필요한 것만** 설정 (노이즈 최소화)
- 동일 알람 반복 발생 시 **억제(Suppression)** 적용
- 정기 점검: 3개월 내 한 번도 발생 안 한 알람은 재검토
- 알람 문서화: 알람별 대응 Runbook 링크 첨부

---

## 대시보드 구성

### Grafana 대시보드 계층

| 대시보드 | 대상 | 내용 |
|---------|------|------|
| Executive Summary | 경영진 | 전사 서비스 가용성, 비용 요약 |
| Service Health | 운영팀 | 서비스별 가용성, 에러율, 응답 시간 |
| Infrastructure | 인프라팀 | EC2, RDS, 네트워크 상세 메트릭 |
| Security | 보안팀 | GuardDuty Finding, WAF 차단 현황 |
| Cost | 재무/경영진 | 계정별, 팀별 비용 추이 |

---

## 관련 문서

- [11. 보안 서비스 운영](./11-security-services.md)
- [14. 백업 & DR 전략](./14-backup-dr.md)
