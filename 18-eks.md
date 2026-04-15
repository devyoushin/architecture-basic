# 18. EKS 전략

## 개요

Amazon EKS(Elastic Kubernetes Service)는 AWS에서 관리형 쿠버네티스를 운영하는 서비스입니다.
멀티 어카운트 환경에서 EKS 클러스터 설계, 네트워킹, 보안, 운영 표준을 정립합니다.

---

## 클러스터 설계 원칙

### 클러스터 분리 기준

| 분리 방식 | 설명 | 권장 |
|---------|------|------|
| 환경별 분리 | Prod / Stg / Dev 클러스터 분리 | 권장 (계정 분리와 일치) |
| 테넌트별 분리 | 서비스 도메인별 클러스터 | 서비스 간 완전 격리 필요 시 |
| 네임스페이스 분리 | 단일 클러스터 내 네임스페이스로 분리 | 소규모 또는 비용 최적화 시 |

> **권장 원칙:** 계정 분리(Prod/Stg/Dev)와 클러스터를 1:1 대응시켜 보안 경계를 명확히 합니다.

### 클러스터 구성 요소

```
EKS Control Plane (AWS 관리, 멀티 AZ 자동 이중화)
        │
  Managed Node Group / Fargate
  ├── AZ-a: Worker Node
  ├── AZ-b: Worker Node
  └── AZ-c: Worker Node
        │
  VPC (계정 전용)
  ├── Private Subnet (Worker Node 배치)
  └── Public Subnet (ALB, Ingress)
```

---

## 네트워킹

### VPC CNI (Amazon VPC CNI Plugin)

EKS의 기본 CNI는 Amazon VPC CNI로, 파드에 VPC IP를 직접 할당합니다.

```
Worker Node (예: m5.xlarge)
  └── 최대 ENI 수 × ENI당 IP 수 = 최대 파드 수
      예: m5.xlarge → 4 ENI × 15 IP = 최대 58 파드/노드
```

**IP 고갈 방지 전략:**
- CIDR 계획 시 파드 IP 수요를 고려하여 충분한 서브넷 크기 확보
- VPC CNI prefix delegation 활성화 (/28 블록 단위 할당, 노드당 파드 수 대폭 증가)
- IPv6 전환 검토 (IP 고갈 근본 해결)

### EKS 엔드포인트 접근 제어

| 설정 | Public | Private | Public + Private |
|------|--------|---------|-----------------|
| API 서버 접근 | 인터넷 경유 | VPC 내부만 | 둘 다 가능 |
| 권장 환경 | 개발/테스트 | 프로덕션 | 관리 편의 필요 시 |

**프로덕션 권장 설정:**
```
Public Endpoint: 비활성화
Private Endpoint: 활성화
API 서버 접근: VPN 또는 Bastion을 통해서만
```

### Ingress 구성

```
인터넷
  │
AWS ALB (AWS Load Balancer Controller로 자동 프로비저닝)
  │
Kubernetes Ingress / Service
  │
Pod
```

- **AWS Load Balancer Controller** 사용 (EKS 공식 권장)
- ALB는 Public Subnet에, Pod는 Private Subnet에 배치
- ACM 인증서 ALB에 연결 (TLS Termination)

---

## IAM 연동

### IRSA (IAM Roles for Service Accounts) — 기존 방식

파드가 AWS 서비스에 접근할 때 IAM 역할을 직접 사용합니다.
노드 전체에 EC2 Instance Profile 부여하는 방식보다 훨씬 안전합니다.

```
파드 (ServiceAccount 연결)
  │ OIDC 토큰
  ▼
EKS OIDC Provider
  │ AssumeRoleWithWebIdentity
  ▼
IAM Role (파드 전용 최소 권한)
  │
AWS 서비스 (S3, DynamoDB, Secrets Manager 등)
```

**IRSA 설정 예시 (Terraform):**
```hcl
# IAM Role 생성 (특정 ServiceAccount만 AssumeRole 허용)
resource "aws_iam_role" "app_role" {
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Federated = aws_iam_openid_connect_provider.eks.arn
      }
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "${replace(aws_eks_cluster.main.identity[0].oidc[0].issuer, "https://", "")}:sub" =
            "system:serviceaccount:production:payment-api"
        }
      }
    }]
  })
}
```

### EKS Pod Identity — 권장 (신규 환경)

2023 re:Invent에서 발표된 IRSA의 진화형입니다. OIDC Provider 관리가 필요 없고, 클러스터 수가 많아질수록 운영이 훨씬 단순해집니다.

