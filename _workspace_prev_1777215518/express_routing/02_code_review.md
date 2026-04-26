# 코드 리뷰 결과 — 급행 노선 별도 논리 노선 모델링

리뷰 일시: 2026-04-19
대상 plan: `~/.claude/plans/serene-fluttering-pie.md`

---

## 요약

전반적으로 **잘 설계된 변경**입니다. 그래프 빌더에 옵셔널 인자를 추가하여 하위 호환성을 유지했고, 가상 노선 ID(`{line}E`/`{line}M`) 도입과 비대칭 환승 edge 처리가 명확합니다. Freezed/JSON 직렬화·캐시·테스트 커버리지도 견고합니다.

다만 **데이터 추출 단계에서 비현실적인 skip edge가 그래프에 들어와 Dijkstra 결과를 왜곡할 가능성**이 가장 큰 문제입니다. UI 계층에 일관성 없는 색상 조회와 누수된 호환성 이슈도 함께 존재합니다.

판정: **차단(Block) — HIGH 1건 + MEDIUM 다수.** HIGH(데이터 정합성)을 수정하거나 추출 로직 보강 후 머지 권장.

---

## CRITICAL

없음.

---

## HIGH

### H1. `extract_express_skip_edges.py` — 비현실적 skip edge가 다수 생성됨 (그래프 신뢰성 훼손)
파일: `tool/extract_express_skip_edges.py:130-168`
산출물: `assets/json/express_skip_edges.json`

**현상**: 1호선 478개 edge 중 일부가 "역 7개를 30~60초에 통과"하는 것으로 기록됨.
```
142 → 137: 120s, skipped 4역
183 → 178: 150s, skipped 3역
130 → 122: 60s, skipped 7역    ← 비현실적
133 → 125: 60s, skipped 7역    ← 비현실적
134 → 126: 30s, skipped 7역    ← 비현실적 (130km/h+ 필요)
```
이런 edge는 Dijkstra가 항상 최단 경로로 선택하게 되어 잘못된 추천이 발생합니다.

**원인**:
1. 같은 trainno가 시발/종착역으로 회송하면서 동일한 정차역을 두 번 거친 경우, 짧은 인접 시간 차가 잘못된 페어로 기록됨.
2. 1호선은 본선/지선(경원·경인·경부·장항) 분기로 trainno가 다양한 운행 패턴을 가짐. 다른 패턴의 trainno가 같은 (from, to) 페어를 가질 때 BFS가 단순히 첫 경로만 잡으면서 실제 운행하지 않은 가상의 skip 경로가 생성됨.
3. `if 0 < gap < 1800` 필터(30분 미만)만으로는 비현실적인 짧은 gap을 거르지 못함.

**수정 제안**:
```python
# 1. 평균 운행속도(예: 60km/h) 기반 최소 시간 계산이 어렵다면
#    skipped 역 수 기반 하한선을 부과:
MIN_SECONDS_PER_SKIPPED_STATION = 30  # 정차역당 최소 30초

# bfs 결과 후:
if len(skipped_ids) > 0:
    min_required = (len(skipped_ids) + 1) * MIN_SECONDS_PER_SKIPPED_STATION
    if median < min_required:
        # 비현실적 — 스킵
        skipped_pairs += 1
        continue

# 2. 또는 trainno 단위 필터링: 같은 trainno가 동일 역을 두 번 이상 등장
#    하면 이상치로 간주하고 해당 trainno의 모든 페어 제외.
for (tno, dr), seq in stops.items():
    seen = set()
    has_dup = False
    for stn, _ in seq:
        if stn in seen:
            has_dup = True
            break
        seen.add(stn)
    if has_dup:
        continue  # 회송/순환 패턴은 신뢰 불가
    for i in range(len(seq) - 1):
        ...

# 3. 최소 trainno 빈도수 임계값:
#    동일 (from, to) 페어가 N개 미만의 trainno에서만 등장하면 제외
MIN_TRAINNO_COUNT = 3
filtered = {pair: gaps for pair, gaps in pair_times.items() if len(gaps) >= MIN_TRAINNO_COUNT}
```

