# 10. IAM 전략

## 개요

멀티 어카운트 환경에서 IAM은 단순한 사용자/역할 관리를 넘어
계정 간 권한 위임, 권한 경계 설정, 감사 추적의 핵심입니다.
모든 접근은 IAM Identity Center를 통해 중앙 관리하고,
장기 자격증명(Long-term Credential) 사용을 원칙적으로 금지합니다.

---

## 핵심 원칙

| 원칙 | 내용 |
|------|------|
| 최소 권한 (Least Privilege) | 필요한 권한만 부여, 주기적 검토 |
| 장기 자격증명 금지 | Access Key 발급 원칙적 금지, 예외 시 엄격한 통제 |
| 사람 접근: Identity Center | 콘솔/CLI 접근은 SSO로만 허용 |
| 워크로드 접근: IAM Role | EC2, Lambda 등은 Instance Profile/Execution Role 사용 |
| 권한 경계 (Permission Boundary) | 개발팀이 생성하는 Role의 최대 권한 제한 |

---

## IAM Identity Center (SSO) 설계

### 전체 구조

```
외부 IdP (Active Directory, Okta, Azure AD 등)
        │ SAML 2.0 / SCIM (자동 동기화)
IAM Identity Center (Management Account)
        │
   Permission Set 매핑
        │
   각 계정 → IAM Role로 위임 (AssumeRole)
        │
   사용자 접근 (콘솔 / CLI / SDK)
```

### Permission Set 설계

Permission Set = IAM 정책 집합으로, 계정별로 역할에 매핑됩니다.

| Permission Set | 주요 대상 | 정책 구성 |
|---------------|---------|---------|
| PlatformAdmin | 플랫폼/인프라팀 | AdministratorAccess (제한적 계정만) |
| NetworkAdmin | 네트워크팀 | VPC, TGW, DX, Route53 관련 권한 |
| SecurityAuditor | 보안팀 | SecurityAudit (AWS Managed) + Security Hub, GuardDuty 읽기 |
| Developer | 개발팀 | EC2, ECS, Lambda, RDS, S3 등 서비스 권한 (Prod는 읽기 전용) |
| DataEngineer | 데이터팀 | Glue, Athena, S3, Redshift 관련 권한 |
| ReadOnly | 경영진, 감사 | ReadOnlyAccess (AWS Managed) |
| BillingViewer | 재무팀 | Billing, Cost Explorer 읽기 전용 |

### 계정별 Permission Set 매핑 예시

| 계정 | Permission Set | 대상 그룹 |
|------|---------------|---------|
| Management | PlatformAdmin | 클라우드팀 리드 (2-3명) |
| Network | NetworkAdmin | 네트워크팀 |
| Prod-ServiceA | Developer (ReadOnly) | 개발팀 |
| Dev-ServiceA | Developer (Full) | 개발팀 |
| Audit | SecurityAuditor | 보안팀 |

---

## IAM Role 설계 (워크로드용)

사람이 아닌 서비스가 사용하는 Role 설계입니다.

### Role 명명 규칙

```
{서비스명}-{환경}-{역할}
예:
  payment-prod-ec2-role
  auth-dev-lambda-role
  batch-stg-glue-role
```

### 크로스 어카운트 Role

Shared Services Account의 CI/CD가 워크로드 계정에 배포할 때 사용합니다.

```
[Shared Services Account]
CI/CD Pipeline (CodePipeline / GitHub Actions)
        │
        │ AssumeRole
        ▼
[워크로드 계정]
deploy-role (배포 전용 Role)
  - 필요한 서비스 권한만 허용
  - Trust Policy: Shared Services Account ID만 허용
```

**Trust Policy 예시:**
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "AWS": "arn:aws:iam::{SHARED_SERVICES_ACCOUNT_ID}:role/cicd-pipeline-role"
      },
      "Action": "sts:AssumeRole",
      "Condition": {
        "StringEquals": {
          "sts:ExternalId": "my-org-cicd"
        }
      }
    }
  ]
}
```

---

## Permission Boundary (권한 경계)

개발팀이 직접 IAM Role을 생성할 때 최대 권한을 제한합니다.
"개발자가 자신보다 높은 권한의 Role을 만들어 권한 상승"하는 것을 방지합니다.

### 동작 원리

```
실제 허용 권한 = IAM Policy ∩ Permission Boundary

