import 'dart:math' as math;

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
/// `arrivalSeconds` 의 세 상태를 구분해 유지한다:
/// - 양수: 잔여초 (receivedAt 기준 카운트다운)
/// - 0: "그 역에 있음" 상태 — 경과시간 차감 대상이 아니며 receivedAt 을 보존한다
/// - null: **알 수 없음** — 추정 실패, 또는 경과시간이 추정값을 넘겨 무효가 된 경우
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

  // 추정값 0 은 잔여초가 아니라 "그 역에 있음"이라는 **상태**다. 경과시간을 차감하면
  // 곧바로 음수가 되어 아래에서 무효 처리되므로, 기준 시각(recptnDt)을 유지한 채
  // 그대로 통과시킨다. 데이터가 낡았는지는 표시 단계가
  // ApiConstants.arrivalStateGrace 로 판단한다.
  if (estimated == 0) {
    return arrival.copyWith(arrivalSeconds: 0, isEstimated: true);
  }

  // recptnDt 경과 시간 보정: 추정값은 recptnDt 기준 → 현재까지 경과분 차감.
  // 경과에 0 하한을 둔다 — 일부 노선(신분당선 등)은 recptnDt 를 실제보다 수 분
  // 앞선 시각으로 보내며, 음수 경과를 그대로 빼면 추정값이 그만큼 **부풀어** 오른다
  // (예: 정자→판교 203초 추정이 350초로). arrival_card 의 `_liveSeconds` 와 동일 규칙.
  final now = DateTime.now();
  final elapsed = math.max(0, now.difference(arrival.receivedAt).inSeconds);
  final corrected = estimated - elapsed;

  // 경과시간이 추정값을 넘었다면 이 데이터로는 잔여시간을 알 수 없다.
  // 예전에는 0 으로 클램프해 "곧 도착"으로 보였다 — GTX-A 는 recptnDt 지연이
  // 최대 817초라 구간 소요시간(300초)보다 커서 이 경로로 0초가 대량 생성됐다.
  // 모르는 값은 0 이 아니라 **알 수 없음**(arrivalSeconds: null)으로 남긴다.
  if (corrected <= 0) return arrival;

  return arrival.copyWith(
    arrivalSeconds: corrected,
    isEstimated: true,
    receivedAt: now,
  );
}
