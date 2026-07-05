---
name: subway-app-orchestrator
description: "서울 지하철 앱의 에이전트 팀을 조율하는 오케스트레이터. 새 기능 구현, 버그 수정, 리팩토링, UI/지도 개선, 알고리즘 최적화, 실시간 데이터 처리 등 앱 개발 작업 요청 시 이 스킬을 사용. 후속 작업: 결과 수정, 부분 재실행, 업데이트, 보완, 다시 실행, 이전 결과 개선, 특정 에이전트만 재호출 요청 시에도 반드시 이 스킬을 사용. 단순 질문/설정 변경/1~2줄 수정은 제외."
---

# Subway App Orchestrator

서울 지하철 앱의 7인 전문가 팀을 조율하여 앱 개발 작업을 수행하는 통합 오케스트레이터.

## 실행 모드: 에이전트 팀 (감독자 패턴)

## 모델 및 컨텍스트 전략

### 모델 차등 배치 (토큰 비용 최적화)

에이전트 역할 특성에 따라 **Opus 4.7** 과 **Sonnet 4.5** 를 차등 배치한다. 모든 에이전트를 opus로 돌리면 품질은 좋지만 비용이 비효율적이다. "설계·리뷰 = opus, 구현 = sonnet" 원칙으로 약 45% 토큰 절감.

| 계층 | 모델 | 에이전트 | 선정 근거 |
|------|------|---------|----------|
| **판단 계층** | **opus** | flutter-architect, subway-code-reviewer, subway-requirements-reviewer | 아키텍처 결정·리뷰 판정은 깊은 추론과 미묘한 부수효과 탐지가 품질을 결정. 여기서 아끼면 하네스 전체 품질이 하락한다. |
| **구현 계층** | **sonnet** | map-math-engineer, graph-algorithm-engineer, realtime-data-engineer, flutter-qa-engineer | 도메인 규칙(4원칙·노선별 방향·API 포맷)이 이미 스킬 문서에 명시되어 있어, sonnet이 가이드를 읽고 따라 구현하면 충분. 테스트·API 통합은 패턴 반복이 많다. |

**모델 변경 시 판단 기준:**
- 판단 계층에서 sonnet으로 내리면 → 리뷰 누락이나 아키텍처 설계 오류 발생 시 즉시 opus로 복귀
- 구현 계층에서 sonnet이 4원칙·알고리즘 규칙을 반복 위반하면 → 해당 에이전트만 opus로 승격
- ⛔ 4원칙 **자체를 변경**해야 한다는 판단이 나오면 이는 모델 승격 문제가 아니다 — CLAUDE.md 최상위 정책이므로 구현을 진행하지 말고 반드시 사용자 승인을 먼저 구한다 (map-math-engineer.md/realtime-data-engineer.md의 "⛔ 4원칙" 섹션 참조)

### 1M 컨텍스트 활용 원칙

모든 에이전트는 **1M context** 윈도우로 실행된다 (Opus 4.7, Sonnet 4.5 모두 1M 지원). 운용 원칙:

1. **모듈 단위 일괄 처리** — 에이전트 1명이 한 feature 폴더 전체(여러 파일·테스트·관련 스킬 문서)를 한 번에 읽고 수정. 작은 범위로 쪼개 라운드트립을 늘리지 말 것.
2. **관련 참조 문서 동시 로딩** — SKILL.md + references/ + 관련 CODEMAP + 실제 코드 파일을 한 컨텍스트에 투입. 에이전트 내부 사전 탐색 부담 감소.
3. **리뷰 단계 컨텍스트 확보** — code-reviewer·requirements-reviewer는 변경 파일 + 인근 파일 + 테스트 + 사용자 원문 전체를 한 번에 받아 전체 맥락에서 판단.
4. **에이전트 통합 재검토** — 역할이 겹치거나 순차적으로 작은 범위만 처리하는 에이전트는 병합 후보. 세션 종료 시 재평가.
5. **성능·비용 균형** — 1M을 꼭 채울 필요는 없다. 작업 범위에 비례한 컨텍스트만 투입. 단순 질문·1~2줄 수정은 에이전트 팀 없이 직접 처리.

## 에이전트 구성

