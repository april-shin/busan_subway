import 'package:freezed_annotation/freezed_annotation.dart';

import 'station.dart';

part 'route_result.freezed.dart';

@freezed
class RouteResult with _$RouteResult {
  const factory RouteResult({
    required List<RouteSegment> segments,
    required int totalTimeSeconds,
    required int transferCount,
    required int stationCount,
    @Default([]) List<int> transferDurations,
  }) = _RouteResult;
}

@freezed
class RouteSegment with _$RouteSegment {
  const factory RouteSegment({
    required String lineId,
    required String lineName,
    required List<Station> stations,
    required int durationSeconds,
    required String direction,
  }) = _RouteSegment;
}
