# 09. Network Firewall & WAF 전략

## 개요

AWS 환경의 네트워크 보안은 트래픽 방향에 따라 다른 도구를 조합합니다.

| 트래픽 유형 | 사용 서비스 |
|-----------|-----------|
| 인터넷 → AWS (L7 HTTP/S) | AWS WAF |
| VPC 간 East-West | AWS Network Firewall |
| 인터넷 Egress (아웃바운드) | AWS Network Firewall |
| DDoS 방어 | AWS Shield |
| 전체 트래픽 위협 탐지 | Amazon GuardDuty |

---

## AWS Network Firewall

### 역할 및 위치

- **L3 ~ L7** 트래픽 검사 (상태 기반 패킷 필터링, IPS, 도메인 필터링)
- **Inspection VPC** 내에 배치 (Network Account)
- TGW를 통해 모든 VPC 간 트래픽이 경유

### 정책 구조

```
Firewall Policy
├── Stateless Rule Group (우선 처리, 순서 중요)
│   - 기본 허용/차단 판단
│   - Forward to Stateful: 심층 검사가 필요한 트래픽 전달
│
└── Stateful Rule Group (연결 단위 검사)
    ├── 5-Tuple Rule     : IP, 포트, 프로토콜 기반 허용/차단
    ├── Domain List Rule : 도메인(SNI/HTTP Host) 기반 필터링
    └── Suricata IPS Rule: 서명 기반 침입 탐지/차단
```

### Stateless Rule Group 예시

| 우선순위 | 소스 | 목적지 | 프로토콜 | 포트 | 액션 |
|---------|------|--------|---------|------|------|
| 10 | 10.0.0.0/8 | 10.0.0.0/8 | TCP | Any | Forward to Stateful |
| 20 | Any | Any | TCP | 443 | Forward to Stateful |
| 30 | Any | Any | TCP | 80 | Forward to Stateful |
| 1000 | Any | Any | Any | Any | Drop |

### Stateful Rule — East-West 트래픽 제어

VPC 간 허용할 통신을 명시적으로 정의합니다.

```
# Prod VPC → Shared Services (허용)
pass tcp 10.0.0.0/16 any → 10.193.0.0/16 [80,443,8080] (msg:"Prod to SharedSvc"; sid:1001;)

# Dev VPC → Prod VPC (차단)
drop ip 10.128.0.0/16 any → 10.0.0.0/16 any (msg:"Dev to Prod BLOCKED"; sid:2001;)

# 모든 내부 트래픽 기본 차단
drop ip any any → any any (msg:"Default Deny"; sid:9999;)
```

### Suricata IPS 규칙셋

| 규칙셋 | 내용 |
|-------|------|
| ET OPEN | 무료 오픈소스 IPS 규칙 (악성 IP, C2 탐지) |
| AWS Managed Threat Signatures | AWS 제공 관리형 규칙 |
| 커스텀 규칙 | 환경에 맞는 추가 규칙 작성 |

---

## AWS WAF

### 역할 및 배치 위치

- **L7 HTTP/HTTPS** 전용 (웹 애플리케이션 방어)
- CloudFront, ALB, API Gateway, AppSync에 연결 가능

```
인터넷
  │
CloudFront + WAF  ← 전역 엣지 레이어
  │
ALB + WAF         ← 리전 레이어 (CloudFront 없는 경우)
  │
워크로드 (ECS, EC2, Lambda)
```

### WAF Rule Group 구성

#### AWS Managed Rule Group (기본 적용 권장)

| Rule Group | 목적 |
|-----------|------|
| AWSManagedRulesCommonRuleSet | OWASP Top 10 일반 공격 차단 |
| AWSManagedRulesKnownBadInputsRuleSet | 알려진 악성 입력 차단 |
| AWSManagedRulesSQLiRuleSet | SQL Injection 방어 |
| AWSManagedRulesLinuxRuleSet | Linux 환경 공격 차단 |
| AWSManagedRulesAmazonIpReputationList | 악성 IP 차단 |

#### 커스텀 Rule 예시

```
# 특정 국가 IP 차단 (Geo Match)
Rule: Block requests from specific countries
  Condition: GeoMatch NOT IN [KR, US, JP]
  Action: Block

# 요청 속도 제한 (Rate Limit)
Rule: Rate limit per IP
  Condition: Rate > 2000 req/5min per IP
  Action: Block

# 특정 URI 경로 보호
Rule: Protect admin endpoints
  Condition: URI starts with /admin
  AND: NOT IP in [허용된 관리자 IP 대역]
  Action: Block
```

### AWS Firewall Manager

멀티 어카운트에서 WAF/SG/Network Firewall 정책을 중앙 관리합니다.

```
Audit Account (또는 Security Account)
  └── AWS Firewall Manager (Administrator 계정 지정)
        │
        ├── WAF Policy → 전 계정 ALB/CloudFront에 자동 적용
        ├── Security Group Policy → 허용/차단 SG 규칙 강제
        └── Network Firewall Policy → 전 계정 VPC에 자동 배포
```

**Firewall Manager 활성화 조건:**
- AWS Organizations 활성화
- AWS Config 활성화 (전 계정)
- Firewall Manager 관리자 계정 지정

---

## AWS Shield

### Shield Standard vs Advanced

| 항목 | Standard | Advanced |
|------|---------|---------|
| 비용 | 무료 | $3,000/월 (최소 1년 약정) |
| 보호 대상 | CloudFront, Route53, ELB | EC2 EIP, ALB, NLB, CloudFront, Route53, Global Accelerator |
| DDoS 탐지 | 기본 | 고급 (L3/L4/L7) |
| 대응팀 (SRT) | 없음 | 24/7 DDoS Response Team |
| 비용 보호 | 없음 | 공격으로 인한 스케일아웃 비용 크레딧 |
| 실시간 가시성 | 없음 | CloudWatch 메트릭, 이벤트 보고서 |

> **권장:** 인터넷 노출 서비스가 있는 프로덕션 환경은 Shield Advanced 도입 검토

---

## 보안 서비스 계층 요약

```
인터넷 트래픽 흐름:
인터넷 → Shield (DDoS) → CloudFront + WAF (L7) → ALB + WAF → 워크로드

내부 트래픽 흐름:
VPC → TGW → Network Firewall (L3-L7) → 목적지 VPC

위협 탐지:
GuardDuty → VPC Flow Log, DNS Log, CloudTrail 분석 → 이상 탐지 알람
```

---

## 로그 수집

| 서비스 | 로그 대상 | 저장소 |
|-------|---------|-------|
| Network Firewall | Alert 및 Flow 로그 | S3 (Log Archive 계정) |
| WAF | 요청 로그 | S3 또는 CloudWatch Logs |
| Shield Advanced | 공격 이벤트 | CloudWatch, 이메일 알람 |
| VPC Flow Log | 전체 VPC 트래픽 | S3 (Log Archive 계정) |

---

## 관련 문서

- [08. 인터넷 Egress 전략](./08-internet-egress.md)
- [11. 보안 서비스 운영](./11-security-services.md)
- [03. Account 전략](./03-account-strategy.md)