| 항목 | IRSA | EKS Pod Identity |
|------|------|-----------------|
| OIDC Provider | 클러스터당 1개 생성 필요 | 불필요 |
| IAM Trust Policy | OIDC ARN 포함, 클러스터별 상이 | 표준 형태, 재사용 가능 |
| 멀티 클러스터 | 클러스터마다 IAM Role 별도 | 동일 IAM Role 여러 클러스터 재사용 |
| 지원 범위 | 전체 EKS 버전 | EKS 1.24 이상 |

```hcl
# Pod Identity Association 설정 (Terraform)
resource "aws_eks_pod_identity_association" "payment_api" {
  cluster_name    = aws_eks_cluster.main.name
  namespace       = "production"
  service_account = "payment-api"
  role_arn        = aws_iam_role.payment_api.arn
}

# IAM Trust Policy — 클러스터 무관, 간단한 형태
data "aws_iam_policy_document" "pod_identity_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole", "sts:TagSession"]
    principals {
      type        = "Service"
      identifiers = ["pods.eks.amazonaws.com"]
    }
  }
}
```

> **신규 EKS 환경은 Pod Identity를 사용하고, 기존 IRSA 환경은 점진적으로 마이그레이션을 권장합니다.**

---

## 노드 그룹 설계

### 노드 그룹 분리 전략

| 노드 그룹 | 인스턴스 유형 | 용도 |
|---------|-----------|------|
| System | m5.large | kube-system, 모니터링 등 시스템 워크로드 |
| Application | m5.xlarge / m5.2xlarge | 일반 애플리케이션 |
| Memory-Optimized | r5.xlarge | 캐시, 인메모리 DB |
| Spot | m5.xlarge (Spot) | 배치, CI/CD 빌드, 내결함성 워크로드 |

### Cluster Autoscaler / Karpenter

| 도구 | 특징 |
|------|------|
| Cluster Autoscaler | 노드 그룹 기반 스케일링, 전통적 방식 |
| Karpenter | 파드 요구사항에 맞는 인스턴스를 직접 프로비저닝, 빠르고 비용 효율적 (AWS 권장) |

**Karpenter 권장 이유:**
- 노드 프로비저닝 시간 단축 (수 분 → 수십 초)
- 다양한 인스턴스 타입 혼합으로 Spot 비용 최적화
- 파드 리소스 요청에 최적화된 인스턴스 자동 선택

### Karpenter 상세 설정 (엔터프라이즈 예시)

```yaml
# EC2NodeClass — 노드가 사용할 AMI, 서브넷, 보안 그룹 정의
apiVersion: karpenter.k8s.aws/v1beta1
kind: EC2NodeClass
metadata:
  name: default
spec:
  amiFamily: Bottlerocket          # 보안 강화 OS (아래 섹션 참고)
  role: "KarpenterNodeRole-prod"
  subnetSelectorTerms:
    - tags:
        karpenter.sh/discovery: "prod-cluster"
  securityGroupSelectorTerms:
    - tags:
        karpenter.sh/discovery: "prod-cluster"
  blockDeviceMappings:
    - deviceName: /dev/xvda
      ebs:
        volumeSize: 50Gi
        volumeType: gp3
        encrypted: true
        kmsKeyID: "arn:aws:kms:ap-northeast-2:123456789:key/xxx"
---
# NodePool — 어떤 파드를 어떤 인스턴스에 올릴지 정의
apiVersion: karpenter.sh/v1beta1
kind: NodePool
metadata:
  name: general
spec:
  template:
    metadata:
      labels:
        node-type: general
    spec:
      nodeClassRef:
        name: default
      requirements:
        - key: karpenter.sh/capacity-type
          operator: In
          values: ["on-demand", "spot"]
        - key: kubernetes.io/arch
          operator: In
          values: ["amd64"]
        - key: node.kubernetes.io/instance-type
          operator: In
          values:
            - m5.xlarge
            - m5.2xlarge
            - m6i.xlarge
            - m6i.2xlarge     # 다양한 타입 → Spot 가용성 극대화
  limits:
    cpu: 1000              # 클러스터 전체 CPU 상한 (비용 제어)
    memory: 2000Gi
  disruption:
    consolidationPolicy: WhenUnderutilized   # 비어있는 노드 자동 정리
    consolidateAfter: 30s
```

---

## 보안

### 파드 보안 (Pod Security)

```
Kubernetes Pod Security Admission (PSA)
  Namespace 레벨로 보안 정책 적용:
  - Privileged: 시스템 네임스페이스만 허용
  - Baseline: 일반 워크로드 (최소 제한)
  - Restricted: 프로덕션 워크로드 (강력한 제한)
```

