import 'package:flutter_test/flutter_test.dart';
import 'package:busan_subway/domain/entities/station.dart';
import 'package:busan_subway/features/subway_map/presentation/providers/subway_map_providers.dart';
import 'package:busan_subway/features/subway_map/presentation/widgets/subway_map_viewer.dart';
import 'package:busan_subway/features/subway_map/presentation/widgets/svg_web_view.dart';

const _stationA = Station(
  id: '201',
  name: '시청',
  lineId: '2',
  latitude: 37.5,
  longitude: 126.9,
  svgX: 100,
  svgY: 200,
);
const _stationB = Station(
  id: '202',
  name: '을지로입구',
  lineId: '2',
  latitude: 37.56,
  longitude: 126.98,
  svgX: 300,
  svgY: 400,
);

void main() {
  group('SvgWebView.shouldPanToDeparture (출발역 선택 시 지도 포커싱)', () {
    test('출발역만 새로 선택하면 포커싱한다', () {
      // (null, null) → (A, null)
      expect(
        SvgWebView.shouldPanToDeparture(
          const SelectedStations(),
          const SelectedStations(departure: _stationA),
        ),
        isTrue,
      );
    });

    test('같은 출발역을 다시 선택해도 재포커싱한다', () {
      // (A, null) → (A, null): 사용자가 지도를 움직인 뒤 같은 역 재선택
      expect(
        SvgWebView.shouldPanToDeparture(
          const SelectedStations(departure: _stationA),
          const SelectedStations(departure: _stationA),
        ),
        isTrue,
      );
    });

    test('출발역을 다른 역으로 바꾸면 포커싱한다', () {
      // (A, null) → (B, null)
      expect(
        SvgWebView.shouldPanToDeparture(
          const SelectedStations(departure: _stationA),
          const SelectedStations(departure: _stationB),
        ),
        isTrue,
      );
    });

    test('도착역까지 선택돼 경로가 완성되면 팬하지 않는다 (panTarget 파이프라인이 담당)', () {
      // (A, null) → (A, B)
      expect(
        SvgWebView.shouldPanToDeparture(
          const SelectedStations(departure: _stationA),
          const SelectedStations(departure: _stationA, arrival: _stationB),
        ),
        isFalse,
      );
    });

    test('도착역을 해제해도(출발역 유지) 재팬하지 않는다', () {
      // (A, B) → (A, null): 홈 화면 도착역 X 버튼
      expect(
        SvgWebView.shouldPanToDeparture(
          const SelectedStations(departure: _stationA, arrival: _stationB),
          const SelectedStations(departure: _stationA),
        ),
        isFalse,
      );
    });

    test('도착역만 선택된 상태에서는 팬하지 않는다', () {
      // (null, null) → (null, B)
      expect(
        SvgWebView.shouldPanToDeparture(
          const SelectedStations(),
          const SelectedStations(arrival: _stationB),
        ),
        isFalse,
      );
    });

    test('출발/도착 swap 시 팬하지 않는다 (arrival != null)', () {
      // (A, B) → (B, A)
      expect(
        SvgWebView.shouldPanToDeparture(
          const SelectedStations(departure: _stationA, arrival: _stationB),
          const SelectedStations(departure: _stationB, arrival: _stationA),
        ),
        isFalse,
      );
    });

    test('전체 해제 시 팬하지 않는다', () {
      // (A, B) → (null, null)
      expect(
        SvgWebView.shouldPanToDeparture(
          const SelectedStations(departure: _stationA, arrival: _stationB),
          const SelectedStations(),
        ),
        isFalse,
      );
    });

    test('prev 가 null 이어도(초기 리스너 발화) 출발역만 있으면 포커싱한다', () {
      expect(
        SvgWebView.shouldPanToDeparture(
          null,
          const SelectedStations(departure: _stationA),
        ),
        isTrue,
      );
    });
  });

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
