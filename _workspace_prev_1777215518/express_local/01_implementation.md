# 급행/완행 선택 기능 구현 — Implementation Log

승인된 plan(`/Users/april/.claude/plans/serene-fluttering-pie.md`)을 따라 1 PR 단위로
데이터 모델 + 데이터 수집 + 경로 계산 + UI 토글까지 일괄 구현했다.

## 변경 파일 목록

### A. 데이터 모델
- `lib/domain/entities/connection.dart` — `expressTimeSeconds: int?` 필드 추가
- `lib/domain/entities/route_result.dart` — `RouteSegment.expressDurationSeconds: int?`,
  `RouteResult.totalExpressTimeSeconds: int?` 추가
- `lib/domain/entities/connection.freezed.dart` — build_runner 재생성 (자동)
- `lib/domain/entities/connection.g.dart` — build_runner 재생성 (자동)
- `lib/domain/entities/route_result.freezed.dart` — build_runner 재생성 (자동)

### B. 데이터 수집
- `tool/compute_travel_times.dart` — `gaps` → `localGaps` / `expressGaps` 분리.
  `etrnYn=='Y'` → 급행, 그 외 → 완행. 통계 출력에도 급행 분포 추가.
  expressGaps 비어있으면 `expressTimeSeconds` 필드를 JSON에서 제거하여 null 보장.
  실제 실행은 별도 진행 (오케스트레이터).

### C. 경로 계산
- `lib/graph/models/graph_edge.dart` — `expressWeightSeconds: int?` 필드 추가
  (Dijkstra 가중치엔 사용 안 함, 세그먼트 빌드 단계 전달 용도)
- `lib/graph/graph_builder.dart` — `_addConnectionEdges`에서
  `connection.expressTimeSeconds` → `expressWeightSeconds` 전달
- `lib/domain/usecases/search_route.dart`
  - `_buildSegments`: `currentExpressDurationSeconds: int?` 누적 변수 추가.
    각 일반 엣지에서 expressWeightSeconds가 있으면 그 값을, 없고 이미 활성화된
    세그먼트면 완행 weight를 합산. 모두 null이면 세그먼트도 null 유지.
    환승/노선 변경/마지막 세그먼트에서 dwell time을 완행/급행 양쪽에 동일 가산.
  - `_createSegment(..., {int? expressDurationSeconds})` 시그니처 확장
  - `_buildRouteResult`: `_computeTotalExpress` 헬퍼로 totalExpressTimeSeconds 계산.
    어떤 세그먼트라도 expressDurationSeconds가 non-null이면 모든 세그먼트의
    `expressDurationSeconds ?? durationSeconds`와 환승 시간을 합산. 모두 null이면 null.
  - `executeAll`은 `_buildRouteResult`를 동일하게 거치므로 fastest/leastTransfer 모두
    totalExpressTimeSeconds를 자동 반영.

### D. UI
- `lib/features/route_search/presentation/screens/route_result_screen.dart`
  - 파일 상단에 `enum TrainMode { local, express }` 정의
  - `_RouteView`: `StatelessWidget` → `ConsumerStatefulWidget`으로 전환,
    `TrainMode _trainMode` 상태 관리. 급행 비활성 경로(`totalExpressTimeSeconds == null`)
    에서는 항상 완행을 사용 (`effectiveMode`).
  - `_RouteSummaryHeader`: 하단에 `_TrainModeToggle` 추가 (SegmentedButton),
    급행 비활성이면 disabled + "이 경로에는 급행 운영 구간이 없습니다" 툴팁
  - `_RouteTimeline`: `useExpress` 파라미터 추가. 모드별 세그먼트 duration 사용,
    transfer item의 segEndTime도 모드별 duration으로 계산.
  - `_SegmentHeader`: `showExpressBadge` 파라미터 추가. true면 노선 배지 옆에
    빨간 "급행" 배지(`arrival_card.dart`의 isExpress 패턴 재사용).
- `lib/features/route_search/utils/departure_time_calculator.dart`
  - `computeSegmentDepartures`에 `bool useExpress = false` 파라미터 추가.
    true면 `segment.expressDurationSeconds ?? segment.durationSeconds` 사용.
    기존 호출자(파라미터 미전달)는 기본값 false로 완행 동작 유지 → 회귀 0건.

### E. 테스트
- `test/domain/entities/connection_test.dart` (신규, 7케이스)
  - 기본 생성, 명시 값, fromJson 역호환 (필드 없음/null/값 있음),
    toJson/fromJson 라운드트립, copyWith 불변성
- `test/domain/entities/route_result_test.dart` (확장, +4케이스)
  - RouteResult.totalExpressTimeSeconds 기본값/명시 값
  - RouteSegment.expressDurationSeconds 기본값/명시 값
