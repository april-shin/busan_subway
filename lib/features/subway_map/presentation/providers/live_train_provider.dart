import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../../core/constants/subway_id_mapping.dart';
import '../../../../domain/entities/arrival_info.dart';
import '../../../../domain/entities/connection.dart';
import '../../../../domain/entities/station.dart';
import '../../../arrival_info/presentation/providers/arrival_providers.dart';
import '../../../route_search/utils/direction_resolver.dart';
import '../providers/subway_map_providers.dart';

part 'live_train_provider.g.dart';

/// JS로 전달할 개별 열차 데이터
class LiveTrain {
  final String trainNo;
  final String lineId;
  final String direction;
  final String destination;
  final String message;
  final int arrivalSeconds;
  final String currentStation;
  final double fromSvgX;
  final double fromSvgY;
  final List<({double x, double y})> pathToTarget;

  const LiveTrain({
    required this.trainNo,
    required this.lineId,
    required this.direction,
    required this.destination,
    required this.message,
    required this.arrivalSeconds,
    required this.currentStation,
    required this.fromSvgX,
    required this.fromSvgY,
    required this.pathToTarget,
  });

  Map<String, dynamic> toJson() => {
        'trainNo': trainNo,
        'lineId': lineId,
        'direction': direction,
        'destination': destination,
        'message': message,
        'arrivalSeconds': arrivalSeconds,
        'currentStation': currentStation,
        'fromSvgX': fromSvgX,
        'fromSvgY': fromSvgY,
        'pathToTarget': [
          for (final p in pathToTarget) {'x': p.x, 'y': p.y},
        ],
      };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LiveTrain &&
          trainNo == other.trainNo &&
          lineId == other.lineId &&
          arrivalSeconds == other.arrivalSeconds &&
          currentStation == other.currentStation;

  @override
  int get hashCode =>
      Object.hash(trainNo, lineId, arrivalSeconds, currentStation);
}

