import '../entities/arrival_info.dart';
import '../entities/connection.dart';
import '../entities/station.dart';

abstract class ArrivalRepository {
  Future<List<ArrivalInfo>> getArrivalInfo(String stationName);

  /// 노선별 실시간 열차 위치를 [targetStationName] 기준 도착정보 형태로 반환한다.
  ///
  /// 도착정보 API 가 해당 (역, 노선) 을 제공하지 않을 때의 폴백이다(계기였던 5호선
  /// 천호는 2026-08-04 부터 정상 제공 — 지금은 이 경로를 타지 않는다).
  /// 잔여초는 API 가 주지 않으므로 **추정값**이며 `isEstimated: true` 로 표시된다.
  /// 조회 불가 노선이거나 대상역을 향하는 열차가 없으면 빈 목록.
  Future<List<ArrivalInfo>> getTrainPositionArrivals({
    required String lineId,
    required String targetStationName,
    required List<Station> stations,
    required List<Connection> connections,
  });
}
