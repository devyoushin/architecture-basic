# 11. 보안 서비스 운영

## 개요

AWS 보안 서비스는 개별적으로 운영하면 효과가 분산됩니다.
Security Hub를 중심으로 전 계정의 보안 상태를 통합 가시화하고,
탐지 → 분석 → 대응으로 이어지는 운영 플로우를 표준화합니다.

---

## 보안 서비스 역할 분담

| 서비스 | 역할 | 관리 계정 |
|-------|------|---------|
| Amazon GuardDuty | 위협 탐지 (행위 기반) | Audit Account (Administrator) |
| AWS Security Hub | 보안 상태 통합 대시보드 | Audit Account (Administrator) |
| AWS Config | 리소스 구성 변경 추적 및 규칙 평가 | Audit Account (Aggregator) |
| Amazon Inspector | EC2/컨테이너 취약점 스캔 | Audit Account (Administrator) |
| AWS Firewall Manager | WAF/SG/방화벽 정책 중앙 관리 | Audit Account (Administrator) |
| Amazon Macie | S3 민감 데이터 탐지 | Audit Account (Administrator) |
| AWS CloudTrail | API 호출 감사 로그 | Management Account (조직 Trail) |

---

## Amazon GuardDuty

### 활성화 전략

- Organizations 레벨에서 자동 활성화 (신규 계정 포함)
- Audit Account를 GuardDuty Administrator로 지정
- 전 계정이 Member로 자동 연결

### 탐지 소스

| 소스 | 탐지 내용 |
|------|---------|
| CloudTrail | 의심스러운 API 호출, 루트 계정 사용 |
| VPC Flow Log | 포트 스캔, C2 통신, 비정상 트래픽 |
| DNS Log | 악성 도메인 질의, DNS Exfiltration |
| S3 Data Event | S3 버킷 이상 접근 패턴 |
| EKS Audit Log | Kubernetes 클러스터 이상 행위 |
| Lambda Network Activity | Lambda의 의심스러운 네트워크 통신 |

### 주요 Finding 유형 및 대응

| Finding 유형 | 심각도 | 즉각 대응 |
|------------|------|---------|
| UnauthorizedAccess:IAMUser/MaliciousIPCaller | High | 해당 IAM 자격증명 즉시 비활성화 |
| CryptoCurrency:EC2/BitcoinTool | High | 해당 EC2 격리, 스냅샷 보존 |
| Backdoor:EC2/C&CActivity | High | EC2 격리, 포렌식 분석 |
| Trojan:EC2/DNSDataExfiltration | High | EC2 격리, DNS 로그 분석 |
| Stealth:IAMUser/CloudTrailLoggingDisabled | Medium | CloudTrail 즉시 재활성화, 원인 추적 |

---

## AWS Security Hub

### 통합 관리 구조

```
각 계정 (Member)
  GuardDuty Finding
  Config Rule 평가
  Inspector Finding
  Macie Finding
        │ 자동 집계
        ▼
Audit Account (Administrator)
  Security Hub 통합 대시보드
        │
  EventBridge → SNS → 알람/티켓
```

### 보안 표준 활성화

| 보안 표준 | 내용 |
|---------|------|
| AWS Foundational Security Best Practices | AWS 권장 보안 설정 검사 (~200개 컨트롤) |
| CIS AWS Foundations Benchmark | CIS 기준 보안 검사 |
| NIST SP 800-53 | 미국 정부 보안 표준 (해당 시) |
| PCI DSS | 카드 결제 환경 보안 기준 (해당 시) |

### Security Hub 점수 관리

- 전사 목표 보안 점수 설정 (예: 85점 이상 유지)
- 주간 보안 점수 리포트 자동 생성
- 점수 하락 시 즉시 알람

---

## AWS Config

### Config Rules 분류

#### 자동 수정 (Auto Remediation) 가능한 규칙

| Rule | 위반 내용 | 자동 수정 |
|------|---------|---------|
| s3-bucket-public-access-prohibited | S3 퍼블릭 접근 허용 | 퍼블릭 차단 활성화 |
| ec2-instance-no-public-ip | EC2 공개 IP 자동 할당 | — (알람만) |
| restricted-ssh | SG에서 0.0.0.0/0:22 허용 | SG 규칙 삭제 |
| cloudtrail-enabled | CloudTrail 비활성화 | CloudTrail 재활성화 |

#### 필수 탐지 규칙 (감사/알람)

| Rule | 탐지 내용 |
|------|---------|
| root-account-mfa-enabled | 루트 계정 MFA 미설정 |
| iam-user-no-policies-check | IAM 사용자 직접 정책 부여 |
| access-keys-rotated | Access Key 90일 미교체 |
| vpc-default-security-group-closed | 기본 SG에 인바운드/아웃바운드 규칙 존재 |
| ebs-snapshot-public-restorable-check | EBS 스냅샷 공개 설정 |
| rds-instance-public-access-check | RDS 퍼블릭 접근 허용 |

---

## Amazon Inspector

### 스캔 대상

| 대상 | 탐지 유형 |
|------|---------|
| EC2 인스턴스 | OS 패키지 취약점, 네트워크 도달성 |
| ECR 컨테이너 이미지 | 컨테이너 레이어 취약점 (push 시 자동 스캔) |
| Lambda 함수 | 코드 취약점, 의존성 패키지 취약점 |

### CVE 심각도별 대응 기준

| 심각도 | CVSS 점수 | 대응 기한 |
|------|---------|---------|
| Critical | 9.0 ~ 10.0 | 24시간 내 패치 또는 완화 |
| High | 7.0 ~ 8.9 | 7일 내 패치 |
| Medium | 4.0 ~ 6.9 | 30일 내 패치 |
| Low | 0.1 ~ 3.9 | 분기 내 패치 |

---

## 탐지 → 대응 플로우

### 자동화 대응 아키텍처

```
GuardDuty / Security Hub Finding 생성
        │
   EventBridge Rule (심각도 필터링)
        │
   ┌────┴──────────────────────────────┐
   │                                   │
SNS Topic (알람)               Lambda (자동 대응)
   │                                   │
   ├── Slack / Teams 알림              ├── EC2 격리 (SG 변경)
   ├── PagerDuty 연동                  ├── IAM 자격증명 비활성화
   └── 이메일 알람                      ├── JIRA/ServiceNow 티켓 생성
                                       └── S3 버킷 퍼블릭 차단
```

### EventBridge Rule 예시

```json
{
  "source": ["aws.securityhub"],
  "detail-type": ["Security Hub Findings - Imported"],
  "detail": {
    "findings": {
      "Severity": {
        "Label": ["CRITICAL", "HIGH"]
      },
      "Workflow": {
        "Status": ["NEW"]
      }
    }
  }
}
```

---

## 보안 운영 주기

| 주기 | 활동 |
|------|------|
| 실시간 | GuardDuty High/Critical → 자동 알람 및 자동 대응 |
| 일간 | Security Hub 신규 Finding 검토, 미해결 건 팔로우업 |
| 주간 | 보안 점수 리포트, Config Rule 위반 현황 검토 |
| 월간 | Inspector 취약점 패치 현황, Access Key 현황 검토 |
| 분기 | IAM 권한 적절성 검토, SCP 유효성 검토 |
| 연간 | 전체 보안 아키텍처 리뷰 |

---

## 관련 문서

- [03. Account 전략](./03-account-strategy.md)
- [10. IAM 전략](./10-iam.md)
- [09. Network Firewall & WAF](./09-network-firewall-waf.md)
