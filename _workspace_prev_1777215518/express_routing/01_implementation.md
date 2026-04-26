# 급행 가상 노선 모델링 — 구현 보고

## 작업 요약

9호선 언주→마곡나루 같은 시나리오에서 Dijkstra가 "완행 N역 + 급행 환승" 경로를 자동 탐색하도록 그래프 구조 확장.

핵심 아이디어:
- 급행 정차역에 가상 노드(`{stationId}_{lineId}E`) 추가
- 급행 정차역 사이에 직통 edge(`{lineId}E`) 추가
- 같은 역의 완행↔급행 노드 사이에 모드 전환 edge(`{lineId}M`, `isTransfer=true`, weight=배차/2)
- 환승 edge에 도착 노선의 배차/2 추가 (양방향 비대칭)

Dijkstra 알고리즘 자체는 수정하지 않음. 그래프 빌드 단계에서 새 노드/edge를 추가하는 것만으로 동일 로직이 급행 경로를 자동 선택.

---

## 변경/신규 파일

### 신규
| 경로 | 설명 |
|---|---|
| `tool/extract_express_skip_edges.py` | 급행 정차역 시퀀스 + skip 시간 추출 스크립트 |
| `assets/json/express_skip_edges.json` | 추출된 skip edge 데이터 (1/9/경춘/수인분당) |
| `lib/domain/entities/express_skip_edge.dart` | Freezed 엔티티 |
| `lib/domain/entities/express_skip_edge.freezed.dart` | (생성) |
| `lib/domain/entities/express_skip_edge.g.dart` | (생성) |
| `lib/core/utils/headway_estimator.dart` | LineSchedule → 평균 배차간격(초) 추출 유틸 |
| `test/domain/entities/express_skip_edge_test.dart` | 엔티티 테스트 (6개) |
| `test/core/utils/headway_estimator_test.dart` | 배차 추출 테스트 (7개) |

### 수정
| 경로 | 변경 요약 |
|---|---|
| `lib/data/local/local_data_source.dart` | `loadExpressSkipEdges()` 추가, 캐시 필드, clearCache 갱신 |
| `lib/domain/repositories/station_repository.dart` | `getExpressSkipEdges()` 인터페이스 |
| `lib/data/repositories/station_repository_impl.dart` | 위 메서드 위임 구현 |
| `lib/graph/graph_builder.dart` | `expressSkipEdges`/`headwaySeconds` 인자 추가, 급행 노드/edge/모드 전환/비대칭 환승 빌더 |
| `lib/domain/usecases/search_route.dart` | `TimetableDataSource` 옵셔널 주입, `_loadHeadwayMap()`, GraphBuilder 호출에 새 인자 전달 |
| `lib/features/home/presentation/screens/home_screen.dart` | SearchRoute 생성 시 `timetableDataSource` 전달 |
| `lib/features/subway_map/presentation/widgets/subway_map_viewer.dart` | 동일 |
| `lib/core/constants/line_colors.dart` | `lineNames`에 `1E`/`9E`/`경춘E`/`수인분당E` 추가, `lineColorFor()` 폴백 헬퍼 |
| `lib/features/route_search/presentation/screens/route_result_screen.dart` | `lineColorFor()` 사용, 급행 배지 조건에 `lineId.endsWith('E')` 추가 |
| `test/graph/graph_builder_test.dart` | 급행 노드/edge/모드 전환/비대칭 환승 테스트 8개 추가 |
| `test/graph/shortest_path_test.dart` | 급행 자동 선택 시나리오 1개 추가 |
| `test/domain/usecases/search_route_test.dart` | 9호선 시뮬레이션, 회귀 테스트 4개 추가 + setUp에 `getExpressSkipEdges` stub |

---

## 핵심 설계 결정

### 1. 그래프 노드 ID
- 완행: `{stationId}_{lineId}` (예: `905_9`)
- 급행: `{stationId}_{lineId}E` (예: `905_9E`)
- 모드 전환 edge lineId: `{lineId}M` (예: `9M`) — 환승 처리 분기에서 인식

### 2. 환승 대기 시간 (배차/2)
- `headwaySeconds` 맵이 **비어있으면** 추가하지 않음 (레거시 호환)
- 맵이 있으면 도착 노선 기준으로 비대칭 weight 계산
- 환승 edge는 `addBidirectionalEdge` 대신 양방향 `addEdge` 두 번으로 분리

### 3. 모드 전환 edge
- `isTransfer=true` → `_buildSegments`가 세그먼트 경계로 인식
- weight = `headwaySeconds[baseLineId] / 2 ?? 90` (기본 90초 = 3분/2)
- `transferDurations`에 자동 누적되어 UI 표시 정확

