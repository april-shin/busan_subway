import 'package:freezed_annotation/freezed_annotation.dart';

part 'arrival_info.freezed.dart';
part 'arrival_info.g.dart';

@freezed
abstract class ArrivalInfo with _$ArrivalInfo {
  const factory ArrivalInfo({
    required String subwayId,
    required String stationName,
    required String trainLineNm,
    required String direction,
    required String arrivalMessage,
    required String destination,
    required String trainType,
    int? arrivalSeconds,
    required DateTime receivedAt,
    @Default('') String currentStationName,
    @Default('') String trainNo,
    @Default('') String positionStatus,
    int? arrivalCode,
    @Default(false) bool isEstimated,
  }) = _ArrivalInfo;

  factory ArrivalInfo.fromJson(Map<String, dynamic> json) =>
      _$ArrivalInfoFromJson(json);
}