`compute_express_skip.py`(기존)와 비교하여 어떤 필터가 누락됐는지 점검 필요.

**검증 방법**: 변경 후 1호선 edge 수가 50~150개 수준으로 감소하고, 평균 seconds가 100~300초 범위에 분포해야 함.

---

## MEDIUM

### M1. `lineColorFor` 폴백이 미적용된 화면 다수
파일:
- `lib/features/route_search/presentation/screens/station_picker_screen.dart:135`
- `lib/features/station_detail/presentation/screens/station_detail_screen.dart:52, 117`
- `lib/features/home/presentation/widgets/search_bar_widget.dart:104`

**이슈**: `lineColors[lineId] ?? Colors.grey` 패턴을 그대로 두어 `9E`/`경춘E` 같은 가상 노선 ID가 우연히 이 화면에 전달되면 회색으로 표시됨. 현재는 가상 노선 ID가 검색·역 상세에 들어오지 않지만, 향후 변경 시 일관성 깨짐. 또한 `lineColorFor`라는 단일 진입점이 있는데 일부만 사용하는 것은 일관성 부족.

**수정**:
```dart
// 모든 화면에서 통일:
final color = lineColorFor(lineId);          // ✓
final lineName = lineNames[lineId] ?? lineId; // 그대로 OK (lineNames도 9E/1E 추가됨)
```

소소한 변경이지만 새 함수의 의도를 살리려면 통일 필요.

---

### M2. `_resolveTransferGuide` — 모드 전환(`9M`) edge에서 부적절한 가이드 매칭 시도
파일: `lib/domain/usecases/search_route.dart:218-265, 347-373`

**이슈**: 모드 전환 edge도 `isTransfer=true`이므로 `_buildSegments`가 환승으로 인식하고 `_resolveTransferGuide`를 호출함. 이 때:
- `prevLineId = '9'` (이전 세그먼트), `nextLineId = '9E'` (다음 세그먼트)
- 키: `"신논현_9_up_9E"` → `transferGuides`에 절대 매칭 안 됨 (가이드는 실제 환승만 등록)

결과적으로 매번 null이 반환되어 동작은 정상이지만, **불필요한 키 조립과 맵 조회가 반복**됨. 또한 향후 누군가 가이드 키 형식을 잘못 추가하면 의도치 않게 매칭될 수 있음.

**수정**:
```dart
// _buildSegments의 환승 처리 분기에서, edge.lineId가 'M'으로 끝나면
// (모드 전환) 가이드 조회를 건너뜀:
if (edge.isTransfer) {
  ...
  final isModeSwitch = edge.lineId.endsWith('M');
  transferGuidesList.add(isModeSwitch
      ? null
      : _resolveTransferGuide(...));
  ...
}
```
또는 `_resolveTransferGuide` 내부에서 `nextLineId`가 `prevLineId + 'E'` 또는 그 역인 경우 즉시 null 반환.

---

### M3. `subway_graph.dart` — `addEdge`도 `addNode` 호출 누락 시 노드가 등록되지 않음
파일: `lib/graph/subway_graph.dart:15-18`

**이슈**: `addEdge`는 `_adjacencyList`만 갱신하고 `_nodes`는 건드리지 않음. 그래프 빌더가 `_addExpressNodeIfNeeded`로 미리 노드를 추가한 뒤에 edge를 넣고 있어 현재는 안전하지만, 누군가 새 코드 경로에서 노드 등록을 잊으면 `getNode(toNodeId)`가 null인 상태에서 인접 리스트에는 등록되어 있는 부정합 발생 가능. `_addExpressSkipEdges`에 `containsNode` 가드가 있는 점은 칭찬할 만함.

**수정 제안**(방어):
```dart
void addEdge(GraphEdge edge) {
  // 디버그 빌드에서만 검증
  assert(_nodes.containsKey(edge.fromNodeId),
      'addEdge: fromNodeId(${edge.fromNodeId}) 노드 미등록');
  assert(_nodes.containsKey(edge.toNodeId),
      'addEdge: toNodeId(${edge.toNodeId}) 노드 미등록');
  _adjacencyList.putIfAbsent(edge.fromNodeId, () => []);
  _adjacencyList[edge.fromNodeId]!.add(edge);
}
```