**Restricted 주요 제한 항목:**
- `runAsRoot: false` 강제
- `readOnlyRootFilesystem: true` 권장
- `allowPrivilegeEscalation: false` 강제
- `seccompProfile: RuntimeDefault` 강제

### 네트워크 정책 (Network Policy)

기본적으로 쿠버네티스 파드 간 통신은 모두 허용됩니다.
Network Policy로 파드 간 통신을 명시적으로 제어합니다.

```yaml
# 예: payment 네임스페이스에서 api 파드만 db 파드에 접근 허용
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: db-access
  namespace: payment
spec:
  podSelector:
    matchLabels:
      role: db
  ingress:
  - from:
    - podSelector:
        matchLabels:
          role: api
    ports:
    - protocol: TCP
      port: 5432
```

### Bottlerocket OS — 노드 보안 강화

일반 Amazon Linux 2 대신 Bottlerocket을 노드 OS로 사용하면 컨테이너 워크로드에 최적화된 보안을 확보합니다.

| 항목 | Amazon Linux 2 | Bottlerocket |
|------|---------------|-------------|
| 패키지 관리자 | yum (범용) | 없음 (컨테이너 전용) |
| SSH 접근 | 기본 허용 | 비활성화 (SSM Session Manager만) |
| 루트 파일시스템 | Read-Write | Read-Only |
| OS 업데이트 | yum update | 이미지 단위 원자적 업데이트 |
| CIS 벤치마크 | 별도 강화 필요 | 기본 준수 수준 높음 |

```yaml
# Karpenter EC2NodeClass에서 Bottlerocket 지정
spec:
  amiFamily: Bottlerocket
  userData: |
    [settings.kubernetes]
    max-pods = 110

    [settings.kernel]
    lockdown = "integrity"    # 커널 무결성 모드 활성화
```

### 컨테이너 이미지 보안 (Supply Chain 보안)

```
이미지 빌드 (CI)
  │
  ├── ECR Image Scanning (기본)
  │     └── Inspector: OS 패키지 + 언어 라이브러리 취약점 스캔
  │
  ├── Cosign 이미지 서명 (공급망 보안)
  │     cosign sign --key awskms:///alias/cosign-key \
  │       123456789.dkr.ecr.ap-northeast-2.amazonaws.com/payment:v1.2.3
  │
  └── ECR → 서명 검증 정책 (OPA/Kyverno)
        파드가 서명되지 않은 이미지를 사용하면 배포 차단
```

```yaml
# Kyverno Policy: 서명된 이미지만 배포 허용
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: verify-image-signature
spec:
  validationFailureAction: Enforce
  rules:
    - name: verify-cosign
      match:
        any:
        - resources:
            kinds: [Pod]
            namespaces: [production, staging]
      verifyImages:
        - imageReferences:
            - "123456789.dkr.ecr.ap-northeast-2.amazonaws.com/*"
          attestors:
            - entries:
              - keyless:
                  rekor:
                    url: https://rekor.sigstore.dev
```

### Secrets 관리

| 방법 | 설명 |
|------|------|
| Kubernetes Secret | 기본 방식, etcd 암호화 필수 |
| AWS Secrets Manager + CSI Driver | Secrets Manager의 값을 파드 볼륨으로 마운트 |
| External Secrets Operator | Secrets Manager → Kubernetes Secret 자동 동기화 |

> **권장:** External Secrets Operator + AWS Secrets Manager 조합
> (쿠버네티스 Secret API를 그대로 사용하면서 AWS 중앙 관리)

---

## 멀티 클러스터 관리

### 클러스터 수가 많아질 때

```
Shared Services Account
  ├── ArgoCD (GitOps 배포 허브)  ← 전체 클러스터 배포 중앙 관리
  │     │
  │  ┌──┴──────────────────────────┐
  │  Prod 클러스터  Stg 클러스터  Dev 클러스터
  │
  └── Amazon EKS Anywhere / Fleet Management (선택)
```

### GitOps (ArgoCD)

```
Git Repository (매니페스트 저장소)
        │ 변경 감지
        ▼
ArgoCD (Shared Services Account)
        │ 크로스 어카운트 배포
        ▼
각 EKS 클러스터 동기화
```

- 선언적 배포: Git이 클러스터 상태의 Single Source of Truth
- 자동 동기화: Git 변경 → 클러스터 자동 반영
- Rollback: Git revert → 클러스터 이전 상태 복구

---

## 오토스케일링 고도화

