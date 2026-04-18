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

  group('findPathOnLine - isDown 방향 제한 (순환선)', () {
    // 4역짜리 가짜 순환선 구성:
    //  201 - 202 - 203 - 204 - 201 (순환)
    // 모든 연결은 단일 노선(lineId='2')으로 구성해 양방향 엣지가 생기도록 한다.
    //
    // 2호선 방향 로직(_isLine2DownBetween):
    //  step > 0 이고 |step|<=21 → 내선(false)
    //  step < 0 이고 |step|<=21 → 외선(true)
    // 따라서:
    //  201→202 step=1 → 내선(false)
    //  202→203 step=1 → 내선(false)
    //  203→204 step=1 → 내선(false)
    //  204→201 step=-3 → 외선(true)
    //  201→204 step=3 → 내선(false) (|step|<=21)
    //
    // 주의: 본 테스트는 가짜 4역 순환선이기 때문에 실제 2호선의 순환 경계(201↔243)
    // 로직(|step|>21)에는 영향을 받지 않는다. BFS의 방향 제한 동작만 검증한다.
    final cycleStations = [
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

    final cycleConnections = [
      const Connection(
        fromStationId: '201', toStationId: '202',
        lineId: '2', travelTimeSeconds: 60,
      ),
      const Connection(
        fromStationId: '202', toStationId: '203',
        lineId: '2', travelTimeSeconds: 60,
      ),
      const Connection(
        fromStationId: '203', toStationId: '204',
        lineId: '2', travelTimeSeconds: 60,
      ),
      const Connection(
        fromStationId: '204', toStationId: '201',
        lineId: '2', travelTimeSeconds: 60,
      ),
    ];

    test('isDown=null (양방향): A→C 최단경로 (3역)', () {
      final result = findPathOnLine(
        fromStationName: 'A',
        toStationName: 'C',
        lineId: '2',
        stations: cycleStations,
        connections: cycleConnections,
      );
      expect(result, isNotNull);
      // A(201) → B(202) → C(203) — 양방향 BFS는 최단경로 택함
      expect(result!.points.length, 3);
      expect(result.durations, [60, 60]);
    });

    test('isDown=false (내선 전용): A→C 경로는 내선으로 2홉', () {
      // 내선 엣지만 허용: 201→202, 202→203, 203→204 (모두 step=1, 내선)
      // 204→201 은 외선이므로 차단됨. A→C 최단: 201→202→203
      final result = findPathOnLine(
        fromStationName: 'A',
        toStationName: 'C',
        lineId: '2',
        stations: cycleStations,
        connections: cycleConnections,
        isDown: false,
      );
      expect(result, isNotNull);
      expect(result!.points.length, 3);
    });

    test('isDown=true (외선 전용): A→C는 외선 우회(4홉 필요)', () {
      // 외선 엣지만 허용: 204→201, 203→202, 202→201, 201→204(없음)
      // 방향 제한 규칙에 따라 각 connection은 방향에 부합하는 한쪽 엣지만 추가됨.
      //   201-202 (step=1 내선) → isDown=true이면 반대 엣지 즉 202→201만 등록
      //   202-203 (step=1 내선) → 203→202만 등록
      //   203-204 (step=1 내선) → 204→203만 등록
      //   204-201 (step=-3 외선) → 204→201만 등록
      // 따라서 외선 전용 인접 그래프: 202→201, 203→202, 204→203, 204→201
      // A(201) → C(203) 탐색 시 201에서 나가는 엣지가 없어 경로 없음 (null).
      final result = findPathOnLine(
        fromStationName: 'A',
        toStationName: 'C',
        lineId: '2',
        stations: cycleStations,
        connections: cycleConnections,
        isDown: true,
      );
      // A에서 외선 방향으로 나가는 엣지가 없으므로 C에 도달 불가
      expect(result, isNull);
    });

    test('isDown=true (외선): D→A는 외선으로 직접 도달', () {
      // 외선 인접: 204→201 존재. D(204)→A(201) 성공.
      final result = findPathOnLine(
        fromStationName: 'D',
        toStationName: 'A',
        lineId: '2',
        stations: cycleStations,
        connections: cycleConnections,
        isDown: true,
      );
      expect(result, isNotNull);
      expect(result!.points.length, 2);
      expect(result.durations, [60]);
    });

    test('isDown=false (내선): D→A는 내선으로 갈 수 없음', () {
      // 내선 인접: 201→202, 202→203, 203→204 (204→201은 외선이라 차단)
      // D(204)에서 내선으로 나가는 엣지가 없음 → 경로 없음
      final result = findPathOnLine(
        fromStationName: 'D',
        toStationName: 'A',
        lineId: '2',
        stations: cycleStations,
        connections: cycleConnections,
        isDown: false,
      );
      expect(result, isNull);
    });

    test('isDown null vs 지정: 같은 쌍에서 결과가 다를 수 있음', () {
      final bidirectional = findPathOnLine(
        fromStationName: 'D',
        toStationName: 'A',
        lineId: '2',
        stations: cycleStations,
        connections: cycleConnections,
      );
      final inner = findPathOnLine(
        fromStationName: 'D',
        toStationName: 'A',
        lineId: '2',
        stations: cycleStations,
        connections: cycleConnections,
        isDown: false,
      );
      // 양방향은 경로를 찾고, 내선 전용은 찾지 못함
      expect(bidirectional, isNotNull);
      expect(inner, isNull);
    });
  });
}
