---
name: graph-pathfinding
description: "부산 지하철 앱의 최단경로 알고리즘, 그래프 자료구조, 환승 최적화, 방향 결정 로직을 수행. Dijkstra 알고리즘 수정, BFS 경로탐색, 환승 페널티 튜닝, 노선별 방향 로직, 그래프 구조 변경, 경로 계산 최적화 요청 시 이 스킬을 사용. graph/ 디렉토리, search_route.dart, direction_resolver.dart, path_on_line.dart 관련 작업에 모두 적용."
---

# Graph Pathfinding

부산 지하철 앱의 최단경로 및 그래프 알고리즘 가이드.

## 그래프 구조

### 노드
- ID 형식: `"{stationId}_{lineId}"` (예: `"216_2"` = 2호선 강남역)
- 속성: id, stationName, lineId

### 엣지
- 양방향 (A→B + B→A)
- 가중치: 소요시간(초) — 일반 구간 90~300초
- 환승 엣지: `isTransfer = true`, 환승시간 별도

### 환승 시간
- 키 형식: `"{역이름}_{lineId1}_{lineId2}"` (예: `"도봉산_1_7": 90`)
- 역방향 키도 검색: `"{역이름}_{lineId2}_{lineId1}"`
- 기본값: 180초 (키 미존재 시)

## Dijkstra 알고리즘

### 최단시간 경로
```dart
findShortestPath(fromNodeId, toNodeId, transferPenalty: 0)
// O((V+E)logV), 우선순위 큐 기반
```

### 최소환승 경로
```dart
findMinTransferPathBetweenStations(fromId, toId)
// transferPenalty = 100,000초 (환승을 극도로 기피)
```

### 전체 역 변형 탐색
```dart
findShortestPathBetweenStations(fromStationId, toStationId)
// 출발역의 모든 노선 변형 × 도착역의 모든 노선 변형을 탐색하여 최적 경로 반환
```

## BFS 단일노선 경로

```dart
findPathOnLine(allStations, allConnections, currentStationName, targetStationName, lineId)
// 반환: (svgCoords, segmentDurations)
// 같은 노선 내 역 순서 + SVG 좌표 + 구간별 소요시간
```

용도: 열차 애니메이션 경로 계산 (현재역 → 출발역, 같은 노선 내)

## 방향 결정

### 일반 노선
```dart
bool isDownDirection(RouteSegment segment) {
  // stationId 숫자 추출 → 증가하면 하행
  return endId > startId;
}
```

### 2호선 (순환선)
```dart
// 내선(201→243 증가) vs 외선(243→201 감소)
// 래핑 경계: |step| > 21이면 반대 방향
if (step.abs() > 21) isDown = !isDown;
```

### 4호선 (진접선 분기)
```dart
// 449~452: 진접선 구간, 방향 반전
if (stationIds의 진접선 구간 포함) isDown = !isDown;
```

### 문자열 방향
```dart
bool isDownDirectionString(String direction) {
  return direction.contains('하행') || direction.contains('외선');
}
```

## RouteResult 구조

```dart
RouteResult(
  segments: [RouteSegment(lineId, lineName, stations, durationSeconds, direction)],
  totalTimeSeconds: int,
  transferCount: int,
  stationCount: int,
  transferDurations: [int],  // 각 환승 소요시간
)
```

## 핵심 파일

| 파일 | 역할 | 줄 수 |
|------|------|------|
| `lib/graph/shortest_path.dart` | Dijkstra 구현 | 180 |
| `lib/graph/graph_builder.dart` | 그래프 생성 | - |
| `lib/graph/subway_graph.dart` | 인접 리스트 | - |
| `lib/domain/usecases/search_route.dart` | 경로 빌드 | 231 |
| `lib/core/utils/path_on_line.dart` | BFS 경로 | 137 |
| `lib/features/route_search/utils/direction_resolver.dart` | 방향 결정 | 95 |

## 테스트 포인트

- 직통 경로 (환승 없음)
- 1회 환승 경로
- 다중 환승 경로
- 2호선 순환선 방향 결정
- 4호선 진접선 분기
- 출발역 = 도착역
- 연결 불가 역 (에러 처리)
- 환승 시간 키 역방향 검색
