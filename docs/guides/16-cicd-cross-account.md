# 16. CI/CD 크로스 어카운트 배포 전략

## 개요

멀티 어카운트 환경에서 CI/CD 파이프라인은 Shared Services Account에 중앙 배치하고,
각 워크로드 계정(Dev/Stg/Prod)에 크로스 어카운트로 배포합니다.
파이프라인은 코드를 직접 배포하지 않고, 대상 계정의 IAM Role을 AssumeRole하여 배포 권한을 얻습니다.

---

## 전체 구조

```
개발자 (로컬 또는 GitHub)
        │ git push
        ▼
소스 저장소 (GitHub / CodeCommit)
        │ 이벤트 트리거
        ▼
[Shared Services Account]
  CI/CD 파이프라인 (CodePipeline / GitHub Actions)
  빌드 서버 (CodeBuild / GitHub Actions Runner)
  컨테이너 레지스트리 (Amazon ECR)
        │
        │ AssumeRole (크로스 어카운트)
        ▼
  ┌─────────────────────────────────┐
  │  Dev 계정      Stg 계정      Prod 계정  │
  │  deploy-role   deploy-role   deploy-role│
  │  (배포 실행)   (배포 실행)   (배포 실행)│
  └─────────────────────────────────┘
```

---

## 배포 역할 (deploy-role) 설계

### 각 계정에 생성할 deploy-role

```json
// Trust Policy: Shared Services Account의 파이프라인 역할만 AssumeRole 허용
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
          "sts:ExternalId": "cicd-deploy-{account-name}"
        }
      }
    }
  ]
}
```

### deploy-role 권한 (Permission Policy)

환경별로 최소 권한 적용:

| 계정 | 권한 |
|------|------|
| Dev | ECS/EKS 배포, Lambda 업데이트, CloudFormation 전체 |
| Stg | ECS/EKS 배포, Lambda 업데이트, CloudFormation 전체 |
| Prod | ECS/EKS 배포, Lambda 업데이트 (인프라 변경은 별도 승인) |

---

## 파이프라인 단계 설계

### 표준 배포 파이프라인

```
[Source]
  GitHub PR Merge → main 브랜치
        │
[Build]
  CodeBuild (Shared Services)
  - 코드 빌드 (컴파일, 테스트)
  - Docker 이미지 빌드
  - ECR에 이미지 Push (태그: Git Commit SHA)
  - 보안 스캔: Trivy (컨테이너 이미지 취약점)
        │
[Deploy Dev]
  AssumeRole → Dev deploy-role
  - ECS Task Definition 업데이트
  - ECS Service 배포 (Rolling Update)
  - 배포 후 자동 통합 테스트 실행
        │
[Approval Gate] ← 스테이징 배포 전 수동 승인
        │
[Deploy Stg]
  AssumeRole → Stg deploy-role
  - ECS 배포
  - E2E 테스트 실행
  - 성능 테스트 실행
        │
[Approval Gate] ← 프로덕션 배포 전 수동 승인 (2인 이상 권장)
        │
[Deploy Prod]
  AssumeRole → Prod deploy-role
  - ECS 배포 (Blue/Green 또는 Canary)
  - 배포 후 Health Check
  - 이상 시 자동 Rollback
```

---

## 배포 전략

### Blue/Green 배포 (ECS + CodeDeploy)

```
현재 (Blue)                    새 버전 (Green)
ECS Service v1.0         ECS Service v1.1 (신규 배포)
ALB Target Group A  →  ALB Target Group B
        │                        │
        └── 트래픽 전환 (0% → 100%) ┘
              (이상 시 즉시 Blue로 복귀)
```

- 다운타임 없는 배포
- 즉각적인 Rollback 가능 (이전 버전 유지)
- CodeDeploy 훅: BeforeAllowTraffic, AfterAllowTraffic 단계에 테스트 삽입

### Canary 배포

```
트래픽 분배:
  1단계: v1.1 → 5% 트래픽
  2단계: v1.1 → 20% 트래픽  (이상 없으면)
  3단계: v1.1 → 100% 트래픽 (전환 완료)

이상 감지 시 → 자동 Rollback (v1.0으로 100% 복귀)
```

### 배포 전략별 사용 기준

| 전략 | 사용 환경 | 특징 |
|------|---------|------|
| Rolling Update | Dev, Stg | 빠르고 간단, 순간적 혼재 |
| Blue/Green | Prod (일반) | 즉각 Rollback, 리소스 2배 |
| Canary | Prod (고위험 변경) | 점진적 전환, 리스크 최소화 |

