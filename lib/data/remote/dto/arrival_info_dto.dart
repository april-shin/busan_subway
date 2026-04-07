import 'package:freezed_annotation/freezed_annotation.dart';

import '../../../core/utils/parse_arrival_message.dart';
import '../../../domain/entities/arrival_info.dart';

part 'arrival_info_dto.freezed.dart';
part 'arrival_info_dto.g.dart';

/// API 응답 값을 String?으로 안전하게 변환 (int 등 비문자열 대응)
String? _toNullableString(dynamic value) => value?.toString();

/// arvlMsg3에서 순수 역명만 추출 ("강남 출발" → "강남")
String _extractStationName(String? raw) {
  if (raw == null || raw.isEmpty) return '';
  final parts = raw.split(' ');
  if (parts.length >= 2) {
    const suffixes = {'출발', '도착', '진입', '전역'};
    if (suffixes.contains(parts.last)) {
      return parts.sublist(0, parts.length - 1).join(' ');
    }
  }
  return raw;
}

/// arvlMsg3에서 위치 상태만 추출 ("강남 출발" → "출발")
String _extractPositionStatus(String? raw) {
  if (raw == null || raw.isEmpty) return '';
  final parts = raw.split(' ');
  if (parts.length >= 2) {
    const suffixes = {'출발', '도착', '진입', '전역'};
    if (suffixes.contains(parts.last)) return parts.last;
  }
  return '';
}

/// barvlDt(도착 예정 초)를 파싱한다.
///
/// API가 도착 시간을 모를 때 "0"을 반환하는 경우가 있다 (특히 신분당선 등).
/// arvlCd가 1(도착) 또는 0(진입)이면 barvlDt "0"은 실제 의미있는 값이므로 0을 반환하고,
/// 그 외(arvlCd 99 등)에서 "0"이면 API가 실제 시간을 모르는 것이므로 null을 반환한다.
int? _parseArrivalSeconds(String? barvlDt, String? arvlCd) {
  if (barvlDt == null) return null;
  final seconds = int.tryParse(barvlDt);
  if (seconds == null) return null;
  if (seconds > 0) return seconds;

  // barvlDt == 0: 도착(1) 또는 진입(0)이면 실제 0초, 그 외는 데이터 없음
  final code = arvlCd != null ? int.tryParse(arvlCd) : null;
  const validZeroCodes = {0, 1}; // 진입, 도착
  if (code != null && validZeroCodes.contains(code)) return 0;
  return null;
}

@freezed
class ArrivalInfoDto with _$ArrivalInfoDto {
  const ArrivalInfoDto._();

  const factory ArrivalInfoDto({
    @JsonKey(fromJson: _toNullableString) String? subwayId,
    @JsonKey(fromJson: _toNullableString) String? updnLine,
    @JsonKey(fromJson: _toNullableString) String? trainLineNm,
    @JsonKey(fromJson: _toNullableString) String? statnNm,
    @JsonKey(fromJson: _toNullableString) String? bstatnNm,
    @JsonKey(fromJson: _toNullableString) String? barvlDt,
    @JsonKey(fromJson: _toNullableString) String? btrainSttus,
    @JsonKey(fromJson: _toNullableString) String? arvlMsg2,
    @JsonKey(fromJson: _toNullableString) String? arvlMsg3,
    @JsonKey(fromJson: _toNullableString) String? arvlCd,
    @JsonKey(fromJson: _toNullableString) String? recptnDt,
    @JsonKey(fromJson: _toNullableString) String? ordkey,
    @JsonKey(fromJson: _toNullableString) String? btrainNo,
    @JsonKey(fromJson: _toNullableString) String? lstcarAt,
  }) = _ArrivalInfoDto;

  factory ArrivalInfoDto.fromJson(Map<String, dynamic> json) =>
      _$ArrivalInfoDtoFromJson(json);

  ArrivalInfo toEntity() {
    return ArrivalInfo(
      subwayId: subwayId ?? '',
      stationName: statnNm ?? '',
      trainLineNm: trainLineNm ?? '',
      direction: updnLine ?? '',
      arrivalMessage: arvlMsg2 ?? '',
      destination: bstatnNm ?? '',
      trainType: btrainSttus ?? '일반',
      arrivalSeconds: _parseArrivalSeconds(barvlDt, arvlCd)
          ?? parseTimeFromMessage(arvlMsg2 ?? ''),
      receivedAt: recptnDt != null
          ? DateTime.tryParse(recptnDt!) ?? DateTime.now()
          : DateTime.now(),
      currentStationName: _extractStationName(arvlMsg3),
      trainNo: btrainNo ?? ordkey ?? '',
      positionStatus: _extractPositionStatus(arvlMsg3),
      arrivalCode: arvlCd != null ? int.tryParse(arvlCd!) : null,
    );
  }
}