### 4. UI 노선명/색상
- `lineNames`에 `9E: '9호선 급행'` 등 추가
- `lineColorFor()`: 등록된 색상 → `E` 접미사 폴백 → `Color(0xFF9E9E9E)`
- 급행 배지: 기존 (useExpress + expressDurationSeconds) 조건에 OR `lineId.endsWith('E')` 추가

### 5. SearchRoute에 TimetableDataSource 옵셔널 주입
- domain → data 레이어 의존: 기존에도 LocalDataSource를 통한 의존이 있어 패턴 일관
- 옵셔널이라 테스트는 기존처럼 단순 mockRepo로 동작 (headwaySeconds 빈 맵 폴백)
- 실제 앱에서는 Riverpod이 `timetableDataSourceProvider`를 주입

### 6. 데이터 추출 필터
- `tool/extract_express_skip_edges.py`: 인접 역(skipped=0)는 완행 edge가 이미 커버하므로 skip edge에서 제외
- 결과: 1호선 478, 9호선 26, 경춘선 0, 수인분당선 6개

---

## 검증 결과

```
$ python3 tool/extract_express_skip_edges.py
━━━ [1] 급행 정차쌍 651개 ━━━ → 478개 skip edge
━━━ [9] 급행 정차쌍 28개 ━━━ → 26개 skip edge
━━━ [경춘] 급행 정차쌍 43개 ━━━ → 0개 (모든 정차쌍이 인접역)
━━━ [수인분당] 급행 정차쌍 92개 ━━━ → 6개

$ dart run build_runner build --delete-conflicting-outputs
Built with build_runner in 20s; wrote 7 outputs.

$ flutter analyze
67 issues found (전부 기존 warnings, 신규 코드 깨끗)

$ flutter test --exclude-tags integration
00:08 +442: All tests passed!
```

신규 테스트 합계: **22개** (엔티티 6 + headway 7 + 그래프 빌더 7 + shortest_path 1 + search_route 4)

---

## 트레이드오프 / 제한사항

1. **수인분당선 일부 edge 부정확**: BFS가 분기점이 있는 노선에서 우회 경로의 짧은 거리만 추출. 후속 PR에서 노선 토폴로지 검증 추가 권장. (예: `B53 -> B57` skipped 8개 등)

2. **경춘선 급행은 완행 정차역과 동일**: trainno 시퀀스에서 모든 인접 정차쌍이 인접역이라 skip edge 0개. 경춘선 급행은 사실상 완행과 정차역 동일하거나 시간표 데이터에 etrnYn=Y가 부정확할 수 있음.

3. **`SearchRoute` → data 레이어 의존**: `TimetableDataSource`를 직접 import. Clean Architecture 엄격 적용 시 `LineScheduleRepository` 인터페이스를 domain에 도입해야 하지만, 현재 LocalDataSource를 통한 직접 의존이 이미 존재(레퍼지토리 구현체에서)하므로 패턴 일관. 후속 PR에서 도메인 인터페이스 도입 검토.

4. **환승 대기 누적**: 급행 경로에서 모드 전환 2회(완행→급행, 급행→완행) + 일반 환승 1회 시나리오에서 `transferDurations` 항목이 모두 누적. UI에서 급행 환승 단계가 일반 환승처럼 표시될 수 있음. UX 검토 필요.

5. **기존 `expressTimeSeconds` 유지**: 기존 완행/급행 토글 UI를 위해 connection의 `expressTimeSeconds` + `expressWeightSeconds`는 그대로 유지. 새 모델과 공존. plan에 명시된 후속 PR에서 토글 제거 시 함께 정리.

6. **노드 수 증가**: 1호선 급행 정차역이 많아 가상 노드/edge 수 비례 증가. 현재 그래프 크기에서 Dijkstra 성능 영향 미미 예상이나 모니터링 필요.

7. **BFS 재실행 후 데이터 안정화**: `extract_express_skip_edges.py` 출력은 재실행 시 정렬되어 diff 안정. 단, 입력 시간표 캐시(`data/timetables/`)가 변경되면 결과 변동.

---

## 후속 작업 권장

1. UI에서 급행 세그먼트의 모드 전환 표시 개선 (3개 환승처럼 보이지 않도록)
2. 수인분당선 분기점 처리 (BFS → 단방향 인접 그래프 사용 검토)
3. 기존 `expressTimeSeconds`/토글 UI 제거 (별도 PR)
4. domain 레이어에 `LineScheduleRepository` 인터페이스 도입