| 팀원 | 서브에이전트 타입 | 역할 | 스킬 | 모델 |
|------|-----------------|------|------|------|
| flutter-architect | general-purpose | 아키텍처/상태관리/라우팅 | flutter-architecture | **opus** |
| map-math-engineer | general-purpose | 지도 UI/수학/애니메이션 | subway-map-math | sonnet |
| graph-algorithm-engineer | general-purpose | 최단경로/그래프/방향결정 | graph-pathfinding | sonnet |
| realtime-data-engineer | general-purpose | API/캐싱/열차추적 | realtime-tracking | sonnet |
| flutter-qa-engineer | general-purpose | 테스트/경계면검증 | subway-testing | sonnet |
| subway-code-reviewer | code-reviewer | 코드 품질/보안/성능 리뷰 | subway-code-review | **opus** |
| subway-requirements-reviewer | general-purpose | 요구사항 충족도 검증 | subway-requirements-review | **opus** |

## 워크플로우

### Phase 0: 컨텍스트 확인

1. `_workspace/` 디렉토리 존재 여부 확인
2. 실행 모드 판정:
   - `_workspace/` 미존재 → **초기 실행** (Phase 1부터)
   - `_workspace/` 존재 + 부분 수정 요청 → **부분 재실행** (해당 에이전트만)
   - `_workspace/` 존재 + 새 입력 → **새 실행** (기존을 `_workspace_prev/`로 이동)

### Phase 1: 분석 및 계획

1. 사용자 요청 분석 — 작업 유형 분류:
   - **기능 구현**: flutter-architect + 관련 전문가
   - **지도/UI 작업**: map-math-engineer + flutter-architect
   - **알고리즘 작업**: graph-algorithm-engineer
   - **실시간 데이터 작업**: realtime-data-engineer
   - **버그 수정**: 관련 전문가 + flutter-qa-engineer
   - **리팩토링**: flutter-architect + subway-code-reviewer

2. 투입 에이전트 결정 (전체 7명 중 필요한 에이전트만 투입)
3. `_workspace/` 생성, 요구사항을 `_workspace/00_requirements.md`에 저장

### Phase 2: 구현

작업 유형에 따라 적절한 에이전트를 서브에이전트로 호출한다.

**에이전트 호출 시 필수 사항:**
- 에이전트 정의 파일(`.claude/agents/{name}.md`)을 프롬프트 첫 줄에 읽도록 지시
- 해당 스킬(`.claude/skills/{name}/SKILL.md`)을 참조하도록 지시
- 모델은 에이전트 정의 파일의 `model:` frontmatter를 따른다 (상단 "모델 및 컨텍스트 전략" 표 참조). Agent 도구 호출 시 `model` 파라미터를 별도로 넘기지 않으면 frontmatter가 적용된다.
- 산출물 경로: `_workspace/{phase}_{agent}_{artifact}` 형식

**병렬 실행 가능한 조합:**
- flutter-architect + map-math-engineer (독립 모듈 작업 시)
- graph-algorithm-engineer + realtime-data-engineer (독립 모듈 작업 시)
- subway-code-reviewer + subway-requirements-reviewer (항상 병렬)

**순차 실행 필수:**
- flutter-architect → (아키텍처 결정 후) → 다른 전문가
- 구현 → 리뷰 → 수정 → 재리뷰

### Phase 3: 리뷰 (2단계 병렬)

구현 완료 후 항상 2개 리뷰를 **동시에** 실행한다:

1. **코드 리뷰** (subway-code-reviewer)
   - 수정된 파일 목록 전달
   - subway-code-review 스킬 참조
   - 심각도별 분류된 이슈 반환

2. **요구사항 리뷰** (subway-requirements-reviewer)
   - 원래 요청 텍스트 + 구현 결과 전달
   - subway-requirements-review 스킬 참조
   - 충족률 + 누락/불일치 항목 반환

### Phase 4: 수정 및 재리뷰 루프

1. 두 리뷰 결과를 통합
2. CRITICAL/HIGH 이슈가 있으면 해당 구현 에이전트에게 수정 요청
3. 수정 후 Phase 3 재실행
4. 이슈가 없을 때까지 반복 (최대 3회)

### Phase 5: 검증 및 완료

1. `flutter analyze` 실행 — 정적 분석 통과 확인
2. 관련 테스트 실행 — `flutter test` (대상 범위)
3. 결과 요약 보고:
   - 변경된 파일 목록
   - 구현 내용 요약
   - 리뷰 통과 여부
   - 테스트 결과
   - 추가 필요 작업 (있는 경우)
4. `_workspace/` 보존

## 데이터 흐름

