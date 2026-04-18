import 'package:freezed_annotation/freezed_annotation.dart';

import 'station.dart';
import 'transfer_guide.dart';

part 'route_result.freezed.dart';

@freezed
class RouteResult with _$RouteResult {
  const factory RouteResult({
    required List<RouteSegment> segments,
    required int totalTimeSeconds,
    required int transferCount,
    required int stationCount,
    @Default([]) List<int> transferDurations,
    @Default([]) List<TransferGuide?> transferGuides,
    // 전 경로를 급행으로 환산한 총 소요시간(초). 모든 세그먼트가 급행 미운영이면 null.
    int? totalExpressTimeSeconds,
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
    // 이 세그먼트를 급행으로 이용할 때의 총 소요시간(초). 세그먼트 내 급행 운영 구간이
    // 하나라도 있을 때만 채워진다. 급행 미운영 구간은 완행 시간으로 합산된다.
    int? expressDurationSeconds,
  }) = _RouteSegment;
}
