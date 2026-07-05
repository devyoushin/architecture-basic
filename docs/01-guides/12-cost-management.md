# 12. 비용 관리 전략

## 개요

멀티 어카운트 환경에서는 비용이 여러 계정에 분산되어 가시성이 낮아지기 쉽습니다.
태깅 전략, 비용 배분, 예산 알람, 구매 전략을 조합하여
"누가, 어떤 서비스에, 얼마를 쓰는지" 실시간으로 파악합니다.

---

## 비용 관리 구조

```
Management Account
  AWS Cost Explorer (전 계정 통합 뷰)
  AWS Budgets (예산 알람)
  Cost and Usage Report (CUR) → S3 → Athena / QuickSight
        │
  계정별 비용 분리 (Linked Account)
        │
  태그 기반 비용 배분 (Cost Allocation Tag)
```

---

## 비용 가시성 확보

### Cost and Usage Report (CUR)

가장 세밀한 비용 데이터를 제공하는 원본 데이터입니다.

| 항목 | 설정 |
|------|------|
| 저장소 | Log Archive 계정 S3 버킷 |
| 형식 | Parquet (Athena 쿼리 최적화) |
| 시간 단위 | Hourly |
| 리소스 ID 포함 | 활성화 |

### Athena + QuickSight 분석 구성

```
CUR (S3)
  │
AWS Glue Crawler (스키마 자동 감지)
  │
Amazon Athena (SQL 쿼리)
  │
Amazon QuickSight (시각화 대시보드)
```

**주요 대시보드 항목:**
- 계정별 월간 비용 추이
- 서비스별 비용 분포
- 태그별 (팀/프로젝트/환경) 비용 배분
- 미태깅 리소스 비용 (태깅 누락 모니터링)

---

## 예산 (AWS Budgets) 설정

### 예산 유형 및 설정 기준

| 예산 유형 | 대상 | 알람 임계값 |
|---------|------|-----------|
| 전사 월 예산 | Management Account | 80%, 100% |
| 계정별 월 예산 | 각 워크로드 계정 | 80%, 100% |
| 서비스별 예산 | EC2, RDS, NAT GW 등 고비용 서비스 | 70%, 90% |
| Dev 환경 예산 | Dev/Sandbox 계정 | 50%, 80% |

### 예산 알람 자동화

```
AWS Budgets 임계값 초과
        │
SNS Topic
        │
  ┌─────┴──────────┐
Slack 알람       Lambda
               (EC2 Stop, 알림 티켓 생성)
```

### Budgets Action (자동 제어)

임계값 도달 시 SCP 또는 IAM 정책을 자동 적용하여 추가 리소스 생성을 차단합니다.

```
Dev 계정 예산 80% 도달
  → Budgets Action: SCP 적용 (EC2 생성 차단)
  → Slack 알람: "Dev 계정 예산 80% 도달, 신규 EC2 생성 차단됨"
```

---

## 비용 배분 (Cost Allocation)

### 계층별 비용 배분 방식

| 레벨 | 방법 | 세밀도 |
|------|------|--------|
| 계정 레벨 | Linked Account 분리 | 계정 단위 |
| 팀/프로젝트 레벨 | Cost Allocation Tag | 태그 단위 |
| 서비스 레벨 | 서비스별 필터링 | 서비스 단위 |

### 공유 비용 배분 처리

Network Account (TGW, DX 등) 비용은 특정 팀에 귀속되지 않으므로 배분 기준이 필요합니다.

| 공유 비용 항목 | 배분 방식 |
|-------------|---------|
| TGW 데이터 처리 비용 | VPC 트래픽 비율로 배분 |
| Direct Connect 포트 비용 | 계정 수 균등 배분 또는 트래픽 비율 |
| Shared Services 계정 비용 | 사용 계정 수 균등 배분 |
| Log Archive S3 비용 | 계정별 로그 용량 비율 배분 |

---

