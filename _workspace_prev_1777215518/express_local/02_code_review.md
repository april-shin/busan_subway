# 급행/완행 선택 기능 코드 리뷰

리뷰 일자: 2026-04-17
리뷰어: subway-code-reviewer
대상: 급행/완행 토글 기능 (express_local) 1차 구현

## 종합 결론

- **승인 여부**: 차단 (CRITICAL 1건, HIGH 2건)
- 핵심 이슈: `_buildSegments`의 급행 누적 로직에 잠복 버그가 있어, 세그먼트 첫 부분이 급행 미운영이고 후반이 운영인 경우 급행 시간이 과소 계산됨
- 테스트 케이스가 우호적인 순서만 다루어 버그가 가려져 있음
- 그 외 아키텍처/불변성/UI 패턴은 대체로 깔끔하며 재사용 폴백/Tooltip 등 좋은 디자인이 보임

---

## CRITICAL

### 1. 세그먼트 내 급행 활성화 이전 edge의 weight가 누락됨

- 파일: `lib/domain/usecases/search_route.dart:264-271`
- 증상: 한 세그먼트 안에서 첫 N개 edge가 `expressWeightSeconds=null`이고 그 뒤 edge가 non-null이면, 앞쪽 N개 edge의 `weightSeconds`가 `currentExpressDurationSeconds`에 합산되지 않음. 그 결과 `expressDurationSeconds`가 실제보다 작아진다.
- 시나리오: A-B-C-D-E를 한 노선에서 이동 (A→B는 모든 차량 정차이므로 expressWeightSeconds=null, B→C부터 급행 운영). 사용자는 A→B는 정차하는 어떤 열차든 타고, B 이후 급행 패턴이 적용되는 시간을 봐야 한다. 현재 로직은 A→B 시간을 통째로 빠뜨림.
- 현재 코드:
  ```dart
  if (edge.expressWeightSeconds != null) {
    currentExpressDurationSeconds =
        (currentExpressDurationSeconds ?? 0) + edge.expressWeightSeconds!;
  } else if (currentExpressDurationSeconds != null) {
    // 활성화 이후 폴백만 수행 — 활성화 이전은 영영 누락
    currentExpressDurationSeconds =
        currentExpressDurationSeconds + edge.weightSeconds;
  }
  ```
- 수정 제안 (두 가지 패턴 중 하나 선택):

  **패턴 A — 사후 보정 (간단)**: 활성화 시점에 currentDurationSeconds까지의 누적값으로 초기화한다.
  ```dart
  if (edge.expressWeightSeconds != null) {
    if (currentExpressDurationSeconds == null) {
      // 첫 활성화: 그동안 누적된 완행 시간을 베이스로 사용
      currentExpressDurationSeconds =
          (currentDurationSeconds - edge.weightSeconds) + edge.expressWeightSeconds!;
      // 주: currentDurationSeconds는 이번 edge의 weight를 이미 반영했으므로 빼주고 express로 대체
    } else {
      currentExpressDurationSeconds += edge.expressWeightSeconds!;
    }
  } else if (currentExpressDurationSeconds != null) {
    currentExpressDurationSeconds += edge.weightSeconds;
  }
  ```
  단, 이 방식은 currentDurationSeconds가 같은 시점에 같이 갱신되는 순서 의존이 있어 가독성이 떨어짐.

  **패턴 B — 두 누적기 분리 (권장)**: 항상 두 누적값을 모두 갱신하고, "급행 활성화 여부"는 별도 플래그로 추적.
  ```dart
  var currentDurationSeconds = 0;
  var currentExpressAccumulated = 0; // 항상 누적
  var hasExpressInSegment = false;

  // ... 매 edge 처리:
  currentDurationSeconds += edge.weightSeconds;
  if (edge.expressWeightSeconds != null) {
    currentExpressAccumulated += edge.expressWeightSeconds!;
    hasExpressInSegment = true;
  } else {
    currentExpressAccumulated += edge.weightSeconds;
  }

  // 세그먼트 종료 시:
  final expressDuration = hasExpressInSegment
      ? currentExpressAccumulated + dwellSum
      : null;
  ```
  이 방식이 의도와 코드가 일치하여 권장.

