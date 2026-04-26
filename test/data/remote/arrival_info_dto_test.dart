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

    test('barvlDt "0" + arvlCd "0"(진입) → arrivalSeconds null (상위 추정으로 위임)', () {
      // 8호선처럼 barvlDt를 항상 0으로 내려주는 노선에서 진입(0) 상태도 0초로
      // 고정하면 실제 위치 대비 애니메이션이 즉시 도착으로 붕괴된다. 도착(1)만
      // 신뢰하고 진입(0)은 null로 떨어뜨려 경로/역 수 기반 추정에 맡긴다.
      const dto = ArrivalInfoDto(barvlDt: '0', arvlCd: '0');
      expect(dto.toEntity().arrivalSeconds, isNull);
    });

    test('barvlDt "0" + arvlCd "99" + arvlMsg2 없음 → arrivalSeconds null', () {
      const dto = ArrivalInfoDto(barvlDt: '0', arvlCd: '99');
      expect(dto.toEntity().arrivalSeconds, isNull);
    });

    test('barvlDt "0" + arvlCd "99" + arvlMsg2 "3분 30초" → 210 (2순위 폴백)', () {
      const dto = ArrivalInfoDto(
        barvlDt: '0',
        arvlCd: '99',
        arvlMsg2: '3분 30초',
      );
      expect(dto.toEntity().arrivalSeconds, 210);
    });

    test('barvlDt "0" + arvlCd "99" + arvlMsg2 "2분" → 120 (2순위 폴백)', () {
      const dto = ArrivalInfoDto(
        barvlDt: '0',
        arvlCd: '99',
        arvlMsg2: '2분',
      );
      expect(dto.toEntity().arrivalSeconds, 120);
    });

    test('barvlDt 정상값이면 arvlMsg2 무시', () {
      const dto = ArrivalInfoDto(
        barvlDt: '60',
        arvlCd: '99',
        arvlMsg2: '3분 30초',
      );
      // 1순위 barvlDt=60이 우선
      expect(dto.toEntity().arrivalSeconds, 60);
    });

    test('barvlDt null + arvlMsg2 "1분 후" → 60 (2순위 폴백)', () {
      const dto = ArrivalInfoDto(
        arvlMsg2: '1분 후',
      );
      expect(dto.toEntity().arrivalSeconds, 60);
    });

    test('barvlDt null + arvlMsg2 "전역 출발" → null (시간 아님)', () {
      const dto = ArrivalInfoDto(
        arvlMsg2: '전역 출발',
      );
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

    // 8호선 API는 실제로는 수 정거장 떨어진 열차에도 arvlCd=1 + barvlDt=0을 주는
    // 데이터 품질 이슈가 있다. arvlMsg2가 "[N]번째 전역..." 형태이면 도착이
    // 아니므로 null로 떨어뜨려 상위 추정 로직에 맡겨야 한다.
    group('8호선 arvlCd=1 데이터 품질 이슈 대응', () {
      test('arvlCd=1 + barvlDt=0 + "[5]번째 전역 (남위례)" → null (추정 위임)', () {
        const dto = ArrivalInfoDto(
          subwayId: '1008',
          barvlDt: '0',
          arvlCd: '1',
          arvlMsg2: '[5]번째 전역 (남위례)',
          arvlMsg3: '남위례',
        );
        expect(dto.toEntity().arrivalSeconds, isNull);
      });

      test('arvlCd=1 + barvlDt=0 + "[11]번째 전역 (모란)" → null', () {
        const dto = ArrivalInfoDto(
          subwayId: '1008',
          barvlDt: '0',
          arvlCd: '1',
          arvlMsg2: '[11]번째 전역 (모란)',
        );
        expect(dto.toEntity().arrivalSeconds, isNull);
      });

      test('arvlCd=1 + barvlDt=0 + "전역 도착" → null (parseStationCount 매칭)', () {
        // arvlCd=1(조회역 도착)과 arvlMsg2="전역 도착"(이전역 도착)은 모순.
        // arvlMsg2를 우선 신뢰해 도착 아님으로 처리.
        const dto = ArrivalInfoDto(
          barvlDt: '0',
          arvlCd: '1',
          arvlMsg2: '전역 도착',
        );
        expect(dto.toEntity().arrivalSeconds, isNull);
      });

      test('arvlCd=1 + barvlDt=0 + "이번역 도착" → 0 유지 (진짜 도착)', () {
        // "이번역 도착"은 parseStationCount가 매칭하지 않으므로 기존 동작 유지.
        const dto = ArrivalInfoDto(
          barvlDt: '0',
          arvlCd: '1',
          arvlMsg2: '이번역 도착',
        );
        expect(dto.toEntity().arrivalSeconds, 0);
      });

      test('arvlCd=1 + barvlDt=0 + arvlMsg2 빈 문자열 → 0 (기존 동작)', () {
        const dto = ArrivalInfoDto(
          barvlDt: '0',
          arvlCd: '1',
          arvlMsg2: '',
        );
        expect(dto.toEntity().arrivalSeconds, 0);
      });
    });

    // 신분당선 등 일부 노선은 btrainNo 를 빈 문자열로 보낸다. `??` 만 쓰면
    // 빈 문자열이 그대로 trainNo 가 되어 단조 감소 clamp 의 매칭 키가 깨지므로,
    // 빈 문자열도 누락으로 간주해 ordkey 로 폴백해야 한다 (원칙 1 보강).
    group('trainNo 폴백 (원칙 1 매칭 키 안정화)', () {
      test('btrainNo 비어있고 ordkey 있으면 ordkey 사용', () {
        const dto = ArrivalInfoDto(btrainNo: '', ordkey: '01077강남0');
        expect(dto.toEntity().trainNo, '01077강남0');
      });

      test('btrainNo null 이고 ordkey 있으면 ordkey 사용', () {
        const dto = ArrivalInfoDto(ordkey: '01077강남0');
        expect(dto.toEntity().trainNo, '01077강남0');
      });

      test('btrainNo 채워져 있으면 btrainNo 우선', () {
        const dto = ArrivalInfoDto(btrainNo: 'D5001', ordkey: '01077강남0');
        expect(dto.toEntity().trainNo, 'D5001');
      });

      test('btrainNo 빈 문자열, ordkey 도 빈 문자열 → 빈 trainNo', () {
        const dto = ArrivalInfoDto(btrainNo: '', ordkey: '');
        expect(dto.toEntity().trainNo, '');
      });

      test('둘 다 null → 빈 trainNo', () {
        const dto = ArrivalInfoDto();
        expect(dto.toEntity().trainNo, '');
      });
    });
  });
}
