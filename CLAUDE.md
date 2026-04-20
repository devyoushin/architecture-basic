# architecture-practice — 프로젝트 가이드

## 목적
AWS 기반 엔터프라이즈 아키텍처를 설계하고 문서화하는 실습 저장소입니다.
Organizations, Landing Zone, 네트워크, 보안, 거버넌스 등 멀티 어카운트 아키텍처를 다룹니다.

---

## 디렉토리 구조

```
architecture-practice/
├── CLAUDE.md                  # 이 파일 (자동 로드)
├── .claude/
│   ├── settings.json          # 권한 설정 + PostToolUse 훅
│   └── commands/              # 커스텀 슬래시 명령어
│       ├── new-doc.md         # /new-doc — 새 아키텍처 문서 생성
│       ├── new-runbook.md     # /new-runbook — 새 런북 생성
│       ├── review-doc.md      # /review-doc — 문서 품질 검토
│       ├── add-troubleshooting.md  # /add-troubleshooting — 트러블슈팅 추가
│       └── search-kb.md       # /search-kb — 지식베이스 검색
├── agents/                    # 전문 에이전트 정의
│   ├── doc-writer.md          # 아키텍처 문서 작성 전문가
│   ├── security-architect.md  # 보안 아키텍처 전문가
│   ├── network-architect.md   # 네트워크 설계 전문가
│   └── cost-optimizer.md      # 비용 최적화 전문가
├── templates/                 # 문서 템플릿
│   ├── service-doc.md         # 아키텍처 컴포넌트 문서 템플릿
│   ├── runbook.md             # 운영 런북 템플릿
│   └── incident-report.md     # 장애/보안 이벤트 보고서 템플릿
├── rules/                     # Claude 작성 규칙
│   ├── doc-writing.md         # 문서 작성 원칙
│   ├── architecture-conventions.md  # 아키텍처 표준 관행
│   ├── security-checklist.md  # Well-Architected 보안 체크리스트
│   └── monitoring.md          # 모니터링 지침
└── docs/                      # 아키텍처 문서 (번호 순서)
    ├── 01-organizations.md
    ├── 02-landing-zone.md
    └── ...
```

---

## 커스텀 슬래시 명령어

| 명령어 | 설명 | 사용 예시 |
|--------|------|---------|
| `/new-doc` | 새 아키텍처 문서 생성 | `/new-doc 03-vpc-design` |
| `/new-runbook` | 새 런북 생성 | `/new-runbook SCP 정책 변경` |
| `/review-doc` | 문서 품질 검토 | `/review-doc docs/01-organizations.md` |
| `/add-troubleshooting` | 트러블슈팅 케이스 추가 | `/add-troubleshooting SCP 권한 거부` |
| `/search-kb` | 지식베이스 검색 | `/search-kb Transit Gateway 라우팅` |

---

## 문서 작성 규칙

### 파일 네이밍
- `{번호}-{주제}.md` 형식 (예: `01-organizations.md`, `15-tagging.md`)
- 번호는 2자리로 패딩

### 필수 포함 항목
각 아키텍처 문서는 `templates/service-doc.md` 구조를 따릅니다:
1. **개요** — 왜 필요한지, 어떤 문제를 해결하는지
2. **설계 원칙** — 주요 설계 결정 사항
3. **아키텍처 설계** — 텍스트 다이어그램 + Terraform 구현 + SCP/정책 예시
4. **운영 고려사항** — 비용, 모니터링, 주의사항
5. **트러블슈팅** — 주요 증상과 해결 방법
6. **구현 체크리스트** — 완료 확인 항목

### 언어 규칙
- 본문은 한국어, 기술 용어(AWS 서비스명, CLI 명령어)는 영어 그대로
- Terraform HCL과 AWS CLI 예시는 실제 동작 가능한 수준으로 작성
- SCP/IAM 정책은 최소 권한 원칙을 기본으로 적용

---

## 아키텍처 레이어

| 레이어 | 번호 범위 | 내용 |
|--------|---------|------|
| 거버넌스 | 01-05 | Organizations, SCP, Control Tower, Landing Zone |
| 네트워크 | 06-10 | VPC, Transit Gateway, Direct Connect, Route53 |
| 보안 | 11-15 | IAM, GuardDuty, Security Hub, 태깅 전략 |
| 운영 | 16-18 | CloudWatch, Config, Backup |
| 플랫폼 | 19-20 | EKS, 서비스 카탈로그 |

---

## 설계 원칙

- **최소 권한**: 모든 IAM/SCP는 필요한 권한만 부여
- **불변 인프라**: Terraform으로 관리, 콘솔 직접 변경 지양
- **멀티 어카운트**: 환경별(dev/staging/prod) 계정 분리
- **방어적 기본값**: 명시적 허용 없이 기본 거부
- **감사 가능성**: 모든 변경은 CloudTrail로 추적

---

## 백로그 (추가 예정)

- `docs/03-network-hub-spoke.md` — Hub-Spoke 네트워크 설계
- `docs/08-route53-resolver.md` — DNS 내부 라우팅
- `docs/12-security-hub-integration.md` — Security Hub 통합
- `docs/17-cost-allocation.md` — 비용 배분 전략