```
[오케스트레이터]
    ├── Phase 1: 요구사항 분석 + _workspace/ 생성
    ├── Phase 2: Agent(전문가, run_in_background) × N
    │              ↓ 각 에이전트가 코드 수정
    ├── Phase 3: Agent(code-reviewer) ‖ Agent(requirements-reviewer)
    │              ↓ 리뷰 결과 수집
    ├── Phase 4: 이슈 있으면 → Agent(전문가) 수정 → Phase 3 반복
    └── Phase 5: flutter analyze + test + 결과 보고
```

## 에이전트 호출 패턴

> `model` 파라미터는 에이전트 정의 frontmatter로 결정된다. 아래 예시는 명시적으로 확인하고 싶을 때만 `model`을 넘기는 형태다. 실제로는 생략 가능.

### 구현 에이전트 호출 (sonnet 기본)
```
Agent(
  subagent_type: "general-purpose",
  # model: "sonnet",  # 에이전트 frontmatter가 이미 sonnet — 생략 권장
  prompt: """
    먼저 .claude/agents/{name}.md를 읽고 역할을 이해하라.
    .claude/skills/{skill}/SKILL.md를 참조하라.

    [구체적 작업 지시]

    프로젝트 루트: /Users/april/StudioProjects/seoul_subway
  """
)
```

### 코드 리뷰 호출 (opus 기본)
```
Agent(
  subagent_type: "code-reviewer",
  # model: "opus",  # subway-code-reviewer.md frontmatter가 opus
  prompt: """
    먼저 .claude/agents/subway-code-reviewer.md를 읽고 역할을 이해하라.
    .claude/skills/subway-code-review/SKILL.md를 참조하라.

    다음 파일들을 리뷰하라: [파일 목록]

    프로젝트 루트: /Users/april/StudioProjects/seoul_subway
  """
)
```

### 요구사항 리뷰 호출 (opus 기본)
```
Agent(
  subagent_type: "general-purpose",
  # model: "opus",  # subway-requirements-reviewer.md frontmatter가 opus
  prompt: """
    먼저 .claude/agents/subway-requirements-reviewer.md를 읽고 역할을 이해하라.
    .claude/skills/subway-requirements-review/SKILL.md를 참조하라.

    원래 요청: [사용자 요청]
    수정된 파일: [파일 목록]

    프로젝트 루트: /Users/april/StudioProjects/seoul_subway
  """
)
```

## 에러 핸들링

| 상황 | 전략 |
|------|------|
| 에이전트 실패 | 1회 재시도, 재실패 시 해당 작업 건너뛰고 보고 |
| 리뷰 3회 반복 후에도 이슈 | 미해결 이슈 목록과 함께 사용자에게 보고 |
| flutter analyze 실패 | 에러 메시지 분석 후 자동 수정 시도 |
| 테스트 실패 | 실패 테스트 분석 후 flutter-qa-engineer에게 위임 |
| build_runner 필요 | `@freezed`/`@riverpod` 변경 감지 시 자동 실행 |

## 작업 유형별 에이전트 투입 가이드

| 작업 유형 | 필수 에이전트 | 선택 에이전트 |
|----------|-------------|-------------|
| 새 기능 구현 | flutter-architect | 관련 전문가 |
| 지도 UI 수정 | map-math-engineer | flutter-architect |
| 알고리즘 변경 | graph-algorithm-engineer | flutter-qa-engineer |
| 실시간 데이터 | realtime-data-engineer | map-math-engineer |
| 버그 수정 | 원인 분석 후 결정 | flutter-qa-engineer |
| 리팩토링 | flutter-architect | subway-code-reviewer |
| 모든 코드 변경 | subway-code-reviewer + subway-requirements-reviewer | - |

## 테스트 시나리오

### 정상 흐름: 지도 애니메이션 개선
1. 사용자: "열차 애니메이션을 부드럽게 해줘"
2. Phase 1: map-math-engineer + realtime-data-engineer 투입 결정
3. Phase 2: 두 에이전트 병렬 실행
4. Phase 3: code-reviewer + requirements-reviewer 병렬 리뷰
5. Phase 4: 이슈 없음 → 스킵
6. Phase 5: analyze 통과, 결과 보고

### 에러 흐름: 리뷰 반복
1. 사용자: "새 노선 추가 기능"
2. Phase 2: flutter-architect 구현
3. Phase 3: 코드 리뷰에서 불변성 위반 (CRITICAL)
4. Phase 4: flutter-architect에게 수정 요청
5. Phase 3 재실행: 통과
6. Phase 5: 완료
