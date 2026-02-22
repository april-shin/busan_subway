import 'package:flutter_test/flutter_test.dart';
import 'package:seoul_subway/domain/entities/station.dart';
import 'package:seoul_subway/features/subway_map/presentation/widgets/subway_map_viewer.dart';

void main() {
  group('SubwayMapViewer', () {
    test('routeStationIds 기본값은 빈 Set이다', () {
      const viewer = SubwayMapViewer(
        stations: [],
        connections: [],
      );

      expect(viewer.routeStationIds, isEmpty);
    });

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
        routeStationIds: {'201'},
      );

      expect(viewer.stations, hasLength(1));
      expect(viewer.stations.first.name, '시청');
      expect(viewer.routeStationIds, contains('201'));
    });
  });
}