## 구매 전략 (Savings Plans & Reserved Instance)

### 비용 절감 도구 비교

| 도구 | 할인율 | 유연성 | 적용 대상 |
|------|------|------|---------|
| On-Demand | 0% | 최고 | 예측 불가 워크로드 |
| Savings Plans (Compute) | 최대 66% | 높음 | EC2, Lambda, Fargate 전체 |
| Savings Plans (EC2 Instance) | 최대 72% | 낮음 | 특정 인스턴스 패밀리 |
| Reserved Instance | 최대 72% | 낮음 | EC2, RDS, ElastiCache 등 |
| Spot Instance | 최대 90% | 중단 가능 | 내결함성 워크로드 (배치, CI/CD) |

### 구매 원칙

```
1. Spot Instance 최대 활용 (내결함성 워크로드)
   → ECS/EKS 워크로드, CI/CD 빌드, 배치 처리

2. Savings Plans (Compute) 구매
   → 최근 3개월 On-Demand 사용량의 70~80%를 1년 약정으로 구매
   → 인스턴스 타입/리전 변경에 유연

3. Reserved Instance
   → RDS, ElastiCache 등 Savings Plans 미적용 서비스에만 사용
   → 1년 단위, 부분 선결제(Partial Upfront) 권장

4. On-Demand 유지
   → 예측 불가한 피크 트래픽, 신규 서비스 초기 운영
```

### 구매 시기 및 검토 주기

| 활동 | 주기 |
|------|------|
| Savings Plans 적용 현황 검토 | 월간 |
| 신규 Savings Plans 구매 검토 | 분기 |
| RI 만료 예정 확인 및 갱신 | 만료 2개월 전 |
| Spot 활용률 검토 | 월간 |

---

## 비용 최적화 체크리스트

### 컴퓨팅
- [ ] 미사용 EC2 인스턴스 중지/종료
- [ ] 과도하게 프로비저닝된 인스턴스 다운사이징 (AWS Compute Optimizer 활용)
- [ ] Dev/Stg 환경 야간/주말 자동 중지 (Instance Scheduler)
- [ ] Spot Instance 활용 가능한 워크로드 전환

### 스토리지
- [ ] S3 스토리지 클래스 최적화 (S3 Intelligent-Tiering 또는 Lifecycle Policy)
- [ ] 미첨부 EBS 볼륨 삭제
- [ ] 오래된 EBS 스냅샷 정리 (보존 정책 외)
- [ ] RDS 스토리지 자동 확장 상한 설정

### 네트워크
- [ ] 미사용 Elastic IP 해제
- [ ] AZ 간 데이터 전송 최소화 (AZ 로컬 통신 우선)
- [ ] NAT Gateway 대신 VPC Endpoint 활용 가능한 서비스 전환
- [ ] CloudFront 캐싱으로 Origin 트래픽 절감

### 데이터베이스
- [ ] Dev 환경 RDS 야간 자동 중지 (Aurora Serverless 전환 검토)
- [ ] 읽기 전용 워크로드 Read Replica 활용
- [ ] 미사용 RDS 스냅샷 정리

---

## 비용 이상 탐지 (Cost Anomaly Detection)

AWS Cost Anomaly Detection으로 비용 급증을 자동 탐지합니다.

| 모니터 유형 | 탐지 대상 |
|-----------|---------|
| AWS Service | 서비스별 비용 급증 |
| Linked Account | 계정별 비용 급증 |
| Cost Category | 비용 카테고리별 급증 |
| Cost Allocation Tag | 팀/프로젝트별 비용 급증 |

**알람 설정:**
- 절대값 기준: $100 이상 초과 시 알람
- 비율 기준: 전주 대비 20% 이상 증가 시 알람
- 알람 채널: 이메일, Slack

---

## 관련 문서

- [15. 태깅 전략](./15-tagging.md)
- [03. Account 전략](./03-account-strategy.md)
