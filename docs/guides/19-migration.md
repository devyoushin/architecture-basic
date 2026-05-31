# 19. 마이그레이션 전략

## 개요

온프레미스 워크로드를 AWS로 이전할 때는 무작정 옮기는 것이 아니라,
워크로드 특성에 맞는 전략(7R)을 선택하고 단계적으로 실행합니다.
마이그레이션은 Landing Zone, 네트워크 연결(DX/VPN)이 먼저 준비된 후 진행합니다.

---

## 마이그레이션 전제 조건

마이그레이션 시작 전 아래가 완료되어 있어야 합니다.

```
✅ Landing Zone 구성 (Control Tower)
✅ OU / 계정 구조 확정
✅ Direct Connect 또는 VPN 연결 (하이브리드 연결)
✅ IP 대역 계획 및 충돌 검증
✅ IAM Identity Center 연동
✅ 기본 보안 서비스 활성화 (GuardDuty, Security Hub, Config)
✅ 태깅 전략 확정
```

---

## 7R 마이그레이션 전략

| 전략 | 설명 | 노력도 | 비용 절감 | 적합한 워크로드 |
|------|------|--------|---------|--------------|
| **Retire** | 사용 안 하는 시스템 폐기 | 없음 | 최대 | 레거시, 미사용 시스템 |
| **Retain** | 현재 유지 (이전 안 함) | 없음 | 없음 | 규정/기술 제약으로 이전 불가 |
| **Rehost** | Lift & Shift (그대로 이전) | 낮음 | 보통 | 빠른 이전이 목표인 경우 |
| **Replatform** | 최소 변경 후 이전 | 중간 | 높음 | DB → RDS, 앱 서버 → ECS |
| **Repurchase** | SaaS로 교체 | 중간 | 상황에 따라 | CRM → Salesforce, 메일 → M365 |
| **Refactor** | 클라우드 네이티브로 재설계 | 높음 | 최대 | 확장성/민첩성 요건이 높은 경우 |
| **Relocate** | VMware → VMware Cloud on AWS | 낮음 | 보통 | VMware 환경 |

### 워크로드별 전략 선택 기준

```
워크로드 분류
  │
  ├── 미사용 / 불필요 → Retire
  │
  ├── 규정/기술 제약 → Retain (온프레미스 유지)
  │
  ├── 빠른 이전 필요, 변경 최소화 → Rehost (Lift & Shift)
  │
  ├── DB 관리 부담 줄이고 싶음 → Replatform (RDS, ElastiCache)
  │
  ├── SaaS 대체제 있음 → Repurchase
  │
  └── 확장성/비용 최적화 중요 → Refactor (컨테이너, 서버리스)
```

---

## 마이그레이션 단계

### Phase 1: Assessment (평가)

```
전체 온프레미스 인벤토리 수집
  └── AWS Migration Hub: 워크로드 추적 중앙 관리
  └── AWS Application Discovery Service: 서버 사양, 연결 관계 자동 탐지

결과물:
  - 서버 목록 (사양, OS, 애플리케이션)
  - 서버 간 의존성 맵 (Migration Hub)
  - 7R 분류 결과
  - 마이그레이션 우선순위 및 웨이브 계획
```

### Phase 2: Mobilize (준비)

```
- Landing Zone 구성 완료
- 네트워크 연결 (DX/VPN) 완료
- 파일럿 마이그레이션 (비중요 워크로드로 프로세스 검증)
- 마이그레이션 런북(Runbook) 작성
- 팀 교육 (AWS 서비스, 운영 방법)
```

### Phase 3: Migrate & Modernize (이전 및 현대화)

웨이브(Wave) 단위로 단계적 이전:

```
Wave 1: 비중요 / 독립적 워크로드 (리스크 최소)
Wave 2: 중요도 중간 워크로드
Wave 3: 핵심 프로덕션 워크로드
```

---

## 주요 마이그레이션 도구

### 서버 마이그레이션 (Rehost)

#### AWS Application Migration Service (MGN)

온프레미스 서버를 EC2로 Lift & Shift 이전하는 주요 도구입니다.

