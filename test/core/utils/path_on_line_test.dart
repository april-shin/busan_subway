import 'package:flutter_test/flutter_test.dart';
import 'package:seoul_subway/core/utils/path_on_line.dart';
import 'package:seoul_subway/domain/entities/connection.dart';
import 'package:seoul_subway/domain/entities/station.dart';

void main() {
  final stations = [
    const Station(
      id: '201', name: '강남', lineId: '2',
      latitude: 0, longitude: 0, svgX: 100, svgY: 100,
    ),
    const Station(
      id: '202', name: '역삼', lineId: '2',
      latitude: 0, longitude: 0, svgX: 200, svgY: 200,
    ),
    const Station(
      id: '203', name: '선릉', lineId: '2',
      latitude: 0, longitude: 0, svgX: 300, svgY: 300,
    ),
  ];

  final connections = [
    const Connection(
      fromStationId: '201', toStationId: '202',
      lineId: '2', travelTimeSeconds: 120,
    ),
    const Connection(
      fromStationId: '202', toStationId: '203',
      lineId: '2', travelTimeSeconds: 90,
    ),
  ];

  group('findPathOnLine', () {
    test('정상 경로 반환: 강남 → 선릉', () {
      final result = findPathOnLine(
        fromStationName: '강남',
        toStationName: '선릉',
        lineId: '2',
        stations: stations,
        connections: connections,
      );

      expect(result, isNotNull);
      expect(result!.points.length, 3);
      expect(result.durations, [120, 90]);
    });

    test('역방향 경로: 선릉 → 강남', () {
      final result = findPathOnLine(
        fromStationName: '선릉',
        toStationName: '강남',
        lineId: '2',
        stations: stations,
        connections: connections,
      );

      expect(result, isNotNull);
      expect(result!.points.length, 3);
      expect(result.durations, [90, 120]);
    });

    test('같은 역이면 단일 포인트', () {
      final result = findPathOnLine(
        fromStationName: '강남',
        toStationName: '강남',
        lineId: '2',
        stations: stations,
        connections: connections,
      );

      expect(result, isNotNull);
      expect(result!.points.length, 1);
      expect(result.durations, isEmpty);
    });

    test('존재하지 않는 역이면 null', () {
      final result = findPathOnLine(
        fromStationName: '없는역',
        toStationName: '선릉',
        lineId: '2',
        stations: stations,
        connections: connections,
      );

      expect(result, isNull);
    });

    test('다른 노선이면 null', () {
      final result = findPathOnLine(
        fromStationName: '강남',
        toStationName: '선릉',
        lineId: '3',
        stations: stations,
        connections: connections,
      );

      expect(result, isNull);
    });
  });

  group('bfs', () {
    test('직접 연결된 노드', () {
      final adjacency = {
        'A': ['B'],
        'B': ['A', 'C'],
        'C': ['B'],
      };

      expect(bfs('A', 'C', adjacency), ['A', 'B', 'C']);
    });

    test('같은 노드', () {
      expect(bfs('A', 'A', {}), ['A']);
    });

    test('경로 없음', () {
      final adjacency = {
        'A': ['B'],
        'B': ['A'],
        'C': ['D'],
        'D': ['C'],
      };

      expect(bfs('A', 'D', adjacency), isNull);
    });
  });

  group('calculateInitialProgress', () {
    test('도착(1) → 0.0', () {
      expect(calculateInitialProgress(1, ''), 0.0);
    });

    test('출발(2) → 0.15', () {
      expect(calculateInitialProgress(2, ''), 0.15);
    });

    test('진입(0) → 0.85', () {
      expect(calculateInitialProgress(0, ''), 0.85);
    });

    test('arvlCd null → positionStatus 폴백', () {
      expect(calculateInitialProgress(null, '출발'), 0.15);
      expect(calculateInitialProgress(null, '도착'), 0.0);
      expect(calculateInitialProgress(null, '진입'), 0.85);
      expect(calculateInitialProgress(null, ''), 0.0);
    });

    test('arvlCd 99 → positionStatus 폴백', () {
      expect(calculateInitialProgress(99, '출발'), 0.15);
    });
  });
}
