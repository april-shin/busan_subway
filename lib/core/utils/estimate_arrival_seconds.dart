import 'dart:math' as math;

import '../../domain/entities/connection.dart';
import '../../domain/entities/station.dart';
import '../constants/dwell_time.dart';
import 'parse_arrival_message.dart';
import 'path_on_line.dart';

/// arrivalSeconds가 null일 때 도착 시간(초)을 추정한다.
///
/// 전체 우선순위 체인:
/// 1순위: barvlDt 직접 파싱 → [ArrivalInfoDto._parseArrivalSeconds]
/// 2순위: arvlMsg2 시간 파싱 → [ArrivalInfoDto.toEntity]에서 [parseTimeFromMessage]
/// 3순위: currentStationName + findPathOnLine 경로 기반 추정 (이 함수)
/// 4순위: arvlMsg2 역 수 × 노선 평균 구간 소요시간 (이 함수)
///
/// 반환값 해석 (0 과 null 은 의미가 다르다):
/// - 양수: `recptnDt` 기준 잔여초 → 경과시간을 차감해 카운트다운
/// - 0: "그 역에 있음"을 뜻하는 **상태**. 잔여초 0 이 아니므로 경과시간을 차감하지
///   않는다. 데이터가 오래되면 [ApiConstants.arrivalStateGrace] 기준으로 표시
///   단계에서 걸러진다.
/// - null: **알 수 없음**. 조회역을 이미 떠난 열차이거나 추정 근거가 없는 경우.
///
/// 모든 폴백이 실패하면 null을 반환한다.
int? estimateArrivalSeconds({
  required String currentStationName,
  required String targetStationName,
  required String lineId,
  required String positionStatus,
  required int? arrivalCode,
  required List<Station> stations,
  required List<Connection> connections,
  String arrivalMessage = '',
}) {
  // 3순위: 경로 기반 추정
  if (currentStationName.isNotEmpty) {
    if (currentStationName == targetStationName) {
      return _atTargetStationSeconds(arrivalCode, positionStatus);
    }

    final pathResult = findPathOnLine(
      fromStationName: currentStationName,
      toStationName: targetStationName,
      lineId: lineId,
      stations: stations,
      connections: connections,
    );
    if (pathResult != null && pathResult.durations.isNotEmpty) {
      final progress = calculateInitialProgress(arrivalCode, positionStatus);
      final durations = pathResult.durations;
      final firstAdj = (durations.first * (1.0 - progress)).round();
      final travelTime =
          firstAdj + durations.skip(1).fold<int>(0, (a, b) => a + b);
      final dwellStops = math.max(0, durations.length - 1);
      return travelTime + dwellStops * dwellTimeSeconds;
    }
  }

  // 4순위: arvlMsg2 역 수 × 평균 구간 소요시간
  final parsed = parseStationCount(arrivalMessage);
  if (parsed != null) {
    final avgDuration = _averageSegmentDuration(lineId, connections);
    final progress = calculateInitialProgress(
      arrivalCode,
      parsed.status.isNotEmpty ? parsed.status : positionStatus,
    );
    final firstAdj = (avgDuration * (1.0 - progress)).round();
    final travelTime4 = firstAdj + avgDuration * (parsed.count - 1);
    final dwellStops4 = math.max(0, parsed.count - 1);
    return travelTime4 + dwellStops4 * dwellTimeSeconds;
  }

  return null;
}

/// 열차의 현재역(`arvlMsg3`)이 조회역과 같을 때의 값.
///
/// 종착역·기점역은 API 가 "그 역에 있는 열차"만 보고하므로 이 분기에 거의 모든 행이
/// 들어온다(GTX-A 서울역·수서, 서해선 대곡 등 실측 3/3). 예전에는 무조건 0 을
/// 반환해, **이미 그 역을 출발한 열차까지 "0초(곧 도착)"** 로 보였다.
///
/// - 도착(1)·진입(0)·전역진입(4)·전역도착(5): 아직 역에 있거나 곧 도착 → 0(상태)
/// - 출발(2)·전역출발(3): 조회역을 **이미 떠난 열차** → 이 역의 도착 정보가 아니다
///   → null(알 수 없음)
/// - 코드 없음/99: `positionStatus` 문자열로 폴백. '출발'이면 null, 그 외는 0.
int? _atTargetStationSeconds(int? arrivalCode, String positionStatus) {
  if (arrivalCode != null && arrivalCode != 99) {
    return switch (arrivalCode) {
      2 || 3 => null, // 출발 / 전역출발 — 이미 떠났다
      _ => 0,
    };
  }
  return positionStatus == '출발' ? null : 0;
}

/// 해당 노선의 비환승 연결 평균 구간 소요시간(초)을 반환한다.
///
/// 데이터가 없으면 [defaultSegmentTravelSeconds]를 반환한다.
int _averageSegmentDuration(String lineId, List<Connection> connections) {
  var totalSeconds = 0;
  var count = 0;
  for (final c in connections) {
    if (c.lineId == lineId && !c.isTransfer) {
      totalSeconds += c.travelTimeSeconds;
      count++;
    }
  }
  if (count == 0) return defaultSegmentTravelSeconds;
  return totalSeconds ~/ count;
}
