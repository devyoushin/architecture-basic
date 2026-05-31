# architecture-basic

AWS 엔터프라이즈 멀티 계정 환경의 아키텍처 설계 전략을 정리한 지식 베이스입니다.

## 어디서 시작할까

- 문서 지도: `docs/README.md`
- 운영/실습 자산: `ops/README.md`
- AI 작업 지침: `CLAUDE.md`

## 구조

| 경로 | 내용 |
|------|------|
| `docs/` | 랜딩존, OU, 계정, 네트워크, 보안, 비용, 관측, DR, EKS 전략 문서 |
| `ops/` | 향후 아키텍처 검증 스크립트와 운영 자산 |
| `.claude/` | Claude Code 커맨드와 설정 |
| `CLAUDE.md` | Claude 작업 지침 |

## 학습 흐름

1. `docs/guides/01-landing-zone.md`에서 전체 Landing Zone 전략 확인
2. `docs/guides/02-ou-strategy.md`, `docs/guides/03-account-strategy.md`로 조직/계정 구조 학습
3. `docs/guides/04-vpc-subnet.md`부터 네트워크, 보안, 비용, 관측, DR 전략을 순서대로 학습
4. `docs/guides/18-eks.md`에서 EKS 플랫폼 전략 확인
