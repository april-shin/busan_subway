import 'dart:collection';

import '../../domain/entities/connection.dart';
import '../../domain/entities/station.dart';

/// findPathOnLine의 반환 타입: 경유 좌표 + 세그먼트별 소요시간
typedef PathWithDurations = ({
  List<({double x, double y})> points,
  List<int> durations,
});

/// 구간 소요시간 데이터가 없을 때 사용하는 기본 소요시간(초)
const defaultSegmentTravelSeconds = 120;

/// 같은 노선 내에서 [fromStationName] → [toStationName] 까지의 경유 역 SVG 좌표 및 세그먼트별 소요시간 반환.
///
/// 경로를 찾을 수 없으면 null을 반환한다.
PathWithDurations? findPathOnLine({
  required String fromStationName,
  required String toStationName,
  required String lineId,
  required List<Station> stations,
  required List<Connection> connections,
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

  // 해당 노선의 비환승 연결로 인접 리스트 + travelTime 맵 구축
  final adjacency = <String, List<String>>{};
  final travelTimeMap = <String, int>{};
  for (final c in connections) {
    if (c.lineId != lineId || c.isTransfer) continue;
    adjacency.putIfAbsent(c.fromStationId, () => []).add(c.toStationId);
    adjacency.putIfAbsent(c.toStationId, () => []).add(c.fromStationId);
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
double calculateInitialProgress(int? arrivalCode, String positionStatus) {
  if (arrivalCode != null && arrivalCode != 99) {
    return switch (arrivalCode) {
      1 => 0.0, // 도착: 역에 정차 중
      2 => 0.15, // 출발: 역을 막 떠남
      0 => 0.85, // 진입: 거의 도착
      3 => 0.15, // 전역출발: 이전역 출발
      4 => 0.85, // 전역진입: 이전역 거의 도착
      5 => 0.0, // 전역도착: 이전역 도착
      _ => 0.0,
    };
  }

  // arvlCd가 null/99일 때 positionStatus 문자열로 폴백
  return switch (positionStatus) {
    '출발' => 0.15,
    '도착' => 0.0,
    '진입' => 0.85,
    _ => 0.0,
  };
}
