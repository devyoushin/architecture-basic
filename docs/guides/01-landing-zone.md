# 01. Landing Zone 전략

## 개요

Landing Zone은 멀티 어카운트 AWS 환경을 안전하고 일관되게 구성하기 위한 기반 프레임워크입니다.
AWS Control Tower를 기반으로 구성하며, 보안·거버넌스·운영 정책을 중앙에서 관리합니다.

---

## 구성 방식: AWS Control Tower

### Control Tower를 선택하는 이유

| 항목 | Control Tower | 수동 구성 |
|------|--------------|----------|
| 초기 구성 속도 | 빠름 (자동화) | 느림 |
| 거버넌스 일관성 | 높음 | 사람에 따라 다름 |
| AWS 업데이트 반영 | 자동 | 수동 추적 필요 |
| 커스터마이징 | 제한적 | 완전 자유 |

> **결론:** 신규 환경 구성 시 Control Tower를 기본으로 채택하고,
> 커스텀 요구사항은 Customizations for Control Tower (CfCT) 또는 AFT로 확장합니다.

---

## 핵심 구성 요소

### 1. Management Account (루트 계정)

- AWS Organizations의 최상위 계정
- Control Tower 배포 주체
- **절대 워크로드 배포 금지**
- MFA 필수, 사용자 접근 최소화
- Billing 및 Cost 관리 전담

### 2. Log Archive Account

- 전사 AWS 서비스 로그 중앙 집계
- 수집 대상 로그:
  - CloudTrail (전 계정 조직 Trail)
  - AWS Config 스냅샷 및 변경 이력
  - S3 Access Log
  - VPC Flow Log
- 로그 보존 정책: **최소 1년 (규정에 따라 조정)**
- 로그 버킷 설정:
  - S3 Object Lock 활성화 (WORM)
  - 버킷 정책으로 삭제 차단
  - 다른 계정에서 쓰기 전용 접근 허용

### 3. Audit Account

- 보안 감사 및 컴플라이언스 전담
- 사용 서비스:
  - AWS Security Hub (전 계정 통합)
  - Amazon GuardDuty (위협 탐지)
  - AWS Config Aggregator
  - Amazon Inspector
- 보안팀만 접근 가능 (IAM Identity Center로 권한 분리)

---

## Account Vending Machine (AVM)

신규 계정 생성 시 일관된 기준선(Baseline)을 자동으로 적용하는 프로세스입니다.

### 자동 적용 항목

```
신규 계정 생성 요청
        │
   Control Tower Account Factory
   또는 Account Factory for Terraform (AFT)
        │
   ┌────┴────────────────────────────┐
   │ 자동 적용 항목                    │
   │  - IAM Identity Center 연동     │
   │  - CloudTrail 활성화             │
   │  - AWS Config 활성화             │
   │  - Security Hub 연동             │
   │  - GuardDuty 활성화              │
   │  - 기본 SCP 상속                 │
   │  - 기본 VPC 삭제 (default VPC)   │
   └─────────────────────────────────┘
```

### AFT (Account Factory for Terraform) 사용 시

- Terraform으로 계정 프로비저닝 코드화
- Git 기반 워크플로우로 계정 요청/승인 관리
- 커스텀 Customization을 계정 타입별로 분리 적용 가능

---

## 보안 기준선 (Security Baseline)

모든 계정에 공통 적용되는 보안 설정입니다.

| 항목 | 설정 |
|------|------|
| 루트 계정 MFA | 필수 |
| 기본 VPC | 전 리전 삭제 |
| CloudTrail | 전 리전, 전 이벤트 활성화 |
| AWS Config | 전 리전 활성화 |
| EBS 암호화 기본값 | 활성화 |
| S3 퍼블릭 액세스 차단 | 계정 레벨 전체 차단 |
| IMDSv2 | 강제 적용 (SCP) |

---

## 멀티 리전 전략

| 구분 | 내용 |
|------|------|
| Primary Region | ap-northeast-2 (서울) |
| DR Region | ap-southeast-1 (싱가포르) — 필요 시 |
| Control Tower 홈 리전 | ap-northeast-2 |
| 거버넌스 적용 리전 | 사용 리전 전체 (미사용 리전은 SCP로 차단) |

---

## 관련 문서

- [02. OU 전략](./02-ou-strategy.md)
- [03. Account 전략](./03-account-strategy.md)