### KEDA (Kubernetes Event-Driven Autoscaling)

HPA(Horizontal Pod Autoscaler)가 CPU/메모리 기반이라면, KEDA는 **외부 이벤트 소스**(SQS 대기열 길이, Kafka Lag, CloudWatch 메트릭 등)를 기반으로 파드를 스케일링합니다.

배치 처리, 비동기 워크로드에 특히 효과적입니다.

```yaml
# SQS 대기열 길이 기반 Worker 스케일링
apiVersion: keda.sh/v1alpha1
kind: ScaledObject
metadata:
  name: order-worker-scaler
  namespace: production
spec:
  scaleTargetRef:
    name: order-worker          # 스케일할 Deployment
  minReplicaCount: 0            # 메시지 없을 때 0으로 축소 (비용 절감)
  maxReplicaCount: 50
  triggers:
    - type: aws-sqs-queue
      authenticationRef:
        name: keda-aws-credentials
      metadata:
        queueURL: https://sqs.ap-northeast-2.amazonaws.com/123456789/order-queue
        queueLength: "5"        # 파드 1개당 처리할 메시지 수
        awsRegion: ap-northeast-2
        identityOwner: operator
```

```yaml
# CloudWatch 메트릭 기반 스케일링 (커스텀 메트릭)
triggers:
  - type: aws-cloudwatch
    metadata:
      namespace: MyApp/OrderProcessing
      dimensionName: ServiceName
      dimensionValue: order-worker
      metricName: QueueDepth
      targetMetricValue: "100"
      awsRegion: ap-northeast-2
```

> **KEDA + Karpenter 조합:** KEDA가 파드를 늘리면 → Karpenter가 자동으로 노드를 추가합니다.
> 메시지가 없을 때 파드 0개 → 노드도 0개로 수렴하여 비용이 거의 0원이 됩니다.

---

## 비용 가시성 (Kubecost)

Kubecost는 EKS 클러스터 내 네임스페이스/파드/레이블 단위로 비용을 분해합니다.

```
EKS 클러스터
  │
Kubecost (Helm으로 설치)
  ├── Node 비용 + EBS/네트워크 비용 수집
  ├── 네임스페이스별 비용 배분
  │     production/payment:    $3,200/month
  │     production/auth:       $1,800/month
  │     staging:               $900/month
  └── 비용 효율화 권고
        - 미사용 리소스 요청 축소 권고
        - Spot 전환 권고 (On-Demand 워크로드 중 내결함성 있는 것)
        - 적정 인스턴스 타입 권고
```

```yaml
# Kubecost Helm 설치 (AWS Managed Prometheus 연동)
helm install kubecost kubecost/cost-analyzer \
  --namespace kubecost \
  --set kubecostToken="<token>" \
  --set prometheus.enabled=false \
  --set prometheus.fqdn="https://aps-workspaces.ap-northeast-2.amazonaws.com/workspaces/<workspace-id>"
```

---

## 관찰가능성

### EKS 메트릭 수집

```
EKS 클러스터
  ├── kube-state-metrics (쿠버네티스 오브젝트 상태)
  ├── node-exporter (노드 리소스)
  └── Application metrics (Prometheus 형식)
        │ Remote Write
        ▼
Amazon Managed Prometheus (Shared Services Account)
        │
Amazon Managed Grafana
```

### EKS 로그 수집

| 로그 유형 | 수집 방법 | 저장소 |
|---------|---------|-------|
| Control Plane 로그 | EKS → CloudWatch Logs 활성화 | CloudWatch → S3 |
| 애플리케이션 로그 | Fluent Bit DaemonSet | CloudWatch Logs → S3 |
| 감사 로그 | EKS API Server Audit → CloudWatch | S3 (장기 보존) |

---

## 업그레이드 전략

EKS는 쿠버네티스 버전을 주기적으로 업그레이드해야 합니다.

| 항목 | 내용 |
|------|------|
| 버전 지원 기간 | 각 마이너 버전 약 14개월 |
| 업그레이드 주기 | 연 1~2회 (마이너 버전 단계별 업그레이드) |
| 순서 | Control Plane 먼저 → Node Group 업그레이드 |
| 전략 | Blue/Green 클러스터 교체 또는 In-place 업그레이드 |
| 사전 검증 | Dev → Stg → Prod 순 단계적 적용 |

### Blue/Green 클러스터 업그레이드 절차 (프로덕션 권장)

In-place 업그레이드는 위험하므로, 프로덕션은 새 클러스터를 별도로 구성 후 트래픽을 전환합니다.

