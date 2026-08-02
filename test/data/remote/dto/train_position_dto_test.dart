// 열차위치 API(realtimePosition) 응답 → ArrivalInfo 매핑 검증.
//
// 도착정보 API 와 필드 의미가 다른 지점이 핵심이다:
//  - 위치 API 의 `statnNm` 은 **열차의 현재 위치**다(도착정보 API 는 조회 대상 역).
//  - `updnLine` 이 문자열 "상행"/"하행" 이 아니라 "0"/"1" 이다.
//  - 잔여초(`barvlDt`)가 없다 → `arrivalSeconds` 는 null 이어야 하고, 추정은 상위
//    계층(fallbackArrivalsFromPositions)이 맡는다.
import 'package:flutter_test/flutter_test.dart';
import 'package:seoul_subway/data/remote/dto/train_position_dto.dart';

void main() {
  /// 5호선 천호를 대상역으로, 하남검단산행 열차가 광나루에 도착한 상태.
  Map<String, dynamic> positionJson({
    String updnLine = '1',
    String trainSttus = '1',
    String directAt = '0',
    String statnNm = '광나루(장신대)',
  }) {
    return {
      'subwayId': '1005',
      'statnNm': statnNm,
      'statnTnm': '하남검단산',
      'trainNo': '5133',
      'updnLine': updnLine,
      'trainSttus': trainSttus,
      'directAt': directAt,
      'lstcarAt': '0',
      'recptnDt': '2026-07-31 06:10:30',
    };
  }

  test('현재 위치 역명은 currentStationName 으로, 대상역은 stationName 으로 들어간다', () {
    final dto = TrainPositionDto.fromJson(positionJson());
    final arrival = dto.toArrivalInfo('천호');

    expect(arrival.stationName, '천호', reason: '이 도착정보가 어느 역에 대한 것인지');
    // 부역명이 붙은 API 등록명은 표시용 역명으로 되돌아가야 stations.json 매칭이 된다.
    expect(arrival.currentStationName, '광나루');
    expect(arrival.trainNo, '5133');
    expect(arrival.destination, '하남검단산');
    expect(arrival.trainLineNm, '하남검단산행');
    expect(arrival.receivedAt, DateTime(2026, 7, 31, 6, 10, 30));
  });

  test('잔여초는 채우지 않는다 — 추정은 상위 계층의 몫', () {
    final arrival = TrainPositionDto.fromJson(positionJson()).toArrivalInfo('천호');
    expect(arrival.arrivalSeconds, isNull);
  });

  test('updnLine 0/1 을 앱의 방향 문자열로 변환한다', () {
    final down = TrainPositionDto.fromJson(positionJson(updnLine: '1'));
    final up = TrainPositionDto.fromJson(positionJson(updnLine: '0'));
    expect(down.toArrivalInfo('천호').direction, '하행');
    expect(up.toArrivalInfo('천호').direction, '상행');
  });

  test('trainSttus 는 도착정보 API 의 arvlCd 와 같은 체계로 옮긴다', () {
    ({int? code, String status}) mapped(String sttus) {
      final a = TrainPositionDto.fromJson(positionJson(trainSttus: sttus))
          .toArrivalInfo('천호');
      return (code: a.arrivalCode, status: a.positionStatus);
    }

    expect(mapped('0'), (code: 0, status: '진입'));
    expect(mapped('1'), (code: 1, status: '도착'));
    expect(mapped('2'), (code: 2, status: '출발'));
    // 전역출발 — arvlMsg3 에 대응 표기가 없어 '출발' 로 둔다(진행도 동일 취급).
    expect(mapped('3'), (code: 3, status: '출발'));
  });

  test('directAt=1 은 급행', () {
    expect(
      TrainPositionDto.fromJson(positionJson(directAt: '1'))
          .toArrivalInfo('천호')
          .trainType,
      '급행',
    );
    expect(
      TrainPositionDto.fromJson(positionJson(directAt: '0'))
          .toArrivalInfo('천호')
          .trainType,
      '일반',
    );
  });
}
