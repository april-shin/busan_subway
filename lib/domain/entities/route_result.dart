import 'package:freezed_annotation/freezed_annotation.dart';

import 'station.dart';
import 'transfer_guide.dart';

part 'route_result.freezed.dart';

@freezed
abstract class RouteResult with _$RouteResult {
  const factory RouteResult({
    required List<RouteSegment> segments,
    required int totalTimeSeconds,
    required int transferCount,
    required int stationCount,
    @Default([]) List<int> transferDurations,
    // 환승별 "도보시간"(초)만 담는 리스트. 결과 화면의 "환승 N분" 라벨 전용이며,
    // 라우팅 비용/총소요시간/출발시각 계산에는 사용되지 않는다(그쪽은 대기 포함
    // transferDurations 사용). transferDurations와 항상 같은 길이(= transferCount).
    @Default(<int>[]) List<int> transferWalkDurations,
    @Default([]) List<TransferGuide?> transferGuides,
  }) = _RouteResult;
}

@freezed
abstract class RouteSegment with _$RouteSegment {
  const factory RouteSegment({
    required String lineId,
    required String lineName,
    required List<Station> stations,
    required int durationSeconds,
    required String direction,
  }) = _RouteSegment;
}
