import 'package:flutter_test/flutter_test.dart';
import 'package:seoul_subway/core/utils/line_direction.dart';
import 'package:seoul_subway/domain/entities/connection.dart';

Connection _c(String from, String to, String lineId,
        {bool isTransfer = false}) =>
    Connection(
      fromStationId: from,
      toStationId: to,
      lineId: lineId,
      travelTimeSeconds: 120,
      isTransfer: isTransfer,
    );

void main() {
  group('isDownBetween - 일반 노선', () {
    test('ID 증가 = 하행 (true)', () {
      expect(isDownBetween('101', '105', '1'), isTrue);
    });

    test('ID 감소 = 상행 (false)', () {
      expect(isDownBetween('105', '101', '1'), isFalse);
    });

    test('알파벳 접두사 ID도 숫자 부분만 비교 (증가 = 하행)', () {
      expect(isDownBetween('K10', 'K20', '경의중앙'), isTrue);
    });

    test('알파벳 접두사 ID도 숫자 부분만 비교 (감소 = 상행)', () {
      expect(isDownBetween('D10', 'D01', 'SB'), isFalse);
    });

    test('숫자 추출 실패(ABC/XYZ) → false', () {
      expect(isDownBetween('ABC', 'XYZ', '1'), isFalse);
    });

    test('한쪽만 숫자 추출 실패 → false', () {
      expect(isDownBetween('ABC', '105', '1'), isFalse);
      expect(isDownBetween('101', 'XYZ', '1'), isFalse);
    });
  });

  group('isDownBetween - 2호선 순환', () {
    test('인접 내선 (201→202): step=1, |step|<=21, step>0 → 내선(false)', () {
      expect(isDownBetween('201', '202', '2'), isFalse);
    });

    test('인접 외선 (202→201): step=-1, |step|<=21, step<0 → 외선(true)', () {
      expect(isDownBetween('202', '201', '2'), isTrue);
    });

    test('순환 경계 (201→243): step=42, |step|>21, step>0 → 외선(true)', () {
      // _isLine2DownBetween: |step|>21 이면 return step > 0
      expect(isDownBetween('201', '243', '2'), isTrue);
    });

    test('순환 경계 (243→201): step=-42, |step|>21, step<0 → 내선(false)', () {
      // _isLine2DownBetween: |step|>21 이면 return step > 0 → false
      expect(isDownBetween('243', '201', '2'), isFalse);
    });

    test('인접 경계 (243→242): step=-1, 내선 아님 → 외선(true)', () {
      expect(isDownBetween('243', '242', '2'), isTrue);
    });

    test('중간 내선 (210→211): step=1 → 내선(false)', () {
      expect(isDownBetween('210', '211', '2'), isFalse);
    });
  });

  group('isDownBetween - 2호선 성수지선 (211-244-245-246-250, 본선과 반대 극성)', () {
    // 실제 관례: ID 증가(신설동 방향) = 하행/외선(true), ID 감소(성수 방향) = 상행/내선(false).
    // 지선 전용 분기가 없던 시절엔 내부 간선이 전부 반대로 판정됐다(회귀 가드).
    test('진입 성수→용답 (211→244): 하행(true)', () {
      expect(isDownBetween('211', '244', '2'), isTrue);
    });
    test('진입 용답→성수 (244→211): 상행(false)', () {
      expect(isDownBetween('244', '211', '2'), isFalse);
    });
    test('내부 용답→신답 (244→245): 하행(true)', () {
      expect(isDownBetween('244', '245', '2'), isTrue);
    });
    test('내부 신답→용답 (245→244): 상행(false)', () {
      expect(isDownBetween('245', '244', '2'), isFalse);
    });
    test('내부 신답→용두 (245→246): 하행(true)', () {
      expect(isDownBetween('245', '246', '2'), isTrue);
    });
    test('내부 용두→신답 (246→245): 상행(false)', () {
      expect(isDownBetween('246', '245', '2'), isFalse);
    });
    test('종점 용두→신설동 (246→250): 하행(true)', () {
      expect(isDownBetween('246', '250', '2'), isTrue);
    });
    test('종점 신설동→용두 (250→246): 상행(false) — 신설동발은 상행만 존재', () {
      expect(isDownBetween('250', '246', '2'), isFalse);
    });
  });

  group('isDownBetween - 2호선 신정지선 (234-247-248-249, 본선 공식과 동일 극성)', () {
    // 실제 관례: ID 증가(신정네거리 방향) = 상행/내선(false), ID 감소 = 하행/외선(true).
    // 본선 공식(작은 step)만으로 이미 정합 — 회귀 가드.
    test('신도림→도림천 (234→247): 내선/상행(false)', () {
      expect(isDownBetween('234', '247', '2'), isFalse);
    });
    test('도림천→신도림 (247→234): 외선/하행(true)', () {
      expect(isDownBetween('247', '234', '2'), isTrue);
    });
    test('도림천→양천구청 (247→248): 내선/상행(false)', () {
      expect(isDownBetween('247', '248', '2'), isFalse);
    });
    test('양천구청→도림천 (248→247): 외선/하행(true)', () {
      expect(isDownBetween('248', '247', '2'), isTrue);
    });
  });

  group('isDownBetween - 4호선', () {
    test('본선 내부 증가 (402→406): 하행(true)', () {
      expect(isDownBetween('402', '406', '4'), isTrue);
    });

    test('본선 내부 감소 (406→402): 상행(false)', () {
      expect(isDownBetween('406', '402', '4'), isFalse);
    });

    test('진접선 내부 증가 (449→450): 하행(true)', () {
      expect(isDownBetween('449', '450', '4'), isTrue);
    });

    test('진접선 내부 증가 (451→452): 하행(true)', () {
      expect(isDownBetween('451', '452', '4'), isTrue);
    });

    test('진접선 내부 감소 (450→449): 상행(false)', () {
      expect(isDownBetween('450', '449', '4'), isFalse);
    });

    test('진접선 → 본선 (452→402): 남쪽 이동 = 하행(true)', () {
      expect(isDownBetween('452', '402', '4'), isTrue);
    });

    test('진접선 → 본선 (449→405): 남쪽 이동 = 하행(true)', () {
      expect(isDownBetween('449', '405', '4'), isTrue);
    });

    test('본선 → 진접선 (402→449): 북쪽 이동 = 상행(false)', () {
      expect(isDownBetween('402', '449', '4'), isFalse);
    });

    test('본선 → 진접선 (405→452): 북쪽 이동 = 상행(false)', () {
      expect(isDownBetween('405', '452', '4'), isFalse);
    });
  });

  group('isDownBetween - 9호선 (API 라벨 반전)', () {
    // 서울 API `updnLine` 정의:
    //   하행 = 개화/김포공항 방면 (ID 감소)
    //   상행 = 중앙보훈병원 방면 (ID 증가)
    test('ID 감소 (926→905, 언주→마곡나루) = 하행(true)', () {
      expect(isDownBetween('926', '905', '9'), isTrue);
    });

    test('ID 증가 (905→926, 마곡나루→언주) = 상행(false)', () {
      expect(isDownBetween('905', '926', '9'), isFalse);
    });

    test('ID 감소 (938→901, 중앙보훈병원→개화 전체) = 하행(true)', () {
      expect(isDownBetween('938', '901', '9'), isTrue);
    });

    test('ID 증가 (901→938, 개화→중앙보훈병원 전체) = 상행(false)', () {
      expect(isDownBetween('901', '938', '9'), isFalse);
    });

    test('같은 ID (926→926) = false', () {
      expect(isDownBetween('926', '926', '9'), isFalse);
    });

    // 회귀 방지: 가상 급행 노선(`9E`)이 9호선 특수 분기를 타지 않으면
    // 일반 노선 규칙(ID 증가=하행)으로 평가되어 방향이 반대로 판정된다.
    // 이로 인해 선정릉(929)→동작(921) 경로 첫 세그먼트(`9E`, 929→920)에서
    // routeFilter.isDown이 false로 잘못 잡혀 반대 방향(중앙보훈병원행) 열차가 표시되는 회귀 발생.
    test('가상 급행 노선 9E도 9호선 동일 규칙: ID 감소(929→920) = 하행(true)', () {
      expect(isDownBetween('929', '920', '9E'), isTrue,
          reason: '9E는 9호선과 동일하게 ID 감소를 하행으로 판정해야 함');
    });

    test('가상 급행 노선 9E: ID 증가(920→929) = 상행(false)', () {
      expect(isDownBetween('920', '929', '9E'), isFalse);
    });

    test('가상 급행 노선 1E도 1호선 동일 규칙: ID 증가 = 하행(true)', () {
      // 1호선은 일반 규칙: ID 증가 = 하행
      expect(isDownBetween('150', '160', '1E'), isTrue);
      expect(isDownBetween('160', '150', '1E'), isFalse);
    });
  });

  group('isDownBetween - 공항철도 (API 라벨 반전)', () {
    // 서울 API `updnLine` 정의:
    //   하행 = 서울역 방면 (A01, ID 감소)
    //   상행 = 인천공항2터미널 방면 (A14, ID 증가)
    test('ID 증가 (A01→A14, 서울역→인천공항) = 상행(false)', () {
      expect(isDownBetween('A01', 'A14', '공항철도'), isFalse);
    });

    test('ID 감소 (A14→A01, 인천공항→서울역) = 하행(true)', () {
      expect(isDownBetween('A14', 'A01', '공항철도'), isTrue);
    });

    test('ID 증가 (A03→A06, 홍대입구→김포공항) = 상행(false)', () {
      expect(isDownBetween('A03', 'A06', '공항철도'), isFalse);
    });
  });

  group('isDownBetween - 경계 및 방어적 케이스', () {
    test('같은 ID (303→303, 일반 노선): step=0 → 하행 아님 (false)', () {
      // 일반 노선 로직: toNum > fromNum. 같으면 false.
      expect(isDownBetween('303', '303', '3'), isFalse);
    });

    test('빈 문자열 → false', () {
      expect(isDownBetween('', '', '1'), isFalse);
    });
  });

  group('findPreviousStationId - 1호선 (ID 증가 = 하행)', () {
    final conns = [
      _c('101', '102', '1'),
      _c('102', '103', '1'),
      _c('103', '104', '1'),
    ];

    test('하행(isDown=true) 방향의 103 직전 역은 102', () {
      expect(
        findPreviousStationId(
          currentId: '103',
          lineId: '1',
          isDown: true,
          connections: conns,
        ),
        '102',
      );
    });

    test('상행(isDown=false) 방향의 103 직전 역은 104', () {
      expect(
        findPreviousStationId(
          currentId: '103',
          lineId: '1',
          isDown: false,
          connections: conns,
        ),
        '104',
      );
    });

    test('경로 끝(101)에서 하행 직전 역 없음 → null', () {
      expect(
        findPreviousStationId(
          currentId: '101',
          lineId: '1',
          isDown: true,
          connections: conns,
        ),
        isNull,
      );
    });

    test('환승 연결(isTransfer=true)은 무시된다', () {
      final withTransfer = [
        ...conns,
        _c('103', 'X99', '1', isTransfer: true),
      ];
      // 환승은 스킵하므로 여전히 102가 하행 직전 역.
      expect(
        findPreviousStationId(
          currentId: '103',
          lineId: '1',
          isDown: true,
          connections: withTransfer,
        ),
        '102',
      );
    });

    test('다른 노선 연결은 무시된다', () {
      final withOther = [
        ...conns,
        _c('103', '999', '2'),
      ];
      expect(
        findPreviousStationId(
          currentId: '103',
          lineId: '1',
          isDown: true,
          connections: withOther,
        ),
        '102',
      );
    });
  });

  group('findPreviousStationId - 2호선 순환', () {
    // 간략화된 인접 관계 (경계 포함).
    final conns = [
      _c('201', '202', '2'),
      _c('202', '203', '2'),
      _c('242', '243', '2'),
      _c('243', '201', '2'), // 순환 경계
    ];

    test('내선(isDown=false): 202의 직전은 201', () {
      // other=201, current=202 → isDownBetween(201,202,"2") = false (내선) = isDown
      expect(
        findPreviousStationId(
          currentId: '202',
          lineId: '2',
          isDown: false,
          connections: conns,
        ),
        '201',
      );
    });

    test('외선(isDown=true): 202의 직전은 203', () {
      // other=203, current=202 → isDownBetween(203,202,"2") = true (외선) = isDown
      expect(
        findPreviousStationId(
          currentId: '202',
          lineId: '2',
          isDown: true,
          connections: conns,
        ),
        '203',
      );
    });

    test('순환 경계 - 내선 201의 직전은 243', () {
      // other=243, current=201 → isDownBetween(243,201,"2"):
      //   step=201-243=-42, |step|>21 → return step>0 → false (내선)
      expect(
        findPreviousStationId(
          currentId: '201',
          lineId: '2',
          isDown: false,
          connections: conns,
        ),
        '243',
      );
    });

    test('순환 경계 - 외선 243의 직전은 201', () {
      // other=201, current=243 → isDownBetween(201,243,"2"):
      //   step=42, |step|>21 → return step>0 → true (외선)
      expect(
        findPreviousStationId(
          currentId: '243',
          lineId: '2',
          isDown: true,
          connections: conns,
        ),
        '201',
      );
    });
  });

  group('findPreviousStationId - 4호선 본선/진접선 경계', () {
    // 본선 불연속: 448(오이도) … 402(상계) … 452(불암산)↔402(상계) 경계
    final conns = [
      _c('402', '403', '4'), // 상계 ↔ 노원
      _c('403', '404', '4'),
      _c('452', '402', '4'), // 진접선 ↔ 본선 경계
      _c('451', '452', '4'),
      _c('450', '451', '4'),
      _c('449', '450', '4'),
    ];

    test('본선 내 하행(isDown=true): 403 직전은 402', () {
      expect(
        findPreviousStationId(
          currentId: '403',
          lineId: '4',
          isDown: true,
          connections: conns,
        ),
        '402',
      );
    });

    test('본선 내 상행(isDown=false): 403 직전은 404', () {
      expect(
        findPreviousStationId(
          currentId: '403',
          lineId: '4',
          isDown: false,
          connections: conns,
        ),
        '404',
      );
    });

    test('진접선→본선 경계 하행(isDown=true): 402 직전은 452', () {
      // other=452, current=402 → isDownBetween(452,402,"4") = 진접→본선 = true
      expect(
        findPreviousStationId(
          currentId: '402',
          lineId: '4',
          isDown: true,
          connections: conns,
        ),
        '452',
      );
    });

    test('진접선→본선 경계 상행(isDown=false): 452 직전은 402', () {
      // other=402, current=452 → isDownBetween(402,452,"4") = 본선→진접 = false
      expect(
        findPreviousStationId(
          currentId: '452',
          lineId: '4',
          isDown: false,
          connections: conns,
        ),
        '402',
      );
    });

    test('진접선 내부 하행(isDown=true): 451 직전은 450', () {
      // other=450, current=451 → isDownBetween(450,451,"4") = 진접선 내부 증가 = true
      expect(
        findPreviousStationId(
          currentId: '451',
          lineId: '4',
          isDown: true,
          connections: conns,
        ),
        '450',
      );
    });

    test('진접선 내부 상행(isDown=false): 451 직전은 452', () {
      expect(
        findPreviousStationId(
          currentId: '451',
          lineId: '4',
          isDown: false,
          connections: conns,
        ),
        '452',
      );
    });

    test('진접선 끝(449) 하행 직전 없음 → null', () {
      // 449 이하 연결 없음
      expect(
        findPreviousStationId(
          currentId: '449',
          lineId: '4',
          isDown: true,
          connections: conns,
        ),
        isNull,
      );
    });
  });
}
