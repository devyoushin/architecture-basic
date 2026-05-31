# 14. 백업 & DR 전략

## 개요

백업은 데이터 손실 복구를, DR(Disaster Recovery)은 서비스 전체 중단 복구를 목표로 합니다.
복구 목표(RTO/RPO)를 먼저 정의하고, 목표에 맞는 전략과 비용을 결정합니다.

---

## 복구 목표 정의

### RTO (Recovery Time Objective)

서비스가 중단된 시점부터 복구 완료까지 허용 가능한 최대 시간

### RPO (Recovery Point Objective)

복구 시 허용 가능한 최대 데이터 손실 시간 (마지막 백업 시점까지 손실 허용)

### 서비스 등급별 목표 설정 예시

| 등급 | 서비스 예시 | RTO | RPO | DR 전략 |
|------|-----------|-----|-----|--------|
| Tier 1 (Critical) | 결제, 인증 | < 15분 | < 1분 | Active-Active 또는 Active-Standby (Hot) |
| Tier 2 (High) | 핵심 업무 API | < 1시간 | < 15분 | Active-Standby (Warm) |
| Tier 3 (Medium) | 관리 도구, 배치 | < 4시간 | < 1시간 | Pilot Light |
| Tier 4 (Low) | 개발/테스트 환경 | < 24시간 | < 24시간 | Backup & Restore |

---

## DR 전략 패턴

### 1. Active-Active (Multi-Region)

```
ap-northeast-2 (서울)          ap-southeast-1 (싱가포르)
  Primary Region                DR Region
  [ALB + ECS + RDS]     ←→    [ALB + ECS + Aurora Read Replica]
        │                              │
   Route53 (지연 기반 라우팅 또는 Health Check 기반 Failover)
```

- 두 리전 모두 트래픽 처리 (Active-Active)
- Aurora Global Database로 리전 간 복제 (RPO < 1초)
- Route53 Health Check로 자동 Failover

### 2. Active-Standby Warm

```
ap-northeast-2 (Active)        ap-southeast-1 (Standby)
  [ALB + ECS(정상 규모) + RDS]  [ALB + ECS(최소 규모) + RDS Read Replica]
        │
   장애 발생 시 → Standby 리전 스케일 아웃 + DNS 전환 (RTO: 수십 분)
```

- Standby 리전에 최소 규모 유지 (비용 절감)
- 장애 시 수동 또는 자동으로 스케일 아웃 후 DNS 전환

### 3. Pilot Light

```
ap-northeast-2 (Active)        ap-southeast-1 (Pilot)
  [전체 스택 운영]               [DB만 복제, 앱 서버 없음]
                                   → 장애 시 CloudFormation으로 앱 배포
                                   (RTO: 1~4시간)
```

### 4. Backup & Restore

- DR 리전에 리소스 없음
- 정기 백업 → DR 리전 S3에 복사
- 장애 시 백업에서 전체 환경 재구성 (RTO: 수 시간 ~ 하루)

---

## AWS Backup 구성

### AWS Backup으로 중앙 관리

모든 계정의 백업 정책을 AWS Backup으로 중앙 관리합니다.

```
Management Account
  AWS Backup 조직 정책 (Backup Policy)
        │ Organizations 통해 자동 적용
        ▼
각 워크로드 계정
  자동 백업 실행 (계정별 별도 설정 불필요)
```

### 백업 정책 설계 (Backup Plan)

#### Tier 1 서비스용

| 항목 | 설정 |
|------|------|
| 백업 빈도 | 1시간 (연속 백업: Aurora, DynamoDB) |
| 보존 기간 | 35일 (일별), 12개월 (월별) |
| 크로스 리전 복사 | ap-southeast-1로 자동 복사 |
| 크로스 계정 복사 | Log Archive 계정으로 복사 |
| 암호화 | 고객 관리 KMS 키 |

#### Tier 2-3 서비스용

| 항목 | 설정 |
|------|------|
| 백업 빈도 | 매일 1회 (자정) |
| 보존 기간 | 35일 (일별), 12개월 (월별) |
| 크로스 리전 복사 | 선택적 |

### 지원 서비스

| AWS 서비스 | 백업 지원 |
|-----------|---------|
| Amazon EBS | 스냅샷 |
| Amazon RDS / Aurora | 자동 스냅샷 + 연속 백업 (PITR) |
| Amazon DynamoDB | 온디맨드 + 연속 백업 (PITR) |
| Amazon EFS | 백업 볼트 |
| Amazon S3 | S3 백업 (선택) |
| Amazon FSx | 백업 |
| AWS Storage Gateway | 스냅샷 |

---

## 데이터베이스 백업 상세

### Aurora / RDS

| 기능 | 내용 |
|------|------|
| 자동 백업 | 매일 백업 윈도우에 수행, 최대 35일 보존 |
| PITR (Point-in-Time Recovery) | 최근 5분 전 시점으로 복구 가능 |
| 스냅샷 | 수동 생성, 명시적 삭제 전까지 보존 |
| 크로스 리전 복사 | 스냅샷 → DR 리전으로 자동 복사 |
| Aurora Global Database | 리전 간 복제 (RPO < 1초, RTO < 1분) |

### DynamoDB

| 기능 | 내용 |
|------|------|
| PITR | 최근 35일 내 임의 시점 복구 |
| 온디맨드 백업 | 즉시 백업, 무기한 보존 |
| Global Table | 멀티 리전 활성 복제 (Active-Active) |
| Export to S3 | DynamoDB 데이터 S3로 내보내기 (분석용) |

---

## DR 훈련 (Disaster Recovery Drill)

DR 계획은 실제로 테스트하지 않으면 장애 시 작동을 보장할 수 없습니다.

### 훈련 유형

| 유형 | 주기 | 내용 |
|------|------|------|
| 백업 복구 테스트 | 월간 | 실제 백업에서 복구 후 데이터 정합성 확인 |
| 부분 Failover 테스트 | 분기 | 개별 서비스 DR 리전 전환 테스트 |
| 전체 DR 훈련 | 연간 | 전체 서비스 DR 리전 전환, 복구 시간 측정 |
| Chaos Engineering | 수시 | 프로덕션 환경 내 의도적 장애 주입 (카오스 몽키) |

### 훈련 체크리스트

- [ ] RTO/RPO 목표 달성 여부 측정
- [ ] 복구 절차 문서(Runbook) 최신 상태 확인
- [ ] 연락망 및 에스컬레이션 절차 확인
- [ ] 백업 데이터 무결성 검증
- [ ] 훈련 결과 기록 및 개선 사항 도출

---

## S3 데이터 보호

### 버킷별 보호 설정

| 데이터 유형 | 버전 관리 | 복제 | Object Lock |
|-----------|---------|------|-----------|
| 감사/규정 데이터 | 활성화 | 크로스 리전 | Compliance 모드 |
| 업무 데이터 | 활성화 | 크로스 리전 | — |
| 임시/캐시 데이터 | 비활성화 | — | — |

### S3 Cross-Region Replication (CRR)

```
Primary S3 (ap-northeast-2)
  신규 오브젝트 / 업데이트
        │ CRR 자동 복제
        ▼
DR S3 (ap-southeast-1)
  복제본 (읽기 전용)
```

- 복제 지연 일반적으로 수 초 ~ 수 분
- 삭제 마커 복제 여부 설정 가능 (의도치 않은 삭제 전파 방지 옵션)

---

## 관련 문서

- [13. 모니터링 & 관찰가능성 전략](./13-monitoring-observability.md)
- [04. VPC & Subnet 전략](./04-vpc-subnet.md)
- [06. Direct Connect 전략](./06-dx.md)
