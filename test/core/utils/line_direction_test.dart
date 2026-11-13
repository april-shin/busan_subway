import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:busan_subway/core/utils/line_direction.dart';
import 'package:busan_subway/domain/entities/connection.dart';

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

  group('isDownBetween - 부산 전 노선 (역 ID 증가 = 하행, 순환·지선 예외 없음)', () {
    // (노선, 시점 역 ID, 종점 역 ID): 다대포해수욕장→노포 등 lines.json 순서
    const lines = [
      ('1', '95', '134'),
      ('2', '201', '243'),
      ('3', '301', '317'),
      ('4', '401', '414'),
      ('동해', '801', '823'),
      ('부산김해', '901', '921'),
    ];
    for (final (line, first, last) in lines) {
      test('$line: $first→$last 하행, $last→$first 상행', () {
        expect(isDownBetween(first, last, line), isTrue);
        expect(isDownBetween(last, first, line), isFalse);
      });
    }

    test('2호선은 순환이 아니다 — 201↔243 은 양 끝일 뿐 경계 반전이 없다', () {
      expect(isDownBetween('243', '201', '2'), isFalse);
      expect(isDownBetween('201', '243', '2'), isTrue);
      expect(isDownBetween('201', '202', '2'), isTrue);
      expect(isDownBetween('202', '201', '2'), isFalse);
    });

    test('인접 쌍: 3호선 거제→연산(306→305) 상행, 연산→거제 하행', () {
      expect(isDownBetween('306', '305', '3'), isFalse);
      expect(isDownBetween('305', '306', '3'), isTrue);
    });

    test('가상 급행 노선 ID({base}E) 는 base 와 같은 규칙', () {
      expect(isDownBetween('201', '202', '2E'), isTrue);
      expect(isDownBetween('202', '201', '2E'), isFalse);
    });

    test('lines.json 의 stationIds 순서는 ID 증가 순이다 (규약 근거)', () {
      final raw = jsonDecode(File('assets/json/lines.json').readAsStringSync())
          as List;
      for (final l in raw.cast<Map<String, dynamic>>()) {
        final ids = (l['stationIds'] as List).cast<String>();
        for (var i = 0; i + 1 < ids.length; i++) {
          expect(isDownBetween(ids[i], ids[i + 1], l['id'] as String), isTrue,
              reason: '${l['id']}: ${ids[i]}→${ids[i + 1]}');
        }
      }
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

  group('findPreviousStationId - 부산 2호선 (선형 — 끝에서 직전 역 없음)', () {
    final conns = [
      _c('201', '202', '2'),
      _c('202', '203', '2'),
      _c('242', '243', '2'),
    ];

    test('하행: 202 의 직전은 201', () {
      expect(
        findPreviousStationId(
            currentId: '202', lineId: '2', isDown: true, connections: conns),
        '201',
      );
    });

    test('상행: 202 의 직전은 203', () {
      expect(
        findPreviousStationId(
            currentId: '202', lineId: '2', isDown: false, connections: conns),
        '203',
      );
    });

    test('순환 경계가 없다 — 시점 201 의 하행 직전 역과 종점 243 의 상행 직전 역은 null', () {
      expect(
        findPreviousStationId(
            currentId: '201', lineId: '2', isDown: true, connections: conns),
        isNull,
      );
      expect(
        findPreviousStationId(
            currentId: '243', lineId: '2', isDown: false, connections: conns),
        isNull,
      );
    });
  });
}