```
[현재] Green 클러스터 (v1.29) ← 100% 트래픽
[신규] Blue 클러스터  (v1.30) ← 구성 중

Step 1: Blue 클러스터 프로비저닝
  - EKS Blueprint/Terraform으로 동일 구성 + 새 버전
  - 모든 Add-on, 애플리케이션 배포 (ArgoCD 동기화)
  - KEDA, Karpenter, 모니터링 에이전트 설치 확인

Step 2: 검증
  - 내부 트래픽으로 기능 테스트
  - 성능 벤치마크 (응답 시간, 처리량)
  - 로그/메트릭 정상 수집 확인

Step 3: 트래픽 전환 (Route 53 Weighted Routing)
  Green: 90% → 50% → 10% → 0%
  Blue:  10% → 50% → 90% → 100%
  (각 단계에서 오류율 모니터링, 이상 시 즉시 Green으로 복원)

Step 4: Green 클러스터 종료
  - 1~2주 대기 (예상치 못한 트래픽 복귀 대비)
  - 이상 없으면 Green 클러스터 삭제
```

### EKS Add-on 업그레이드 관리

```
클러스터 업그레이드 전 반드시 확인:
  ┌─────────────────────────────────────────────┐
  │ Add-on              │ 현재   │ 목표   │ 호환 │
  ├─────────────────────┼────────┼────────┼──────┤
  │ vpc-cni             │ 1.16.x │ 1.18.x │  ✅  │
  │ coredns             │ 1.10.x │ 1.11.x │  ✅  │
  │ kube-proxy          │ 1.29.x │ 1.30.x │  ✅  │
  │ aws-ebs-csi-driver  │ 1.28.x │ 1.30.x │  ✅  │
  │ Karpenter           │ 0.35.x │ 0.36.x │  ✅  │
  └─────────────────────┴────────┴────────┴──────┘

  → aws eks describe-addon-versions 로 호환 버전 확인
  → Terraform EKS module로 Add-on 버전 코드 관리
```

---

## EKS 표준화 (EKS Blueprints)

여러 팀이 각자 클러스터를 만들면 설정이 제각각이 됩니다.
EKS Blueprints(Terraform 모듈)로 클러스터 프로비저닝을 표준화합니다.

```hcl
# EKS Blueprints — 표준 클러스터 정의 (Terraform)
module "eks_blueprints" {
  source  = "aws-ia/eks-blueprints/aws"
  version = "~> 4.0"

  cluster_name    = "prod-cluster"
  cluster_version = "1.30"
  vpc_id          = module.vpc.vpc_id
  subnet_ids      = module.vpc.private_subnets

  # 표준 Add-on 일괄 설치
  eks_addons = {
    aws-ebs-csi-driver       = { most_recent = true }
    coredns                  = { most_recent = true }
    vpc-cni                  = { most_recent = true }
    kube-proxy               = { most_recent = true }
    amazon-cloudwatch-observability = { most_recent = true }
  }
}

# GitOps Bridge — Blueprints와 ArgoCD 연동
module "eks_blueprints_addons" {
  source  = "aws-ia/eks-blueprints-addons/aws"
  version = "~> 1.0"

  cluster_name      = module.eks_blueprints.cluster_name
  cluster_endpoint  = module.eks_blueprints.cluster_endpoint
  oidc_provider_arn = module.eks_blueprints.oidc_provider_arn

  # 플랫폼 표준 도구 설치
  enable_karpenter                  = true
  enable_keda                       = true
  enable_aws_load_balancer_controller = true
  enable_external_secrets           = true
  enable_kubecost                   = true
}
```

```
조직 표준 EKS 클러스터 = Blueprints 모듈 1회 정의
  │
  ├── 개발팀 A: module 호출 → 표준 클러스터 즉시 생성
  ├── 개발팀 B: module 호출 → 동일 구성의 클러스터 생성
  └── 개발팀 C: module 호출 → 동일 구성의 클러스터 생성

효과:
  - 보안 설정 누락 방지 (표준에 이미 포함)
  - 신규 클러스터 프로비저닝 시간 단축 (수일 → 수십 분)
  - 업그레이드 시 모듈 버전 올리면 전체 클러스터 일괄 적용
```

---

## 관련 문서

- [04. VPC & Subnet 전략](./04-vpc-subnet.md)
- [10. IAM 전략](./10-iam.md)
- [16. CI/CD 크로스 어카운트 배포](./16-cicd-cross-account.md)
- [13. 모니터링 & 관찰가능성 전략](./13-monitoring-observability.md)
