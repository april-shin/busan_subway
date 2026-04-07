import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../../core/constants/subway_id_mapping.dart';
import '../../../../core/utils/path_on_line.dart';
import '../../../../domain/entities/arrival_info.dart';
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
  final int? arrivalCode;
  final String positionStatus;
  final double fromSvgX;
  final double fromSvgY;
  final List<({double x, double y})> pathToTarget;
  final List<int> segmentDurations;
  final double initialProgress;

  const LiveTrain({
    required this.trainNo,
    required this.lineId,
    required this.direction,
    required this.destination,
    required this.message,
    required this.arrivalSeconds,
    required this.currentStation,
    this.arrivalCode,
    this.positionStatus = '',
    required this.fromSvgX,
    required this.fromSvgY,
    required this.pathToTarget,
    this.segmentDurations = const [],
    this.initialProgress = 0.0,
  });

  Map<String, dynamic> toJson() => {
        'trainNo': trainNo,
        'lineId': lineId,
        'direction': direction,
        'destination': destination,
        'message': message,
        'arrivalSeconds': arrivalSeconds,
        'currentStation': currentStation,
        'arrivalCode': arrivalCode,
        'positionStatus': positionStatus,
        'fromSvgX': fromSvgX,
        'fromSvgY': fromSvgY,
        'pathToTarget': [
          for (final p in pathToTarget) {'x': p.x, 'y': p.y},
        ],
        'segmentDurations': segmentDurations,
        'initialProgress': initialProgress,
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
  // arrivalInfoProvider를 watch하고 있으므로 invalidate만 하면 자동 재계산됨
  final timer = Timer(const Duration(seconds: 15), () {
    ref.invalidate(arrivalInfoProvider(departureStationName));
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
  final connections = await ref.watch(allConnectionsProvider.future);

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

    // 현재역 → 출발역 경유 좌표 및 세그먼트 소요시간 계산
    final pathResult = findPathOnLine(
      fromStationName: currentName,
      toStationName: departureStationName,
      lineId: lineId,
      stations: stations,
      connections: connections,
    );

    // 경로를 찾을 수 없으면 건너뜀
    if (pathResult == null || pathResult.points.isEmpty) continue;

    // trainNo가 비어있으면 고유 식별 불가 → 건너뜀
    if (arrival.trainNo.isEmpty) continue;

    final initialProgress = calculateInitialProgress(
      arrival.arrivalCode,
      arrival.positionStatus,
    );

    // 도착 예상 초: API 값이 있으면 사용, 없으면 구간 소요시간 합산으로 추정
    final int arrivalSecs;
    if (arrival.arrivalSeconds != null) {
      final elapsed = DateTime.now().difference(arrival.receivedAt).inSeconds;
      arrivalSecs = arrival.arrivalSeconds! - elapsed;
    } else {
      final durations = pathResult.durations;
      if (durations.isEmpty) {
        arrivalSecs = 0;
      } else {
        final firstAdj = (durations.first * (1.0 - initialProgress)).round();
        arrivalSecs = firstAdj + durations.skip(1).fold(0, (a, b) => a + b);
      }
    }

    result.add(LiveTrain(
      trainNo: arrival.trainNo,
      lineId: lineId,
      direction: arrival.direction,
      destination: arrival.destination,
      message: arrival.arrivalMessage,
      arrivalSeconds: arrivalSecs < 0 ? 0 : arrivalSecs,
      currentStation: currentName,
      arrivalCode: arrival.arrivalCode,
      positionStatus: arrival.positionStatus,
      fromSvgX: currentStation.svgX,
      fromSvgY: currentStation.svgY,
      pathToTarget: pathResult.points,
      segmentDurations: pathResult.durations,
      initialProgress: initialProgress,
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
          arrivalCode: t.arrivalCode,
          positionStatus: t.positionStatus,
          fromSvgX: t.fromSvgX,
          fromSvgY: t.fromSvgY + offset,
          pathToTarget: t.pathToTarget,
          segmentDurations: t.segmentDurations,
          initialProgress: t.initialProgress,
        );
      }(),
  ];
}
