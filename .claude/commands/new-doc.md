---
description: AWS 아키텍처 신규 문서를 스캐폴딩합니다. 사용법: /new-doc <번호> <주제>
---

아래 지침에 따라 AWS 엔터프라이즈 아키텍처 문서를 새로 작성해 주세요.

## 입력 정보
- 사용자 입력: $ARGUMENTS
- 첫 번째 인자 = 문서 번호 (21, 22 등 순차 번호)
- 두 번째 인자 이후 = 주제 (하이픈 구분)

## 파일 생성 규칙
1. 파일명: `{번호}-{주제}.md` (소문자, 하이픈 구분)
2. 저장 위치: 프로젝트 루트 (`/Users/sunny/Desktop/architecture-practice/`)
3. `rules/doc-writing.md`의 문서 작성 규칙 준수
4. `rules/architecture-conventions.md`의 설계 원칙 준수
5. `rules/security-checklist.md`의 보안 체크리스트 통과

## 문서 구조 (반드시 아래 섹션 모두 포함)

```markdown
# {번호}. {주제명}

## 1. 개요
(왜 필요한지, 어떤 문제를 해결하는지)

## 2. 설계 원칙

## 3. 아키텍처 설계
### 3.1 구조 및 컴포넌트
### 3.2 Terraform 구현
### 3.3 SCP/정책 예시

## 4. 운영 고려사항
(비용, 모니터링, 주의사항)

## 5. 트러블슈팅

## 6. 구현 체크리스트
```

문서 작성 완료 후 `CLAUDE.md`의 문서 목록과 `README.md`에 항목을 추가해 주세요.