```
온프레미스 서버
  └── MGN 에이전트 설치
        │ 지속적 블록 레벨 복제 (다운타임 없음)
        ▼
AWS (스테이징 영역)
  └── 복제 서버 (지속 업데이트)
        │ 전환 시점에 Cutover
        ▼
프로덕션 EC2 인스턴스
```

**특징:**
- 에이전트 기반 지속 복제 → Cutover 시 다운타임 수 분
- Windows / Linux 모두 지원
- 전환 전 테스트 실행 가능

### 데이터베이스 마이그레이션

#### AWS Database Migration Service (DMS)

| 소스 DB | 대상 DB | 지원 방식 |
|--------|--------|---------|
| Oracle | Aurora PostgreSQL / RDS | 동종 / 이기종 |
| MS SQL Server | Aurora MySQL / RDS | 이기종 |
| MySQL | Aurora MySQL / RDS MySQL | 동종 |
| PostgreSQL | Aurora PostgreSQL | 동종 |
| MongoDB | Amazon DocumentDB | 동종 |

**DMS 마이그레이션 흐름:**

```
온프레미스 DB (소스)
        │ Full Load (초기 전체 적재)
        │ + CDC (Change Data Capture, 실시간 변경 복제)
        ▼
AWS DMS Replication Instance
        │
RDS / Aurora (대상)
        │
검증 완료 후 → 애플리케이션 연결 전환 (Cutover)
```

#### AWS Schema Conversion Tool (SCT)

이기종 DB 마이그레이션 시 스키마 및 코드(Stored Procedure, Function) 자동 변환합니다.

```
Oracle Schema → Aurora PostgreSQL Schema 자동 변환
  - 자동 변환 가능 항목 표시
  - 수동 변환 필요 항목 표시 (인력 작업 필요)
```

### 스토리지 마이그레이션

| 소스 | 대상 | 도구 |
|------|------|------|
| 온프레미스 파일 서버 | Amazon S3 | AWS DataSync |
| NFS / SMB | Amazon EFS / FSx | AWS DataSync |
| 대용량 오프라인 데이터 | Amazon S3 | AWS Snow Family |

#### AWS DataSync

```
온프레미스 NAS/파일 서버
  └── DataSync 에이전트 (온프레미스 배포)
        │ DX/인터넷 경유 암호화 전송
        ▼
Amazon S3 / EFS / FSx
```

#### AWS Snow Family (대용량 오프라인)

| 장치 | 용량 | 사용 케이스 |
|------|------|-----------|
| Snowcone | 8TB | 소규모, 엣지 |
| Snowball Edge | 80TB | 중규모 데이터 이전 |
| Snowmobile | 100PB | 대규모 데이터센터 이전 |

---

## Cutover 계획

### Cutover 절차 (서버 마이그레이션 예시)

```
1. 사전 검증
   - AWS 환경 테스트 완료
   - 성능 검증, 기능 테스트 완료
   - Rollback 계획 확정

2. Cutover 시작 (유지보수 시간 활용)
   - 온프레미스 애플리케이션 중지
   - 최종 DMS 동기화 완료 확인
   - MGN Cutover 실행

3. DNS 전환
   - Route53 레코드 변경 (TTL 미리 낮춰둘 것)
   - 또는 로드밸런서 대상 그룹 전환

4. 검증
   - Health Check 통과 확인
   - 핵심 기능 동작 검증
   - 모니터링 대시보드 확인

5. 완료 또는 Rollback
   - 이상 없으면 온프레미스 서버 종료 예약
   - 이상 발생 시 DNS 복원 → 온프레미스로 즉시 복귀
```

### Rollback 기준 정의

| 조건 | 대응 |
|------|------|
| 핵심 기능 오류 | 즉시 Rollback |
| 성능 목표 미달 (예: 응답 시간 2배 이상) | 즉시 Rollback |
| 데이터 정합성 오류 | 즉시 Rollback + 원인 분석 |
| 경미한 오류 (비핵심 기능) | AWS 환경에서 즉시 수정 후 유지 |

