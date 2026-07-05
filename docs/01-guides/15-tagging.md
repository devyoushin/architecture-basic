# 15. 태깅 전략

## 개요

태그(Tag)는 AWS 리소스에 붙이는 키-값 메타데이터입니다.
태그 전략이 없으면 비용 배분, 보안 정책 적용, 운영 자동화 모두 어려워집니다.
초기에 전사 표준을 수립하고 SCP로 강제하는 것이 핵심입니다.

---

## 태그의 활용 목적

| 목적 | 활용 방법 |
|------|---------|
| 비용 배분 | Cost Allocation Tag로 팀/프로젝트별 비용 분리 |
| 접근 제어 | IAM Condition에서 태그 기반 리소스 접근 제어 |
| 운영 자동화 | Instance Scheduler, 자동 패치 대상 선정 |
| 보안 정책 | Firewall Manager, Config Rule 태그 기반 적용 |
| 인벤토리 관리 | Resource Groups & Tag Editor로 리소스 검색 |

---

## 필수 태그 정의

모든 리소스에 반드시 부여해야 하는 태그입니다.

| 태그 키 | 설명 | 예시 값 |
|--------|------|--------|
| `Environment` | 환경 구분 | `prod`, `stg`, `dev`, `sandbox` |
| `Owner` | 담당 팀 또는 개인 | `platform-team`, `payment-squad` |
| `Project` | 프로젝트/서비스명 | `payment`, `auth`, `data-pipeline` |
| `CostCenter` | 비용 센터 코드 | `CC-1001`, `CC-2005` |
| `ManagedBy` | 리소스 관리 방법 | `terraform`, `cloudformation`, `manual` |

## 권장 태그 정의

| 태그 키 | 설명 | 예시 값 |
|--------|------|--------|
| `Service` | 세부 서비스명 | `api-server`, `batch-worker`, `rds-primary` |
| `DataClassification` | 데이터 민감도 | `public`, `internal`, `confidential`, `restricted` |
| `BackupPolicy` | 백업 정책 등급 | `tier1`, `tier2`, `tier3`, `none` |
| `PatchGroup` | 패치 그룹 | `linux-prod`, `windows-stg` |
| `AutoStop` | 자동 중지 대상 여부 | `true`, `false` |

---

## 태그 표준 규칙

### 키 명명 규칙

| 항목 | 규칙 |
|------|------|
| 대소문자 | PascalCase 또는 kebab-case로 전사 통일 (혼용 금지) |
| AWS 예약 접두사 | `aws:` 접두사는 AWS 내부 사용, 사용 금지 |
| 사내 접두사 | 필요 시 `org:Owner`, `org:Project` 형태로 구분 |
| 최대 길이 | 키: 128자, 값: 256자 |

### 값 표준화

```
# 나쁜 예 (비표준)
Environment: Production
Environment: PROD
Environment: prd

# 좋은 예 (표준화)
Environment: prod
```

- 소문자 통일 권장
- 공백 대신 하이픈(-) 또는 언더스코어(_) 사용
- 허용 값 목록(Enum) 사전 정의

---

## SCP로 태그 강제

필수 태그 없이 리소스를 생성할 수 없도록 SCP로 강제합니다.

### 필수 태그 미부여 시 리소스 생성 차단

```json
{
  "Effect": "Deny",
  "Action": [
    "ec2:RunInstances",
    "rds:CreateDBInstance",
    "s3:CreateBucket",
    "ecs:CreateService",
    "lambda:CreateFunction"
  ],
  "Resource": "*",
  "Condition": {
    "Null": {
      "aws:RequestTag/Environment": "true",
      "aws:RequestTag/Owner": "true",
      "aws:RequestTag/Project": "true"
    }
  }
}
```

> **주의:** SCP로 태그를 강제하면 자동화 파이프라인(IaC)에서도 태그를 반드시 포함해야 합니다.
> 적용 전 기존 파이프라인 점검 필수.

### 태그 값 허용 목록 제한 (선택)

```json
{
  "Effect": "Deny",
  "Action": "ec2:RunInstances",
  "Resource": "*",
  "Condition": {
    "StringNotEquals": {
      "aws:RequestTag/Environment": ["prod", "stg", "dev", "sandbox"]
    }
  }
}
```

---

## Cost Allocation Tag 활성화

비용 배분용 태그는 Management Account에서 별도로 활성화해야 Cost Explorer에 반영됩니다.

```
Management Account
  AWS Billing → Cost Allocation Tags
        │
  사용자 정의 태그 활성화:
    - Environment ✓
    - Owner ✓
    - Project ✓
    - CostCenter ✓
        │
  (활성화 후 최대 24시간 후 Cost Explorer에 반영)
```

---

## 태그 누락 리소스 탐지 및 교정

### AWS Config Rule 활용

```
required-tags Config Rule 설정:
  필수 태그: Environment, Owner, Project
  적용 리소스: EC2, RDS, S3, Lambda 등

→ 태그 누락 리소스 탐지 → Security Hub로 Finding 전송
→ 담당팀 알람 → 태그 추가 또는 리소스 삭제
```