---

### M4. `headway_estimator.dart` — `buildHeadwayMap` 가상 노선 헤드웨이 누락 가능성
파일: `lib/core/utils/headway_estimator.dart:48-53`

**이슈**: `headwaySeconds` 맵의 키는 `LineSchedule`의 lineId(예: `9`). 그래프 빌더가 `9E`/`9M` edge에서 헤드웨이를 조회할 때 base lineId(`9`)로 조회한다고 주석에 명시되어 있고, 실제로 `_addModeSwitchEdges`도 `headwaySeconds[key.baseLineId]`로 조회하므로 동작은 OK. 그러나 `_addTransferEdges`에서 `from.lineId` / `to.lineId`로 조회하는데 만약 그래프상의 from/to가 가상 노선이면 baseLineId 변환이 누락될 수 있음.

현재 `_addTransferEdges`는 실제 환승역(같은 이름의 다른 노선) 사이의 edge만 만들고 가상 노선 노드는 환승역에 포함되지 않으므로 OK. 그러나 향후 가상 노선에 환승 edge가 도입되면 버그 가능. 명시적 헬퍼로 추출하면 안전:

```dart
String _baseLine(String lineId) =>
    lineId.endsWith('E') || lineId.endsWith('M')
        ? lineId.substring(0, lineId.length - 1)
        : lineId;

final fromHeadway = headwaySeconds[_baseLine(from.lineId)] ?? _defaultHeadwaySeconds;
```

---

### M5. `SearchRoute._loadHeadwayMap` 예외 무음 처리 — 디버그 로그 부족
파일: `lib/domain/usecases/search_route.dart:127-136`

**이슈**: `catch (_)` 으로 모든 예외를 삼킴. 시간표 로드 실패는 사용자에게는 영향이 없지만(폴백 동작), 디버깅 시 헤드웨이가 적용되지 않는 이유를 알 수 없음. 프로젝트는 `print`/`debugPrint` 금지 규칙이 있으므로 예외 정보를 어떻게 노출할지 정책 정립 필요.

**제안**: assert (디버그 빌드에서만):
```dart
} catch (e, st) {
  assert(() {
    // 테스트/개발 빌드에서 에러 가시화
    Zone.current.handleUncaughtError(e, st);
    return true;
  }());
  return const <String, int>{};
}
```
또는 별도 로깅 인프라가 있으면 그쪽 사용.

---

### M6. `loadExpressSkipEdges` 빈 catch — 동일한 디버그 가시성 이슈
파일: `lib/data/local/local_data_source.dart:122-126`

**이슈**: M5와 같은 패턴. `try { ... } catch (_)` 빈 catch가 두 군데. 하나는 파일 부재, 다른 하나는 개별 항목 파싱. 둘 다 의도적 폴백이지만 가시성이 없음.

**수정**: 적어도 캐시 변수가 처음 비어있을 때 한 번은 로깅하도록.

---

### M7. `route_result_screen.dart:535-537` — 급행 배지 조건이 두 모델을 OR로 결합
```dart
final showExpressBadge =
    (useExpress && segment.expressDurationSeconds != null) ||
        segment.lineId.endsWith('E');
```

**이슈**:
1. 새 모델(`9E` 세그먼트)에서는 `lineName`에 이미 "급행"이 들어있음 (`9호선 급행`). 빨간 배지 + "급행" 텍스트 + lineName "9호선 급행"이 중복 표시됨.
2. 신규 모델은 토글(useExpress)과 무관하게 항상 배지 표시 — 사용자가 "완행으로 보기" 토글 시에도 가상 급행 세그먼트는 그대로 급행 배지를 단 채 남음. 이는 의도된 동작인지 확인 필요.

**제안**:
- 신규 가상 급행 세그먼트는 lineName에 "급행"이 이미 있으니 빨간 배지를 생략 (`segment.lineId.endsWith('E')` 분기 제거)하거나,
- lineName을 "9호선" + 별도 "급행" 배지로 분리하여 표시 일관성 확보.

UX 결정 필요.

---

