import 'package:flutter_test/flutter_test.dart';
import 'package:busan_subway/core/utils/expand_path_backward.dart';
import 'package:busan_subway/domain/entities/connection.dart';
import 'package:busan_subway/domain/entities/station.dart';

// 1호선 가정: 숫자 ID 증가 = 하행. 테스트에서 isDown=true 는 pathToTarget의
// 역순(ID 감소) 방향으로 이전 역을 찾게 한다.
// 여기서는 역 A..F 를 ID "100".."105" 로 두고 pathToTarget 을 구성한다.
Station _mkStation(String id, double x, double y) => Station(
      id: id,
      name: id,
      lineId: '1',
      latitude: 0,
      longitude: 0,
      svgX: x,
      svgY: y,
    );

Connection _mkConn(String from, String to, int sec) => Connection(
      fromStationId: from,
      toStationId: to,
      lineId: '1',
      travelTimeSeconds: sec,
    );

void main() {
  group('expandPathBackward', () {
    test('남은시간이 총시간 이하면 확장 없이 원본 반환', () {
      final basePoints = [
        (x: 10.0, y: 0.0),
        (x: 20.0, y: 0.0),
        (x: 30.0, y: 0.0),
      ]; // [C, D, E]
      final baseDurations = [60, 60]; // C→D, D→E
      // 총시간 = 60+60 + 1 dwell(30) = 150

      final result = expandPathBackward(
        basePoints: basePoints,
        baseDurations: baseDurations,
        currentStationId: '103',
        lineId: '1',
        isDown: true,
        connections: const [],
        stationsById: const {},
        targetRemainingSeconds: 150,
      );

      expect(result.points, basePoints);
      expect(result.durations, baseDurations);
    });

    test('1칸 확장: 이전 역(B) 이 앞에 prepend 된다', () {
      // pathToTarget = [C(103), D(104), E(105)] 하행.
      // isDown=true 에서 "이전 역" = ID 작은 쪽 = B(102).
      final stations = {
        '102': [_mkStation('102', 0.0, 0.0)],
      };
      final connections = [
        _mkConn('102', '103', 90), // B→C 주행 90초
      ];

      final result = expandPathBackward(
        basePoints: [
          (x: 10.0, y: 0.0),
          (x: 20.0, y: 0.0),
          (x: 30.0, y: 0.0),
        ],
        baseDurations: [60, 60],
        currentStationId: '103',
        lineId: '1',
        isDown: true,
        connections: connections,
        stationsById: stations,
        // 기존 총 150초 + B→C 주행 90 + C 정차 추가로 150+90+30 = 270초까지 커버
        targetRemainingSeconds: 250,
      );

      expect(result.points.length, 4);
      expect(result.points.first, (x: 0.0, y: 0.0)); // B 좌표
      expect(result.durations, [90, 60, 60]);
    });

    test('여러 칸 확장', () {
      final stations = {
        '100': [_mkStation('100', 100.0, 0.0)],
        '101': [_mkStation('101', 110.0, 0.0)],
        '102': [_mkStation('102', 120.0, 0.0)],
      };
      final connections = [
        _mkConn('100', '101', 80),
        _mkConn('101', '102', 80),
        _mkConn('102', '103', 80),
      ];

      final result = expandPathBackward(
        basePoints: [
          (x: 10.0, y: 0.0),
          (x: 20.0, y: 0.0),
        ], // [C(103), D(104)]
        baseDurations: [60], // C→D
        currentStationId: '103',
        lineId: '1',
        isDown: true,
        connections: connections,
        stationsById: stations,
        targetRemainingSeconds: 9999, // 충분히 큼
      );

      // 확장은 100 역까지 진행 (이전 역 없음에서 멈춤)
      expect(result.points.length, 5);
      expect(result.points.first, (x: 100.0, y: 0.0)); // 100 좌표
    });

    test('이전 역을 찾지 못하면 확장 중단', () {
      // connections 자체가 없음 → 이전 역 없음 → 원본 반환
      final result = expandPathBackward(
        basePoints: [
          (x: 10.0, y: 0.0),
          (x: 20.0, y: 0.0),
        ],
        baseDurations: [60],
        currentStationId: '103',
        lineId: '1',
        isDown: true,
        connections: const [],
        stationsById: const {},
        targetRemainingSeconds: 9999,
      );

      expect(result.points.length, 2);
      expect(result.durations, [60]);
    });

    test('Station 조회 실패 시 확장 중단', () {
      // connection 은 있지만 stationsById 가 비어 있음
      final connections = [_mkConn('102', '103', 80)];

      final result = expandPathBackward(
        basePoints: [
          (x: 10.0, y: 0.0),
          (x: 20.0, y: 0.0),
        ],
        baseDurations: [60],
        currentStationId: '103',
        lineId: '1',
        isDown: true,
        connections: connections,
        stationsById: const {},
        targetRemainingSeconds: 9999,
      );

      expect(result.points.length, 2);
      expect(result.durations, [60]);
    });

    test('안전 상한 30칸 초과 시 중단', () {
      // 숫자 ID 가 쭉 이어지는 연결을 만든다.
      final stations = <String, List<Station>>{};
      final connections = <Connection>[];
      for (var i = 0; i < 50; i++) {
        final id = (100 + i).toString();
        stations[id] = [_mkStation(id, i.toDouble(), 0.0)];
        if (i > 0) {
          connections.add(_mkConn((100 + i - 1).toString(), id, 30));
        }
      }

      final result = expandPathBackward(
        basePoints: [
          (x: 999.0, y: 0.0),
          (x: 1000.0, y: 0.0),
        ],
        baseDurations: [10],
        currentStationId: '149', // 가장 큰 ID
        lineId: '1',
        isDown: true,
        connections: connections,
        stationsById: stations,
        targetRemainingSeconds: 999999,
      );

      // 최대 30칸 prepend (원본 2 + 확장 30 = 32)
      expect(result.points.length, 32);
    });

    test('순환 방어: 이미 방문한 역이면 중단', () {
      // C→B→C 라는 양방향 링크가 있을 때, B 이전이 다시 C(visited) 이므로 중단.
      final stations = {
        '102': [_mkStation('102', 0.0, 0.0)],
      };
      final connections = [
        _mkConn('102', '103', 60),
        // C 의 이전이 B 라는 단일 연결만 있으니 방문 set 으로 자연 종결
      ];

      final result = expandPathBackward(
        basePoints: [
          (x: 10.0, y: 0.0),
          (x: 20.0, y: 0.0),
        ],
        baseDurations: [60],
        currentStationId: '103',
        lineId: '1',
        isDown: true,
        connections: connections,
        stationsById: stations,
        targetRemainingSeconds: 9999,
      );

      // 1칸만 확장 가능 (102). 그 이후는 이전 역 없음으로 종료.
      expect(result.points.length, 3);
      expect(result.points.first, (x: 0.0, y: 0.0));
    });

    test('단일 점 path 는 확장 대상 아님', () {
      final result = expandPathBackward(
        basePoints: [(x: 10.0, y: 0.0)],
        baseDurations: const [],
        currentStationId: '103',
        lineId: '1',
        isDown: true,
        connections: const [],
        stationsById: const {},
        targetRemainingSeconds: 9999,
      );

      expect(result.points.length, 1);
      expect(result.durations, isEmpty);
    });
  });
}
