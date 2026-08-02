import 'package:flutter_test/flutter_test.dart';
import 'package:seoul_subway/domain/entities/connection.dart';

void main() {
  group('Connection', () {
    test('기본 생성자 — 선택 필드는 기본값', () {
      const conn = Connection(
        fromStationId: '201',
        toStationId: '202',
        lineId: '2',
        travelTimeSeconds: 120,
      );

      expect(conn.travelTimeSeconds, 120);
      expect(conn.isTransfer, isFalse);
      expect(conn.transferTimeSeconds, 0);
    });

    test('toJson/fromJson 라운드트립', () {
      const original = Connection(
        fromStationId: '901',
        toStationId: '902',
        lineId: '9',
        travelTimeSeconds: 180,
        isTransfer: true,
        transferTimeSeconds: 90,
      );

      final decoded = Connection.fromJson(original.toJson());

      expect(decoded, equals(original));
    });

    test('copyWith — travelTimeSeconds 변경 시 원본 불변', () {
      const conn = Connection(
        fromStationId: '901',
        toStationId: '902',
        lineId: '9',
        travelTimeSeconds: 180,
      );

      final updated = conn.copyWith(travelTimeSeconds: 150);

      expect(updated.travelTimeSeconds, 150);
      expect(conn.travelTimeSeconds, 180);
    });

    // 구 급행 모델(2026-08 폐지) 회귀 가드.
    //
    // `expressTimeSeconds` 는 `etrnYn` 을 급행 지표로 오신뢰해 만들어진 표시
    // 전용 필드였고, 배관 전체가 제거됐다. 급행은 `express_skip_edges.json`
    // 기반 가상 노선(`{base}E`)으로만 표현한다.
    //
    // 오래된 번들 JSON 이나 되살아난 생성기가 이 키를 다시 넣더라도 파싱이
    // 깨지지 않아야 한다 — 조용히 무시되는 것이 올바른 동작이다.
    // (에셋에 실제로 이 키가 없는지는 connections_no_express_asset_test.dart 가 본다.)
    test('fromJson — 폐지된 expressTimeSeconds 키가 있어도 무시하고 파싱', () {
      final conn = Connection.fromJson({
        'fromStationId': '901',
        'toStationId': '902',
        'lineId': '9',
        'travelTimeSeconds': 180,
        'expressTimeSeconds': 90,
      });

      expect(conn.travelTimeSeconds, 180);
      expect(conn.toJson().containsKey('expressTimeSeconds'), isFalse);
    });
  });
}
