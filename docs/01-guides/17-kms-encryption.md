# 17. KMS & 암호화 전략

## 개요

암호화는 데이터 보호의 기본이며, AWS KMS(Key Management Service)는
암호화 키의 생성, 관리, 감사를 중앙에서 처리합니다.
키 계층 구조를 올바르게 설계하지 않으면 운영 복잡도와 보안 리스크가 동시에 증가합니다.

---

## 암호화 범위

### 저장 데이터 암호화 (Encryption at Rest)

| 서비스 | 암호화 방식 | 키 유형 |
|-------|-----------|--------|
| S3 | SSE-S3, SSE-KMS, SSE-C | CMK 권장 |
| EBS | AES-256 | CMK 권장 |
| RDS / Aurora | TDE (Transparent Data Encryption) | CMK 권장 |
| DynamoDB | AWS Owned Key 또는 CMK | 민감 데이터는 CMK |
| Secrets Manager | CMK | CMK 필수 |
| CloudWatch Logs | CMK | 보안 로그는 CMK |
| ECR | CMK | 권장 |

### 전송 데이터 암호화 (Encryption in Transit)

| 구간 | 방식 |
|------|------|
| 클라이언트 → ALB | TLS 1.2 이상 강제 |
| ALB → 앱 서버 | TLS (내부 통신도 암호화 권장) |
| 앱 서버 → RDS | SSL/TLS 강제 (require_secure_transport) |
| VPC 간 (TGW) | 기본 암호화 없음 → MACsec 또는 IPsec 적용 |
| 온프레미스 ↔ AWS (DX) | MACsec 또는 IPsec over DX |

---

## KMS 키 유형

| 유형 | 관리 주체 | 비용 | 사용 권장 상황 |
|------|---------|------|-------------|
| AWS Managed Key | AWS | 무료 | 기본 암호화, 감사 요건 없는 경우 |
| Customer Managed Key (CMK) | 고객 | $1/월/키 + API 호출 비용 | 규정 준수, 키 교체 정책, 크로스 계정 공유 |
| AWS Owned Key | AWS (내부) | 무료 | DynamoDB 기본값 등 |

> **원칙:** 규정 준수 환경 및 민감 데이터는 반드시 **CMK(고객 관리 키)** 사용

---

## 키 계층 구조 설계

### 멀티 계정 키 전략

```
[Security Account 또는 각 계정]
  KMS CMK (계정별 독립 키)
        │
   키 정책(Key Policy)으로 크로스 계정 접근 허용
        │
  워크로드 계정에서 키 사용 (Encrypt/Decrypt)
```

### 키 분리 기준

| 키 | 용도 | 계정 |
|----|------|------|
| `prod-s3-key` | 프로덕션 S3 버킷 암호화 | Prod 계정 |
| `prod-rds-key` | 프로덕션 RDS 암호화 | Prod 계정 |
| `prod-secrets-key` | Secrets Manager 암호화 | Prod 계정 |
| `log-archive-key` | 감사 로그 암호화 | Log Archive 계정 |
| `backup-key` | 백업 데이터 암호화 | 각 계정 또는 중앙 |

> **원칙:** 서비스별, 환경별로 키를 분리하여 폭발 반경(Blast Radius) 최소화.
> 하나의 키가 침해되어도 다른 서비스 데이터는 안전.

---

## KMS 키 정책 설계