---

## Amazon ECR 멀티 계정 전략

### ECR 중앙 레지스트리 (Shared Services Account)

```
Shared Services Account
  ECR Repository (컨테이너 이미지 저장소)
        │
   ECR Repository Policy (크로스 어카운트 Pull 허용)
        │
  ┌─────┴─────────────────┐
Dev 계정 ECS     Stg 계정 ECS     Prod 계정 ECS
(이미지 Pull)    (이미지 Pull)    (이미지 Pull)
```

**ECR Repository Policy (크로스 어카운트 허용):**
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "AWS": [
          "arn:aws:iam::{DEV_ACCOUNT_ID}:root",
          "arn:aws:iam::{STG_ACCOUNT_ID}:root",
          "arn:aws:iam::{PROD_ACCOUNT_ID}:root"
        ]
      },
      "Action": [
        "ecr:GetDownloadUrlForLayer",
        "ecr:BatchGetImage",
        "ecr:BatchCheckLayerAvailability"
      ]
    }
  ]
}
```

### 이미지 태깅 전략

| 태그 | 설명 | 예시 |
|------|------|------|
| Git Commit SHA | 불변 식별자 (권장) | `a1b2c3d4` |
| 환경 태그 | 현재 배포 환경 | `prod`, `stg`, `dev` |
| `latest` | **사용 금지** | 어떤 버전인지 불명확 |

```
# 빌드 시
docker build -t {ECR_REPO}:{GIT_SHA} .
docker tag {ECR_REPO}:{GIT_SHA} {ECR_REPO}:dev

# Prod 배포 시 동일 이미지에 prod 태그 추가 (재빌드 없이)
docker tag {ECR_REPO}:{GIT_SHA} {ECR_REPO}:prod
```

---

## Secrets 관리

파이프라인에서 DB 패스워드, API Key 등 민감 정보를 안전하게 처리합니다.

### 절대 금지
- 소스 코드에 하드코딩
- 환경 변수에 평문 저장
- ECR 이미지에 포함

### 권장 방식

```
AWS Secrets Manager (각 계정)
  또는
AWS Parameter Store (SecureString, KMS 암호화)
        │
ECS Task Definition: Secrets 참조 (ARN)
Lambda: Secrets Manager SDK로 런타임 로드
CodeBuild: Secrets Manager 환경 변수 주입
```

---

## 파이프라인 보안

| 항목 | 적용 방법 |
|------|---------|
| 소스 코드 보안 스캔 | SAST: Semgrep, Checkov (IaC 스캔) |
| 컨테이너 취약점 스캔 | Trivy, Amazon Inspector (ECR Push 시 자동) |
| Dependency 취약점 | Dependabot, `pip audit`, `npm audit` |
| Secrets 노출 탐지 | git-secrets, Gitleaks (Pre-commit Hook) |
| 빌드 환경 격리 | CodeBuild: VPC 내 실행, 인터넷 접근 최소화 |

### 배포 감사 로그

모든 배포 활동은 CloudTrail로 기록됩니다.

```
CodePipeline 배포 이벤트
  → CloudTrail (API 호출 기록)
  → 배포 담당자, 배포 시각, 배포 대상 추적 가능
```

---

## IaC (Infrastructure as Code) 전략

### Terraform 멀티 계정 구성

```
infra-repo/
├── modules/          ← 재사용 가능한 모듈
│   ├── vpc/
│   ├── ecs-service/
│   └── rds/
├── environments/
│   ├── dev/          ← Dev 계정 tfvars
│   ├── stg/          ← Stg 계정 tfvars
│   └── prod/         ← Prod 계정 tfvars
└── global/           ← 공통 리소스 (IAM Role 등)
```

**Terraform State 백엔드:**
```hcl
terraform {
  backend "s3" {
    bucket         = "tfstate-{account-id}"
    key            = "service-name/terraform.tfstate"
    region         = "ap-northeast-2"
    encrypt        = true
    kms_key_id     = "alias/terraform-state"
    dynamodb_table = "terraform-lock"
  }
}
```

- State 파일은 각 계정 S3에 격리 저장
- DynamoDB로 State Lock (동시 변경 방지)
- KMS로 State 파일 암호화

---

## 관련 문서

- [03. Account 전략](./03-account-strategy.md)
- [10. IAM 전략](./10-iam.md)
- [15. 태깅 전략](./15-tagging.md)
