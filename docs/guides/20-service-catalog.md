# 20. Service Catalog & 셀프서비스 전략

## 개요

멀티 어카운트 환경에서 개발팀이 인프라를 필요로 할 때마다
인프라팀에 요청하면 병목이 발생합니다.
AWS Service Catalog를 통해 사전 승인된 인프라 템플릿을 셀프서비스로 제공하고,
인프라팀은 표준 정의와 거버넌스에 집중합니다.

---

## 셀프서비스 원칙

```
인프라팀 (Platform Team)
  └── 표준 제품(Product) 정의 및 관리
  └── 거버넌스 정책 설정 (보안, 비용, 태그 등)

개발팀 (Consumer)
  └── Service Catalog에서 승인된 제품 선택
  └── 파라미터 입력 후 셀프 프로비저닝
  └── 인프라팀 대기 시간 없음
```

---

## AWS Service Catalog 구성

### 핵심 구성 요소

| 구성 요소 | 설명 |
|---------|------|
| Portfolio | 관련 제품의 묶음. 특정 팀/OU에 공유 |
| Product | CloudFormation 또는 Terraform 기반 인프라 템플릿 |
| Provisioned Product | 개발팀이 배포한 제품 인스턴스 |
| Constraint | 제품에 적용되는 제한 (IAM, 파라미터, 알람 등) |
| Launch Role | 제품 배포 시 사용하는 IAM 역할 (개발자 권한 불필요) |

### 멀티 계정 공유 구조

```
Shared Services Account (또는 Management Account)
  Service Catalog 포트폴리오 생성
        │ AWS Organizations 또는 계정별 공유
        ▼
각 워크로드 계정
  Service Catalog 제품 목록 조회 및 배포
```

---

## 제공 제품(Product) 구성 예시

### 1. VPC 표준 제품

개발팀이 신규 VPC가 필요할 때 요청합니다.

```
파라미터:
  - 환경 (dev / stg / prod)
  - CIDR 블록 (사전 정의된 목록에서 선택)
  - AZ 수 (2 또는 3)

자동 생성 리소스:
  - VPC
  - Public / Private / Isolated 서브넷
  - Internet Gateway
  - NAT Gateway
  - Route Table
  - TGW Attachment (자동 연결 요청)
  - 기본 보안 그룹
```

### 2. RDS 표준 제품

```
파라미터:
  - DB 엔진 (Aurora MySQL / Aurora PostgreSQL / RDS MySQL 등)
  - 인스턴스 클래스 (선택 목록 제한)
  - 스토리지 크기
  - 멀티 AZ 여부
  - 암호화 여부 (기본 활성화 강제)

자동 적용:
  - KMS CMK 암호화
  - 자동 백업 7일 보존
  - 삭제 보호 활성화 (Prod)
  - Parameter Group (최적화된 표준 설정)
  - 필수 태그 자동 부여
```

### 3. ECS 서비스 표준 제품

```
파라미터:
  - 서비스명
  - 컨테이너 이미지 URI
  - CPU / 메모리
  - 원하는 태스크 수
  - ALB 연결 여부

자동 생성:
  - ECS Task Definition
  - ECS Service
  - ALB Target Group
  - Auto Scaling 정책
  - CloudWatch 알람 (CPU, 메모리)
  - IAM Task Role (최소 권한)
```

### 4. S3 버킷 표준 제품

```
파라미터:
  - 버킷 용도 (data / logs / artifacts / backup)
  - 데이터 분류 (public / internal / confidential)
  - 수명 주기 정책 (30일 / 90일 / 365일)

자동 적용:
  - 퍼블릭 액세스 차단 (강제)
  - KMS 암호화 (강제)
  - 버전 관리 (confidential은 강제)
  - 수명 주기 정책
  - 필수 태그
```

---

## Constraint (제약) 설계

제품 배포 시 적용하는 제한 규칙입니다.

### Launch Constraint

- 개발팀이 아닌 **사전 정의된 Launch Role**로 배포
- 개발팀에게 인프라 배포 권한을 직접 부여하지 않아도 됨

```
개발팀 (제한된 권한)
  → Service Catalog에 배포 요청
  → Launch Role (인프라팀이 설정, 적절한 권한 보유)이 실제 CloudFormation 실행
```

### Parameter Constraint

특정 파라미터 값을 허용 목록으로 제한합니다.

```
인스턴스 타입 허용 목록:
  t3.medium, t3.large, m5.large, m5.xlarge
  (p4d, trn1 등 고비용 타입 제외)

리전 제한:
  ap-northeast-2만 허용
```

### Notification Constraint

배포 이벤트를 SNS로 알람 전송합니다.

```
제품 배포 / 업데이트 / 삭제
  → SNS Topic → Slack 알람 (인프라팀 채널)
```

---

## 승인 워크플로우 (선택)

비용이 크거나 민감한 제품은 자동 배포 대신 승인 프로세스를 추가합니다.

```
개발팀: Service Catalog에서 배포 요청
        │
   AWS Service Catalog 승인 요청
        │
   SNS → 인프라팀 알람 (Slack, 이메일)
        │
   인프라팀 검토 및 승인/거부
        │
   승인 → 자동 CloudFormation 배포
   거부 → 개발팀에 사유 전달
```

### 승인이 필요한 제품 기준 (예시)

| 제품 | 승인 필요 여부 |
|------|-------------|
| t3.medium EC2 | 불필요 (자동 배포) |
| m5.4xlarge 이상 EC2 | 필요 |
| Prod 환경 RDS | 필요 |
| 외부 접근 가능한 S3 버킷 | 필요 |
| DX 연결 변경 | 필요 |

---

## IaC 연동 (Terraform 기반)

Service Catalog는 CloudFormation 외에 Terraform을 외부 패키지로 사용할 수 있습니다.

### Service Catalog + Terraform 구성

```
Git Repository (Terraform 모듈)
        │ 버전 태그 (v1.0.0)
        ▼
S3 (Terraform 패키지 저장)
        │
AWS Service Catalog (External Product - Terraform)
        │
개발팀 배포 요청
        │
AWS Service Catalog Terraform Engine
  (별도 엔진 계정 또는 Shared Services Account에 배포)
        │
워크로드 계정 Terraform Apply
```

---

## 제품 버전 관리

인프라 표준이 변경될 때 기존 배포에 영향 없이 신규 버전을 배포합니다.

```
Product v1.0 → 기존 배포에 유지
Product v2.0 → 신규 배포는 v2.0 사용
               기존 v1.0 배포는 v2.0으로 업데이트 안내
```

- 버전별 변경 이력 및 마이그레이션 가이드 제공
- 하위 호환 불가 변경 시 별도 마이그레이션 지원

---

## 운영 대시보드

인프라팀이 전체 배포 현황을 모니터링합니다.

| 항목 | 확인 내용 |
|------|---------|
| 배포 현황 | 계정별, 팀별 배포된 제품 목록 |
| 비용 현황 | 제품별 발생 비용 (태그 기반) |
| 드리프트 감지 | CloudFormation Drift Detection으로 수동 변경 탐지 |
| 미사용 제품 | 배포 후 사용하지 않는 리소스 탐지 |

---

## 관련 문서

- [03. Account 전략](./03-account-strategy.md)
- [10. IAM 전략](./10-iam.md)
- [15. 태깅 전략](./15-tagging.md)
- [16. CI/CD 크로스 어카운트 배포](./16-cicd-cross-account.md)