/// 같은 노선 내에서 [fromStationName] → [toStationName] 까지의 경유 역 SVG 좌표 리스트 반환.
///
/// 경로를 찾을 수 없으면 빈 리스트를 반환한다.
List<({double x, double y})> findPathOnLine({
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
  if (fromIds == null || toIds == null) return [];

  // 해당 노선의 비환승 연결로 인접 리스트 구축
  final adjacency = <String, List<String>>{};
  for (final c in connections) {
    if (c.lineId != lineId || c.isTransfer) continue;
    adjacency.putIfAbsent(c.fromStationId, () => []).add(c.toStationId);
    adjacency.putIfAbsent(c.toStationId, () => []).add(c.fromStationId);
  }

  // BFS: fromId → toId
  for (final fromId in fromIds) {
    for (final toId in toIds) {
      final path = _bfs(fromId, toId, adjacency);
      if (path != null) {
        return [
          for (final id in path)
            if (idToStation[id] case final s?)
              (x: s.svgX, y: s.svgY),
        ];
      }
    }
  }

  return [];
}

List<String>? _bfs(
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

/// 네트워크 오류 시 마지막 성공 데이터를 유지하기 위한 캐시
final _lastSuccessfulTrainsProvider =
    StateProvider<List<LiveTrain>>((ref) => []);

/// 실시간 열차 데이터를 가공하여 반환하는 프로바이더.
///
/// 출발역이 선택되어 있을 때만 활성화되며, 15초 타이머로 자동 새로고침한다.
@riverpod
Future<List<LiveTrain>> liveTrains(Ref ref) async {
  final selected = ref.watch(selectedStationsProvider);
  if (!selected.isComplete) return [];

  // 활성 경로 필터 (노선 + 방향)
  final routeFilter = ref.watch(activeRouteFilterProvider);
  if (routeFilter == null) return [];

  final departureStation = selected.departure!;
  final departureStationName = departureStation.name;

  // 15초마다 자동 새로고침
  final timer = Timer(const Duration(seconds: 15), () {
    ref.invalidateSelf();
  });
  ref.onDispose(timer.cancel);

  // 도착 정보 API 호출
  final List<ArrivalInfo> arrivals;
  try {
    arrivals =
        await ref.watch(arrivalInfoProvider(departureStationName).future);
  } catch (e, st) {
    if (kDebugMode) {
      debugPrint('실시간 열차 데이터 로드 실패: $e\n$st');
    }
    // 네트워크 오류 시 마지막 성공 데이터 반환 (기존 애니메이션 유지)
    return ref.read(_lastSuccessfulTrainsProvider);
  }

  // stations와 connections 로드
  final stations = await ref.watch(allStationsProvider.future);
  final repo = ref.watch(stationRepositoryProvider);
  final connections = await repo.getAllConnections();

  // 역명 → Station 매핑 (SVG 좌표 조회용)
  final stationsByName = <String, List<Station>>{};
  for (final s in stations) {
    stationsByName.putIfAbsent(s.name, () => []).add(s);
  }

  final result = <LiveTrain>[];

  for (final arrival in arrivals) {
    // subwayId → lineId 변환
    final lineId = subwayIdToLineId[arrival.subwayId];
    if (lineId == null) continue;

    // 활성 경로의 노선만 필터링
    if (lineId != routeFilter.lineId) continue;

    // 방향 필터링: 활성 경로 방향과 일치하는 열차만
    final trainIsDown = isDownDirectionString(arrival.direction);
    if (trainIsDown != routeFilter.isDown) continue;

    // 현재 위치 역명이 없으면 건너뜀
    final currentName = arrival.currentStationName;
    if (currentName.isEmpty) continue;

    // 현재역의 SVG 좌표 조회 (같은 노선의 역 우선)
    final candidates = stationsByName[currentName];
    if (candidates == null || candidates.isEmpty) continue;

    final currentStation = candidates.firstWhere(
      (s) => s.lineId == lineId,
      orElse: () => candidates.first,
    );

    // 도착 예상 초
    final arrivalSecs = arrival.arrivalSeconds ?? 0;

    // 현재역 → 출발역 경유 좌표 계산
    final path = findPathOnLine(
      fromStationName: currentName,
      toStationName: departureStationName,
      lineId: lineId,
      stations: stations,
      connections: connections,
    );

    // 경로를 찾을 수 없으면 건너뜀
    if (path.isEmpty) continue;

    // trainNo가 비어있으면 고유 식별 불가 → 건너뜀
    if (arrival.trainNo.isEmpty) continue;

    result.add(LiveTrain(
      trainNo: arrival.trainNo,
      lineId: lineId,
      direction: arrival.direction,
      destination: arrival.destination,
      message: arrival.arrivalMessage,
      arrivalSeconds: arrivalSecs < 0 ? 0 : arrivalSecs,
      currentStation: currentName,
      fromSvgX: currentStation.svgX,
      fromSvgY: currentStation.svgY,
      pathToTarget: path,
    ));
  }

  // 같은 역에 여러 열차가 있는 경우 Y축 오프셋 적용
  final adjusted = _applyOverlapOffset(result);

  // 성공 시 캐시 업데이트
  ref.read(_lastSuccessfulTrainsProvider.notifier).state = adjusted;

  return adjusted;
}

/// 같은 현재역에 위치한 열차들에 Y축 오프셋을 적용하여 겹침을 방지한다.
List<LiveTrain> _applyOverlapOffset(List<LiveTrain> trains) {
  // 현재역별 열차 수 카운팅
  final countByStation = <String, int>{};
  for (final t in trains) {
    countByStation[t.currentStation] =
        (countByStation[t.currentStation] ?? 0) + 1;
  }

  final indexByStation = <String, int>{};
  return [
    for (final t in trains)
      () {
        final count = countByStation[t.currentStation] ?? 1;
        if (count <= 1) return t;

        final index = indexByStation[t.currentStation] ?? 0;
        indexByStation[t.currentStation] = index + 1;

        final offset = (index - (count - 1) / 2) * 12.0;
        return LiveTrain(
          trainNo: t.trainNo,
          lineId: t.lineId,
          direction: t.direction,
          destination: t.destination,
          message: t.message,
          arrivalSeconds: t.arrivalSeconds,
          currentStation: t.currentStation,
          fromSvgX: t.fromSvgX,
          fromSvgY: t.fromSvgY + offset,
          pathToTarget: t.pathToTarget,
        );
      }(),
  ];
}