- 테스트 추가 필요:
  ```dart
  test('첫 edge가 완행 only, 두번째가 급행 — 첫 edge weight도 합산되어야 함', () async {
    when(() => mockRepo.getAllConnections()).thenAnswer((_) async => [
      const Connection(
        fromStationId: '201', toStationId: '202', lineId: '2',
        travelTimeSeconds: 90,
      ),
      const Connection(
        fromStationId: '202', toStationId: '203', lineId: '2',
        travelTimeSeconds: 90, expressTimeSeconds: 60,
      ),
    ]);
    final result = await searchRoute.execute('201', '203');
    // 90(완행 폴백) + 60(급행) + dwell30 = 180
    expect(result!.segments.first.expressDurationSeconds, 180);
    expect(result.totalExpressTimeSeconds, 180);
  });
  ```
  현재 구현으로는 60 + 30 = 90이 나와 실패해야 정상이다.

---

## HIGH

### 1. 파일 길이 한계 근접 — route_result_screen.dart 681줄

- 파일: `lib/features/route_search/presentation/screens/route_result_screen.dart` (681줄)
- 사실 확인: 800줄 한계 이내이나, 이번 변경으로 `_RouteView`(state), `_TrainModeToggle`, `_RouteSummaryHeader`(props 5개 추가) 등이 부풀어 응집도가 떨어짐.
- 수정 제안: 위젯들을 별도 파일로 추출하여 본 파일을 400~500줄로 축소.
  ```
  lib/features/route_search/presentation/widgets/
    route_summary_header.dart   // _RouteSummaryHeader, _InfoChip, _ChipDivider
    train_mode_toggle.dart      // _TrainModeToggle
    route_timeline.dart         // _RouteTimeline, _SegmentHeader, _StationRow
  ```
  이미 `widgets/transfer_row.dart`가 분리된 사례가 있어 컨벤션에도 부합.

### 2. `findFirstDirectionalSegment` 폴백이 급행 모드와 무관하게 완행 기준 출발시각만 계산

- 파일: `lib/features/route_search/utils/departure_time_calculator.dart:15-51`
- 증상: `computeDepartureTime`은 `useExpress` 인자를 받지 않는다. 하지만 김포공항(9호선) 같은 시나리오에서 일반 열차와 급행 열차의 다음 출발 시각이 서로 다르다. 사용자가 급행 모드를 선택했는데도 다음 일반 열차의 시각을 보여주면 도착 시각 계산이 부정확해진다.
- 영향: 실시간 도착정보(arrivalAsync)나 시간표(LineSchedule) 모두 급행/완행을 구분하지 않고 가장 빠른 열차를 채택. 본 PR 범위에서 모드별 출발시각 보정까지 가는 것이 과한 스코프라면, 최소한 다음 처리가 필요:
  1. **명시적 한계 주석**: 출발시각은 모드와 무관하게 가장 빠른 열차 기준으로 계산되며, 도착시각은 마지막 세그먼트에 한해 모드별 소요시간으로 계산된다는 사실을 README/주석에 기록.
  2. **TODO 마커 + 티켓 번호**: `// TODO(express-mode): 모드별 출발 열차 필터링` 형식으로 추적.
- 수정 제안 (스코프 확장 시):
  ```dart
  DateTime computeDepartureTime({
    required AsyncValue<List<ArrivalInfo>> arrivalAsync,
    required RouteResult routeResult,
    required DateTime now,
    LineSchedule? lineSchedule,
    bool useExpress = false, // 추가
  }) {
    // ...
    // arrivalAsync 필터에 btrainSttus(급행/완행) 조건 추가
  }
  ```
  단, ArrivalInfo가 급행 여부 필드를 갖고 있어야 하며 시간표에도 etrnYn 필드가 있어야 하므로 별도 작업이 필요. 본 PR은 `최소한 한계 주석 + TODO`만 포함하여 닫고 후속 PR에서 처리 권장.

---

## MEDIUM

### 1. 활성 노선/방향 필터(`activeRouteFilterProvider`)가 급행 모드와 동기화되지 않음

- 파일: 화면 전반 (live_train_provider, activeRouteFilter)
- 증상: 사용자가 급행 모드를 선택해도 지도의 실시간 열차 표시는 모든 열차(완행 포함)를 그대로 보여줄 가능성 — 본 PR 범위 외이지만 UX 일관성 차원에서 후속 트리거 필요. CLAUDE.md의 "오버 엔지니어링 금지" 원칙에 따라 본 PR에서는 다루지 않더라도 이슈 트래킹 권장.