### Tag Editor로 일괄 태그 추가

```
AWS Resource Groups & Tag Editor
  → 리전/리소스 타입/기존 태그 조건으로 검색
  → 태그 누락 리소스 일괄 태그 추가
```

### 미태깅 리소스 비용 추적

```
Cost Explorer
  → 태그 없음(Untagged) 필터
  → 미태깅 리소스가 발생시킨 비용 확인
  → 월간 미태깅 비용 목표: 전체의 5% 이하
```

---

## IaC 태그 적용 자동화

### Terraform 태그 모듈화

```hcl
# 공통 태그 locals 정의
locals {
  common_tags = {
    Environment    = var.environment
    Owner          = var.owner
    Project        = var.project
    CostCenter     = var.cost_center
    ManagedBy      = "terraform"
  }
}

# 리소스에 적용
resource "aws_instance" "app" {
  ami           = var.ami_id
  instance_type = var.instance_type

  tags = merge(local.common_tags, {
    Service = "api-server"
  })
}
```

### Terraform AWS Provider default_tags (권장)

`locals` 방식보다 발전된 형태로, Provider 수준에서 모든 리소스에 태그를 자동 부여합니다.
개별 리소스 코드에 `tags =` 블록이 없어도 공통 태그가 보장됩니다.

```hcl
# providers.tf
provider "aws" {
  region = "ap-northeast-2"

  default_tags {
    tags = {
      Environment = var.environment   # "prod" | "stg" | "dev"
      Owner       = var.owner         # "platform-team"
      Project     = var.project       # "payment"
      CostCenter  = var.cost_center   # "CC-1001"
      ManagedBy   = "terraform"
    }
  }
}

# 리소스 코드에서는 리소스 고유 태그만 추가하면 됨
resource "aws_instance" "app" {
  ami           = var.ami_id
  instance_type = var.instance_type

  # default_tags가 자동으로 공통 태그 부여
  tags = {
    Service = "api-server"   # 리소스 고유 태그만 추가
  }
}
```

> **주의:** `default_tags`와 리소스 `tags`에 동일한 키가 있으면 리소스 `tags`가 우선합니다.
> 이를 이용해 Environment 기본값을 Provider에 설정하고, 특수 케이스는 리소스 수준에서 Override 가능합니다.

### AWS CloudFormation 태그 전파

스택 레벨 태그는 스택 내 모든 리소스에 자동 전파됩니다.

```yaml
# CloudFormation 스택 생성 시 태그 전달
aws cloudformation deploy \
  --stack-name my-service \
  --tags \
    Environment=prod \
    Owner=platform-team \
    Project=payment \
    CostCenter=CC-1001 \
    ManagedBy=cloudformation
```

---

## AWS Organizations Tag Policy

SCP가 리소스 생성 자체를 차단하는 방식이라면, **Tag Policy**는 태그 값의 형식(대소문자, 허용 값)을 조직 전체에서 강제합니다. 두 가지를 함께 사용합니다.

```json
{
  "tags": {
    "Environment": {
      "tag_key": {
        "@@assign": "Environment"
      },
      "tag_value": {
        "@@assign": ["prod", "stg", "dev", "sandbox"]
      },
      "enforced_for": {
        "@@assign": [
          "ec2:instance",
          "rds:db",
          "s3:bucket",
          "lambda:function"
        ]
      }
    },
    "CostCenter": {
      "tag_key": {
        "@@assign": "CostCenter"
      },
      "tag_value": {
        "@@assign": ["CC-\\d{4}"]
      }
    }
  }
}
```

| 항목 | SCP | Tag Policy |
|------|-----|-----------|
| 목적 | 태그 없으면 생성 자체 차단 | 태그 값 형식 표준화 강제 |
| 적용 시점 | API 호출 시 | 태그 적용 시 |
| 위반 시 | 리소스 생성 실패 | 태그 적용 실패 (또는 경고) |
| 권장 사용 | 필수 태그 강제 | 태그 값 enum/포맷 강제 |

---

## 태그 기반 ABAC (Attribute-Based Access Control)

태그를 IAM 조건으로 활용하면 역할 수를 줄이고 팀별 리소스 접근을 자동화할 수 있습니다.

### 팀 태그 기반 리소스 접근 제어

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AccessOwnTeamResources",
      "Effect": "Allow",
      "Action": [
        "ec2:StartInstances",
        "ec2:StopInstances",
        "ec2:RebootInstances"
      ],
      "Resource": "*",
      "Condition": {
        "StringEquals": {
          "ec2:ResourceTag/Owner": "${aws:PrincipalTag/Team}"
        }
      }
    }
  ]
}
```

> **동작 원리:** IAM 역할에 `Team=payment-squad` 태그가 붙어 있으면,
> `Owner=payment-squad` 태그가 붙은 EC2만 시작/중지 가능합니다.
> 팀이 늘어나도 IAM 정책 변경 없이 태그만 추가하면 됩니다.

### 환경별 리소스 접근 분리

```json
{
  "Sid": "DenyProdFromDevRole",
  "Effect": "Deny",
  "Action": "*",
  "Resource": "*",
  "Condition": {
    "StringEquals": {
      "aws:ResourceTag/Environment": "prod"
    },
    "StringNotEquals": {
      "aws:PrincipalTag/Environment": "prod"
    }
  }
}
```

> Dev 역할을 가진 사용자는 `Environment=prod` 리소스에 접근 불가.
> 계정 분리와 함께 적용하면 이중 방어 구성이 됩니다.

---

## 태그 자동 교정 파이프라인

### EventBridge + Lambda로 리소스 생성 시 자동 태그 추가

IaC 없이 콘솔에서 생성된 리소스에도 기본 태그를 자동으로 부여합니다.

```
리소스 생성 이벤트 발생
  │ (EC2 RunInstances, S3 CreateBucket 등)
  ▼
