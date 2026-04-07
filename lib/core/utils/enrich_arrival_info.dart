import '../../domain/entities/arrival_info.dart';
import '../../domain/entities/connection.dart';
import '../../domain/entities/station.dart';
import '../constants/subway_id_mapping.dart';
import 'estimate_arrival_seconds.dart';

/// ArrivalInfo 리스트에서 arrivalSeconds가 null인 항목에 구간 소요시간 합산으로 추정값을 채운다.
///
/// 추정 성공 시 isEstimated: true로 설정한다.
/// 추정값은 recptnDt 기준이므로 경과 시간을 차감하고 receivedAt을 현재 시각으로 갱신한다.
/// 원본 리스트를 변경하지 않고 새 리스트를 반환한다.
///
/// [previousArrivals]가 주어지면, 동일 열차·동일 역 위치의 이전 추정값을 재사용하여
/// API 재조회 시 카운트다운이 리셋되는 것을 방지한다.
List<ArrivalInfo> enrichArrivalInfoList({
  required List<ArrivalInfo> arrivals,
  required String targetStationName,
  required List<Station> stations,
  required List<Connection> connections,
  List<ArrivalInfo> previousArrivals = const [],
}) {
  // 이전 추정값을 Map으로 인덱싱 (trainNo_subwayId → ArrivalInfo)
  final prevMap = <String, ArrivalInfo>{};
  for (final prev in previousArrivals) {
    if (prev.isEstimated && prev.arrivalSeconds != null) {
      prevMap['${prev.trainNo}_${prev.subwayId}'] = prev;
    }
  }

  return [
    for (final arrival in arrivals)
      if (arrival.arrivalSeconds != null)
        arrival
      else
        _enrichSingle(
          arrival, targetStationName, stations, connections, prevMap,
        ),
  ];
}

ArrivalInfo _enrichSingle(
  ArrivalInfo arrival,
  String targetStationName,
  List<Station> stations,
  List<Connection> connections,
  Map<String, ArrivalInfo> prevMap,
) {
  // 이전 추정값 재사용: 같은 열차, 같은 역 위치면 재추정하지 않음
  final prev = prevMap['${arrival.trainNo}_${arrival.subwayId}'];
  if (prev != null &&
      prev.currentStationName == arrival.currentStationName &&
      prev.positionStatus == arrival.positionStatus) {
    return arrival.copyWith(
      arrivalSeconds: prev.arrivalSeconds,
      isEstimated: true,
      receivedAt: prev.receivedAt,
    );
  }

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
    arrivalMessage: arrival.arrivalMessage,
  );
  if (estimated == null) return arrival;

  // recptnDt 경과 시간 보정: 추정값은 recptnDt 기준 → 현재까지 경과분 차감
  final now = DateTime.now();
  final elapsed = now.difference(arrival.receivedAt).inSeconds;
  final corrected = estimated - elapsed;

  return arrival.copyWith(
    arrivalSeconds: corrected < 0 ? 0 : corrected,
    isEstimated: true,
    receivedAt: now,
  );
}