### 2. `_RouteSummaryHeader`의 `totalMinutes` 표시는 급행/완행 토글 직후 즉시 갱신되지만 _RouteSummaryHeader는 StatelessWidget로서 5개 필드가 늘었음

- 파일: `lib/features/route_search/presentation/screens/route_result_screen.dart:214-311`
- 수정 제안: 추후 partial state 분리. 현재는 부모 `_RouteView`가 setState 시 전체 Column이 리빌드되어 ListView 스크롤 위치가 보존되는지 검증 필요. ListView.builder는 키 없이 재생성되면 스크롤 리셋 위험. 테스트 추가:
  ```dart
  testWidgets('급행 토글 후 ListView 스크롤 위치가 유지된다', ...);
  ```

### 3. 환승역 역 정차시간이 급행 모드에서 동일하게 가산됨

- 파일: `lib/domain/usecases/search_route.dart:194-202, 234-241, 285-292`
- 사실 확인: 코드 주석(`// 급행 시간도 동일한 dwell 가산 (단순화 가정).`)에 명시됨. 다만 급행은 일부 역을 통과하므로 dwell 수가 적어야 정확하다. 현재 단순화는 보수적(과대 추정) 방향이라 큰 문제는 아니지만, 향후 정확도 개선이 필요하면 `급행 정차역` 메타데이터를 도입해야 함.
- 권장: 한계 주석을 `_buildSegments` 함수 헤더에 docstring으로 옮겨, 이 단순화가 의도적임을 명확히 표시.

### 4. `_addTransferItem`에서 `transferDurations` 가드의 폴백 값이 `0`

- 파일: `lib/features/route_search/presentation/screens/route_result_screen.dart:503-509`
- 사실 확인: assert로 디버그 빌드에서는 위반 시 충돌. 릴리스 빌드에서는 0초 환승으로 표시되어 잘못된 정보가 됨. 폴백 값을 `?` 또는 "—" 텍스트로 분기 처리하거나, RouteResult 생성 시점에 불변식이 보장되도록 freezed factory에 assert 추가.
  ```dart
  factory RouteResult({
    ...
  }) = _RouteResult;

  // 추가
  factory RouteResult.checked({
    required List<RouteSegment> segments,
    ...
  }) {
    assert(transferGuides.length == transferDurations.length);
    assert(transferDurations.length == segments.length - 1 || segments.isEmpty);
    return RouteResult(...);
  }
  ```

### 5. `_TrainModeToggle.tooltip`은 비활성 시에만 노출 — 비활성 세그먼트 단독 클릭 시 SnackBar 등 즉각 피드백 없음

- 파일: `lib/features/route_search/presentation/screens/route_result_screen.dart:313-350`
- 증상: ButtonSegment.enabled=false인 항목은 탭이 무시되어 사용자가 왜 안 되는지 즉시 모른다. Tooltip은 long-press에서만 보이는 것이 일반적.
- 수정 제안: 급행 비활성 시 헤더에 작은 안내 캡션을 표시:
  ```dart
  if (!isExpressAvailable)
    Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Text(
        '이 경로에는 급행 운영 구간이 없습니다',
        style: TextStyle(fontSize: 11, color: Colors.grey[500]),
      ),
    ),
  ```

### 6. `compute_travel_times.dart`의 급행 데이터 무존재 시 `c.remove('expressTimeSeconds')`

- 파일: `tool/compute_travel_times.dart:147`
- 사실 확인: 데이터가 사라진 경우 명시적으로 필드를 제거 → 의도와 일치(연속 실행 시 stale 값 잔존 방지). 단, 한 번 시간표에 짧게 누락이 발생하면 직전까지 잘 들어있던 값이 날아갈 위험. 보수적으로 동작하려면:
  ```dart
  // 데이터 없음: 기존 값 유지 (잠시 시간표 누락 대비). 다음 실행 시 다시 계산.
  // 만약 기존 값을 명시적으로 무효화하려면 --reset-express 플래그를 추가.
  ```
- 수정 제안: 옵션 플래그 추가하여 명시적으로 결정.

---

## LOW

### 1. 테스트 케이스에서 첫 edge express, 두 번째 local인 케이스만 다룸

- 파일: `test/domain/usecases/search_route_test.dart:322-349`
- 사실 확인: CRITICAL 이슈와 직결. 위 CRITICAL의 추가 테스트 케이스 함께 도입.

### 2. `_computeTotalExpress`에 빈 segments 케이스 가드 미명시