EventBridge Rule
  (source: "aws.ec2", detail-type: "AWS API Call via CloudTrail")
  │
  ▼
Lambda: auto-tagger
  ├── CloudTrail 이벤트에서 리소스 ARN, 생성자 정보 추출
  ├── 생성자 IAM Role/User → 팀/프로젝트 매핑 테이블 조회
  ├── 부족한 태그 자동 추가 (Owner, Project, CostCenter)
  └── 추가 불가 시 → SNS → Slack 알람 (담당자 수동 처리 요청)
```

```python
# Lambda 예시 (핵심 로직)
import boto3, json

TEAM_MAPPING = {
    "arn:aws:iam::123456789:role/payment-dev-role": {
        "Owner": "payment-squad",
        "Project": "payment",
        "CostCenter": "CC-1001"
    }
}

def handler(event, context):
    detail = event["detail"]
    principal_arn = detail["userIdentity"]["arn"]
    instance_ids  = [i["instanceId"] for i in
                     detail["responseElements"]["instancesSet"]["items"]]

    tags = TEAM_MAPPING.get(principal_arn, {})
    if not tags:
        # 매핑 없는 경우 알람 발송
        notify_slack(f"태그 매핑 없는 EC2 생성: {instance_ids}, by {principal_arn}")
        return

    ec2 = boto3.client("ec2")
    ec2.create_tags(
        Resources=instance_ids,
        Tags=[{"Key": k, "Value": v} for k, v in tags.items()]
    )
```

### AWS Config 자동 교정 (Auto Remediation)

```
Config Rule: required-tags
  태그 누락 리소스 탐지
        │
  SSM Automation: AWS-AddTagsToResource
        │ (자동 교정)
  기본값 태그 추가 → 담당자에게 후속 확인 알람
```

---

## 비용 차지백(Chargeback) 모델

태그를 기반으로 팀/사업부별 AWS 비용을 실제 발생 조직에 청구하는 방식입니다.

### 차지백 vs 쇼백

| 모델 | 설명 | 권장 시점 |
|------|------|---------|
| **쇼백(Showback)** | 팀별 비용을 보여주기만 함 (청구 없음) | 태깅 문화 정착 초기 |
| **차지백(Chargeback)** | 팀별 비용을 실제 내부 회계에 반영 | 태깅 정확도 90% 이상 달성 후 |

### Cost Explorer 태그 기반 리포트 구조

```
Management Account - Cost Explorer
  │
  ├── 필터: CostCenter = CC-1001 (결제팀)
  │     → 이번 달 비용: $12,450
  │     → EC2 40% / RDS 35% / 데이터 전송 15% / 기타 10%
  │
  ├── 필터: CostCenter = CC-2005 (데이터팀)
  │     → 이번 달 비용: $8,200
  │
  └── 미태깅(Untagged)
        → 이번 달 비용: $1,100 (전체의 4.5%)
        → 목표: 5% 이하 유지
```

### 월간 비용 배분 자동화

```
월말 자동 실행 (EventBridge Scheduler):
  1. Cost Explorer API → 팀별 태그 비용 추출
  2. S3 → 팀별 CSV 리포트 저장
  3. SES → 팀 리더에게 비용 리포트 이메일 발송
  4. QuickSight 대시보드 자동 갱신
```

---

## 태그 거버넌스 운영

| 활동 | 주기 |
|------|------|
| 미태깅 리소스 현황 리포트 | 주간 |
| Cost Allocation Tag 정확도 검토 | 월간 |
| 태그 표준 정책 업데이트 | 분기 |
| 신규 서비스/팀 온보딩 시 태그 가이드 제공 | 필요 시 |

### 태그 컴플라이언스 KPI

| 지표 | 목표 |
|------|------|
| 필수 태그 준수율 (전체 리소스) | ≥ 95% |
| 미태깅 리소스 비용 비율 | ≤ 5% |
| 태그 값 표준 준수율 (Tag Policy 위반 없음) | ≥ 99% |
| Config Rule non-compliant 리소스 | 72시간 내 교정 |

---

## 관련 문서

- [12. 비용 관리 전략](./12-cost-management.md)
- [02. OU 전략](./02-ou-strategy.md)
- [10. IAM 전략](./10-iam.md)