### 기본 키 정책 구조

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "키 관리자 권한",
      "Effect": "Allow",
      "Principal": {
        "AWS": "arn:aws:iam::{ACCOUNT_ID}:role/key-admin-role"
      },
      "Action": [
        "kms:Create*", "kms:Describe*", "kms:Enable*",
        "kms:List*", "kms:Put*", "kms:Update*",
        "kms:Revoke*", "kms:Disable*", "kms:Delete*",
        "kms:ScheduleKeyDeletion", "kms:CancelKeyDeletion"
      ],
      "Resource": "*"
    },
    {
      "Sid": "키 사용자 권한 (암호화/복호화만)",
      "Effect": "Allow",
      "Principal": {
        "AWS": [
          "arn:aws:iam::{ACCOUNT_ID}:role/app-role",
          "arn:aws:iam::{ACCOUNT_ID}:role/cicd-pipeline-role"
        ]
      },
      "Action": [
        "kms:Encrypt", "kms:Decrypt",
        "kms:ReEncrypt*", "kms:GenerateDataKey*",
        "kms:DescribeKey"
      ],
      "Resource": "*"
    }
  ]
}
```

### 크로스 계정 키 공유

Shared Services의 ECR 이미지를 다른 계정에서 복호화할 때 등 크로스 계정 키 공유가 필요합니다.

```json
{
  "Sid": "크로스 계정 사용 허용",
  "Effect": "Allow",
  "Principal": {
    "AWS": "arn:aws:iam::{WORKLOAD_ACCOUNT_ID}:root"
  },
  "Action": [
    "kms:Decrypt",
    "kms:DescribeKey",
    "kms:GenerateDataKey"
  ],
  "Resource": "*"
}
```

> 크로스 계정 허용 후, 대상 계정의 IAM 정책에서도 `kms:*` 허용 필요 (양쪽 모두 허용해야 동작).

---

## 키 교체 (Key Rotation)

| 항목 | 설정 |
|------|------|
| 자동 교체 | CMK 생성 시 **자동 교체 활성화** (연 1회) |
| 교체 방식 | 키 ID는 변경되지 않음, 내부 키 재료만 교체 |
| 기존 데이터 | 이전 키 재료로 암호화된 데이터는 자동 복호화 가능 |
| 수동 교체 | 규정상 필요 시 새 키 생성 후 데이터 재암호화 |

---

## EBS 기본 암호화

계정 레벨에서 EBS 기본 암호화를 활성화합니다.

```
계정 레벨 EBS 기본 암호화 활성화
  → 이후 생성되는 모든 EBS 볼륨 자동 CMK 암호화
  → SCP로 강제 가능:
    Deny ec2:CreateVolume if Encrypted != true
```

---

## S3 암호화 정책

### 버킷 정책으로 암호화 강제

```json
{
  "Effect": "Deny",
  "Principal": "*",
  "Action": "s3:PutObject",
  "Resource": "arn:aws:s3:::my-bucket/*",
  "Condition": {
    "StringNotEquals": {
      "s3:x-amz-server-side-encryption": "aws:kms"
    }
  }
}
```

### S3 기본 암호화 설정

- 버킷 레벨에서 기본 암호화(SSE-KMS) 활성화
- 암호화 없이 업로드된 객체도 자동 암호화

---

## TLS 인증서 관리 (ACM)

### AWS Certificate Manager 전략

| 항목 | 내용 |
|------|------|
| 퍼블릭 인증서 | ACM 무료 발급 (ALB, CloudFront에 연결) |
| 프라이빗 인증서 | AWS Private CA (내부 서비스 간 mTLS) |
| 자동 갱신 | ACM 관리 인증서 자동 갱신 (만료 전 알람) |
| 크로스 계정 공유 | Private CA는 RAM으로 크로스 계정 공유 가능 |

### Private CA 활용 (내부 mTLS)

```
AWS Private CA (Network Account 또는 Shared Services)
        │ RAM 공유
        ▼
각 워크로드 계정
  ECS / EKS 서비스 → Private CA에서 인증서 발급
  서비스 간 mTLS (Mutual TLS) 통신
```

---

## 감사 및 모니터링

| 항목 | 방법 |
|------|------|
| 키 사용 감사 | CloudTrail → KMS API 호출 기록 |
| 이상 사용 탐지 | CloudWatch Metric: `NumberOfRequestsForKeyId` 급증 시 알람 |
| 키 삭제 방지 | 삭제 예약 시 CloudWatch 알람 + SNS 알람 |
| 키 미사용 탐지 | CloudTrail 분석으로 90일 이상 미사용 키 탐지 |

---

## 관련 문서

- [11. 보안 서비스 운영](./11-security-services.md)
- [10. IAM 전략](./10-iam.md)
- [14. 백업 & DR 전략](./14-backup-dr.md)