- 파일: `lib/domain/usecases/search_route.dart:134-150`
- `segments.any(...)`는 빈 리스트에서 false를 반환하므로 정상 null. 명시적 주석으로 의도를 표기 권장.
  ```dart
  // segments가 비면 hasAnyExpress=false → null. 명시적으로:
  if (segments.isEmpty) return null;
  ```

### 3. `_buildSegments`의 분기마다 dwell 가산이 3번 중복

- 파일: `lib/domain/usecases/search_route.dart:194-202, 234-241, 285-292`
- 추출 함수로 정리하면 가독성과 유지보수성 향상.
  ```dart
  ({int local, int? express}) _addDwell({
    required int durationSeconds,
    required int? expressDurationSeconds,
    required int stationCount,
  }) {
    final intermediateCount = math.max(0, stationCount - 2);
    final dwellSum = intermediateCount * dwellTimeSeconds;
    return (
      local: durationSeconds + dwellSum,
      express: expressDurationSeconds != null
          ? expressDurationSeconds + dwellSum
          : null,
    );
  }
  ```

### 4. `route_result_screen.dart:172-177` 마지막 세그먼트 duration 분기 중복

- 동일 로직이 `_RouteTimeline._segmentDuration`(L400-405)에도 있음. 헬퍼로 공유.
  ```dart
  int segmentDuration(RouteSegment s, bool useExpress) =>
      useExpress ? (s.expressDurationSeconds ?? s.durationSeconds) : s.durationSeconds;
  ```

### 5. `print` 사용 — `tool/compute_travel_times.dart`

- 파일: `tool/compute_travel_times.dart` 전반
- `// ignore_for_file: avoid_print`로 정상 처리됨. CLI 도구이므로 OK. 칭찬.

### 6. 한국어 주석 일관성

- 파일: `lib/domain/usecases/search_route.dart` 주석에 영어 단어 혼용(`null propagation`, `dwell` 등). 컨벤션상 한국어 주석 우선이지만 기술 용어는 허용 범위. LOW.

---

## 칭찬

### 1. Freezed nullable 필드 처리

- `Connection.expressTimeSeconds`, `RouteResult.totalExpressTimeSeconds`, `RouteSegment.expressDurationSeconds` 모두 nullable 정의 + 설명 주석으로 의도가 명확. JSON 역호환 테스트 4건으로 안전성 입증. (`test/domain/entities/connection_test.dart:32-66`)

### 2. UI 폴백 안전성

- `_RouteView`의 `effectiveMode = _isExpressAvailable ? _trainMode : TrainMode.local` (L143-144) — 사용자가 급행 선택 후 다른 경로로 진입했을 때 잘못된 상태가 유지되는 것을 막는 좋은 방어 패턴.

### 3. SegmentedButton enabled 분기

- `ButtonSegment(value: TrainMode.express, enabled: isExpressAvailable)` (L336) + Tooltip 폴백 — Material3 컨벤션에 맞는 깔끔한 처리.

### 4. compute_travel_times.dart의 etrnYn 분리

- `localGaps`/`expressGaps` 별도 누적 + 각각 중앙값 산출 — outlier에 강건한 통계 처리. 코드 가독성도 좋음.

### 5. 테스트 그룹화

- `group('급행 시간 합산', ...)` 하위에 4개 케이스로 의도가 잘 드러나며 setUp의 mock 오버라이드 패턴도 깔끔.

### 6. 환승 시간은 모드 무관 — 의미적으로 정확

- `_computeTotalExpress`에서 transferDurations를 그대로 더함. 환승 자체는 급행/완행과 독립이므로 정확한 모델링.

### 7. ConsumerStatefulWidget 분리

- `_RouteView`를 별도 ConsumerStatefulWidget으로 추출하여 탭 전환 시 각 뷰의 _trainMode가 독립적으로 유지됨. `_RouteResultScreenState`의 TabController dispose도 깔끔하게 처리.

---

## 후속 작업 권장

1. CRITICAL 1번 수정 + 테스트 추가 (필수, 머지 차단)
2. HIGH 1번 (파일 분리) — 후속 작업으로 빠르게 진행
3. HIGH 2번 (출발시각 모드별 분리) — 별도 PR. 본 PR엔 한계 주석 추가.
4. MEDIUM 4, 5번 — 사용자 경험 개선, 본 PR 또는 후속.
5. `flutter analyze` + 신규/수정 테스트 전체 통과 확인.

