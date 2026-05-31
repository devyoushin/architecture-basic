# 보안 검토 체크리스트

AWS 엔터프라이즈 아키텍처 문서 작성 시 반드시 확인해야 할 보안 항목입니다.

---

## 1. SCP (Service Control Policy)

- [ ] 루트 계정 사용 차단 SCP 존재 여부
- [ ] 승인되지 않은 리전 차단 SCP
- [ ] 태그 필수 강제 SCP
- [ ] cloudtrail:StopLogging 차단 SCP

## 2. IAM

- [ ] `AdministratorAccess` 직접 부여 금지 (Permission Boundary 필요)
- [ ] 장기 Access Key 사용 금지 (IAM Role 사용 권장)
- [ ] Cross-account Role에 조건 설정
- [ ] Identity Center SSO 활용 여부

## 3. 네트워크

- [ ] Security Group: 0.0.0.0/0 인바운드 허용 시 주의 경고
- [ ] VPC Flow Logs: 활성화 여부
- [ ] Network Firewall/WAF: 인터넷 트래픽 검사 여부

## 4. 데이터 보호

- [ ] S3 버킷: 퍼블릭 액세스 차단 활성화
- [ ] S3 버킷: SSE-KMS 암호화 적용
- [ ] 민감 데이터: Secrets Manager 또는 Parameter Store 사용

## 5. 탐지 및 대응

- [ ] CloudTrail: 모든 계정/리전 활성화
- [ ] GuardDuty: Organization 수준 활성화
- [ ] Config: 규정 준수 규칙 설정
- [ ] Security Hub: 통합 활성화

## 6. 금지 표현

- 실제 계정 ID (12자리) 노출 금지 → `<ACCOUNT_ID>`
- 실제 ARN 노출 금지 → `<RESOURCE_ARN>`
- 실제 KMS Key ID 노출 금지 → `<KMS_KEY_ID>`
