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
/// arvlCd=1(도착) + barvlDt=0은 원칙적으로 실제 0초이지만, 8호선 등 일부 노선은
/// 실제로는 수 정거장 떨어진 열차에도 arvlCd=1을 주는 데이터 품질 이슈가 있다.
/// 이 경우 arvlMsg2가 "[N]번째 전역..." 형태이면 도착 상태가 아니므로 null로
/// 떨어뜨려 상위 추정 로직(estimateArrivalSeconds)에 맡긴다.
///
/// 반환값 해석:
/// - 양수: API가 명시한 실제 잔여 초
/// - 0: 해당 역에 실제 도착한 상태
/// - null: 정보 없음 → 상위 추정 로직에서 채워야 함
int? _parseArrivalSeconds(String? barvlDt, String? arvlCd, String arvlMsg2) {
  if (barvlDt == null) return null;
  final seconds = int.tryParse(barvlDt);
  if (seconds == null) return null;
  if (seconds > 0) return seconds;

  // barvlDt == 0 인 경우만 처리.
  final code = arvlCd != null ? int.tryParse(arvlCd) : null;

  // arvlCd=1(도착)이어도 메시지가 "[N]번째 전역..." 형태면 실제 도착이 아님
  // (8호선 API의 광범위 arvlCd=1 버그 대응). 이 경우 null로 넘겨 추정에 위임.
  if (code == 1 && parseStationCount(arvlMsg2) != null) {
    return null;
  }

  // 도착(1)만 실제 0초로 신뢰.
  // 진입(0)은 짧은 잔여시간이 남아 있을 수 있고, barvlDt=0 오판 위험이 커
  // null로 떨어뜨려 상위 추정 로직에 맡긴다.
  const validZeroCodes = {1};
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
      arrivalSeconds: _parseArrivalSeconds(barvlDt, arvlCd, arvlMsg2 ?? '')
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
