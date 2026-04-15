# 04. VPC & Subnet 전략

## 개요

멀티 어카운트 환경에서 VPC와 서브넷은 계정 간 IP 충돌 없이,
확장 가능하게 설계되어야 합니다.
CIDR 계획은 초기에 충분히 수립하지 않으면 나중에 변경이 매우 어렵습니다.

---

## CIDR 설계 원칙

### 전사 IP 대역 할당 계획

```
10.0.0.0/8  ← 전사 AWS 전용 대역 (예시)
│
├── 10.0.0.0/10   → Production 환경
├── 10.64.0.0/10  → Staging 환경
├── 10.128.0.0/10 → Dev 환경
└── 10.192.0.0/10 → Infrastructure (Network, Shared Services)
```

> **핵심 원칙:**
> - AWS VPC 대역과 온프레미스 대역은 **절대 중복 불가**
> - 계정별 VPC CIDR은 **겹치지 않게** 중앙 관리대장 필수 운영
> - TGW, VPC Peering 환경에서 CIDR 중복 시 라우팅 불가

### 계정별 VPC CIDR 할당 예시

| 계정 | VPC CIDR | 용도 |
|------|----------|------|
| Network (Hub) | 10.192.0.0/16 | TGW, DX, Inspection |
| Shared Services | 10.193.0.0/16 | CI/CD, ECR, 모니터링 |
| Prod-ServiceA | 10.0.0.0/16 | 프로덕션 워크로드 |
| Prod-ServiceB | 10.1.0.0/16 | 프로덕션 워크로드 |
| Stg-ServiceA | 10.64.0.0/16 | 스테이징 워크로드 |
| Dev-ServiceA | 10.128.0.0/16 | 개발 워크로드 |

---

## VPC 설계

### VPC 기본 설정

| 항목 | 권장 값 |
|------|--------|
| VPC CIDR | /16 (계정당 최대 65,536개 IP) |
| DNS Hostname | 활성화 |
| DNS Resolution | 활성화 |
| Default VPC | 전 리전 삭제 (기준선 적용) |
| IPv6 | 필요 시 선택적 활성화 |

### 가용 영역 (AZ) 전략

- **최소 2개 AZ** 사용 (고가용성 기본)
- **권장 3개 AZ** 사용 (AZ 장애 시 2/3 유지)
- AZ당 동일한 서브넷 구조 유지 (대칭 설계)

---

## 서브넷 티어 설계

### 3-Tier 서브넷 구조

```
VPC (10.0.0.0/16)
│
├── Public Subnet (10.0.0.0/20) — AZ-a
│   인터넷 직접 노출, IGW 라우팅
│   용도: ALB, NAT Gateway, Bastion (필요 시)
│
├── Public Subnet (10.0.16.0/20) — AZ-b
│
├── Public Subnet (10.0.32.0/20) — AZ-c
│
├── Private Subnet (10.0.64.0/20) — AZ-a
│   인터넷 직접 노출 없음, NAT GW 통해 아웃바운드만
│   용도: ECS/EKS 워크로드, EC2 애플리케이션, Lambda
│
├── Private Subnet (10.0.80.0/20) — AZ-b
│
├── Private Subnet (10.0.96.0/20) — AZ-c
│
├── Isolated Subnet (10.0.128.0/20) — AZ-a
│   인터넷 접근 없음 (인바운드/아웃바운드 모두 차단)
│   용도: RDS, ElastiCache, 내부 API
│
├── Isolated Subnet (10.0.144.0/20) — AZ-b
│
└── Isolated Subnet (10.0.160.0/20) — AZ-c
```

### 티어별 특성 요약

| 티어 | 인바운드 | 아웃바운드 | 주요 용도 |
|------|---------|-----------|----------|
| Public | IGW (인터넷) | IGW (인터넷) | ALB, NAT GW |
| Private | VPC 내부, TGW | NAT GW 통해 인터넷 | 앱 서버, 컨테이너 |
| Isolated | VPC 내부만 | VPC 내부만 | DB, 캐시, 내부 서비스 |

---

## 라우팅 테이블 설계

### Public Subnet 라우팅

| 대상 | 타겟 |
|------|------|
| 0.0.0.0/0 | Internet Gateway |
| 10.0.0.0/8 | Transit Gateway |
| 온프레미스 CIDR | Transit Gateway |

### Private Subnet 라우팅

| 대상 | 타겟 |
|------|------|
| 0.0.0.0/0 | NAT Gateway |
| 10.0.0.0/8 | Transit Gateway |
| 온프레미스 CIDR | Transit Gateway |

### Isolated Subnet 라우팅

| 대상 | 타겟 |
|------|------|
| 10.0.0.0/8 | Transit Gateway (필요 시) |
| (기본값 없음) | — |

---

## NAT Gateway 구성

### 고가용성 구성

```
AZ-a                AZ-b                AZ-c
NAT GW-a            NAT GW-b            NAT GW-c
   ↑                   ↑                   ↑
Private-a           Private-b           Private-c
```

- AZ당 NAT Gateway 1개 배치
- 각 AZ의 Private 서브넷은 **동일 AZ의 NAT GW** 사용 (AZ 간 데이터 전송 비용 절감)
- 비용 최소화가 필요한 Dev 환경은 NAT GW 1개 공유 허용

---

## 보안 그룹 설계 원칙

### 계층 간 트래픽 흐름

```
인터넷
  │ HTTPS(443)
  ▼
ALB (Public Subnet)
  │ HTTP(8080) 또는 HTTPS(443)
  ▼
App Server (Private Subnet)
  │ TCP(5432/3306/6379)
  ▼
DB / Cache (Isolated Subnet)
```

### 보안 그룹 작성 원칙

- **인바운드:** 최소 허용 (필요한 포트, 소스만)
- **아웃바운드:** 기본 전체 허용 또는 필요 대역만 제한
- CIDR 대신 **보안 그룹 참조** 우선 사용 (유지보수 용이)
- 0.0.0.0/0 인바운드는 ALB 등 인터넷 엔드포인트 외 금지

---

## VPC Endpoint 구성

VPC에서 AWS 서비스 접근 시 인터넷 경유를 방지합니다.

| 서비스 | 엔드포인트 타입 | 필수 여부 |
|-------|--------------|---------|
| S3 | Gateway | 필수 |
| DynamoDB | Gateway | 권장 |
| ECR (API, DKR) | Interface | 필수 (컨테이너 환경) |
| SSM, SSMMessages | Interface | 필수 (Session Manager) |
| Secrets Manager | Interface | 권장 |
| CloudWatch Logs | Interface | 권장 |
| STS | Interface | 권장 |

> **비용 고려:** Interface 엔드포인트는 AZ당 요금 발생 ($0.01/시간)
> Shared Services 계정에 중앙 엔드포인트 구성 후 공유하는 방식도 검토

---

## 관련 문서

- [03. Account 전략](./03-account-strategy.md)
- [05. Transit Gateway 전략](./05-tgw.md)
