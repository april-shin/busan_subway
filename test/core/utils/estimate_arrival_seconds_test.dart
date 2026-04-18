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

  group('estimateArrivalSeconds - 3순위: 경로 기반', () {
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
      // 정차시간: 중간역 1개(역B) × 30 = 30
      // 합계: 240
      expect(result, 240);
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
      // 정차시간: 중간역 1개 × 30 = 30
      // 합계: 222
      expect(result, 222);
    });

    test('진입 상태: currentStation 근사로 첫 세그먼트 전체 시간 반환', () {
      final result = estimateArrivalSeconds(
        currentStationName: '역A',
        targetStationName: '역B',
        lineId: '2',
        positionStatus: '진입',
        arrivalCode: 0,
        stations: stations,
        connections: connections,
      );

      // 진입(arrivalCode 0) → progress 0.0 (currentStation 근사)
      // 단일 세그먼트: 120 * (1.0 - 0.0) = 120
      // 근거: initialProgress는 currentStation→next 세그먼트 내 진행률이므로
      //      "진입"(실제로는 이전 세그먼트 끝) 상태를 표현할 수 없어 0.0 근사.
      expect(result, 120);
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

    test('경로를 찾을 수 없으면 null 반환 (arrivalMessage도 없음)', () {
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

    test('다른 노선이면 null 반환 (arrivalMessage도 없음)', () {
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

  group('estimateArrivalSeconds - 4순위: 역 수 × 평균 구간 소요시간', () {
    test('currentStationName 빈 + "2번째 전역 출발" → 역 수 기반 추정', () {
      final result = estimateArrivalSeconds(
        currentStationName: '',
        targetStationName: '역C',
        lineId: '2',
        positionStatus: '',
        arrivalCode: null,
        stations: stations,
        connections: connections,
        arrivalMessage: '2번째 전역 출발',
      );

      // 평균 구간: (120 + 90) / 2 = 105
      // 출발 → progress 0.15
      // 첫 세그먼트: 105 * (1.0 - 0.15) = 89 (반올림)
      // 둘째 세그먼트: 105
      // 정차시간: 중간역 1개 × 30 = 30
      // 합계: 89 + 105 + 30 = 224
      expect(result, isNotNull);
      final avgDuration = 105;
      final firstAdj = (avgDuration * (1.0 - 0.15)).round(); // 89
      final travelTime = firstAdj + avgDuration * (2 - 1); // 89 + 105 = 194
      final dwellTime = 1 * 30; // 중간역 1개
      final expected = travelTime + dwellTime; // 224
      expect(result, expected);
    });

    test('"전역 도착" → 1개 역 전, 도착 상태', () {
      final result = estimateArrivalSeconds(
        currentStationName: '',
        targetStationName: '역C',
        lineId: '2',
        positionStatus: '',
        arrivalCode: null,
        stations: stations,
        connections: connections,
        arrivalMessage: '전역 도착',
      );

      // 평균: 105, count: 1, 도착 → progress 0.0
      // 105 * 1.0 = 105
      expect(result, 105);
    });

    test('"전역 진입" → 1개 역 전, 진입 상태(progress 0.0 근사)', () {
      final result = estimateArrivalSeconds(
        currentStationName: '',
        targetStationName: '역C',
        lineId: '2',
        positionStatus: '',
        arrivalCode: null,
        stations: stations,
        connections: connections,
        arrivalMessage: '전역 진입',
      );

      // 평균: 105, count: 1, 진입 → progress 0.0 (currentStation 근사)
      // 105 * (1.0 - 0.0) = 105
      expect(result, 105);
    });

    test('3순위 실패 + arrivalMessage 없음 → null', () {
      final result = estimateArrivalSeconds(
        currentStationName: '',
        targetStationName: '역C',
        lineId: '2',
        positionStatus: '',
        arrivalCode: null,
        stations: stations,
        connections: connections,
        arrivalMessage: '',
      );

      expect(result, isNull);
    });

    test('3순위 실패 + 파싱 불가 arrivalMessage → null', () {
      final result = estimateArrivalSeconds(
        currentStationName: '',
        targetStationName: '역C',
        lineId: '2',
        positionStatus: '',
        arrivalCode: null,
        stations: stations,
        connections: connections,
        arrivalMessage: '곧 도착',
      );

      expect(result, isNull);
    });

    test('3순위 성공 시 4순위 미사용', () {
      final result = estimateArrivalSeconds(
        currentStationName: '역A',
        targetStationName: '역C',
        lineId: '2',
        positionStatus: '도착',
        arrivalCode: 1,
        stations: stations,
        connections: connections,
        arrivalMessage: '전역 출발',
      );

      // 3순위로 240이 나와야 하고 (210 + 정차시간 30), 4순위의 역 수 기반이 아님
      expect(result, 240);
    });

    test('해당 노선 연결이 없으면 기본값(120) 사용', () {
      final result = estimateArrivalSeconds(
        currentStationName: '',
        targetStationName: '역C',
        lineId: '99',
        positionStatus: '',
        arrivalCode: null,
        stations: stations,
        connections: connections,
        arrivalMessage: '전역 출발',
      );

      // 노선 99 연결 없음 → 기본값 120, count 1, 출발 → progress 0.15
      // 120 * (1.0 - 0.15) = 102
      expect(result, (120 * 0.85).round());
    });
  });
}
