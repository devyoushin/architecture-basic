# 아키텍처 설계 원칙 및 코드 규칙

이 저장소의 AWS 엔터프라이즈 아키텍처 설계 원칙과 코드 작성 규칙입니다.

---

## 1. 핵심 설계 원칙

### 최소 권한 원칙 (Least Privilege)
- 계정/OU 단위 SCP로 권한 경계 명확히 설정
- IAM: Permission Boundary로 권한 에스컬레이션 차단
- 서비스 계정: 용도별 Role 분리 (공유 Role 사용 금지)

### 네트워크 중앙화 (Centralized Networking)
- Transit Gateway: Network 계정에 집중
- Inspection VPC: East-West 트래픽 모두 검사
- DNS: Route53 Resolver 중앙화

### 환경 격리 (Environment Isolation)
- Dev / Staging / Production 계정 완전 분리
- OU 단위로 SCP 적용하여 환경별 가드레일

### 가시성 확보 (Observability)
- Log Archive 계정: 전사 CloudTrail, Config, VPC Flow Logs 중앙 집계
- CloudWatch OAM: 크로스 계정 지표/로그 통합
- Security Hub: 멀티 계정 보안 점수 통합

## 2. Terraform 코드 규칙

### 기본 구조
```hcl
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  backend "s3" {
    bucket = "<TERRAFORM_STATE_BUCKET>"
    key    = "<PATH>/terraform.tfstate"
    region = "ap-northeast-2"
  }
}
```

### 필수 태그 (`15-tagging.md` 기준)
```hcl
tags = {
  Name        = "<RESOURCE_NAME>"
  Environment = "<dev|staging|prod>"
  Team        = "<TEAM_NAME>"
  CostCenter  = "<COST_CENTER>"
  ManagedBy   = "terraform"
}
```

### 네이밍 규칙
- 리소스: `{환경}-{서비스}-{역할}`
- 예시: `prod-network-tgw`, `shared-security-guardduty`

## 3. SCP 작성 규칙

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "<UNIQUE_SID>",
      "Effect": "Deny",
      "Action": [
        "<SERVICE>:<Action>"
      ],
      "Resource": "*",
      "Condition": {
        "StringNotEquals": {
          "aws:RequestedRegion": ["ap-northeast-2"]
        }
      }
    }
  ]
}
```

- Sid: 의미있는 이름 사용 (예: `DenyRootUserActions`)
- Effect: 가능하면 `Deny` 사용
- 조건 활용: `StringNotEquals`, `ArnNotLike` 등으로 예외 처리
