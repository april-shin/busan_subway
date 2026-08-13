// freezed factory 생성자 파라미터의 @JsonKey 는 freezed 3 + json_serializable
// 조합에서 알려진 케이스로, analyzer 8.4 부터 invalid_annotation_target warning 을
// 낸다(freezed 가 생성 코드에서 올바르게 소비하므로 무해). 전역 대신 이 파일에만
// 한정해 억제한다 — 다른 곳의 진짜 annotation 오배치는 계속 검출되도록.
// ignore_for_file: invalid_annotation_target
import 'package:freezed_annotation/freezed_annotation.dart';

import '../../../core/constants/station_api_name_overrides.dart';
import '../../../core/utils/parse_arrival_message.dart';
import '../../../domain/entities/arrival_info.dart';

part 'arrival_info_dto.freezed.dart';
part 'arrival_info_dto.g.dart';

/// API 응답 값을 String?으로 안전하게 변환 (int 등 비문자열 대응)
String? _toNullableString(dynamic value) => value?.toString();

/// arvlMsg3에서 순수 역명만 추출 ("강남 출발" → "강남").
///
/// 추출한 역명은 API 등록명이므로 [resolveDisplayStationName]으로 표시용 역명으로
/// 되돌린다. 예: "지제 도착" → "평택지제", "관악산 출발" → "관악산(서울대)".
/// 이 정규화가 없으면 축약·치환형 역(예: 지제)에서 stations.json 매칭이 실패해
/// 라이브맵 좌표 조회·도착시간 추정이 깨진다.
String _extractStationName(String? raw) {
  if (raw == null || raw.isEmpty) return '';
  final parts = raw.split(' ');
  if (parts.length >= 2) {
    const suffixes = {'출발', '도착', '진입', '전역'};
    if (suffixes.contains(parts.last)) {
      return resolveDisplayStationName(
        parts.sublist(0, parts.length - 1).join(' '),
      );
    }
  }
  return resolveDisplayStationName(raw);
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
int? _parseArrivalSeconds(
  String? barvlDt,
  String? arvlCd,
  String arvlMsg2, {
  required bool atQueriedStation,
}) {
  if (barvlDt == null) return null;
  final seconds = int.tryParse(barvlDt);
  if (seconds == null) return null;

  final code = arvlCd != null ? int.tryParse(arvlCd) : null;

  if (seconds > 0) {
    // 양수 barvlDt 라도 **도착 상태가 우선**한다.
    //
    // API 는 `arvlCd=1`(도착) + `arvlMsg3` 가 조회역 자신인 행에도 양수
    // `barvlDt` 를 함께 보낸다 — 2026-08-13 총신대입구(이수) 실측:
    //   `barvlDt='60' arvlCd='1' arvlMsg2='총신대입구(이수) 도착'
    //    arvlMsg3='총신대입구(이수)'`
    // 이 60 을 그대로 믿으면 **이미 승강장에 서 있는 열차가 "1분 후 도착"** 으로
    // 표시된다(지도 말풍선·도착정보 카드 양쪽). 60 초 뒤에는 잔여초가 소진돼
    // "정보 없음"이 되므로, 사용자에게는 "1분 후 도착 → 정보 없음" 으로 보인다.
    //
    // 8호선의 광범위 `arvlCd=1` 오보고(수 정거장 떨어진 열차에도 도착 코드)는
    // 두 조건으로 막는다: ① 현재역이 조회역과 같을 것 ② `arvlMsg2` 가
    // "[N]번째 전역..." 형태가 아닐 것. 아래 `barvlDt == 0` 분기의 가드와 같은 취지.
    if (code == 1 &&
        atQueriedStation &&
        parseStationCount(arvlMsg2) == null) {
      return 0;
    }
    return seconds;
  }

  // 이하 barvlDt == 0 인 경우만 처리.

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
abstract class ArrivalInfoDto with _$ArrivalInfoDto {
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
    // 이 열차가 **조회역 자신에 있는지**. `_parseArrivalSeconds` 의 도착 우선
    // 판정에 쓴다. 양쪽 다 `resolveDisplayStationName` 을 거친 표시용 역명이라
    // API 등록명 차이(예: 지제 ↔ 평택지제)로 비교가 어긋나지 않는다.
    final currentName = _extractStationName(arvlMsg3);
    final atQueriedStation = currentName.isNotEmpty &&
        currentName == resolveDisplayStationName(statnNm ?? '') &&
        // "○○ 전역" 은 조회역이 아니라 그 **직전 역**에 있다는 뜻이다.
        // `_extractStationName` 이 접미사를 벗기면 역명만으로는 구분이 안 되므로
        // 위치 상태로 걸러낸다 (이게 없으면 한 정거장 떨어진 열차를 0 으로 읽는다).
        _extractPositionStatus(arvlMsg3) != '전역';

    return ArrivalInfo(
      subwayId: subwayId ?? '',
      // 표시 필드는 API 등록명을 표시용 역명으로 되돌린다(인바운드). 역명 단독
      // 필드는 resolveDisplayStationName, 역명이 텍스트에 섞인 필드는
      // resolveDisplayInText. (예: 응암순환(상선)→응암) 시간·역수 파싱은 아래에서
      // raw arvlMsg2 를 그대로 쓰므로 이 정규화의 영향을 받지 않는다.
      stationName: resolveDisplayStationName(statnNm ?? ''),
      trainLineNm: resolveDisplayInText(trainLineNm ?? ''),
      direction: updnLine ?? '',
      arrivalMessage: resolveDisplayInText(arvlMsg2 ?? ''),
      destination: resolveDisplayStationName(bstatnNm ?? ''),
      trainType: btrainSttus ?? '일반',
      arrivalSeconds: _parseArrivalSeconds(
            barvlDt,
            arvlCd,
            arvlMsg2 ?? '',
            atQueriedStation: atQueriedStation,
          ) ??
          parseTimeFromMessage(arvlMsg2 ?? ''),
      receivedAt: recptnDt != null
          ? DateTime.tryParse(recptnDt!) ?? DateTime.now()
          : DateTime.now(),
      currentStationName: currentName,
      // 빈 문자열도 누락으로 간주해 ordkey 로 폴백한다. 신분당선 등 일부 노선이
      // btrainNo 를 빈 문자열로 보내는 케이스가 있어, `??` 만으로는 trainNo 가
      // 흔들려 JS 의 열차 식별(activeTrains 키)이 깨진다. 식별이 깨지면 아이콘이
      // 매 refresh 새 열차로 재생성되어 단조 전진 기억(원칙 1)도 함께 초기화된다.
      trainNo: (btrainNo?.isNotEmpty ?? false)
          ? btrainNo!
          : (ordkey?.isNotEmpty ?? false ? ordkey! : ''),
      positionStatus: _extractPositionStatus(arvlMsg3),
      arrivalCode: arvlCd != null ? int.tryParse(arvlCd!) : null,
    );
  }
}
