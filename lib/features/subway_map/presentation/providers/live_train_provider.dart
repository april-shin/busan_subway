import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../../core/constants/api_constants.dart';
import '../../../../core/constants/dwell_time.dart';
import '../../../../core/constants/subway_id_mapping.dart';
import '../../../../core/utils/enrich_arrival_info.dart';
import '../../../../core/utils/expand_path_backward.dart';
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

  /// 세그먼트별 "주행시간만" (초). 중간역 정차시간(dwell)은 포함하지 않는다.
  /// JS 측은 매 frame 남은시간 역산 시 이 값과 [dwellSeconds]를 분리 사용한다.
  final List<int> segmentDurations;

  /// 중간역 정차시간 상수(초). 현재는 항상 0으로 전달한다 — 정차 시각화는
  /// JS 의 "segmentIndex > 0 ⇒ 첫 세그먼트 95% 고정" 클램프가 대신 표현한다.
  /// 필드 자체는 JS 계약(`estimateTrainPosition`)과의 호환을 위해 유지.
  final int dwellSeconds;

  /// [arrivalSeconds] 가 측정된 기준 시각(epoch ms).
  /// JS 측은 이 시각과 현재 시각의 차이로 실제 남은시간을 계산한다.
  final int receivedAtEpochMs;

  /// 호환성용 필드. 신규 JS 로직은 읽지 않음. 항상 0.0 권장.
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
    required this.dwellSeconds,
    required this.receivedAtEpochMs,
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
        'dwellSeconds': dwellSeconds,
        'receivedAtEpochMs': receivedAtEpochMs,
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

/// 추정값 캐시 엔트리: 초단위 도착시간 없는 열차의 최초 추정값과 시점을 보존
class _EstimateEntry {
  final int estimate;
  final DateTime estimatedAt;
  final String currentStation;
  final String positionStatus;

  const _EstimateEntry({
    required this.estimate,
    required this.estimatedAt,
    required this.currentStation,
    required this.positionStatus,
  });
}

/// 추정값 캐시: 역 정보 변경 시에만 재추정하여 카운트다운 리셋 방지
final _estimateCacheProvider =
    StateProvider<Map<String, _EstimateEntry>>((ref) => {});

/// 네트워크 오류 시 마지막 성공 데이터를 유지하기 위한 캐시
final _lastSuccessfulTrainsProvider =
    StateProvider<List<LiveTrain>>((ref) => []);

/// enrichment 추정값 캐시: 동일 열차·동일 위치에서 추정값 재사용으로 카운트다운 안정화
final _lastEnrichedArrivalsProvider =
    StateProvider<List<ArrivalInfo>>((ref) => []);

