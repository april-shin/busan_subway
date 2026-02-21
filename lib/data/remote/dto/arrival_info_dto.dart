import 'package:freezed_annotation/freezed_annotation.dart';

import '../../../domain/entities/arrival_info.dart';

part 'arrival_info_dto.freezed.dart';
part 'arrival_info_dto.g.dart';

@freezed
class ArrivalInfoDto with _$ArrivalInfoDto {
  const ArrivalInfoDto._();

  const factory ArrivalInfoDto({
    String? subwayId,
    String? updnLine,
    String? trainLineNm,
    String? statnNm,
    String? bstatnNm,
    String? barvlDt,
    String? btrainSttus,
    String? arvlMsg2,
    String? arvlMsg3,
    String? arvlCd,
    String? recptnDt,
    String? ordkey,
    String? lstcarAt,
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
      arrivalSeconds: barvlDt != null ? int.tryParse(barvlDt!) : null,
      receivedAt: recptnDt != null
          ? DateTime.tryParse(recptnDt!) ?? DateTime.now()
          : DateTime.now(),
    );
  }
}
