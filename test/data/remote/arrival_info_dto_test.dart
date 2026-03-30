import 'package:flutter_test/flutter_test.dart';
import 'package:seoul_subway/data/remote/dto/arrival_info_dto.dart';

void main() {
  group('ArrivalInfoDto', () {
    test('fromJson parses correctly', () {
      final json = {
        'subwayId': '1002',
        'updnLine': '상행',
        'trainLineNm': '성수행 - 을지로입구방면',
        'statnNm': '강남',
        'bstatnNm': '성수',
        'barvlDt': '120',
        'btrainSttus': '일반',
        'arvlMsg2': '전역 도착',
        'arvlMsg3': '역삼',
        'arvlCd': '1',
        'recptnDt': '2024-01-01 12:00:00',
        'ordkey': '01002강남0',
        'lstcarAt': '0',
      };

      final dto = ArrivalInfoDto.fromJson(json);

      expect(dto.subwayId, '1002');
      expect(dto.updnLine, '상행');
      expect(dto.statnNm, '강남');
      expect(dto.barvlDt, '120');
      expect(dto.btrainSttus, '일반');
    });

    test('toEntity maps correctly', () {
      const dto = ArrivalInfoDto(
        subwayId: '1002',
        updnLine: '상행',
        trainLineNm: '성수행',
        statnNm: '강남',
        bstatnNm: '성수',
        barvlDt: '120',
        btrainSttus: '급행',
        arvlMsg2: '전역 도착',
        recptnDt: '2024-01-01 12:00:00',
      );

      final entity = dto.toEntity();

      expect(entity.subwayId, '1002');
      expect(entity.direction, '상행');
      expect(entity.stationName, '강남');
      expect(entity.destination, '성수');
      expect(entity.arrivalSeconds, 120);
      expect(entity.trainType, '급행');
      expect(entity.arrivalMessage, '전역 도착');
    });

    test('toEntity handles null fields', () {
      const dto = ArrivalInfoDto();

      final entity = dto.toEntity();

      expect(entity.subwayId, '');
      expect(entity.stationName, '');
      expect(entity.arrivalSeconds, isNull);
      expect(entity.trainType, '일반');
    });

    test('toEntity handles invalid arrival seconds', () {
      const dto = ArrivalInfoDto(barvlDt: 'not_a_number');

      final entity = dto.toEntity();

      expect(entity.arrivalSeconds, isNull);
    });

    test('barvlDt "0" + arvlCd "1"(도착) → arrivalSeconds 0', () {
      const dto = ArrivalInfoDto(barvlDt: '0', arvlCd: '1');
      expect(dto.toEntity().arrivalSeconds, 0);
    });

    test('barvlDt "0" + arvlCd "0"(진입) → arrivalSeconds 0', () {
      const dto = ArrivalInfoDto(barvlDt: '0', arvlCd: '0');
      expect(dto.toEntity().arrivalSeconds, 0);
    });

    test('barvlDt "0" + arvlCd "99" → arrivalSeconds null (데이터 없음)', () {
      const dto = ArrivalInfoDto(barvlDt: '0', arvlCd: '99');
      expect(dto.toEntity().arrivalSeconds, isNull);
    });

    test('barvlDt "0" + arvlCd "5"(전역도착) → arrivalSeconds null', () {
      const dto = ArrivalInfoDto(barvlDt: '0', arvlCd: '5');
      expect(dto.toEntity().arrivalSeconds, isNull);
    });

    test('barvlDt "0" + arvlCd null → arrivalSeconds null', () {
      const dto = ArrivalInfoDto(barvlDt: '0');
      expect(dto.toEntity().arrivalSeconds, isNull);
    });
  });
}
