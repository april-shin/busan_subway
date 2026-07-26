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
    // 급행 운영 구간이면 양 끝역 간 급행 소요시간(초). 양쪽 모두 급행 정차역일 때만 채워진다.
    // null이면 해당 구간은 급행 미운영(또는 한쪽 미정차).
    int? expressTimeSeconds,
  }) = _Connection;

  factory Connection.fromJson(Map<String, dynamic> json) =>
      _$ConnectionFromJson(json);
}
