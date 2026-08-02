// freezed factory 생성자 파라미터의 @JsonKey 는 freezed 3 + json_serializable
// 조합에서 알려진 케이스로 invalid_annotation_target warning 을 낸다(생성 코드는
// 올바르다). arrival_info_dto.dart 와 같은 이유로 이 파일에만 한정해 억제한다.
// ignore_for_file: invalid_annotation_target
import 'package:freezed_annotation/freezed_annotation.dart';

import '../../../core/constants/station_api_name_overrides.dart';
import '../../../domain/entities/arrival_info.dart';

part 'train_position_dto.freezed.dart';
part 'train_position_dto.g.dart';

String? _toNullableString(dynamic value) => value?.toString();

/// 실시간 열차 위치 API(`realtimePosition`) 응답 1건.
///
/// **엔드포인트:** `.../json/realtimePosition/0/100/{노선명}`
///
/// | 필드 | 설명 |
/// |------|------|
/// | `subwayId` | 노선 ID (예: `"1005"` = 5호선) |
/// | `statnNm` | 열차의 **현재 위치 역명** (API 등록명) |
/// | `statnTnm` | 종착역명 |
/// | `trainNo` | 열차 번호 |
/// | `updnLine` | 방향 — `"0"`: 상행/내선, `"1"`: 하행/외선 |
/// | `trainSttus` | 상태 — `0`: 진입, `1`: 도착, `2`: 출발, `3`: 전역출발 |
/// | `directAt` | `"1"`: 급행, `"0"`: 일반 |
/// | `lstcarAt` | `"1"`: 막차 |
/// | `recptnDt` | 데이터 수신 시각 |
///
/// 도착정보 API 와 달리 **잔여초(`barvlDt`)가 없다.** 남은시간은 현재역에서
/// 대상 역까지의 구간 소요시간으로 추정해야 한다
/// (`fallbackArrivalsFromPositions` 가 담당).
@freezed
abstract class TrainPositionDto with _$TrainPositionDto {
  const TrainPositionDto._();

  const factory TrainPositionDto({
    @JsonKey(fromJson: _toNullableString) String? subwayId,
    @JsonKey(fromJson: _toNullableString) String? statnNm,
    @JsonKey(fromJson: _toNullableString) String? statnTnm,
    @JsonKey(fromJson: _toNullableString) String? trainNo,
    @JsonKey(fromJson: _toNullableString) String? updnLine,
    @JsonKey(fromJson: _toNullableString) String? trainSttus,
    @JsonKey(fromJson: _toNullableString) String? directAt,
    @JsonKey(fromJson: _toNullableString) String? lstcarAt,
    @JsonKey(fromJson: _toNullableString) String? recptnDt,
  }) = _TrainPositionDto;

  factory TrainPositionDto.fromJson(Map<String, dynamic> json) =>
      _$TrainPositionDtoFromJson(json);

  /// 도착정보 형태로 변환한다. **잔여초는 채우지 않는다**(`arrivalSeconds: null`)
  /// — 추정은 노선 데이터가 있는 상위 계층(`fallbackArrivalsFromPositions`)의 몫이다.
  ///
  /// `trainSttus` 를 `arrivalCode` 에 그대로 넣는 것은 두 API 의 코드 체계가
  /// 같기 때문이다(0 진입 / 1 도착 / 2 출발 / 3 전역출발). 둘 다 **열차의 현재
  /// 위치 역** 기준이라 의미도 일치한다.
  ///
  /// [targetStationName] 은 이 도착정보가 어느 역에 대한 것인지 — 도착정보 API
  /// 의 `statnNm`(조회 대상 역)에 대응한다. 위치 API 의 `statnNm` 은 그와 달리
  /// **열차의 현재 위치**이므로 `currentStationName` 으로 들어간다.
  ArrivalInfo toArrivalInfo(String targetStationName) {
    final code = trainSttus != null ? int.tryParse(trainSttus!) : null;
    final dest = resolveDisplayStationName(statnTnm ?? '');
    return ArrivalInfo(
      subwayId: subwayId ?? '',
      stationName: targetStationName,
      trainLineNm: dest.isEmpty ? '' : '$dest행',
      direction: updnLine == '1' ? '하행' : '상행',
      // 위치 API 는 도착 메시지를 주지 않는다. 빈 값이면 표시 단계가 잔여초로
      // 문구를 만들고, `parseStationCount` 힌트도 쓰이지 않는다.
      arrivalMessage: '',
      destination: dest,
      trainType: directAt == '1' ? '급행' : '일반',
      arrivalSeconds: null,
      receivedAt: recptnDt != null
          ? DateTime.tryParse(recptnDt!) ?? DateTime.now()
          : DateTime.now(),
      currentStationName: resolveDisplayStationName(statnNm ?? ''),
      trainNo: trainNo ?? '',
      positionStatus: _positionStatusOf(code),
      arrivalCode: code,
    );
  }
}

/// `trainSttus` → 도착정보 API 의 `arvlMsg3` 상태 표기.
///
/// `3`(전역출발)은 도착정보 API 의 `arvlMsg3` 에 대응 표기가 없다. 이전 역을
/// 떠나 현재역으로 접근하는 상태이므로 `출발` 로 둔다 — 진행도 계산
/// (`calculateInitialProgress`)에서 같은 취급을 받는다.
String _positionStatusOf(int? code) {
  switch (code) {
    case 0:
      return '진입';
    case 1:
      return '도착';
    case 2:
    case 3:
      return '출발';
    default:
      return '';
  }
}