/// 실시간 열차 데이터를 가공하여 반환하는 프로바이더.
///
/// 출발역이 선택되어 있을 때만 활성화되며, `ApiConstants.refreshInterval`
/// 타이머로 자동 새로고침한다.
@riverpod
Future<List<LiveTrain>> liveTrains(Ref ref) async {
  final selected = ref.watch(selectedStationsProvider);
  if (!selected.isComplete) return [];

  // 활성 경로 필터 (노선 + 방향)
  final routeFilter = ref.watch(activeRouteFilterProvider);
  if (routeFilter == null) return [];

  final departureStation = selected.departure!;
  final departureStationName = departureStation.name;

  // `ApiConstants.refreshInterval` 주기로 자동 새로고침.
  // arrivalInfoProvider 를 watch 하고 있으므로 invalidate 만 하면 자동 재계산됨.
  final timer = Timer(ApiConstants.refreshInterval, () {
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

  // 8호선 등 barvlDt를 제공하지 않는 노선 대응: arrivalSeconds가 null이면
  // 경로/역 수 기반으로 추정값을 채워 넣는다.
  // previousArrivals를 전달하여 동일 열차·동일 위치에서 추정값을 재사용,
  // 15초마다 카운트다운이 리셋되는 현상을 방지한다.
  final enrichedArrivals = enrichArrivalInfoList(
    arrivals: arrivals,
    targetStationName: departureStationName,
    stations: stations,
    connections: connections,
    previousArrivals: ref.read(_lastEnrichedArrivalsProvider),
  );
  ref.read(_lastEnrichedArrivalsProvider.notifier).state = enrichedArrivals;

  // 역명 → Station 매핑 (SVG 좌표 조회용)
  final stationsByName = <String, List<Station>>{};
  for (final s in stations) {
    stationsByName.putIfAbsent(s.name, () => []).add(s);
  }

  // ID → Station 매핑 (경로 확장 시 이전 역 Station 조회용).
  final stationsById = <String, List<Station>>{};
  for (final s in stations) {
    stationsById.putIfAbsent(s.id, () => []).add(s);
  }

  final estimateCache = Map<String, _EstimateEntry>.from(
    ref.read(_estimateCacheProvider),
  );

  final result = <LiveTrain>[];

  for (final arrival in enrichedArrivals) {
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

    // 현재역의 SVG 좌표 조회 (같은 노선의 역 우선). 경로 확장 시작점으로 필요.
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
      isDown: routeFilter.isDown,
    );

    // 경로를 찾을 수 없으면 건너뜀
    if (pathResult == null || pathResult.points.isEmpty) continue;

    // trainNo가 비어있으면 고유 식별 불가 → 건너뜀
    if (arrival.trainNo.isEmpty) continue;

    final initialProgress = calculateInitialProgress(
      arrival.arrivalCode,
      arrival.positionStatus,
    );

    // 도착 예상 초: API 값이 있으면 사용, 없으면 구간 소요시간 합산으로 추정.
    // `arrivalSecs` 값 자체는 API/enrich 와 같은 척도(정차시간 포함)를 유지한다.
    // 화면 애니메이션의 시간축에서만 dwell 을 제외하는 것은 segmentDurations/
    // dwellSeconds=0 / 95% 클램프 조합으로 수행한다.
    final cacheKey = '${arrival.trainNo}_$lineId';
    final int arrivalSecs;
    if (arrival.arrivalSeconds != null) {
      // API 제공값 → 캐시 불필요
      estimateCache.remove(cacheKey);
      final elapsed = DateTime.now().difference(arrival.receivedAt).inSeconds;
      arrivalSecs = arrival.arrivalSeconds! - elapsed;
    } else {
      final cached = estimateCache[cacheKey];
      if (cached != null &&
          cached.currentStation == currentName &&
          cached.positionStatus == arrival.positionStatus) {
        // 역 정보 동일 → 최초 추정값에서 경과시간만 차감
        final elapsed =
            DateTime.now().difference(cached.estimatedAt).inSeconds;
        arrivalSecs = cached.estimate - elapsed;
      } else {
        // 새 열차 또는 역 변경 → 새로 추정.
        // durations 는 주행시간만. 중간역(durations.length - 1 개)마다
        // dwellTimeSeconds 를 더해 enrich/API 값과 같은 척도를 유지한다.
        final durations = pathResult.durations;
        if (durations.isEmpty) {
          arrivalSecs = 0;
        } else {
          final firstAdj =
              (durations.first * (1.0 - initialProgress)).round();
          final travelSecs =
              firstAdj + durations.skip(1).fold<int>(0, (a, b) => a + b);
          final dwellStops = math.max(0, durations.length - 1);
          arrivalSecs = travelSecs + dwellStops * dwellTimeSeconds;
        }
        estimateCache[cacheKey] = _EstimateEntry(
          estimate: arrivalSecs,
          estimatedAt: DateTime.now(),
          currentStation: currentName,
          positionStatus: arrival.positionStatus,
        );
      }
    }

    // 남은시간이 현재 pathToTarget 총시간보다 크면 이전 역을 prepend 해 경로 확장.
    // (순환선 방어 + 30칸 상한은 expandPathBackward 내부에서 처리)
    final expanded = expandPathBackward(
      basePoints: pathResult.points,
      baseDurations: pathResult.durations,
      currentStationId: currentStation.id,
      lineId: lineId,
      isDown: routeFilter.isDown,
      connections: connections,
      stationsById: stationsById,
      targetRemainingSeconds: arrivalSecs < 0 ? 0 : arrivalSecs,
    );

    final safeArrivalSecs = arrivalSecs < 0 ? 0 : arrivalSecs;

    result.add(LiveTrain(
      trainNo: arrival.trainNo,
      lineId: lineId,
      direction: arrival.direction,
      destination: arrival.destination,
      message: arrival.arrivalMessage,
      arrivalSeconds: safeArrivalSecs,
      currentStation: currentName,
      arrivalCode: arrival.arrivalCode,
      positionStatus: arrival.positionStatus,
      fromSvgX: expanded.points.first.x,
      fromSvgY: expanded.points.first.y,
      pathToTarget: expanded.points,
      // 주행시간만. 중간역 정차시간은 알고리즘에서 제외하고 95% 클램프로 시각화한다.
      segmentDurations: expanded.durations,
      dwellSeconds: 0,
      // arrivalSecs 는 위에서 receivedAt 기준 경과시간을 차감한 "지금" 기준 값이다.
      // JS 측이 `realRemaining = arrivalSeconds - (Date.now() - receivedAtEpochMs)/1000`
      // 로 추가 경과를 빼므로, 기준 시각을 과거 receivedAt 으로 넘기면 경과가
      // 이중 차감되어 열차가 앞쪽 세그먼트로 넘어가 버린다. 따라서 "Dart 가 값을
      // 확정한 순간"인 지금 시각을 기준으로 전달한다.
      receivedAtEpochMs: DateTime.now().millisecondsSinceEpoch,
      initialProgress: initialProgress,
    ));
  }

  // 사라진 열차의 캐시 제거
  final activeKeys = result.map((t) => '${t.trainNo}_${t.lineId}').toSet();
  estimateCache.removeWhere((k, _) => !activeKeys.contains(k));
  ref.read(_estimateCacheProvider.notifier).state = estimateCache;

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
          dwellSeconds: t.dwellSeconds,
          receivedAtEpochMs: t.receivedAtEpochMs,
          initialProgress: t.initialProgress,
        );
      }(),
  ];
}