예:
  IAM Policy: S3 FullAccess + IAM FullAccess
  Permission Boundary: S3 FullAccess + EC2 FullAccess (IAM 제외)
  → 실제 허용: S3 FullAccess만 (교집합)
```

### Permission Boundary 정책 예시

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "s3:*", "ec2:*", "ecs:*", "lambda:*",
        "logs:*", "cloudwatch:*", "xray:*"
      ],
      "Resource": "*"
    },
    {
      "Effect": "Deny",
      "Action": [
        "iam:CreateUser",
        "iam:DeleteUser",
        "organizations:*"
      ],
      "Resource": "*"
    }
  ]
}
```

### SCP로 Permission Boundary 강제

개발팀이 Permission Boundary 없이 Role을 생성하지 못하도록 SCP로 강제합니다.

```json
{
  "Effect": "Deny",
  "Action": [
    "iam:CreateRole",
    "iam:PutRolePolicy",
    "iam:AttachRolePolicy"
  ],
  "Resource": "*",
  "Condition": {
    "StringNotLike": {
      "iam:PermissionsBoundary": "arn:aws:iam::*:policy/dev-permission-boundary"
    }
  }
}
```

---

## 장기 자격증명(Access Key) 통제

### 원칙

- **사람 사용자:** Access Key 발급 금지 → Identity Center CLI 사용 (`aws sso login`)
- **워크로드:** IAM Role 사용 (Instance Profile, Execution Role, IRSA)
- **예외 케이스:** CI/CD 외부 시스템 등 불가피한 경우 엄격한 통제 적용

### 예외 허용 시 통제 방안

| 통제 항목 | 방법 |
|---------|------|
| 키 수명 제한 | AWS Config Rule: access-keys-rotated (90일 초과 시 알람) |
| 사용 모니터링 | CloudTrail → 마지막 사용일 추적 |
| 최소 권한 적용 | 특정 IP에서만 사용 가능하도록 Condition 추가 |
| Secrets Manager 저장 | 평문 환경변수 저장 금지 |

**IP 제한 Condition 예시:**
```json
{
  "Effect": "Deny",
  "Action": "*",
  "Resource": "*",
  "Condition": {
    "NotIpAddress": {
      "aws:SourceIp": ["203.0.113.0/24"]
    },
    "Bool": {
      "aws:ViaAWSService": "false"
    }
  }
}
```

---

## IAM Access Analyzer

계정 내 외부에 노출된 리소스(S3, IAM Role, KMS, Lambda 등)를 자동 탐지합니다.

| 분석 유형 | 탐지 대상 |
|---------|---------|
| 외부 접근 분석 | 다른 계정/인터넷에 공개된 리소스 |
| 미사용 접근 분석 | 사용하지 않는 Role, 정책, 권한 탐지 |
| 정책 검증 | IAM 정책 작성 시 오류/경고 검출 |

- **Audit Account**에 Organizations 레벨 Analyzer 생성 (전 계정 분석)
- 외부 접근 탐지 즉시 Security Hub로 연동하여 알람

---

## 감사 및 주기적 검토

| 항목 | 주기 | 방법 |
|------|------|------|
| 미사용 Role/Policy | 분기 | IAM Access Analyzer + AWS Config |
| Access Key 사용 이력 | 월 | IAM 자격증명 보고서 |
| Permission Set 적절성 | 반기 | 접근 검토 (Access Review) |
| SCP 유효성 | 연 | 정책 시뮬레이터로 검증 |

---

## 관련 문서

- [02. OU 전략](./02-ou-strategy.md)
- [03. Account 전략](./03-account-strategy.md)
- [11. 보안 서비스 운영](./11-security-services.md)
