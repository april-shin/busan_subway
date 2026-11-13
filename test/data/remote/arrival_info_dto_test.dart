import 'package:flutter_test/flutter_test.dart';
import 'package:busan_subway/data/remote/dto/arrival_info_dto.dart';

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

    group('[D] 양수 barvlDt 라도 조회역 도착 상태가 우선한다', () {
      // 2026-08-13 총신대입구(이수) 실측: API 가 "이 역에 도착해 있다"고 말하면서
      // 동시에 barvlDt=60 을 보낸다. 60 을 믿으면 이미 승강장에 서 있는 열차가
      // "1분 후 도착"으로 표시되고, 60 초 뒤 잔여초가 소진돼 "정보 없음"이 된다.
      test('arvlCd=1 + 현재역 == 조회역 → 0 (양수 barvlDt 무시)', () {
        const dto = ArrivalInfoDto(
          barvlDt: '60',
          arvlCd: '1',
          statnNm: '총신대입구(이수)',
          arvlMsg2: '총신대입구(이수) 도착',
          arvlMsg3: '총신대입구(이수)',
        );
        expect(dto.toEntity().arrivalSeconds, 0);
      });

      test('현재역이 조회역과 다르면 양수 barvlDt 를 그대로 쓴다', () {
        // 8호선의 광범위 arvlCd=1 오보고 방어 — 수 정거장 떨어진 열차에도
        // 도착 코드를 주므로, 역이 다르면 도착으로 신뢰하지 않는다.
        const dto = ArrivalInfoDto(
          barvlDt: '60',
          arvlCd: '1',
          statnNm: '총신대입구(이수)',
          arvlMsg2: '남성 도착',
          arvlMsg3: '남성',
        );
        expect(dto.toEntity().arrivalSeconds, 60);
      });

      test('"[N]번째 전역" 메시지면 도착으로 신뢰하지 않는다', () {
        const dto = ArrivalInfoDto(
          barvlDt: '60',
          arvlCd: '1',
          statnNm: '모란',
          arvlMsg2: '[3]번째 전역',
          arvlMsg3: '모란',
        );
        expect(dto.toEntity().arrivalSeconds, 60);
      });

      test('도착이 아닌 코드(진입 0)는 양수 barvlDt 를 그대로 쓴다', () {
        // 진입은 아직 잔여시간이 남아 있을 수 있다.
        const dto = ArrivalInfoDto(
          barvlDt: '60',
          arvlCd: '0',
          statnNm: '총신대입구(이수)',
          arvlMsg2: '총신대입구(이수) 진입',
          arvlMsg3: '남성',
        );
        expect(dto.toEntity().arrivalSeconds, 60);
      });

      test('"○○ 전역" 은 조회역이 아니므로 양수를 그대로 쓴다', () {
        // 접미사를 벗기면 역명이 조회역과 같아지지만, 실제 위치는 직전 역이다.
        const dto = ArrivalInfoDto(
          barvlDt: '60',
          arvlCd: '1',
          statnNm: '총신대입구(이수)',
          arvlMsg2: '전역 도착',
          arvlMsg3: '총신대입구(이수) 전역',
        );
        expect(dto.toEntity().arrivalSeconds, 60);
      });

      test('접미사가 붙은 arvlMsg3 도 조회역이면 0 으로 읽는다', () {
        const dto = ArrivalInfoDto(
          barvlDt: '60',
          arvlCd: '1',
          statnNm: '총신대입구(이수)',
          arvlMsg2: '총신대입구(이수) 도착',
          arvlMsg3: '총신대입구(이수) 도착',
        );
        expect(dto.toEntity().arrivalSeconds, 0);
      });

      test('치환맵 역도 양쪽이 같은 정규화를 거쳐 일치한다 (지제 → 평택지제)', () {
        // 비교 한쪽에만 resolveDisplayStationName 이 적용되도록 리팩터링되면
        // 이 테스트가 깨진다.
        const dto = ArrivalInfoDto(
          barvlDt: '60',
          arvlCd: '1',
          statnNm: '지제',
          arvlMsg2: '지제 도착',
          arvlMsg3: '지제 도착',
        );
        expect(dto.toEntity().arrivalSeconds, 0);
      });

      test('대조군: 일반 접근 열차는 영향 없다', () {
        const dto = ArrivalInfoDto(
          barvlDt: '180',
          arvlCd: '99',
          statnNm: '총신대입구(이수)',
          arvlMsg2: '3분 후 (남성)',
          arvlMsg3: '남성',
        );
        expect(dto.toEntity().arrivalSeconds, 180);
      });
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
      const dto = ArrivalInfoDto(barvlDt: '0', arvlCd: '99', arvlMsg2: '2분');
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
      const dto = ArrivalInfoDto(arvlMsg2: '1분 후');
      expect(dto.toEntity().arrivalSeconds, 60);
    });

    test('barvlDt null + arvlMsg2 "전역 출발" → null (시간 아님)', () {
      const dto = ArrivalInfoDto(arvlMsg2: '전역 출발');
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
        const dto = ArrivalInfoDto(barvlDt: '0', arvlCd: '1', arvlMsg2: '');
        expect(dto.toEntity().arrivalSeconds, 0);
      });
    });

    // 6호선 응암순환 종착역: API 는 "응암순환(상선)"으로 응답하며 이 문자열이
    // 역명·방면·메시지 전반에 섞여 온다. toEntity 가 표시 필드를 "응암"으로 정리하되,
    // 시간 파싱(arrivalSeconds)은 raw arvlMsg2 를 써야 하므로 영향받지 않아야 한다.
    group(
      '응암순환(상선) 표시 정규화 (인바운드)',
      () {
        test('역명·방면·종착·메시지의 응암순환(상선)을 응암으로 정리한다', () {
          const dto = ArrivalInfoDto(
            subwayId: '1006',
            statnNm: '응암순환(상선)',
            trainLineNm: '응암순환(상선)행 - 응암순환(상선)방면',
            bstatnNm: '응암순환(상선)',
            arvlMsg2: '응암순환(상선) 도착',
            arvlMsg3: '응암순환(상선) 도착',
          );
          final e = dto.toEntity();
          expect(e.stationName, '응암');
          expect(e.trainLineNm, '응암행 - 응암방면');
          expect(e.destination, '응암');
          expect(e.arrivalMessage, '응암 도착');
          expect(e.currentStationName, '응암');
        });

        test('시간 파싱은 raw arvlMsg2 기준이라 정규화 영향 없음 ("4분 후" → 240)', () {
          const dto = ArrivalInfoDto(
            statnNm: '응암순환(상선)',
            arvlMsg2: '4분 후 (증산(명지대앞))',
          );
          final e = dto.toEntity();
          expect(e.arrivalSeconds, 240);
          // 표시 메시지는 부역명까지 정리됨
          expect(e.arrivalMessage, '4분 후 (증산)');
        });
      },
      skip:
          '부산 전환: 역명 치환 맵(arrivalApiStationNameOverrides 등)이 const 빈 맵이라 서울 치환 사례를 검증할 수 없음 — 부산 API 등록명을 채울 때 부산 사례로 교체',
    );

    // arvlMsg3(현재역)는 API 등록명으로 오므로 표시용 역명으로 되돌려야
    // stations.json 매칭(라이브맵 좌표·도착추정)이 성립한다. (인바운드 역치환)
    group(
      'currentStationName 표시명 정규화',
      () {
        test('축약형 API명 → 표시명 ("지제 도착" → 평택지제)', () {
          const dto = ArrivalInfoDto(arvlMsg3: '지제 도착');
          final e = dto.toEntity();
          expect(e.currentStationName, '평택지제');
          expect(e.positionStatus, '도착');
        });

        test('공백 포함 API명 → 표시명 ("4.19 민주묘지 출발" → 4·19민주묘지)', () {
          const dto = ArrivalInfoDto(arvlMsg3: '4.19 민주묘지 출발');
          expect(dto.toEntity().currentStationName, '4·19민주묘지');
        });

        test('부역명 덧붙임형 → 표시명 ("오목교(목동운동장앞) 진입" → 오목교)', () {
          const dto = ArrivalInfoDto(arvlMsg3: '오목교(목동운동장앞) 진입');
          expect(dto.toEntity().currentStationName, '오목교');
        });

        test('치환 대상 아닌 역명은 그대로 ("역삼 출발" → 역삼)', () {
          const dto = ArrivalInfoDto(arvlMsg3: '역삼 출발');
          expect(dto.toEntity().currentStationName, '역삼');
        });
      },
      skip:
          '부산 전환: 역명 치환 맵(arrivalApiStationNameOverrides 등)이 const 빈 맵이라 서울 치환 사례를 검증할 수 없음 — 부산 API 등록명을 채울 때 부산 사례로 교체',
    );

    // 신분당선 등 일부 노선은 btrainNo 를 빈 문자열로 보낸다. `??` 만 쓰면
    // 빈 문자열이 그대로 trainNo 가 되어 JS 의 열차 식별(activeTrains 키)이
    // 깨지므로, 빈 문자열도 누락으로 간주해 ordkey 로 폴백해야 한다.
    // (식별이 깨지면 단조 전진 기억까지 매 refresh 초기화된다 — 원칙 1)
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
