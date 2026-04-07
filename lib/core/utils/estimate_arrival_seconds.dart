import '../../domain/entities/connection.dart';
import '../../domain/entities/station.dart';
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
    if (currentStationName == targetStationName) return 0;

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
      return firstAdj + durations.skip(1).fold(0, (a, b) => a + b);
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
    return firstAdj + avgDuration * (parsed.count - 1);
  }

  return null;
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