### M8. 모드 전환 edge에 `isTransfer=true` — 사용자에게 "환승" 메시지 노출 위험
파일: `lib/graph/graph_builder.dart:165-200` + `route_result_screen.dart:568-599` (`_addTransferItem`)

**이슈**: 모드 전환은 같은 역에서 완행→급행 환승을 표시하는 것인데, 현재 `_addTransferItem`은 `TransferRow(transferMinutes: ..., guide: guide)`로 일반 환승과 동일한 위젯을 사용. 사용자에게는 "신논현역에서 X분 환승"으로 표시되고 가이드는 null. 의도된 동작이지만 사용자에게 "X분 대기"로 인식시키는 게 맞는지 UX 검증 필요.

또한 `transferCount = segments.length - 1`이라 모드 전환도 환승 1회로 카운트됨. **9호선 언주→마곡나루**가 "환승 2회"로 표시되면 직관과 어긋남 (사용자는 "같은 9호선 안에서 급행 갈아탐 = 환승 0회"로 인식).

**제안**:
- `route_result.dart`의 `transferCount`를 "실제 환승" 기준으로 분리:
  ```dart
  // RouteResult에 추가
  int get realTransferCount =>
      segments.length - 1 -
      _modeSwitchCount; // 모드 전환은 제외
  ```
- 또는 `_buildSegments`에서 모드 전환 직전·직후 세그먼트를 같은 라인으로 합쳐 처리하는 옵션 (그러나 시각적으로 급행/완행 구분이 사라짐).

UX 결정 필요. 요구사항 리뷰어와 협의 필수.

---

## LOW

### L1. `tool/extract_express_skip_edges.py` — Python 도구의 한국어 print + 이모지
파일: `tool/extract_express_skip_edges.py:139, 176, 182`

```python
print(f'━━━ [{line}] 급행 정차쌍 {len(pair_times)}개 ━━━')
print(f'  {len(line_edges)}개 skip edge 생성 ({skipped_pairs}개 스킵)')
print(f'\n✓ {OUTPUT_JSON.relative_to(ROOT)} 생성: 총 {total_edges}개 edge')
```
프로젝트 규칙은 "코드/주석에 이모지 금지". 도구 스크립트의 `━━━`/`✓`는 이모지에 준하는 장식문자. 단순 `===`/`OK:`로 변경 권장.

---

### L2. `_extractLineId` — 컴팩트/레거시 분기 OK, 그러나 타입 캐스트 검증 부족
파일: `lib/data/local/timetable_data_source.dart:40-42`
```dart
return (json['id'] ?? json['lineId']) as String;
```
둘 다 없으면 `null as String` → `TypeError`. 호출부에서 `loadSchedules`가 try/catch 없이 호출되므로 빌드/런타임 폴백 없음. 단, JSON이 깨지면 어차피 앱이 동작 못 하므로 우선순위는 낮음.

---

### L3. `_addExpressNodeIfNeeded` — `addedNodes` 매개변수 추가 컨테이너 의존
파일: `lib/graph/graph_builder.dart:115-133`

함수가 호출자의 `Set<String>`을 변경하는 부수효과가 있음. 이는 불변성 원칙(CLAUDE.md)과 약간 충돌. 다만 그래프 빌더 내부 구현이고, `SubwayGraph.addNode` 자체가 idempotent하므로 `addedNodes` 가드가 필수는 아님. `addedNodes` 매개변수를 제거하고 graph.containsNode(expressNodeId)로 가드해도 동일 동작:

```dart
void _addExpressNodeIfNeeded({
  required SubwayGraph graph,
  required Map<String, Station> stationLookup,
  required String baseLineId,
  required String stationId,
}) {
  final expressLineId = '${baseLineId}E';
  final expressNodeId = '${stationId}_$expressLineId';
  if (graph.containsNode(expressNodeId)) return;
  ...
}
```
가독성 ↑, 매개변수 ↓. 현재 코드도 정상 동작.

---

### L4. `_addTransferEdges` — 양방향 weight 계산 시 `from.lineId`/`to.lineId` 변수명 모호
파일: `lib/graph/graph_builder.dart:243-265`

`fromWait`/`toWait`은 각각 from/to 노선의 배차/2이지만, 코드에서 `to→from edge`에 `fromWait`가 가산됨. 변수명을 `fromLineWait`/`toLineWait`로 변경하면 더 명확:

