import 'package:flutter_test/flutter_test.dart';
import 'package:seoul_subway/core/utils/estimate_arrival_seconds.dart';
import 'package:seoul_subway/domain/entities/connection.dart';
import 'package:seoul_subway/domain/entities/station.dart';

void main() {
  // 테스트용 역 데이터: A → B → C (2호선)
  final stations = [
    const Station(
      id: '201', name: '역A', lineId: '2',
      latitude: 0, longitude: 0, svgX: 100, svgY: 100,
    ),
    const Station(
      id: '202', name: '역B', lineId: '2',
      latitude: 0, longitude: 0, svgX: 200, svgY: 200,
    ),
    const Station(
      id: '203', name: '역C', lineId: '2',
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

  group('estimateArrivalSeconds', () {
    test('정상 경로: 역A → 역C 전체 소요시간 합산', () {
      final result = estimateArrivalSeconds(
        currentStationName: '역A',
        targetStationName: '역C',
        lineId: '2',
        positionStatus: '도착',
        arrivalCode: 1,
        stations: stations,
        connections: connections,
      );

      // 도착(arrivalCode 1) → progress 0.0
      // 첫 세그먼트: 120 * (1.0 - 0.0) = 120
      // 둘째 세그먼트: 90
      // 합계: 210
      expect(result, 210);
    });

    test('진행률 보정: 출발 상태에서 첫 세그먼트 15% 감소', () {
      final result = estimateArrivalSeconds(
        currentStationName: '역A',
        targetStationName: '역C',
        lineId: '2',
        positionStatus: '출발',
        arrivalCode: 2,
        stations: stations,
        connections: connections,
      );

      // 출발(arrivalCode 2) → progress 0.15
      // 첫 세그먼트: 120 * (1.0 - 0.15) = 102
      // 둘째 세그먼트: 90
      // 합계: 192
      expect(result, 192);
    });

    test('진입 상태: 첫 세그먼트 85% 감소', () {
      final result = estimateArrivalSeconds(
        currentStationName: '역A',
        targetStationName: '역B',
        lineId: '2',
        positionStatus: '진입',
        arrivalCode: 0,
        stations: stations,
        connections: connections,
      );

      // 진입(arrivalCode 0) → progress 0.85
      // 단일 세그먼트: 120 * (1.0 - 0.85) = 18
      expect(result, 18);
    });

    test('같은 역이면 0 반환', () {
      final result = estimateArrivalSeconds(
        currentStationName: '역A',
        targetStationName: '역A',
        lineId: '2',
        positionStatus: '',
        arrivalCode: null,
        stations: stations,
        connections: connections,
      );

      expect(result, 0);
    });

    test('빈 역명이면 null 반환', () {
      final result = estimateArrivalSeconds(
        currentStationName: '',
        targetStationName: '역C',
        lineId: '2',
        positionStatus: '',
        arrivalCode: null,
        stations: stations,
        connections: connections,
      );

      expect(result, isNull);
    });

    test('경로를 찾을 수 없으면 null 반환', () {
      final result = estimateArrivalSeconds(
        currentStationName: '존재하지않는역',
        targetStationName: '역C',
        lineId: '2',
        positionStatus: '',
        arrivalCode: null,
        stations: stations,
        connections: connections,
      );

      expect(result, isNull);
    });

    test('다른 노선이면 null 반환', () {
      final result = estimateArrivalSeconds(
        currentStationName: '역A',
        targetStationName: '역C',
        lineId: '3',
        positionStatus: '',
        arrivalCode: null,
        stations: stations,
        connections: connections,
      );

      expect(result, isNull);
    });
  });
}
