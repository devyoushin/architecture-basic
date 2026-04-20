---
description: 문서에 트러블슈팅/운영 사례를 추가합니다. 사용법: /add-troubleshooting <파일명> <증상>
---

`$ARGUMENTS`를 파싱합니다:
- 첫 번째 인자: 대상 파일 경로
- 나머지: 추가할 증상 또는 운영 사례

## 작성 형식

```markdown
### {증상/사례}

**상황**: {발생 상황 설명}

**원인**: {근본 원인}

**해결 방법**:
```bash
# AWS CLI 해결 명령어
aws ...
```

**재발 방지**:
- {SCP/Config Rule/GuardDuty 등으로 예방 방법}
```
