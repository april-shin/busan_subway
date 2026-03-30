import '../../domain/entities/connection.dart';
import '../../domain/entities/station.dart';
import 'path_on_line.dart';

/// arrivalSeconds가 null일 때 구간 소요시간 합산으로 도착 시간(초)을 추정한다.
///
/// 경로를 찾을 수 없거나 currentStationName이 비어있으면 null을 반환한다.
int? estimateArrivalSeconds({
  required String currentStationName,
  required String targetStationName,
  required String lineId,
  required String positionStatus,
  required int? arrivalCode,
  required List<Station> stations,
  required List<Connection> connections,
}) {
  if (currentStationName.isEmpty) return null;
  if (currentStationName == targetStationName) return 0;

  final pathResult = findPathOnLine(
    fromStationName: currentStationName,
    toStationName: targetStationName,
    lineId: lineId,
    stations: stations,
    connections: connections,
  );
  if (pathResult == null || pathResult.durations.isEmpty) return null;

  final progress = calculateInitialProgress(arrivalCode, positionStatus);
  final durations = pathResult.durations;
  final firstAdj = (durations.first * (1.0 - progress)).round();
  return firstAdj + durations.skip(1).fold(0, (a, b) => a + b);
}
