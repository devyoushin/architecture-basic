# 03. Account 전략

## 개요

멀티 어카운트 구조는 보안 경계 확보, 폭발 반경(Blast Radius) 최소화,
비용 가시성 확보를 위한 AWS 권장 전략입니다.

---

## 계정 분리 기준

### 분리 기준 우선순위

```
1순위: 환경 (Production / Staging / Dev)
2순위: 서비스 도메인 (필요 시)
3순위: 팀 / 조직 단위 (선택적)
```

> **원칙:** 계정은 보안 경계이자 비용 단위입니다.
> 계정이 너무 많으면 관리 복잡도가 증가하고,
> 너무 적으면 환경 간 격리가 깨집니다.

---

## 공통(Foundation) 계정 구성

멀티 어카운트 환경에서 모든 워크로드 계정이 공유하는 기반 계정들입니다.

### 계정 목록

| 계정명 | OU | 목적 |
|--------|----|------|
| Management | Root | AWS Organizations 관리, Billing |
| Log Archive | Security OU | 전사 로그 중앙 수집 |
| Audit | Security OU | 보안 감사, Security Hub 통합 |
| Network | Infrastructure OU | TGW, DX, Route53 Resolver 관리 |
| Shared Services | Infrastructure OU | 공용 도구 (CICD, 모니터링, AMI 등) |

---

### Management Account

```
역할: AWS Organizations 최상위 관리
      Control Tower 홈, Billing 통합, SCP 관리

제약:
  - 워크로드 배포 절대 금지
  - 루트 계정 MFA 필수
  - 접근 가능 인원 최소화 (2-3명)
  - 장기 IAM 사용자 생성 금지 (IAM Identity Center만 사용)
```

---

### Log Archive Account

```
역할: 전사 로그 수집 및 장기 보존

수집 로그:
  - CloudTrail (조직 Trail → S3)
  - AWS Config 스냅샷 및 변경 이력
  - VPC Flow Log (각 계정 → 중앙 S3)
  - ALB / NLB Access Log
  - S3 Server Access Log

S3 버킷 보호:
  - S3 Object Lock (Compliance 모드, 보존 기간 1년 이상)
  - 버킷 정책: 쓰기 전용 허용, 삭제 명시적 Deny
  - MFA Delete 활성화
  - Bucket Versioning 활성화
```

---

### Audit Account

```
역할: 보안 상태 가시성 및 컴플라이언스

사용 서비스:
  - AWS Security Hub (전 계정 Administrator)
  - Amazon GuardDuty (전 계정 Administrator)
  - AWS Config Aggregator (전 계정 집계)
  - Amazon Inspector (취약점 스캔)
  - AWS Firewall Manager (WAF/SG 정책 중앙 관리)

접근 제한:
  - 보안팀 전용 Permission Set (IAM Identity Center)
  - 읽기 권한 중심, 수정 권한 최소화
```

---

### Network Account

```
역할: 전사 네트워크 허브

관리 리소스:
  - Transit Gateway (TGW) — 전 계정 VPC 연결 허브
  - Direct Connect Gateway (DXGW) — 온프레미스 연결
  - Route53 Resolver — 중앙 DNS 관리
  - AWS Network Firewall — 트래픽 검사 (선택)
  - VPC (Hub VPC) — 공유 서비스용 중앙 VPC

접근 제한:
  - 네트워크/인프라팀 전용
  - 라우팅 변경은 변경 관리 프로세스 필수
```

---

### Shared Services Account

```
역할: 전사 공용 도구 및 서비스 제공

호스팅 서비스 예시:
  - CI/CD 파이프라인 (GitHub Actions Runner, Jenkins, CodePipeline)
  - Amazon ECR (컨테이너 이미지 공용 레지스트리)
  - 공용 AMI 빌드 (EC2 Image Builder)
  - 중앙 모니터링 (Grafana, Prometheus, Amazon Managed Grafana)
  - 내부 패키지 저장소 (CodeArtifact)
  - AWS Systems Manager (패치 관리, Session Manager)
```

---

## 워크로드 계정 구성

### 환경별 분리 원칙

```
Production 계정
  - 독립된 네트워크 (VPC)
  - 최소 권한 IAM (개발자 직접 접근 제한)
  - 변경 관리 프로세스 적용
  - 고가용성 구성 필수

Staging 계정
  - Production과 동일한 아키텍처 유지
  - 비용 절감을 위한 인스턴스 사이즈 조정 허용
  - 배포 전 최종 검증 환경

Dev 계정
  - 개발자 상대적으로 넓은 권한 허용
  - 비용 제한 SCP 적용
  - 야간/주말 자동 리소스 중지 권장
```

### 서비스 도메인별 계정 분리 기준

계정 수가 너무 많아지면 관리 오버헤드가 증가합니다.
아래 기준을 충족할 때 별도 계정으로 분리를 검토합니다:

| 기준 | 설명 |
|------|------|
| 규정 준수 | PCI-DSS, HIPAA 등 별도 컴플라이언스 요건 |
| 독립 팀 운영 | 별도 팀이 독자적으로 운영하는 서비스 |
| 비용 독립성 | 비용 센터가 다른 서비스 |
| 보안 민감도 | 다른 서비스와 격리가 필요한 고보안 워크로드 |

---

## IAM Identity Center (SSO) 연동

모든 계정 접근은 IAM Identity Center를 통해 중앙 관리합니다.

```
사용자 디렉토리 (AD 또는 IdP)
        │ SAML/SCIM
   IAM Identity Center
        │
   Permission Set 매핑
   ┌────┴──────────────────────────┐
   │ Admin PS    │ Developer PS    │ ReadOnly PS
   │ (인프라팀)  │ (개발팀)        │ (감사/경영진)
   └─────────────┴─────────────────┘
        │
   각 계정별 Role로 위임 (AssumeRole)
```

### Permission Set 예시

| Permission Set | 대상 | 주요 권한 |
|---------------|------|----------|
| NetworkAdmin | 네트워크팀 | TGW, DX, VPC 관리 |
| Developer | 개발팀 | EC2, ECS, RDS, S3 (생산 읽기 전용) |
| SecurityAuditor | 보안팀 | Security Hub, GuardDuty, Config 읽기 |
| ReadOnly | 경영진, 감사 | 전체 읽기 전용 |
| BillingViewer | 재무팀 | Cost Explorer, Billing 읽기 |

---

## 관련 문서

- [02. OU 전략](./02-ou-strategy.md)
- [04. VPC & Subnet 전략](./04-vpc-subnet.md)
