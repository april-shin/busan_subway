import 'package:flutter_test/flutter_test.dart';
import 'package:seoul_subway/domain/entities/station.dart';
import 'package:seoul_subway/features/subway_map/presentation/widgets/subway_map_viewer.dart';

void main() {
  group('SubwayMapViewer', () {
    test('stations와 connections를 올바르게 전달받는다', () {
      const stations = [
        Station(
          id: '201',
          name: '시청',
          lineId: '2',
          latitude: 37.5,
          longitude: 126.9,
          svgX: 100,
          svgY: 200,
        ),
      ];

      const viewer = SubwayMapViewer(
        stations: stations,
        connections: [],
      );

      expect(viewer.stations, hasLength(1));
      expect(viewer.stations.first.name, '시청');
    });
  });
}