---

## 마이그레이션 후 최적화

이전 완료 직후 최적화 작업을 병행합니다.

| 항목 | 내용 |
|------|------|
| 인스턴스 최적화 | Compute Optimizer 권장 사항 적용 |
| 스토리지 최적화 | EBS gp2 → gp3 전환 (성능↑ 비용↓) |
| 구매 전략 | Savings Plans / RI 도입 |
| 아키텍처 현대화 | Replatform/Refactor 대상 식별 및 단계적 전환 |

---

## Migration Factory 모델 (대규모 엔터프라이즈)

수백~수천 대 서버를 이전하는 대형 프로젝트에서는 공장(Factory) 방식으로 팀을 구성하고 반복 가능한 프로세스를 표준화합니다.

### 팀 구성

```
Migration Factory
  ├── Platform Team      : Landing Zone, 네트워크, 보안 기반 관리
  ├── Wave Team          : 실제 서버/DB 마이그레이션 실행 (반복 수행)
  ├── App Testing Team   : 전환 후 기능/성능 검증
  └── Operations Team    : 모니터링, 사후 안정화 지원
```

### 웨이브(Wave) 설계 기준

단순히 "중요도 순서"가 아니라 의존성(dependency)을 기준으로 묶어야 합니다.

```
Wave 설계 원칙:
  1. Application Discovery Service로 서버 간 통신 의존성 맵 추출
  2. 의존성 그래프에서 독립 노드부터 Wave 1 배치
  3. 같은 Wave에는 상호 의존하는 서버를 함께 묶음
  4. Wave당 20~50대 규모 유지 (너무 크면 Cutover 위험 증가)

예시:
  Wave 1: 독립 배치 서버 (모니터링, 내부 툴, 백오피스)
  Wave 2: 미들티어 (배치 처리, 내부 API)
  Wave 3: 핵심 프론트엔드 + 연결 DB
  Wave 4: 가장 복잡한 레거시 코어 시스템
```

### 반복 실행 Runbook 표준화

```
각 Wave마다 동일한 Runbook 사용:
  1. T-2주: 환경 준비 체크리스트 확인
  2. T-1주: MGN 복제 상태 확인, 테스트 Cutover 실행
  3. T-3일: 성능 테스트, 데이터 정합성 검증
  4. T-1일: Rollback 계획 최종 확인, 담당자 연락처 공유
  5. D-Day:  Cutover 실행 (유지보수 시간 내)
  6. D+1:   안정화 모니터링 (24h 집중 감시)
  7. D+7:   Wave 회고 → 다음 Wave 개선 반영
```

---

## 대용량 데이터베이스 마이그레이션 전략

### 수 TB 이상 DB 마이그레이션

네트워크 대역폭 한계로 인해 단순 DMS 복제만으로는 초기 Full Load에 수일~수주가 소요됩니다.

```
대용량 DB 이전 권장 절차:

1단계: 오프라인 덤프 → Snowball 물리 반입
  ├── Oracle: expdp (Data Pump) → S3 (Snowball)
  └── PostgreSQL: pg_dump → S3 (Snowball)

2단계: 대상 DB에 복원
  └── S3 → RDS/Aurora 임포트 (또는 EC2에서 복원 후 DMS)

3단계: DMS CDC로 증분 변경만 동기화
  └── 초기 적재 완료 시점부터 실시간 변경 복제

4단계: Lag 0 확인 후 Cutover
  └── CDC Latency < 1분 → 애플리케이션 전환
```

### Oracle → Aurora PostgreSQL 이전 (라이선스 절감)

엔터프라이즈 환경에서 가장 흔하고 효과적인 이전 경로입니다.

