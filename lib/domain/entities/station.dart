import 'package:freezed_annotation/freezed_annotation.dart';

part 'station.freezed.dart';
part 'station.g.dart';

@freezed
abstract class Station with _$Station {
  const factory Station({
    required String id,
    required String name,
    required String lineId,
    required double latitude,
    required double longitude,
    @Default(0) double svgX,
    @Default(0) double svgY,
    @Default(false) bool isTransfer,
    @Default([]) List<String> transferLines,
    @Default(0) int labelDirection,
  }) = _Station;

  factory Station.fromJson(Map<String, dynamic> json) =>
      _$StationFromJson(json);
}
