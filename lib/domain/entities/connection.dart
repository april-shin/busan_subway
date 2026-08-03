import 'package:freezed_annotation/freezed_annotation.dart';

part 'connection.freezed.dart';
part 'connection.g.dart';

@freezed
abstract class Connection with _$Connection {
  const factory Connection({
    required String fromStationId,
    required String toStationId,
    required String lineId,
    required int travelTimeSeconds,
    @Default(false) bool isTransfer,
    @Default(0) int transferTimeSeconds,

    /// 단선 일방통행 구간 — 열차가 `fromStationId → toStationId` 방향으로만
    /// 운행한다. 경로 그래프(`GraphBuilder`)가 역방향 edge 를 만들지 않는다.
    /// 현재 유일한 사례: 6호선 응암 순환 폐합 edge(구산 606 → 응암 601).
    /// 역방향을 열어두면 "응암→구산"이 실존하지 않는 1구간 역주행으로 잡힌다.
    @Default(false) bool isOneWay,
  }) = _Connection;

  factory Connection.fromJson(Map<String, dynamic> json) =>
      _$ConnectionFromJson(json);
}
