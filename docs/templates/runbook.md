# Runbook: {작업명}

> **분류**: {아키텍처 변경 | 계정 생성 | 정책 변경 | 긴급 대응}
> **영향 계정**: {계정 목록}
> **작성일**: {YYYY-MM-DD}
> **예상 소요 시간**: {N분}
> **영향 범위**: {무중단 | 서비스 영향 있음}

---

## 사전 체크리스트

- [ ] Management 계정 MFA 활성화 확인
- [ ] 변경 영향 계정 목록 파악
- [ ] Terraform 상태 파일 백업
- [ ] 롤백 방법 확인
- [ ] 변경 승인 확인

---

## 환경 변수 설정

```bash
export AWS_PROFILE=<MANAGEMENT_ACCOUNT_PROFILE>
export AWS_DEFAULT_REGION=ap-northeast-2
export TARGET_ACCOUNT_ID=<ACCOUNT_ID>
```

---

## Step 1: 사전 상태 확인

```bash
aws organizations describe-organization
aws organizations list-accounts
```

---

## Step 2: {작업 내용}

```bash
{명령어}
```

또는

```hcl
# Terraform 변경사항
{변경 내용}
```

---

## Step 3: 완료 확인

```bash
{확인 명령어}
```

**성공 기준**:
- [ ] {조건 1}
- [ ] {조건 2}

---

## 롤백 절차

```bash
terraform plan -target={resource}
terraform apply -target={resource}
```

---

## 모니터링 포인트

| 지표 | 확인 방법 | 정상 기준 |
|------|---------|---------|
| {지표} | CloudWatch/Config | {기준} |
