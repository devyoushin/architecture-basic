# 08. 인터넷 Egress 전략

## 개요

멀티 어카운트 환경에서 인터넷 아웃바운드(Egress) 트래픽을 각 계정에서 개별 처리하면
보안 통제가 분산되고 NAT Gateway 비용이 계정 수만큼 증가합니다.
중앙집중식 Egress 아키텍처로 보안과 비용을 동시에 최적화합니다.

---

## 분산 Egress vs 중앙 Egress 비교

| 항목 | 계정별 분산 Egress | 중앙집중식 Egress |
|------|-----------------|----------------|
| NAT Gateway | 계정 × AZ 수만큼 비용 발생 | Network Account에서 통합 |
| 보안 통제 | 계정별 개별 관리 | 단일 지점에서 중앙 통제 |
| 트래픽 가시성 | 계정별 분산 | Network Firewall로 통합 검사 |
| 구성 복잡도 | 낮음 | 높음 |
| 아웃바운드 IP | 계정마다 다른 EIP | 고정 EIP 관리 용이 |

> **권장:** 보안 요건이 있거나 계정이 5개 이상이면 중앙 Egress 구성 검토

---

## 중앙집중식 Egress 아키텍처

### Inspection VPC 패턴

```
[워크로드 계정 VPC]
  Private Subnet
        │ 0.0.0.0/0 → TGW
        ▼
[Network Account]
  Transit Gateway
        │ 0.0.0.0/0 → Inspection VPC Attachment
        ▼
  Inspection VPC
  ┌─────────────────────────────┐
  │  TGW Attachment Subnet      │
  │        │                    │
  │  AWS Network Firewall       │ ← 트래픽 검사 (URL 필터링, IPS)
  │        │                    │
  │  NAT Gateway Subnet         │
  │   NAT Gateway (고정 EIP)    │
  │        │                    │
  │  Public Subnet → IGW        │
  └─────────────────────────────┘
        │
   인터넷
```

### TGW Appliance Mode

- Inspection VPC의 TGW Attachment에는 **Appliance Mode 활성화 필수**
- 비활성화 시 비대칭 라우팅 발생 → 패킷 드롭

---

## Inspection VPC 상세 구성

### 서브넷 구조 (AZ당 3개 서브넷)

```
Inspection VPC (10.192.0.0/16)
│
├── TGW Attachment Subnet (10.192.0.0/28) — AZ-a
│   └── TGW ENI 배치
│
├── Firewall Subnet (10.192.0.16/28) — AZ-a
│   └── Network Firewall Endpoint
│
└── NAT Subnet (10.192.0.32/28) — AZ-a
    ├── NAT Gateway
    └── Internet Gateway 연결
```

### 라우팅 테이블 구성

#### TGW Attachment Subnet RT
| 대상 | 타겟 |
|------|------|
| 0.0.0.0/0 | Network Firewall Endpoint |
| 10.0.0.0/8 | TGW (리턴 트래픽) |

#### Firewall Subnet RT
| 대상 | 타겟 |
|------|------|
| 0.0.0.0/0 | NAT Gateway |
| 10.0.0.0/8 | TGW |

#### NAT Subnet RT
| 대상 | 타겟 |
|------|------|
| 0.0.0.0/0 | Internet Gateway |
| 10.0.0.0/8 | Network Firewall Endpoint |

---

## TGW 라우팅 테이블 연동

중앙 Egress 구성 시 TGW 라우팅 테이블에 기본 경로를 추가합니다.

### RT-Workload (워크로드 계정 Attachment용)

| 대상 | 타겟 |
|------|------|
| 0.0.0.0/0 | Inspection VPC Attachment |
| 10.0.0.0/8 | 각 VPC Attachment (전파) |

### RT-Inspection (Inspection VPC Attachment용)

| 대상 | 타겟 |
|------|------|
| 10.0.0.0/8 | 각 VPC Attachment (전파) |
| (0.0.0.0/0 없음) | — Inspection VPC 자체가 IGW로 나감 |

---

## AWS Network Firewall 정책

### 정책 구성 레이어

```
Network Firewall Policy
├── Stateless Rule Group  ← 패킷 단위 빠른 필터링
│   - 특정 포트 차단 (예: Telnet 23, RDP 3389 → 인터넷)
│   - 허용/차단 후 Stateful로 전달
│
└── Stateful Rule Group   ← 연결 단위 심층 검사
    ├── Domain List Rule  ← URL 기반 허용/차단
    │   예: .amazonaws.com, .ubuntu.com 허용
    │       .torrent, .xyz 차단
    │
    └── Suricata Rule     ← IPS 서명 기반 탐지
        예: ET OPEN 규칙셋 적용
```

### 도메인 기반 필터링 예시

**허용 도메인 (Allowlist 방식 권장):**
```
.amazonaws.com
.ubuntu.com
.centos.org
.docker.io
.github.com
.pypi.org
.npmjs.org
```

**차단 도메인:**
```
# 데이터 유출 우려 도메인 예시
.pastebin.com
.ngrok.io
```

> **원칙:** 기본 차단(Default Deny) + 필요 도메인 허용(Allowlist) 방식이 보안상 권장

---

## 고정 EIP 관리

중앙 Egress 구성 시 NAT Gateway에 EIP를 고정 할당합니다.

| 항목 | 내용 |
|------|------|
| EIP 수 | AZ 수 × 1개 (AZ당 NAT GW 1개) |
| 등록 관리 | IP 대역을 외부 파트너/방화벽에 Allowlist로 등록 |
| 변경 영향 | EIP 변경 시 외부 파트너 화이트리스트 업데이트 필요 |

---

## 비용 분석

### 분산 Egress 비용 (예: 3계정 × 3AZ)
```
NAT Gateway: 9개 × $0.059/시간 × 720시간 = 약 $382/월
데이터 처리: 별도
```

### 중앙 Egress 비용 (3AZ)
```
NAT Gateway: 3개 × $0.059/시간 × 720시간 = 약 $127/월
Network Firewall: 3개 Endpoint × $0.395/시간 = 약 $854/월
데이터 처리: 별도

→ 계정 수가 많아질수록 NAT GW 절감 효과 증가
→ Network Firewall 비용은 보안 요건으로 판단
```

---

## 인터넷 Ingress 전략

Egress와 별도로 인터넷 인바운드(Ingress) 트래픽도 중앙화할 수 있습니다.

```
인터넷
  │
CloudFront (엣지 캐싱, DDoS 방어)
  │
ALB (Network Account 또는 각 계정)
  │
TGW
  │
워크로드 계정 VPC
```

> 워크로드 계정에서 직접 ALB를 노출하는 방식도 일반적.
> 보안 요건에 따라 중앙화 여부 결정.

---

## 관련 문서

- [05. Transit Gateway 전략](./05-tgw.md)
- [09. Network Firewall & WAF](./09-network-firewall-waf.md)
- [04. VPC & Subnet 전략](./04-vpc-subnet.md)
