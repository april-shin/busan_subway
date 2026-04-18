# 환승 가이드 기능 코드 리뷰

리뷰 대상 커밋: 환승 가이드(내리는 문 방향 / 추천 객차 / 문 번호) 기능 구현
리뷰어: subway-code-reviewer
리뷰 일자: 2026-04-15

## 총평

- Clean Architecture 계층 분리 준수(domain → data 의존 없음), Freezed 불변 모델 사용, Riverpod 계층 영향 최소, 테스트 커버리지 양호.
- nullable TransferGuide 처리가 UI/유스케이스/테스트 전반에 걸쳐 일관되게 graceful하다.
- index 매칭 불변식(`transferGuides.length == transferDurations.length == transferCount`) 유지.
- 2호선 순환선 처리는 `isDownBetween`에 적절히 위임되어 있고, 세그먼트 "마지막 두 역 쌍"을 사용하므로 경계(243↔201) 통과 세그먼트도 안전하게 판정된다.
- 차단성 이슈(CRITICAL/HIGH) 없음. MEDIUM/LOW 개선 권장 항목 일부 존재.

결과: 승인(WARNING 수준), MEDIUM 이슈는 후속 개선 권장.

---

## CRITICAL

없음.

---

## HIGH

없음.

---

## MEDIUM

### M1. `SearchRoute.execute`와 `_buildRouteResult`의 중복 코드
- 위치: `lib/domain/usecases/search_route.dart:19-58` (execute), `:117-135` (_buildRouteResult)
- 문제: `execute`가 `_buildSegments` 호출 후 `RouteResult`를 직접 조립하는데, 동일한 조립 로직이 `_buildRouteResult`에도 있다. stationCount/transferCount 계산식이 두 곳에 복사되어 장기적으로 규칙 변경 시 drift 위험.
- 수정 제안: `execute`도 `_buildRouteResult` 재사용.

```dart
// 수정 후 (예시)
Future<RouteResult?> execute(String fromStationId, String toStationId) async {
  final stations = await _stationRepository.getAllStations();
  final connections = await _stationRepository.getAllConnections();
  final transferTimes = await _stationRepository.getTransferTimes();
  final transferGuides = await _stationRepository.getTransferGuides();

  final graph = GraphBuilder().build(
    stations: stations,
    connections: connections,
    transferTimes: transferTimes,
  );
  final stationMap = {for (final s in stations) s.id: s};
  final fromStation = stationMap[fromStationId];
  final toStation = stationMap[toStationId];
  if (fromStation == null || toStation == null) return null;

  final finder = ShortestPathFinder(graph: graph);
  final results = finder.findShortestPathBetweenStations(
    fromStation.name,
    toStation.name,
  );
  if (results.isEmpty) return null;

  return _buildRouteResult(results.first, graph, stationMap, transferGuides);
}
```

### M2. `_buildRouteResult`/`_buildSegments`의 `graph` 파라미터 타입이 `dynamic`
- 위치: `lib/domain/usecases/search_route.dart:119`, `:143`
- 문제: `dynamic`으로 선언되어 있어 컴파일러/IDE 타입 체크가 비활성화됨. 이 메서드들은 실제로 `graph`를 사용하지 않는데도 계속 전달되고 있다.
- 수정 제안: 사용하지 않는 파라미터라면 제거하거나, 필요하다면 정확한 타입(`Graph` 등)으로 선언한다.

```dart
// 현재 _buildSegments는 graph를 사용하지 않으므로 제거 가능.
({List<RouteSegment> segments, List<int> transferDurations, List<TransferGuide?> transferGuides})
    _buildSegments(
  PathResult path,
  Map<String, Station> stationMap,
  Map<String, TransferGuide> transferGuides,
) { ... }
```

### M3. `_addTransferItem`의 인덱스 안전 폴백이 불변식을 감춘다
- 위치: `lib/features/route_search/presentation/screens/route_result_screen.dart:390-406`
- 문제: `transferGuides.length < transferIndex + 1`인 경우 null로 폴백하는데, 유스케이스 쪽에서 이미 `transferGuides.length == transferDurations.length == segments.length - 1`이 보장되므로 실질적으로 항상 맞아떨어진다. 불필요한 방어 코드가 "맞지 않아도 괜찮다"는 잘못된 메시지를 준다.
- 수정 제안: 같은 인덱스 방어 코드를 유지하되 `assert`로 불변식 명시하거나, 단순히 직접 인덱싱한다.

