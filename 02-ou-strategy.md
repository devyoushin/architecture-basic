# 02. OU (Organizational Unit) 전략

## 개요

OU는 AWS Organizations에서 계정을 논리적으로 그룹화하는 단위입니다.
OU 단위로 SCP(Service Control Policy)를 적용하여 계정별 권한 경계를 일관되게 관리합니다.

---

## OU 계층 구조

```
Root
├── Security OU
│   ├── Log Archive Account
│   └── Audit Account
│
├── Infrastructure OU
│   ├── Network Account
│   └── Shared Services Account
│
├── Workload OU
│   ├── Production OU
│   │   ├── Prod-ServiceA Account
│   │   └── Prod-ServiceB Account
│   ├── Staging OU
│   │   └── Stg-ServiceA Account
│   └── Dev OU
│       └── Dev-ServiceA Account
│
├── Sandbox OU
│   └── 개발자 개인 실습 계정
│
└── Suspended OU
    └── 비활성화 예정 계정
```

---

## OU별 목적 및 SCP 설계

### Security OU

| 항목 | 내용 |
|------|------|
| 목적 | 보안 감사, 로그 수집 전담 |
| 접근 대상 | 보안팀 Only |
| 핵심 SCP | 로그 버킷 삭제 금지, CloudTrail 비활성화 금지 |

**적용 SCP 예시:**
```json
{
  "Effect": "Deny",
  "Action": [
    "cloudtrail:DeleteTrail",
    "cloudtrail:StopLogging",
    "s3:DeleteBucket"
  ],
  "Resource": "*"
}
```

---

### Infrastructure OU

| 항목 | 내용 |
|------|------|
| 목적 | 네트워크, 공유 서비스 관리 |
| 접근 대상 | 인프라팀 |
| 핵심 SCP | 리전 제한, TGW 외부 공유 금지 |

---

### Workload OU

환경(Prod / Stg / Dev)별로 하위 OU를 분리하여 SCP를 계층적으로 적용합니다.

#### Production OU SCP
```json
{
  "Effect": "Deny",
  "Action": [
    "ec2:TerminateInstances",
    "rds:DeleteDBInstance"
  ],
  "Resource": "*",
  "Condition": {
    "StringNotEquals": {
      "aws:PrincipalTag/Role": "admin"
    }
  }
}
```

| OU | 주요 제한 |
|----|----------|
| Production OU | 인스턴스 임의 종료 금지, 삭제 보호 강제 |
| Staging OU | 고비용 인스턴스 타입 제한 |
| Dev OU | 특정 리전 외 리소스 생성 금지, 비용 임계 제한 |

---

### Sandbox OU

| 항목 | 내용 |
|------|------|
| 목적 | 개발자 자유 실습 환경 |
| 핵심 SCP | 비용 상한 리소스 타입 제한 (예: p4d, trn1 금지), 프로덕션 리전 외 사용 제한 |
| 계정 정리 | 주기적 자동 삭제 또는 리셋 정책 적용 |

---

### Suspended OU

- 퇴역 예정 계정 임시 보관
- 강력한 Deny-All SCP 적용 (신규 리소스 생성 불가)
- 일정 기간 후 계정 삭제 프로세스 진행

---

## SCP 설계 원칙

### 1. 계층적 상속 이해

```
Root SCP (전사 공통)
    └── OU SCP (OU 공통)
            └── 계정 SCP (계정 개별)
```

- 상위 OU의 SCP는 하위 OU/계정 모두에 상속됨
- Allow가 아닌 **Deny 기반**으로 설계 (Deny가 항상 우선)
- 계정 IAM 정책과 SCP의 교집합만 허용됨

### 2. 필수 공통 SCP (Root 적용)

| SCP | 목적 |
|-----|------|
| Deny 루트 계정 사용 | 루트 자격증명 사용 차단 |
| Deny 미승인 리전 | 허가된 리전 외 리소스 생성 차단 |
| Deny IMDSv1 | 메타데이터 서비스 v1 사용 차단 |
| Deny S3 퍼블릭 ACL | 공개 ACL 설정 차단 |
| Deny GuardDuty 비활성화 | 위협 탐지 무력화 방지 |
| Deny Config 비활성화 | 컴플라이언스 감사 무력화 방지 |

### 3. SCP 작성 시 주의사항

- SCP는 **IAM 정책을 대체하지 않음** — 최대 권한 경계 역할
- Management Account에는 SCP 적용 안 됨
- 서비스 연결 역할(Service-Linked Role)은 SCP 우회 가능한 경우 있음
- 너무 많은 SCP 중첩은 디버깅 어려움 → **OU 레벨 집중 관리** 권장

---

## 관련 문서

- [01. Landing Zone 전략](./01-landing-zone.md)
- [03. Account 전략](./03-account-strategy.md)
