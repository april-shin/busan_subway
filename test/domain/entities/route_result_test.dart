import 'package:flutter_test/flutter_test.dart';
import 'package:seoul_subway/domain/entities/route_result.dart';
import 'package:seoul_subway/domain/entities/station.dart';

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
  });
}
