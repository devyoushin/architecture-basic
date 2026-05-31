# AGENTS.md — architecture-basic Codex 작업 지침

이 저장소는 AWS 엔터프라이즈 아키텍처와 운영 플레이북 지식 베이스입니다. Codex 작업 시 `CLAUDE.md`와 `docs/rules/`의 규칙을 동일하게 따릅니다.

## 공통 원칙

- 설계 문서는 `docs/` 아래에 둡니다.
- runbook, 부하 테스트, 모니터링 쿼리, 설정 예시는 `ops/` 아래에 둡니다.
- 아키텍처 문서는 보안, 비용, 관측, 장애 대응, rollback 관점을 함께 포함합니다.
- 수치나 한도는 변동 가능하므로 공식 문서 확인 또는 확인 필요 표시를 남깁니다.

## Claude와의 싱크

- Claude 지침은 `CLAUDE.md`를 참고합니다.
- Codex도 공통 규칙은 `docs/rules/`를 따릅니다.
- 구조 변경 시 `README.md`, `docs/README.md`, `ops/README.md`를 함께 갱신합니다.

## 작업 체크리스트

- `git status --short` 확인
- 링크 검사
- YAML/shell/SQL 등 추가 자산 문법 검사
- `git diff --check` 수행