- `test/domain/usecases/search_route_test.dart` (확장, +5케이스)
  - 모든 connection이 expressTimeSeconds 보유 → totalExpressTimeSeconds non-null
  - 일부 구간만 보유 → 해당 세그먼트가 express+local 혼합 합산
  - 어떤 connection도 없으면 totalExpressTimeSeconds null
  - 환승 경로 — 한 세그먼트만 급행이면 합계는 local+express+환승
  - executeAll의 fastest에 totalExpressTimeSeconds 반영
- `test/features/route_search/presentation/route_result_screen_test.dart` (신규, 4케이스)
  - SegmentedButton 렌더(완행/급행)
  - 급행 비활성(`totalExpressTimeSeconds == null`)이면 ButtonSegment.enabled=false
  - 급행 토글 클릭 시 _SegmentHeader 시간이 급행 기준으로 변경 + 배지
  - 급행 미지원 세그먼트는 급행 모드에서도 배지 미표시

## 핵심 설계 결정

### 1. GraphEdge.expressWeightSeconds — Dijkstra 가중치엔 미반영
경로 자체는 완행 기준 Dijkstra가 찾은 그대로 유지(plan 사용자 결정사항 #1).
`expressWeightSeconds`는 세그먼트 빌드 단계에서 급행 환산 시간 계산에만 쓰인다.

### 2. 세그먼트 내 활성화 규칙
"세그먼트 내 expressTimeSeconds non-null이 하나라도 있어야 final expressDurationSeconds
non-null"이라는 plan 요구사항을 정확히 구현. 한 번 활성화되면 미운영 구간은 완행
시간으로 채워 합산 (자연스러운 lift 처리, plan 사용자 결정사항 #3).

### 3. dwell time 단순화
완행/급행 모두 동일한 dwellCount × dwellTimeSeconds로 가산. plan 명시.

### 4. 토글 비활성 처리
SegmentedButton의 ButtonSegment에 `enabled: isExpressAvailable` 제어. plan 권장.
+ Tooltip("이 경로에는 급행 운영 구간이 없습니다")로 사용자 피드백 강화.

### 5. departure_time_calculator 변경 최소화
`useExpress` 옵셔널 파라미터(기본 false)로 추가하여 기존 호출자 회귀 0건.

## 빌드/테스트 결과

### build_runner
```
Built with build_runner in 18s; wrote 8 outputs.
```
정상 (connection.freezed/g.dart, route_result.freezed.dart 등 재생성).

### flutter analyze
lib/test 영역에 에러/경고 0건. 사전 존재한 `JsonKey.new` warning, tool/ avoid_print 경고는
이번 작업과 무관.

### flutter test --exclude-tags integration
```
+409: All tests passed!
```
회귀 0건. 신규 테스트 16개 모두 통과 (connection 7 + route_result 4 + search_route 5 +
route_result_screen 4 — `find.text('급행')`이 SegmentedButton 라벨과 배지 모두에 매치되는
점을 고려해 `findsWidgets`로 검증).

(integration 태그 테스트 1건은 .env에 SEOUL_API_KEY가 없어 사전부터 실패. 본 작업과 무관.)

## 트레이드오프 / 알려진 제약

1. **dwell time 단순화**: 급행도 완행과 동일한 정차 시간을 쓴다. 실제 급행은 일부
   역을 통과하므로 추가 단축이 가능하지만, plan에서 명시적으로 단순화를 채택했다.
   추후 정확도 개선 시: 세그먼트 내 급행 정차역/통과역을 식별해 dwell을 차등 적용 필요.

2. **GraphEdge에 expressWeightSeconds 추가의 영향 범위**: 그래프 모델은 독립 모듈이지만
   이 필드는 Dijkstra 가중치엔 영향 없도록 weightSeconds와 분리됨. 급행 가중치로
   별도 Dijkstra를 돌리고 싶을 때 활용 가능한 확장점이기도 하다.

3. **compute_travel_times 미실행**: 코드 수정만 했고 실제 데이터 갱신은 오케스트레이터가
   별도 진행. 이번 PR의 connections.json 변경은 없음.

4. **route_result_screen_test 4번째 케이스의 가상 시나리오**: 실제로는 세그먼트 모두가
   expressDurationSeconds가 null이면 totalExpressTimeSeconds도 null이어서 토글 자체가
   비활성된다. 테스트를 위해 `totalExpressTimeSeconds`를 강제로 non-null로 설정해
   토글 활성화 + 배지 미표시 동작을 분리 검증했다.

## 다음 단계 (오케스트레이터 영역)

1. `dart run tool/compute_travel_times.dart --dry-run` 실행하여 expressGaps 통계 확인
2. 실제 `dart run tool/compute_travel_times.dart`로 connections.json 갱신
3. 시뮬레이터에서 plan Verification 항목 4가지 시나리오 수동 확인
4. subway-code-review + subway-requirements-review 병렬 리뷰