```dart
assert(routeResult.transferGuides.length == routeResult.transferDurations.length,
    'transferGuides와 transferDurations의 길이가 일치해야 한다');
final guide = routeResult.transferGuides[transferIndex];
final transferSeconds = routeResult.transferDurations[transferIndex];
```

### M4. `_buildGuideKey` 키 포맷 공통화 필요
- 위치: `lib/domain/usecases/search_route.dart:294-302`
- 문제: 키 포맷(`{역명}_{이전노선}_{up|down}_{다음노선}`)이 `search_route.dart`에서만 조립되고 있다. 향후 `transfer_guides.json` 생성 툴/역방향 조회/테스트 검증에서 같은 키 규칙을 다시 작성해야 한다면 drift 위험이 있다.
- 수정 제안: `lib/core/utils/transfer_guide_key.dart` 같은 위치에 `buildTransferGuideKey(stationName, prevLineId, isDown, nextLineId)`를 추출해 재사용한다.

```dart
// lib/core/utils/transfer_guide_key.dart
String buildTransferGuideKey(
  String stationName,
  String prevLineId,
  bool isDown,
  String nextLineId,
) => '${stationName}_${prevLineId}_${isDown ? 'down' : 'up'}_$nextLineId';
```

### M5. `TransferRow`의 점선 높이 `hasGuide ? 52 : 36` 매직 넘버
- 위치: `lib/features/route_search/presentation/widgets/transfer_row.dart:24`
- 문제: 점선 높이가 가이드 렌더 여부에 따라 분기하는 두 매직 넘버(36, 52)로 하드코딩. 디자인 변경 시 위치 유추가 어렵다.
- 수정 제안: 상수로 분리하거나 `LayoutBuilder`로 내부 컬럼 실제 높이에 맞추는 방식 고려.

```dart
static const _dashedHeightCompact = 36.0;
static const _dashedHeightExpanded = 52.0;
final dashedLineHeight = hasGuide ? _dashedHeightExpanded : _dashedHeightCompact;
```

### M6. `_formatTime` 중복 정의 (기존 이슈 — 이 PR이 아님)
- 위치: `lib/features/route_search/presentation/screens/route_result_screen.dart:184`
- 참고: 파일 내부에서 private top-level 함수로 존재. 이 PR의 변경 범위는 아니므로 LOW로 분류해도 됨. 언급만 남김.

---

## LOW

### L1. `transfer_guides.json`이 빈 맵 `{}` 상태
- 위치: `assets/json/transfer_guides.json`
- 상태: 현재 콘텐츠가 없음. 코드/테스트 경로상 null 폴백이 정상 동작하므로 기능적으로 문제 없음.
- 제안: README 또는 `assets/json/transfer_guides.json` 상단에 키 포맷 예시 주석(혹은 별도 `.md`)을 추가하거나, 데이터 작성자가 이해할 수 있는 샘플 엔트리 1~2개만 넣어 두는 것 고려. JSON 포맷은 주석을 허용하지 않으므로 인근 문서에서 처리.

예시 샘플:
```json
{
  "을지로3가_2_up_3": { "doorSide": "right", "car": 5, "door": 1, "note": "충무로 방면 가까움" }
}
```

### L2. `DashedLinePainter.shouldRepaint`가 항상 false
- 위치: `lib/features/route_search/presentation/widgets/transfer_row.dart:138`
- 상태: 색상이 상수로 전달되는 현 사용 시나리오에서는 문제 없음. 다만 color가 dynamic으로 바뀌는 경우 재그리기가 되지 않는다.
- 제안: `oldDelegate is DashedLinePainter && oldDelegate.color != color` 로 유지보수성 향상.

### L3. `_doorSideLabel` / `_resolveGuideIcon` 등 private top-level 함수
- 위치: `lib/features/route_search/presentation/widgets/transfer_row.dart:150-189`
- 상태: 현재는 동일 파일에 있으므로 문제 없음. 향후 i18n 확장이나 다른 위젯에서 공용이 되면 `transfer_guide_format.dart` 같은 유틸로 분리 권장.

### L4. `car` / `door` 값 범위 검증 부재
- 위치: `lib/domain/entities/transfer_guide.dart`
- 상태: `int?`만 지정되어 음수나 0 같은 비정상 값이 들어와도 그대로 표시된다. 외부 소스(JSON)가 개발자 통제 하에 있다면 과도한 방어.
- 제안: 데이터 로딩 시점에 `car >= 1 && car <= 10` 등 sanity check 추가(경고만 하고 null로 치환) 고려. 현재는 LOW.

---

## 칭찬

