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
  }) = _Connection;

  factory Connection.fromJson(Map<String, dynamic> json) =>
      _$ConnectionFromJson(json);
}
