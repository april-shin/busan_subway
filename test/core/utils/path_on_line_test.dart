import 'package:flutter_test/flutter_test.dart';
import 'package:busan_subway/core/utils/path_on_line.dart';
import 'package:busan_subway/domain/entities/connection.dart';
import 'package:busan_subway/domain/entities/station.dart';

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
    // initialProgress는 "currentStation → next 세그먼트 내 진행률"로 정의된다.
    // '진입' 상태는 실제로는 currentStation의 *이전* 세그먼트 끝이지만, 이 함수 구조에서는
    // 이전 세그먼트를 표현할 수 없어 currentStation 근사(0.0)로 반환한다.
    test('도착(1) → 0.0 (역에 정차 중)', () {
      expect(calculateInitialProgress(1, ''), 0.0);
    });

    test('출발(2) → 0.15 (역을 막 떠남)', () {
      expect(calculateInitialProgress(2, ''), 0.15);
    });

    test('진입(0) → 0.0 (currentStation 근사, 이전 세그먼트 끝 표현 불가)', () {
      expect(calculateInitialProgress(0, ''), 0.0);
    });

    test('전역출발(3) → 0.15 (이전역 출발)', () {
      expect(calculateInitialProgress(3, ''), 0.15);
    });

    test('전역진입(4) → 0.0 (currentStation 근사)', () {
      expect(calculateInitialProgress(4, ''), 0.0);
    });

    test('전역도착(5) → 0.0 (이전역 도착)', () {
      expect(calculateInitialProgress(5, ''), 0.0);
    });

    test('arvlCd null → positionStatus 폴백', () {
      expect(calculateInitialProgress(null, '출발'), 0.15);
      expect(calculateInitialProgress(null, '도착'), 0.0);
      // '진입' 은 arvlCd 0/4와 동일 근거(currentStation 근사)로 0.0 반환
      expect(calculateInitialProgress(null, '진입'), 0.0);
      expect(calculateInitialProgress(null, ''), 0.0);
    });

    test('arvlCd 99 → positionStatus 폴백', () {
      expect(calculateInitialProgress(99, '출발'), 0.15);
      expect(calculateInitialProgress(99, '진입'), 0.0);
      expect(calculateInitialProgress(99, '도착'), 0.0);
    });

    test('알 수 없는 arvlCd → 기본 0.0', () {
      expect(calculateInitialProgress(7, ''), 0.0);
    });
  });

  group('findPathOnLine - isDown 방향 제한 (선형 노선)', () {
    // 4역짜리 선형 노선: 201 - 202 - 203 - 204 (부산 규약: ID 증가 = 하행).
    // 모든 연결은 단일 노선(lineId='2')으로 구성해 양방향 엣지가 생기도록 한다.
    final lineStations = [
      const Station(
        id: '201', name: 'A', lineId: '2',
        latitude: 0, longitude: 0, svgX: 0, svgY: 0,
      ),
      const Station(
        id: '202', name: 'B', lineId: '2',
        latitude: 0, longitude: 0, svgX: 10, svgY: 0,
      ),
      const Station(
        id: '203', name: 'C', lineId: '2',
        latitude: 0, longitude: 0, svgX: 10, svgY: 10,
      ),
      const Station(
        id: '204', name: 'D', lineId: '2',
        latitude: 0, longitude: 0, svgX: 0, svgY: 10,
      ),
    ];

    final lineConnections = [
      const Connection(
        fromStationId: '201', toStationId: '202',
        lineId: '2', travelTimeSeconds: 60,
      ),
      const Connection(
        fromStationId: '202', toStationId: '203',
        lineId: '2', travelTimeSeconds: 70,
      ),
      const Connection(
        fromStationId: '203', toStationId: '204',
        lineId: '2', travelTimeSeconds: 80,
      ),
    ];

    PathWithDurations? find(String from, String to, {bool? isDown}) =>
        findPathOnLine(
          fromStationName: from,
          toStationName: to,
          lineId: '2',
          stations: lineStations,
          connections: lineConnections,
          isDown: isDown,
        );

    test('isDown=null (양방향): A→C 3역, 구간 시간 보존', () {
      final result = find('A', 'C');
      expect(result, isNotNull);
      expect(result!.points.length, 3);
      expect(result.durations, [60, 70]);
    });

    test('isDown=true (하행): A→D 는 ID 증가 방향이라 도달', () {
      final result = find('A', 'D', isDown: true);
      expect(result, isNotNull);
      expect(result!.points.length, 4);
      expect(result.durations, [60, 70, 80]);
    });

    test('isDown=false (상행): A→C 는 거슬러 갈 수 없어 null', () {
      expect(find('A', 'C', isDown: false), isNull);
    });

    test('isDown=false (상행): D→A 는 ID 감소 방향이라 도달', () {
      final result = find('D', 'A', isDown: false);
      expect(result, isNotNull);
      expect(result!.points.length, 4);
      expect(result.durations, [80, 70, 60]);
    });

    test('isDown=true (하행): D→A 는 거슬러 갈 수 없어 null — 순환 우회가 없다', () {
      expect(find('D', 'A', isDown: true), isNull);
    });

    test('isDown null vs 지정: 반대 방향 지정은 양방향이 찾은 경로를 못 찾는다', () {
      expect(find('D', 'A'), isNotNull);
      expect(find('D', 'A', isDown: true), isNull);
    });
  });
}