- `lib/domain/entities/transfer_guide.dart`: Freezed + json_serializable 표준 패턴을 단정하게 지켰고, 모든 필드를 nullable로 유지하여 부분 데이터만 있어도 graceful 렌더가 가능하다.
- `lib/data/local/local_data_source.dart:62-79`: 기존 `loadTransferTimes` 등과 동일한 캐시 패턴을 그대로 유지, `clearCache`도 추가해 캐시 무효화가 일관적이다.
- `lib/features/route_search/presentation/widgets/transfer_row.dart`: 가이드 텍스트 조합 규칙(8가지 조합)이 명확한 주석으로 문서화되어 있고, `_buildGuideText`/`_doorSideLabel`/`_buildCarDoorText`로 작은 함수 단위 분해가 잘 되어 있다.
- `lib/domain/usecases/search_route.dart:269-302`: `_resolveTransferGuide`는 null-safe 조기 반환, 세그먼트 길이 체크, 마지막 두 역으로 2호선 경계까지 올바르게 처리. 주석이 키 포맷을 명시해 드리프트 위험을 낮춘다.
- `test/domain/usecases/search_route_test.dart`: up/down 양방향, 같은 노선 경로, 출발이 환승역인 경우, executeAll fastest, 불변식 길이 일치까지 커버. stub은 `setUp`에서 기본값(빈 맵) 후 테스트별로 override 하는 패턴이 깔끔.
- `test/features/route_search/presentation/transfer_row_test.dart`: 8가지 조합(모두 있음 / 일부만 / 전부 null / note) 및 좌/우 아이콘까지 폭넓게 커버.
- `test/core/utils/line_direction_test.dart`: 2호선 순환 경계(201↔243)와 4호선 진접선 분기 방향 판정을 모두 검증. 방어적 입력(빈 문자열, 알파벳 접두사)까지 포함.

---

## 불변식 / 아키텍처 체크 결과

- [x] domain 레이어에 Flutter 임포트 없음 (`transfer_guide.dart`, `route_result.dart`, `search_route.dart`, `station_repository.dart`)
- [x] graph 모듈에 Flutter 의존성 없음 (변경 없음)
- [x] 리포지토리 인터페이스(domain) / 구현체(data) 분리 유지
- [x] `@freezed` 불변 모델 사용
- [x] `List.unmodifiable`로 세 리스트(segments, transferDurations, transferGuides) 모두 감싸 반환
- [x] Index 매칭 불변식: `transferGuides.length == transferDurations.length == segments.length - 1` 유지
- [x] nullable 처리: guide가 null이면 UI 2행이 생략되어 기존 UX 유지
- [x] `_buildGuideKey` 키 포맷 단일 소스: `search_route.dart` 내 1곳에서만 생성됨 (M4에서 유틸 추출 권장)
- [x] 2호선 순환 처리: `_resolveTransferGuide`가 세그먼트의 "마지막 두 역" 쌍을 사용하므로 경계(243↔201) 통과 세그먼트도 안전
- [x] 파일당 라인수: 모두 800줄 이하 (최대 `route_result_screen.dart` 552줄)
- [x] 보안: 하드코딩 시크릿 없음, rootBundle 경로는 상수, 경로 조작 위험 없음
- [x] 성능: LocalDataSource 캐시 패턴 기존과 일관, getTransferGuides 1회 호출 후 재사용
- [x] 코드 컨벤션: 한국어 주석/문자열, 네이밍 일관

---

## 추가 권장

1. `build_runner` 실행 확인: `route_result.dart`에 새 필드(`transferGuides`)가 추가되었고 freezed 생성 파일도 업데이트되어 있는 것을 확인. 추가 실행 불필요.
2. 향후 `transfer_guides.json` 데이터가 추가될 때, 키 포맷을 검증하는 간단한 유닛 테스트(로드된 모든 키가 `{역명}_{라인}_up|down_{라인}` 패턴을 만족하는지) 추가 권장.
3. UI 쪽 테스트에서 `dashedLineHeight` 분기(36 vs 52)가 정상인지를 골든 테스트로 검증해도 좋음. 현재는 LOW.

---

## 수정 권장 우선순위

1. M1 (execute 중복 제거) — 30분 내 리팩토링
2. M2 (`dynamic` graph 파라미터 제거) — 15분 내
3. M4 (`buildTransferGuideKey` 유틸 추출) — 30분 내, 후속 데이터 작업 툴과 공유 예정 시 우선
4. M3, M5 — 시간 있을 때
5. L1~L4 — 후속 태스크로 충분