```dart
final fromLineWait = addHeadway
    ? (headwaySeconds[from.lineId] ?? _defaultHeadwaySeconds) ~/ 2
    : 0;
final toLineWait = addHeadway
    ? (headwaySeconds[to.lineId] ?? _defaultHeadwaySeconds) ~/ 2
    : 0;
// from→to: 도착 노선 = to → toLineWait 추가
graph.addEdge(... weightSeconds: transferTime + toLineWait ...);
// to→from: 도착 노선 = from → fromLineWait 추가
graph.addEdge(... weightSeconds: transferTime + fromLineWait ...);
```

---

### L5. `_buildSegments` 함수 길이 — 100줄 초과
파일: `lib/domain/usecases/search_route.dart:185-339`

함수가 약 155줄. 코딩 스타일 가이드의 "함수 < 50줄" 위반. 다음 헬퍼로 추출 가능:
- `_handleTransferEdge(...)` (i가 transfer일 때)
- `_handleSegmentBoundary(...)` (lineId 전환 처리)
- `_finalizeSegment(...)` (마지막 세그먼트 마무리)

단, 기존 코드부터 유지된 부분이라 이번 PR 스코프 외. 후속 작업으로 권장.

---

### L6. `route_result_screen.dart` — 파일 길이 766줄
파일 전체가 클래스 6개 (`RouteResultScreen`, `_RouteView`, `_RouteSummaryHeader`, `_TrainModeToggle`, `_TrainModeTab`, `_RouteTimeline`, `_SegmentHeader`, `_StationRow` 등) 포함. 800줄 한계에 근접. 향후 `widgets/` 하위로 분리 권장 (이번 PR 범위 외).

---

### L7. `extract_express_skip_edges.py` — `bfs_station_ids` 그래프 캐시 누락
파일: `tool/extract_express_skip_edges.py:91-108`

매 (from, to) 쌍마다 BFS를 새로 실행. 같은 노선 내 페어 수가 많으면 O(N×M×V). 1호선 478 페어 × 노드 수 100 = 50K 회 탐색. 도구 실행 1회 작업이라 성능 무관하나, 노선 단위로 단방향 스캔(인접 정차역만 BFS) + 캐싱 가능.

---

## 칭찬

- **`GraphBuilder.build`의 옵셔널 매개변수 기본값**: 기존 호출자(테스트, 일부 사용처)가 무수정으로 동작하도록 `expressSkipEdges = const []`, `headwaySeconds = const {}`. 하위호환 우수.
- **`_addExpressSkipEdges`의 `containsNode` 가드**: 노드 미등록 시 silent skip. 강건한 방어.
- **`_addTransferEdges`의 비대칭 분기**: `addBidirectionalEdge` 대신 양방향 별도 edge로 분리한 점 정확. 주석에 이유 명시 좋음.
- **`headwaySeconds.isNotEmpty`로 레거시 호환 분기**: 기존 그래프 빌더 호출부가 영향받지 않음. 회귀 테스트 통과.
- **`SubwayGraph.addBidirectionalEdge`의 `expressWeightSeconds` 역방향 전달**: 기존 버그 수정 흔적. 주석으로 회귀 방지 명확.
- **`ExpressSkipEdge`의 Freezed 사용 + `@Default([])`**: 불변성 + JSON 역호환 모두 충족. fromJson 테스트 라운드트립 검증 완비.
- **테스트 커버리지**: graph_builder_test, shortest_path_test, search_route_test에 급행 시나리오 다수. 회귀(`expressSkipEdges 비어있을 때`)도 별도 테스트.
- **`headway_estimator`의 3단 폴백 (평시→전체→기본)**: 데이터 결손에 강건. 테스트도 폴백 케이스 모두 포함.
- **`lineColorFor`의 base lineId 폴백**: `9E`→`9` 자동 매핑. 새 가상 노선 추가 시 색상 매핑 누락 방지.
- **`_buildSegments`의 dwell 처리 일관성**: 환승 분기/세그먼트 경계 분기/마지막 분기 모두 동일한 `intermediateCount × dwellTimeSeconds` 패턴. 누락 없음.
- **세그먼트별 `expressDurationSeconds` 누적 전략 주석**: "첫 N개 완행 + 뒤 M개 급행" 순서 의존성 버그 방지 의도가 명확히 기록됨.

