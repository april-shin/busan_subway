import 'package:flutter_test/flutter_test.dart';
import 'package:busan_subway/domain/entities/route_result.dart';
import 'package:busan_subway/domain/entities/station.dart';
import 'package:busan_subway/domain/entities/transfer_guide.dart';

void main() {
  group('RouteResult', () {
    test('creates with required fields', () {
      const result = RouteResult(
        segments: [],
        totalTimeSeconds: 300,
        transferCount: 1,
        stationCount: 5,
      );

      expect(result.totalTimeSeconds, 300);
      expect(result.transferCount, 1);
      expect(result.stationCount, 5);
      expect(result.segments, isEmpty);
      expect(result.transferDurations, isEmpty);
      expect(result.transferGuides, isEmpty);
    });

    test('transferGuides 기본값은 빈 리스트', () {
      const result = RouteResult(
        segments: [],
        totalTimeSeconds: 0,
        transferCount: 0,
        stationCount: 0,
      );

      expect(result.transferGuides, isEmpty);
    });

    test('transferGuides 필드를 담은 객체 생성', () {
      const result = RouteResult(
        segments: [],
        totalTimeSeconds: 0,
        transferCount: 1,
        stationCount: 0,
        transferGuides: [TransferGuide(doorSide: DoorSide.left, car: 6, door: 3)],
      );

      expect(result.transferGuides.length, 1);
      expect(result.transferGuides.first?.doorSide, DoorSide.left);
    });

    test('copyWith creates modified copy', () {
      const result = RouteResult(
        segments: [],
        totalTimeSeconds: 300,
        transferCount: 1,
        stationCount: 5,
      );

      final modified = result.copyWith(totalTimeSeconds: 600);

      expect(modified.totalTimeSeconds, 600);
      expect(modified.transferCount, 1);
    });

  });

  group('RouteSegment', () {
    test('creates with station list', () {
      const segment = RouteSegment(
        lineId: '2',
        lineName: '2호선',
        stations: [
          Station(
            id: '201',
            name: '시청',
            lineId: '2',
            latitude: 37.56,
            longitude: 126.97,
          ),
          Station(
            id: '202',
            name: '을지로입구',
            lineId: '2',
            latitude: 37.56,
            longitude: 126.98,
          ),
        ],
        durationSeconds: 90,
        direction: '을지로입구 방면',
      );

      expect(segment.lineId, '2');
      expect(segment.stations.length, 2);
      expect(segment.durationSeconds, 90);
    });

    // 급행 세그먼트는 가상 노선(`{base}E`)의 skip edge 가중치로 만들어지므로
    // `durationSeconds` 자체가 급행 소요시간이다. 구 모델의 별도
    // `expressDurationSeconds` 필드는 2026-08 에 제거됐다.
    test('급행 세그먼트는 lineId 로만 구분되고 소요시간은 durationSeconds 하나', () {
      const segment = RouteSegment(
        lineId: '9E',
        lineName: '9호선',
        stations: [],
        durationSeconds: 90,
        direction: '중앙보훈병원 방면',
      );

      expect(segment.lineId, '9E');
      expect(segment.durationSeconds, 90);
    });
  });
}
