import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/subway_id_mapping.dart';
import '../../../domain/entities/arrival_info.dart';
import '../../../domain/entities/line_schedule.dart';
import '../../../domain/entities/route_result.dart';
import '../../../domain/usecases/find_next_departure.dart';
import 'direction_resolver.dart';

/// 시간표 기반 + 실시간 보정 방식으로 출발 시각을 계산한다.
///
/// 1순위: 실시간 도착정보가 있으면 이를 사용 (가장 정확, 방향 필터 적용)
/// 2순위: 시간표(배차간격)에서 다음 출발 시각을 추정 (방향별)
/// 3순위: 둘 다 없으면 현재 시각을 반환
DateTime computeDepartureTime({
  required AsyncValue<List<ArrivalInfo>> arrivalAsync,
  required RouteResult routeResult,
  required DateTime now,
  LineSchedule? lineSchedule,
}) {
  if (routeResult.segments.isEmpty) return now;

  final firstSegment = routeResult.segments.first;
  final isDown = isDownDirection(firstSegment);

  // 1순위: 실시간 도착정보로 보정 (방향 필터 적용)
  final realtimeDeparture = _getRealtimeDeparture(
    arrivalAsync: arrivalAsync,
    lineId: firstSegment.lineId,
    isDown: isDown,
    now: now,
  );
  if (realtimeDeparture != null) return realtimeDeparture;

  // 2순위: 시간표 기반 추정 (방향별)
  if (lineSchedule != null) {
    final timetableDeparture = findNextDeparture(
      schedule: lineSchedule,
      now: now,
      isDown: isDown,
    );
    if (timetableDeparture != null) return timetableDeparture;
  }

  // 3순위: 현재 시각 반환 (운행 시간 외이거나 데이터 없음)
  return now;
}

/// 경로 내 각 구간의 출발시각을 계산한다 (환승역 포함).
///
/// 출발역의 출발시각을 기준으로, 각 구간의 소요시간과 환승시간을
/// 순서대로 누적하여 구간별 출발시각 리스트를 반환한다.
///
/// 환승역에서의 출발시각 결정 우선순위:
/// 1순위: [transferArrivals]에서 해당 역의 실시간 데이터 (afterTransfer 이후 열차만)
/// 2순위: 시간표 기반 다음 출발
/// 3순위: afterTransfer 그대로 사용
List<DateTime> computeSegmentDepartures({
  required RouteResult routeResult,
  required DateTime initialDeparture,
  required Map<String, LineSchedule> schedules,
  Map<String, AsyncValue<List<ArrivalInfo>>> transferArrivals = const {},
  required DateTime now,
}) {
  final departures = <DateTime>[initialDeparture];
  var currentTime = initialDeparture;

  for (var i = 0; i < routeResult.segments.length; i++) {
    final segment = routeResult.segments[i];
    // 구간 종료 시각
    final segmentEnd =
        currentTime.add(Duration(seconds: segment.durationSeconds));

    if (i < routeResult.segments.length - 1) {
      // 환승 시간 추가
      final transferSeconds = i < routeResult.transferDurations.length
          ? routeResult.transferDurations[i]
          : 0;
      final afterTransfer =
          segmentEnd.add(Duration(seconds: transferSeconds));

      // 다음 구간 정보
      final nextSegment = routeResult.segments[i + 1];
      final nextIsDown = isDownDirection(nextSegment);
      final transferStationName = nextSegment.stations.first.name;

      // 1순위: 환승역 실시간 도착정보 (afterTransfer 이후 열차만 유효)
      final arrivalAsync = transferArrivals[transferStationName];
      DateTime? nextDeparture;
      if (arrivalAsync != null) {
        final minSeconds = afterTransfer.difference(now).inSeconds;
        nextDeparture = _getRealtimeDeparture(
          arrivalAsync: arrivalAsync,
          lineId: nextSegment.lineId,
          isDown: nextIsDown,
          now: now,
          minArrivalSeconds: minSeconds,
        );
      }

      // 2순위: 시간표 기반 다음 출발
      if (nextDeparture == null) {
        final nextSchedule = schedules[nextSegment.lineId];
        if (nextSchedule != null) {
          nextDeparture = findNextDeparture(
            schedule: nextSchedule,
            now: afterTransfer,
            isDown: nextIsDown,
          );
        }
      }

      // 3순위: afterTransfer 그대로 사용
      nextDeparture ??= afterTransfer;

      departures.add(nextDeparture);
      currentTime = nextDeparture;
    }
  }

  return departures;
}

/// 실시간 도착정보에서 해당 노선 + 방향의 가장 빠른 도착 열차를 찾는다.
///
/// [minArrivalSeconds]를 지정하면 해당 초 이상인 열차만 대상으로 한다.
/// 환승역에서는 사용자가 환승역에 도달하는 시점 이후의 열차만 유효하므로
/// `afterTransfer.difference(now).inSeconds`를 전달한다.
DateTime? _getRealtimeDeparture({
  required AsyncValue<List<ArrivalInfo>> arrivalAsync,
  required String lineId,
  required bool isDown,
  required DateTime now,
  int minArrivalSeconds = 0,
}) {
  return arrivalAsync.whenOrNull(
    data: (arrivals) {
      final matching = arrivals.where((a) {
        final mappedLineId = subwayIdToLineId[a.subwayId] ?? a.subwayId;
        return mappedLineId == lineId &&
            isDownDirectionString(a.direction) == isDown &&
            a.arrivalSeconds != null &&
            a.arrivalSeconds! > minArrivalSeconds;
      }).toList();

      if (matching.isEmpty) return null;

      matching
          .sort((a, b) => a.arrivalSeconds!.compareTo(b.arrivalSeconds!));
      return now.add(Duration(seconds: matching.first.arrivalSeconds!));
    },
  );
}
