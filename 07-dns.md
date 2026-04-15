# 07. DNS 전략

## 개요

멀티 어카운트 환경에서 DNS는 단순히 이름 해석을 넘어
온프레미스 ↔ AWS 간 서비스 디스커버리의 핵심 인프라입니다.
Route53 Resolver를 중심으로 중앙집중식 DNS 아키텍처를 구성합니다.

---

## 전체 DNS 아키텍처

```
온프레미스 DNS 서버 (예: 192.168.0.1)
        │
        │ ← corp.example.com 질의 응답
        │ → aws.example.com 질의 전달 (Forwarding)
        │
   [Direct Connect / VPN]
        │
Route53 Resolver Inbound Endpoint   ← 온프레미스에서 AWS 도메인 질의 수신
(Network Account VPC, Private Subnet)
        │
Route53 Private Hosted Zone
  aws.example.com, svc.internal 등
        │
Route53 Resolver Outbound Endpoint  → 온프레미스 도메인 질의 전달
(Network Account VPC, Private Subnet)
        │
   [Direct Connect / VPN]
        │
온프레미스 DNS 서버
```

---

## Route53 구성 요소

### Private Hosted Zone (PHZ)

AWS 내부에서 사용하는 사설 DNS 도메인입니다.

| 항목 | 내용 |
|------|------|
| 용도 | VPC 내 리소스 이름 해석 |
| 연결 방식 | VPC에 Association |
| 멀티 계정 공유 | RAM 또는 CLI로 크로스 어카운트 Association |

**PHZ 네이밍 전략 예시:**

| 도메인 | 용도 |
|--------|------|
| aws.example.com | AWS 전용 내부 도메인 |
| prod.aws.example.com | 프로덕션 서비스 |
| dev.aws.example.com | 개발 환경 서비스 |
| svc.internal | 마이크로서비스 내부 통신 |
| db.internal | 데이터베이스 엔드포인트 |

> **원칙:** 퍼블릭 도메인(example.com)과 내부 도메인을 동일하게 쓰지 말 것.
> Split-horizon DNS로 관리 가능하지만 복잡도가 높아짐.

### Resolver Endpoint

| 타입 | 방향 | 역할 |
|------|------|------|
| Inbound Endpoint | 온프레미스 → AWS | 온프레미스 DNS 서버가 AWS 도메인을 질의할 때 수신 |
| Outbound Endpoint | AWS → 온프레미스 | AWS에서 온프레미스 도메인을 질의할 때 전달 |

**Endpoint 설계:**
- Network Account VPC의 **Private Subnet**에 배치
- AZ당 ENI 1개 (최소 2개 AZ → 최소 2개 ENI)
- IP 주소는 고정값 사용 (온프레미스 DNS Forwarder 설정에 필요)

---

## 멀티 어카운트 DNS 통합 패턴

### 중앙 집중식 Resolver (권장)

```
워크로드 계정 VPC
        │
        │ DNS 질의 (169.254.169.253 또는 VPC+2 주소)
        ▼
Route53 Resolver (각 VPC 기본)
        │
        │ Forwarding Rule 적용
        ▼
Network Account Outbound Endpoint   ← RAM으로 Forwarding Rule 공유
        │
온프레미스 DNS 서버
```

**Resolver Forwarding Rule 공유:**
- Network Account에서 Forwarding Rule 생성
- AWS RAM으로 Organizations 전체 또는 특정 OU에 공유
- 각 계정 VPC에 Rule Association → 별도 설정 불필요

### Forwarding Rule 예시

| Rule 타입 | 도메인 | 전달 대상 |
|----------|--------|---------|
| Forward | corp.example.com | 온프레미스 DNS (192.168.0.1) |
| Forward | on-prem.internal | 온프레미스 DNS (192.168.0.1) |
| System | aws.example.com | Route53 (기본값 사용) |

---

## 크로스 어카운트 Private Hosted Zone Association

워크로드 계정의 VPC에서 Network Account의 PHZ를 조회하려면
크로스 어카운트 VPC Association이 필요합니다.

### 연결 절차

```
1. Network Account: PHZ 생성 (aws.example.com)
2. Network Account: 크로스 어카운트 Authorization 생성
   aws route53 create-vpc-association-authorization \
     --hosted-zone-id <PHZ_ID> \
     --vpc VPCRegion=ap-northeast-2,VPCId=<WORKLOAD_VPC_ID>

3. Workload Account: VPC Association 요청
   aws route53 associate-vpc-with-hosted-zone \
     --hosted-zone-id <PHZ_ID> \
     --vpc VPCRegion=ap-northeast-2,VPCId=<WORKLOAD_VPC_ID>

4. Network Account: Authorization 삭제 (연결 완료 후)
```

> **자동화:** AWS RAM + Terraform 또는 Lambda로 계정 생성 시 자동 Association 처리 권장

---

## VPC Interface Endpoint와 DNS

VPC Interface Endpoint 생성 시 AWS 서비스의 프라이빗 DNS가 자동 생성됩니다.

```
예: ECR API Endpoint 생성 시
api.ecr.ap-northeast-2.amazonaws.com
  → VPC 내에서 해당 도메인이 Endpoint ENI IP로 해석됨
```

**멀티 계정 Endpoint DNS 공유 전략:**

| 방식 | 설명 | 장단점 |
|------|------|--------|
| 계정별 Endpoint | 각 계정에 Interface Endpoint 생성 | 독립적, 비용 증가 |
| 중앙 Endpoint + PHZ | Network Account에 Endpoint 생성, PHZ로 DNS 공유 | 비용 절감, 구성 복잡 |

**중앙 Endpoint 공유 구성:**
```
Network Account: Interface Endpoint 생성 (예: ECR)
                 → ENI IP 확인 (예: 10.192.1.10, 10.192.2.10)
Network Account: PHZ 생성 (api.ecr.ap-northeast-2.amazonaws.com)
                 → A 레코드: 10.192.1.10, 10.192.2.10
Network Account: PHZ → 각 워크로드 VPC에 크로스 어카운트 Association
```

---

## DNS 설계 체크리스트

- [ ] 내부 도메인 네이밍 컨벤션 확정
- [ ] Resolver Inbound/Outbound Endpoint IP 고정 및 온프레미스 DNS 팀에 공유
- [ ] Forwarding Rule RAM 공유 설정
- [ ] PHZ 크로스 어카운트 Association 자동화
- [ ] 온프레미스 DNS 서버에 AWS 도메인 Forwarder 설정 확인
- [ ] DNS 질의 로그 활성화 (Route53 Resolver Query Logging)

---

## 관련 문서

- [05. Transit Gateway 전략](./05-tgw.md)
- [06. Direct Connect 전략](./06-dx.md)
- [08. 인터넷 Egress 전략](./08-internet-egress.md)
