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

  group('isDownDirection - 4호선', () {
    test('본선 내부: ID 증가 = 하행(오이도 방향)', () {
      // 당고개(402) → 창동(406)
      final segment = makeSegment(lineId: '4', stationIds: ['402', '406']);
      expect(isDownDirection(segment), isTrue);
    });

    test('본선 내부: ID 감소 = 상행(진접 방향)', () {
      // 창동(406) → 당고개(402)
      final segment = makeSegment(lineId: '4', stationIds: ['406', '402']);
      expect(isDownDirection(segment), isFalse);
    });

    test('진접선 내부: ID 증가 = 하행(남쪽, 오이도 방향)', () {
      // 진접(449) → 오남(450): 남쪽 이동 = 하행
      final segment = makeSegment(lineId: '4', stationIds: ['449', '450']);
      expect(isDownDirection(segment), isTrue);
    });

    test('진접선 내부: ID 감소 = 상행(북쪽, 진접 방향)', () {
      // 오남(450) → 진접(449): 북쪽 이동 = 상행
      final segment = makeSegment(lineId: '4', stationIds: ['450', '449']);
      expect(isDownDirection(segment), isFalse);
    });

    test('진접선 → 본선: 하행(남쪽, 오이도 방향)', () {
      // 불암산(452) → 상계(402): ID 감소하지만 남쪽 이동 = 하행
      final segment = makeSegment(lineId: '4', stationIds: ['452', '402']);
      expect(isDownDirection(segment), isTrue);
    });

    test('본선 → 진접선: 상행(북쪽, 진접 방향)', () {
      // 상계(402) → 불암산(452): ID 증가하지만 북쪽 이동 = 상행
      final segment = makeSegment(lineId: '4', stationIds: ['402', '452']);
      expect(isDownDirection(segment), isFalse);
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
