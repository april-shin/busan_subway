import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/subway_id_mapping.dart';
import '../../../domain/entities/arrival_info.dart';
import '../../../domain/entities/route_result.dart';

/// 실시간 도착정보를 기반으로 가장 빠른 출발 시각을 계산한다.
///
/// [arrivalAsync]가 성공 데이터를 포함하고 첫 구간의 노선에 해당하는
/// 도착 정보가 있으면, 현재 시각 + 최소 도착 초를 반환한다.
/// 그 외의 경우(로딩, 에러, 매칭 없음) [now]를 그대로 반환한다.
DateTime computeDepartureTime({
  required AsyncValue<List<ArrivalInfo>> arrivalAsync,
  required RouteResult routeResult,
  required DateTime now,
}) {
  return arrivalAsync.when(
    data: (arrivals) {
      if (routeResult.segments.isEmpty) return now;
      final firstSegment = routeResult.segments.first;
      final matching = arrivals.where((a) {
        final lineId = subwayIdToLineId[a.subwayId] ?? a.subwayId;
        return lineId == firstSegment.lineId &&
            a.arrivalSeconds != null &&
            a.arrivalSeconds! > 0;
      }).toList();

      if (matching.isEmpty) return now;

      matching.sort((a, b) => a.arrivalSeconds!.compareTo(b.arrivalSeconds!));
      return now.add(Duration(seconds: matching.first.arrivalSeconds!));
    },
    loading: () => now,
    error: (_, _) => now,
  );
}
