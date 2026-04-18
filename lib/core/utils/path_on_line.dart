import 'dart:collection';

import '../../domain/entities/connection.dart';
import '../../domain/entities/station.dart';
import 'line_direction.dart';

/// findPathOnLine의 반환 타입: 경유 좌표 + 세그먼트별 소요시간
typedef PathWithDurations = ({
  List<({double x, double y})> points,
  List<int> durations,
});

/// 구간 소요시간 데이터가 없을 때 사용하는 기본 소요시간(초)
const defaultSegmentTravelSeconds = 120;

/// 같은 노선 내에서 [fromStationName] → [toStationName] 까지의 경유 역 SVG 좌표 및 세그먼트별 소요시간 반환.
///
/// [isDown]을 지정하면 해당 방향(true: 하행/외선, false: 상행/내선)에 부합하는
/// 엣지만 따라 BFS를 수행한다. null이면 양방향 모두 허용 (기존 동작).
/// 2호선 같은 순환선에서 진행 방향과 반대 경로가 뽑히는 것을 방지하기 위함.
///
/// 경로를 찾을 수 없으면 null을 반환한다.
PathWithDurations? findPathOnLine({
  required String fromStationName,
  required String toStationName,
  required String lineId,
  required List<Station> stations,
  required List<Connection> connections,
  bool? isDown,
}) {
  // 해당 노선의 역 ID 매핑 (이름 → ID, ID → Station)
  final nameToIds = <String, List<String>>{};
  final idToStation = <String, Station>{};
  for (final s in stations) {
    if (s.lineId == lineId) {
      nameToIds.putIfAbsent(s.name, () => []).add(s.id);
      idToStation[s.id] = s;
    }
  }

  final fromIds = nameToIds[fromStationName];
  final toIds = nameToIds[toStationName];
  if (fromIds == null || toIds == null) return null;

  // 해당 노선의 비환승 연결로 인접 리스트 + travelTime 맵 구축.
  // isDown이 지정되면 각 연결을 방향에 맞는 단일 엣지로만 등록하여 역방향 탐색을 차단.
  final adjacency = <String, List<String>>{};
  final travelTimeMap = <String, int>{};
  for (final c in connections) {
    if (c.lineId != lineId || c.isTransfer) continue;

    if (isDown == null) {
      // 기존 동작: 양방향 엣지 모두 추가
      adjacency.putIfAbsent(c.fromStationId, () => []).add(c.toStationId);
      adjacency.putIfAbsent(c.toStationId, () => []).add(c.fromStationId);
    } else {
      // 방향 제한: connection의 from→to 방향이 요청 방향과 같으면 from→to만,
      // 반대면 to→from만 추가 (역방향 edge 차단)
      final connectionIsDown =
          isDownBetween(c.fromStationId, c.toStationId, lineId);
      if (connectionIsDown == isDown) {
        adjacency.putIfAbsent(c.fromStationId, () => []).add(c.toStationId);
      } else {
        adjacency.putIfAbsent(c.toStationId, () => []).add(c.fromStationId);
      }
    }

    travelTimeMap['${c.fromStationId}_${c.toStationId}'] =
        c.travelTimeSeconds;
    travelTimeMap['${c.toStationId}_${c.fromStationId}'] =
        c.travelTimeSeconds;
  }

  // BFS: fromId → toId
  for (final fromId in fromIds) {
    for (final toId in toIds) {
      final path = bfs(fromId, toId, adjacency);
      if (path != null) {
        final points = <({double x, double y})>[];
        final durations = <int>[];

        for (var i = 0; i < path.length; i++) {
          if (idToStation[path[i]] case final s?) {
            points.add((x: s.svgX, y: s.svgY));
          }
          if (i > 0) {
            final key = '${path[i - 1]}_${path[i]}';
            durations.add(travelTimeMap[key] ?? defaultSegmentTravelSeconds);
          }
        }

        return (points: points, durations: durations);
      }
    }
  }

  return null;
}

/// BFS로 [fromId] → [toId] 경로를 찾는다.
///
/// 경로를 찾을 수 없으면 null을 반환한다.
List<String>? bfs(
  String fromId,
  String toId,
  Map<String, List<String>> adjacency,
) {
  if (fromId == toId) return [fromId];

  final visited = <String>{fromId};
  final prev = <String, String>{};
  final queue = Queue<String>()..add(fromId);

  while (queue.isNotEmpty) {
    final current = queue.removeFirst();

    for (final neighbor in adjacency[current] ?? <String>[]) {
      if (visited.contains(neighbor)) continue;
      prev[neighbor] = current;
      if (neighbor == toId) {
        final path = <String>[toId];
        var node = toId;
        while (prev.containsKey(node)) {
          node = prev[node]!;
          path.add(node);
        }
        return path.reversed.toList();
      }
      visited.add(neighbor);
      queue.add(neighbor);
    }
  }

  return null;
}

/// arvlCd/positionStatus 기반 첫 세그먼트 내 초기 진행률 (0.0~1.0)
///
/// initialProgress는 "currentStation → next 세그먼트 내 진행률"로 정의된다.
/// "진입"은 열차가 currentStation의 *이전* 세그먼트 끝(= currentStation에 거의 도달한
/// 상태)에 있으므로, 이 함수 구조에서는 이전 세그먼트를 표현할 수 없다.
/// 따라서 진입 상태는 열차 위치를 currentStation 근사로 표시한다
/// (실제로는 이전 세그먼트 끝이지만 initialProgress 구조상 정밀 표현 불가
/// → currentStation 위치로 근사).
double calculateInitialProgress(int? arrivalCode, String positionStatus) {
  if (arrivalCode != null && arrivalCode != 99) {
    return switch (arrivalCode) {
      1 => 0.0, // 도착: 역에 정차 중
      2 => 0.15, // 출발: 역을 막 떠남
      0 => 0.0, // 진입: currentStation 근사 (이전 세그먼트 끝이나 표현 불가)
      3 => 0.15, // 전역출발: 이전역 출발
      4 => 0.0, // 전역진입: currentStation 근사 (이전 세그먼트 끝이나 표현 불가)
      5 => 0.0, // 전역도착: 이전역 도착
      _ => 0.0,
    };
  }

  // arvlCd가 null/99일 때 positionStatus 문자열로 폴백
  return switch (positionStatus) {
    '출발' => 0.15,
    '도착' => 0.0,
    '진입' => 0.0, // currentStation 근사 (arvlCd 0/4와 동일 근거)
    _ => 0.0,
  };
}