---

## 체크 항목별 결과

| 항목 | 결과 | 비고 |
|---|---|---|
| 1. Freezed 불변성 + nullable/default 정확 | OK | `@Default([])` + 라운드트립 테스트 |
| 2. JSON 역호환 (빈 파일 OK) | OK | `loadExpressSkipEdges`의 catch + 기본값 |
| 3. GraphBuilder 인자 기본값 | OK | `const []`, `const {}` |
| 4. 노드 ID 충돌 (`{id}_{line}E`) | OK | 모든 stationId가 숫자/B+숫자라 충돌 없음 (확인됨) |
| 5. Dijkstra 알고리즘 미수정 | OK | `shortest_path.dart` 변경 없음 |
| 6. 모드 전환 edge `isTransfer=true` | OK | `_buildSegments`가 세그먼트 경계로 인식 |
| 7. 환승 edge 비대칭 | OK | `addBidirectionalEdge` 대신 양방향 개별 |
| 8. headway 폴백 (평시→전체→180) | OK | 테스트 완비 |
| 9. 레이어 위반 (domain → data) | **WARN** | `SearchRoute`가 `TimetableDataSource` 직접 import. 옵셔널 주입이지만 domain → data 의존 발생 |
| 10. lineColorFor 폴백 정확 | OK | `9E`→`9`, 미정의→grey |
| 11. 기존 expressTimeSeconds 토글 충돌 | OK | 신규 `9E` 세그먼트는 `expressDurationSeconds=null`이라 토글 미관여 |
| 12. 테스트 커버리지 | OK | 급행 자동 선택, 비대칭 환승, 모드 전환, 회귀 모두 |

### 9번 부연: 레이어 위반 검토
`SearchRoute`(domain)가 `TimetableDataSource`(data)를 옵셔널로 import:
```dart
import '../../data/local/timetable_data_source.dart';
```
Clean Architecture 원칙상 domain → data 의존은 위반. 단 옵셔널이고 운영 시에는 provider에서 주입하므로 실용적 타협. **개선안**: `StationRepository`에 `Future<Map<String, LineSchedule>> getLineSchedules()` 추가하여 의존 제거. 시간표는 station 데이터와 별도이지만 같은 도메인 데이터로 묶을 명분은 충분.

```dart
// domain/repositories/station_repository.dart
Future<Map<String, LineSchedule>> getLineSchedules();

// data/repositories/station_repository_impl.dart
final TimetableDataSource _timetableDataSource;

@override
Future<Map<String, LineSchedule>> getLineSchedules() =>
    _timetableDataSource.loadSchedules();

// usecases/search_route.dart — TimetableDataSource import 제거
final headwaySeconds = buildHeadwayMap(await _stationRepository.getLineSchedules());
```

---

## 종합 판정

**판정: 차단 (Block) — 단, HIGH 1건만 수정하면 즉시 해제**

- HIGH 1건 (H1: 비현실적 skip edge): 데이터 추출 단계에서 필터 보강 필요. 그래프에 들어가는 edge가 실제 운행에 부합하지 않으면 잘못된 경로 추천 위험.
- MEDIUM 8건: 머지 전후로 단계적 개선. M2(가이드 무용한 호출), M7(배지 중복), M8(환승 카운트)은 사용자 경험에 영향 → 우선 정리 권장.
- LOW 7건: 후속 PR에서 정리.

**다음 단계**:
1. `extract_express_skip_edges.py`에 trainno 회송 필터 + skipped 역 수 기반 하한 추가
2. JSON 재생성 후 1호선 edge 수가 합리적인 범위(50~200)로 줄어드는지 확인
3. M2, M7, M8 UX 결정 (요구사항 리뷰어와 협의)
4. M1(lineColorFor 일관 적용)은 동일 PR 내 마무리 권장
5. (선택) 9번 레이어 위반은 `getLineSchedules()` 추가로 개선

