import 'package:flutter_test/flutter_test.dart';
import 'package:seoul_subway/domain/entities/connection.dart';

void main() {
  group('Connection', () {
    test('기본 생성자 — expressTimeSeconds 미지정 시 null', () {
      const conn = Connection(
        fromStationId: '201',
        toStationId: '202',
        lineId: '2',
        travelTimeSeconds: 120,
      );

      expect(conn.expressTimeSeconds, isNull);
      expect(conn.travelTimeSeconds, 120);
      expect(conn.isTransfer, isFalse);
      expect(conn.transferTimeSeconds, 0);
    });

    test('expressTimeSeconds = 120 명시 생성', () {
      const conn = Connection(
        fromStationId: '901',
        toStationId: '902',
        lineId: '9',
        travelTimeSeconds: 180,
        expressTimeSeconds: 120,
      );

      expect(conn.expressTimeSeconds, 120);
    });

    test('fromJson — expressTimeSeconds 필드가 없어도 null로 역호환', () {
      final conn = Connection.fromJson({
        'fromStationId': '201',
        'toStationId': '202',
        'lineId': '2',
        'travelTimeSeconds': 120,
      });

      expect(conn.expressTimeSeconds, isNull);
    });

    test('fromJson — expressTimeSeconds=null이 명시되어도 null', () {
      final conn = Connection.fromJson({
        'fromStationId': '201',
        'toStationId': '202',
        'lineId': '2',
        'travelTimeSeconds': 120,
        'expressTimeSeconds': null,
      });

      expect(conn.expressTimeSeconds, isNull);
    });

    test('fromJson — expressTimeSeconds 값이 있으면 그대로 파싱', () {
      final conn = Connection.fromJson({
        'fromStationId': '901',
        'toStationId': '902',
        'lineId': '9',
        'travelTimeSeconds': 180,
        'expressTimeSeconds': 90,
      });

      expect(conn.expressTimeSeconds, 90);
      expect(conn.travelTimeSeconds, 180);
    });

    test('toJson/fromJson 라운드트립 — expressTimeSeconds 보존', () {
      const original = Connection(
        fromStationId: '901',
        toStationId: '902',
        lineId: '9',
        travelTimeSeconds: 180,
        expressTimeSeconds: 90,
      );

      final encoded = original.toJson();
      final decoded = Connection.fromJson(encoded);

      expect(decoded, equals(original));
      expect(decoded.expressTimeSeconds, 90);
    });

    test('copyWith — expressTimeSeconds 변경', () {
      const conn = Connection(
        fromStationId: '901',
        toStationId: '902',
        lineId: '9',
        travelTimeSeconds: 180,
      );

      final updated = conn.copyWith(expressTimeSeconds: 60);

      expect(updated.expressTimeSeconds, 60);
      expect(updated.travelTimeSeconds, 180);
      expect(conn.expressTimeSeconds, isNull); // 원본 불변
    });
  });
}
