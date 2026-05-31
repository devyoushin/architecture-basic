# 05. Transit Gateway (TGW) 전략

## 개요

Transit Gateway는 멀티 어카운트 환경에서 VPC 간, VPC-온프레미스 간 연결을
중앙에서 관리하는 허브 역할을 합니다.
VPC Peering 대비 확장성과 운영 효율성이 뛰어납니다.

---

## VPC Peering vs Transit Gateway

| 항목 | VPC Peering | Transit Gateway |
|------|-------------|----------------|
| 연결 방식 | 1:1 (Mesh) | Hub-Spoke |
| 확장성 | VPC 증가 시 연결 수 폭발적 증가 | VPC 추가 시 TGW 연결만 추가 |
| 전이적 라우팅 | 불가 | 가능 (라우팅 테이블 설정) |
| 대역폭 | 무제한 | 최대 50Gbps/연결 |
| 비용 | 데이터 전송 비용만 | 연결 비용 + 데이터 전송 비용 |
| 관리 복잡도 | VPC 많을수록 복잡 | 중앙 집중 관리 |

> **결론:** 멀티 어카운트 환경에서는 **Transit Gateway** 표준 채택

---

## TGW Hub-Spoke 아키텍처

```
                    [Network Account]
                    Transit Gateway
                          │
          ┌───────────────┼───────────────┐
          │               │               │
   [Shared Services]  [Prod VPC]     [Dev VPC]
      Account             │               │
                    [Stg VPC]        [Sandbox VPC]
                          │
                   [온프레미스]
                  (DX or VPN)
```

### 구성 원칙

- TGW는 **Network Account**에 단일 배치 (Resource Access Manager로 다른 계정 공유)
- 각 워크로드 계정의 VPC는 TGW에 Attachment로 연결
- 라우팅 정책은 TGW 라우팅 테이블로 중앙 제어

---

## TGW 구성 상세

### 기본 설정

| 항목 | 값 |
|------|---|
| ASN | 64512 (사설 ASN, 온프레미스 ASN과 충돌 금지) |
| DNS Support | 활성화 |
| VPN ECMP Support | 활성화 |
| Default Route Table Association | 비활성화 (라우팅 테이블 수동 관리) |
| Default Route Table Propagation | 비활성화 (라우팅 테이블 수동 관리) |

> Default Association/Propagation을 비활성화하면
> 모든 라우팅을 명시적으로 설정해야 합니다.
> 초기에는 복잡하지만 환경 간 격리를 정확히 제어할 수 있습니다.

---

## TGW 라우팅 테이블 설계

### 라우팅 테이블 분리 전략

환경별로 라우팅 테이블을 분리하여 트래픽 흐름을 제어합니다.

```
TGW
├── RT-Production     → Prod VPC, Shared Services, 온프레미스만 통신 허용
├── RT-NonProduction  → Stg/Dev VPC, Shared Services 통신 허용, Prod 격리
├── RT-SharedServices → 모든 RT와 통신 (공통 서비스 제공)
└── RT-OnPrem         → 온프레미스 ↔ 허용된 VPC만 통신
```

### 라우팅 테이블 상세

#### RT-Production

| 대상 CIDR | 연결 대상 | 설명 |
|----------|----------|------|
| 10.0.0.0/16 | Prod VPC | 자기 자신 |
| 10.193.0.0/16 | Shared Services VPC | 공용 서비스 접근 |
| 온프레미스 CIDR | DX/VPN Attachment | 온프레미스 연결 |

#### RT-NonProduction

| 대상 CIDR | 연결 대상 | 설명 |
|----------|----------|------|
| 10.64.0.0/16 | Stg VPC | 스테이징 |
| 10.128.0.0/16 | Dev VPC | 개발 |
| 10.193.0.0/16 | Shared Services VPC | 공용 서비스 접근 |
| ~~10.0.0.0/16~~ | ~~(없음)~~ | Prod와 격리 |

#### RT-SharedServices

| 대상 CIDR | 연결 대상 | 설명 |
|----------|----------|------|
| 10.0.0.0/8 | 모든 VPC | 전체 환경에 서비스 제공 |

---

## RAM (Resource Access Manager)을 통한 TGW 공유

TGW는 Network Account에 위치하며, RAM으로 다른 계정에 공유합니다.

```
Network Account (TGW 소유)
        │
   AWS RAM Share
        │
   ┌────┴────────────────────┐
   │                         │
Prod Account            Dev Account
(TGW Attachment 생성)   (TGW Attachment 생성)
```

### 공유 설정

- RAM 공유 단위: AWS Organizations OU 또는 개별 계정
- 공유 받은 계정에서 TGW Attachment 생성 후 Network Account에서 수락
- Attachment 수락 후 라우팅 테이블 연결은 **Network Account**에서 수행

---

## 트래픽 검사 (선택)

보안 요건에 따라 VPC 간 트래픽 또는 인터넷 트래픽을 검사할 수 있습니다.

### Inspection VPC 패턴

```
Spoke VPC → TGW → [Inspection VPC (AWS Network Firewall)] → TGW → 목적지
```

- Inspection VPC는 Network Account에 배치
- TGW Appliance Mode 활성화 필요 (비대칭 라우팅 방지)
- 대상: 인터넷 Egress 트래픽, VPC 간 East-West 트래픽

---

## 비용 최적화

| 항목 | 비용 발생 기준 | 절감 방법 |
|------|-------------|---------|
| TGW Attachment | 계정당 시간당 요금 | 계정 수 최소화 |
| 데이터 처리 | GB당 요금 | 리전 내 트래픽 최소화 |
| AZ 간 트래픽 | GB당 요금 | AZ 로컬 통신 우선 설계 |

---

## 관련 문서

- [04. VPC & Subnet 전략](./04-vpc-subnet.md)
- [06. Direct Connect 전략](./06-dx.md)
