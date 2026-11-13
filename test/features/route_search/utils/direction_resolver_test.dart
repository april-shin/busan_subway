import 'package:flutter_test/flutter_test.dart';
import 'package:busan_subway/domain/entities/route_result.dart';
import 'package:busan_subway/domain/entities/station.dart';
import 'package:busan_subway/features/route_search/utils/direction_resolver.dart';

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

  group('isDownDirection - 부산 2호선·4호선 (선형, 예외 없음)', () {
    test('2호선: ID 증가 = 하행 (201→202→205)', () {
      final segment = makeSegment(lineId: '2', stationIds: ['201', '202', '205']);
      expect(isDownDirection(segment), isTrue);
    });

    test('2호선: ID 감소 = 상행 (210→209→205)', () {
      final segment = makeSegment(lineId: '2', stationIds: ['210', '209', '205']);
      expect(isDownDirection(segment), isFalse);
    });

    test('2호선: 양 끝 243→201 도 순환 반전 없이 상행', () {
      final segment = makeSegment(lineId: '2', stationIds: ['243', '201', '202']);
      expect(isDownDirection(segment), isFalse);
    });

    test('2호선: 201→243 은 하행', () {
      final segment = makeSegment(lineId: '2', stationIds: ['201', '243', '242']);
      expect(isDownDirection(segment), isTrue);
    });

    test('4호선: ID 증가 = 하행(안평 방향), 감소 = 상행(미남 방향)', () {
      expect(
          isDownDirection(makeSegment(lineId: '4', stationIds: ['401', '406'])),
          isTrue);
      expect(
          isDownDirection(makeSegment(lineId: '4', stationIds: ['406', '401'])),
          isFalse);
    });

    test('동해선·부산김해선도 ID 증가 = 하행', () {
      expect(
          isDownDirection(makeSegment(lineId: '동해', stationIds: ['801', '805'])),
          isTrue);
      expect(
          isDownDirection(
              makeSegment(lineId: '부산김해', stationIds: ['921', '901'])),
          isFalse);
    });
  });

  group('findFirstDirectionalSegment', () {
    test('역 2개 이상인 첫 세그먼트를 반환한다', () {
      final route = RouteResult(
        segments: [
          makeSegment(lineId: '2', stationIds: ['201', '202']),
        ],
        totalTimeSeconds: 120,
        transferCount: 0,
        stationCount: 2,
      );
      final result = findFirstDirectionalSegment(route);
      expect(result, isNotNull);
      expect(result!.lineId, '2');
    });

    test('첫 세그먼트가 1역이면 두 번째 세그먼트를 반환한다', () {
      final route = RouteResult(
        segments: [
          makeSegment(lineId: '2', stationIds: ['201']),
          makeSegment(lineId: '3', stationIds: ['330', '331']),
        ],
        totalTimeSeconds: 240,
        transferCount: 1,
        stationCount: 3,
      );
      final result = findFirstDirectionalSegment(route);
      expect(result, isNotNull);
      expect(result!.lineId, '3');
    });

    test('모든 세그먼트가 1역이면 null을 반환한다', () {
      final route = RouteResult(
        segments: [
          makeSegment(lineId: '2', stationIds: ['201']),
          makeSegment(lineId: '3', stationIds: ['330']),
        ],
        totalTimeSeconds: 240,
        transferCount: 1,
        stationCount: 2,
      );
      expect(findFirstDirectionalSegment(route), isNull);
    });

    test('segments가 비어있으면 null을 반환한다', () {
      const route = RouteResult(
        segments: [],
        totalTimeSeconds: 0,
        transferCount: 0,
        stationCount: 0,
      );
      expect(findFirstDirectionalSegment(route), isNull);
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
