import 'package:flutter_test/flutter_test.dart';
import 'package:seoul_subway/domain/entities/route_result.dart';
import 'package:seoul_subway/domain/entities/station.dart';
import 'package:seoul_subway/features/route_search/utils/direction_resolver.dart';

void main() {
  Station makeStation(String id, String lineId) {
    return Station(
      id: id,
      name: '역$id',
      lineId: lineId,
      latitude: 0,
      longitude: 0,
    );
  }

  RouteSegment makeSegment({
    required String lineId,
    required List<String> stationIds,
  }) {
    return RouteSegment(
      lineId: lineId,
      lineName: '테스트',
      stations: stationIds.map((id) => makeStation(id, lineId)).toList(),
      durationSeconds: 120,
      direction: '테스트 방면',
    );
  }

  group('isDownDirection - 일반 노선', () {
    test('ID 증가 = 하행(true)', () {
      final segment = makeSegment(lineId: '3', stationIds: ['301', '305']);
      expect(isDownDirection(segment), isTrue);
    });

    test('ID 감소 = 상행(false)', () {
      final segment = makeSegment(lineId: '3', stationIds: ['305', '301']);
      expect(isDownDirection(segment), isFalse);
    });

    test('알파벳 접두사 역 ID도 숫자부분 비교', () {
      final segment = makeSegment(lineId: '경의중앙', stationIds: ['K10', 'K20']);
      expect(isDownDirection(segment), isTrue);
    });

    test('알파벳 접두사 역 ID 감소 = 상행', () {
      final segment = makeSegment(lineId: 'SB', stationIds: ['D10', 'D01']);
      expect(isDownDirection(segment), isFalse);
    });

    test('역이 1개뿐이면 false 반환', () {
      final segment = makeSegment(lineId: '3', stationIds: ['301']);
      expect(isDownDirection(segment), isFalse);
    });

    test('역이 비어있으면 false 반환', () {
      final segment = RouteSegment(
        lineId: '3',
        lineName: '테스트',
        stations: const [],
        durationSeconds: 0,
        direction: '테스트',
      );
      expect(isDownDirection(segment), isFalse);
    });
  });

  group('isDownDirection - 2호선 순환', () {
    test('내선(상행): ID 증가 방향 (201→202)', () {
      final segment = makeSegment(lineId: '2', stationIds: ['201', '202', '205']);
      expect(isDownDirection(segment), isFalse);
    });

    test('외선(하행): ID 감소 방향 (210→209)', () {
      final segment = makeSegment(lineId: '2', stationIds: ['210', '209', '205']);
      expect(isDownDirection(segment), isTrue);
    });

    test('순환 경계: 내선 243→201 (큰 감소 = 내선, 상행)', () {
      // 243에서 201로 가는 건 내선 방향 (step = 201-243 = -42, |step|>21 → 반전)
      final segment = makeSegment(lineId: '2', stationIds: ['243', '201', '202']);
      // step = 201 - 243 = -42, abs > 21, step < -21 → false (내선)
      expect(isDownDirection(segment), isFalse);
    });

    test('순환 경계: 외선 201→243 (큰 증가 = 외선, 하행)', () {
      // 201에서 243으로 가는 건 외선 방향 (step = 243-201 = 42, |step|>21 → 반전)
      final segment = makeSegment(lineId: '2', stationIds: ['201', '243', '242']);
      // step = 243 - 201 = 42, abs > 21, step > 21 → true (외선)
      expect(isDownDirection(segment), isTrue);
    });
  });

  group('isDownDirectionString', () {
    test('"하행"은 true', () {
      expect(isDownDirectionString('하행'), isTrue);
    });

    test('"외선"은 true', () {
      expect(isDownDirectionString('외선'), isTrue);
    });

    test('"상행"은 false', () {
      expect(isDownDirectionString('상행'), isFalse);
    });

    test('"내선"은 false', () {
      expect(isDownDirectionString('내선'), isFalse);
    });
  });
}