```
Oracle DB (온프레미스)
  │
  ├── 1. SCT 스키마 분석
  │     - 자동 변환 가능 비율 확인 (보통 60~80%)
  │     - Stored Procedure, Trigger 수동 변환 계획 수립
  │
  ├── 2. 스키마 변환 (SCT)
  │     - 데이터 타입 매핑 (NUMBER → NUMERIC, DATE → TIMESTAMP)
  │     - Oracle 전용 함수 → PostgreSQL 함수로 재작성
  │
  ├── 3. DMS Full Load + CDC
  │     - 소스: Oracle (LogMiner 기반 CDC)
  │     - 대상: Aurora PostgreSQL
  │
  └── 4. 검증 → Cutover
        - 데이터 행 수 비교, Checksum 비교
        - Oracle 라이선스 비용 절감: 최대 90%↓
```

---

## 데이터 검증 프레임워크

Cutover 전 데이터 정합성은 가장 중요한 검증 항목입니다.

### 3단계 검증

```
Level 1: 행(Row) 수 비교
  SELECT COUNT(*) 비교 (테이블별)
  → 빠르고 기본적인 검증

Level 2: 집계 값 비교 (Aggregate Check)
  SELECT SUM(amount), MAX(updated_at) 비교
  → 금액, 날짜 등 핵심 수치 비교

Level 3: 샘플링 비교 (Row-level)
  랜덤 샘플 또는 최근 변경 N건 상세 비교
  → 컬럼 값 수준의 정확한 검증
```

### AWS DMS 데이터 검증 활성화

```
DMS Task 설정:
  "ValidationEnabled": true,
  "ValidationMode": "ROW_LEVEL"

→ DMS가 자동으로 소스/대상 행 비교
→ 불일치 항목을 awsdms_validation_failures 테이블에 기록
→ Cutover 전 불일치 0건 확인 필수
```

---

## 병렬 운영(Parallel Run) 전략

핵심 시스템(결제, 계정계 등)은 Cutover 직후 일정 기간 온프레미스와 AWS를 동시 운영하여 리스크를 최소화합니다.

```
병렬 운영 아키텍처:

         사용자 트래픽
              │
    ┌─────────┴──────────┐
    │                    │
온프레미스 (Primary)   AWS (Shadow)
    │                    │
    └──── 결과 비교 ──────┘
              │
         차이 발생 시 알람
              │
         분석 → 수정 후 AWS를 Primary로 전환

기간: 2~4주 권장 (비용 vs. 안전성 트레이드오프)
```

### 트래픽 전환 단계

```
Step 1: Shadow 모드 (AWS: 0% 트래픽)
  - 온프레미스 → AWS DMS 복제 중
  - AWS 환경 성능 측정만

Step 2: Canary (AWS: 5~10%)
  - 소량 트래픽 AWS로 분기
  - 오류율, 응답 시간 비교

Step 3: 점진적 전환 (AWS: 50%)
  - 문제 없으면 비중 증가

Step 4: Full Cutover (AWS: 100%)
  - 온프레미스 서버 대기 상태 유지 (Rollback용, 1~2주)
  - 이상 없으면 온프레미스 서버 종료
```

---

## 마이그레이션 리스크 레지스터

| 리스크 | 가능성 | 영향 | 대응 방안 |
|--------|-------|------|---------|
| DB 마이그레이션 중 데이터 손실 | 낮음 | 매우 높음 | DMS 검증 활성화, 백업 스냅샷 보존 |
| 애플리케이션 성능 저하 | 중간 | 높음 | 사전 부하 테스트, Compute Optimizer 적용 |
| 온프레미스 연결(DX) 장애 | 낮음 | 높음 | VPN Failover 구성, 전환 기간 중 DX 증설 |
| 예상치 못한 의존성 (숨겨진 연결) | 높음 | 중간 | Application Discovery Service 재탐지 |
| Cutover 시간 초과 (유지보수 윈도우 내 완료 불가) | 중간 | 높음 | 테스트 Cutover 반복 → 소요 시간 정확히 측정 |
| IaC 태그 누락으로 비용 배분 오류 | 중간 | 낮음 | SCP 태그 강제, 마이그레이션 템플릿에 태그 포함 |

---

## 마이그레이션 후 최적화

- [01. Landing Zone 전략](./01-landing-zone.md)
- [06. Direct Connect 전략](./06-dx.md)
- [03. Account 전략](./03-account-strategy.md)
