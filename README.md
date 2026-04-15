# AWS 엔터프라이즈 아키텍처 전략

AWS 멀티 어카운트 환경에서의 아키텍처 설계 전략을 정리한 문서입니다.

## 목차

| 문서 | 설명 |
|------|------|
| [01. Landing Zone 전략](./01-landing-zone.md) | Control Tower 기반 랜딩존 설계 원칙 |
| [02. OU 전략](./02-ou-strategy.md) | 조직 단위(OU) 계층 구조 및 SCP 설계 |
| [03. Account 전략](./03-account-strategy.md) | 계정 분리 기준 및 공통 계정 구성 |
| [04. VPC & Subnet 전략](./04-vpc-subnet.md) | CIDR 계획 및 서브넷 티어 설계 |
| [05. Transit Gateway 전략](./05-tgw.md) | TGW Hub-Spoke 구성 및 라우팅 정책 |
| [06. Direct Connect 전략](./06-dx.md) | 전용선 연결 및 VIF 구성 전략 |
| [07. DNS 전략](./07-dns.md) | Route53 Resolver, PHZ, 온프레미스 DNS 통합 |
| [08. 인터넷 Egress 전략](./08-internet-egress.md) | 중앙집중식 Egress, Inspection VPC, NAT GW |
| [09. Network Firewall & WAF](./09-network-firewall-waf.md) | East-West 검사, WAF, Shield, Firewall Manager |
| [10. IAM 전략](./10-iam.md) | Permission Boundary, Identity Center, 장기 자격증명 통제 |
| [11. 보안 서비스 운영](./11-security-services.md) | GuardDuty, Security Hub, Config Rules, 자동 대응 플로우 |
| [12. 비용 관리 전략](./12-cost-management.md) | CUR, Budgets, Savings Plans, 비용 이상 탐지 |
| [13. 모니터링 & 관찰가능성](./13-monitoring-observability.md) | 로그/메트릭/트레이스 중앙화, 알람 설계 |
| [14. 백업 & DR 전략](./14-backup-dr.md) | RTO/RPO, AWS Backup, DR 패턴, DR 훈련 |
| [15. 태깅 전략](./15-tagging.md) | 필수 태그 표준, SCP 강제, Cost Allocation Tag |
| [16. CI/CD 크로스 어카운트 배포](./16-cicd-cross-account.md) | 파이프라인 설계, Blue/Green, ECR 멀티 계정, IaC |
| [17. KMS & 암호화 전략](./17-kms-encryption.md) | 키 계층 구조, CMK 설계, 크로스 계정 키 공유, TLS |
| [18. EKS 전략](./18-eks.md) | 클러스터 설계, IRSA, Karpenter, GitOps, 보안 |
| [19. 마이그레이션 전략](./19-migration.md) | 7R 전략, MGN, DMS, DataSync, Cutover 계획 |
| [20. Service Catalog & 셀프서비스](./20-service-catalog.md) | 셀프 프로비저닝, 표준 제품, 승인 워크플로우 |

## 전체 구조 개요

```
온프레미스 데이터센터
        │
   Direct Connect
        │
  [Network 계정]
   Transit Gateway
    ┌──────┼──────┐
    │      │      │
 Dev 계정  Stg 계정  Prd 계정
  VPC      VPC     VPC
```

## 설계 원칙

- **최소 권한 원칙** — 계정/OU 단위 SCP로 권한 경계 명확히 설정
- **네트워크 중앙화** — TGW를 Network 계정에 집중, 라우팅 통제
- **환경 격리** — Dev / Staging / Production 계정 완전 분리
- **가시성 확보** — Log Archive 계정으로 전사 로그 중앙 집계
