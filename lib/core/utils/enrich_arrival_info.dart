import '../../domain/entities/arrival_info.dart';
import '../../domain/entities/connection.dart';
import '../../domain/entities/station.dart';
import '../constants/subway_id_mapping.dart';
import 'estimate_arrival_seconds.dart';

/// ArrivalInfo 리스트에서 arrivalSeconds가 null인 항목에 구간 소요시간 합산으로 추정값을 채운다.
///
/// 추정 성공 시 isEstimated: true로 설정한다.
/// 원본 리스트를 변경하지 않고 새 리스트를 반환한다.
List<ArrivalInfo> enrichArrivalInfoList({
  required List<ArrivalInfo> arrivals,
  required String targetStationName,
  required List<Station> stations,
  required List<Connection> connections,
}) {
  return [
    for (final arrival in arrivals)
      if (arrival.arrivalSeconds != null)
        arrival
      else
        _enrichSingle(arrival, targetStationName, stations, connections),
  ];
}

ArrivalInfo _enrichSingle(
  ArrivalInfo arrival,
  String targetStationName,
  List<Station> stations,
  List<Connection> connections,
) {
  final lineId = subwayIdToLineId[arrival.subwayId];
  if (lineId == null) return arrival;

  final estimated = estimateArrivalSeconds(
    currentStationName: arrival.currentStationName,
    targetStationName: targetStationName,
    lineId: lineId,
    positionStatus: arrival.positionStatus,
    arrivalCode: arrival.arrivalCode,
    stations: stations,
    connections: connections,
  );
  if (estimated == null) return arrival;

  return arrival.copyWith(
    arrivalSeconds: estimated,
    isEstimated: true,
  );
}
