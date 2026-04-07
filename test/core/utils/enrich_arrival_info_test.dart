import 'package:flutter_test/flutter_test.dart';
import 'package:seoul_subway/core/utils/enrich_arrival_info.dart';
import 'package:seoul_subway/domain/entities/arrival_info.dart';
import 'package:seoul_subway/domain/entities/connection.dart';
import 'package:seoul_subway/domain/entities/station.dart';

void main() {
  // 테스트용 역 데이터: 강남 → 역삼 → 선릉 (2호선)
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

  group('enrichArrivalInfoList', () {
    test('arrivalSeconds가 null인 항목에 추정값을 채운다', () {
      final now = DateTime.now();
      final arrivals = [
        ArrivalInfo(
          subwayId: '1002',
          stationName: '선릉',
          trainLineNm: '2호선',
          direction: '상행',
          arrivalMessage: '역삼 도착',
          destination: '시청',
          trainType: '일반',
          arrivalSeconds: null,
          receivedAt: now,
          currentStationName: '역삼',
          positionStatus: '도착',
          arrivalCode: 1,
        ),
      ];

      final result = enrichArrivalInfoList(
        arrivals: arrivals,
        targetStationName: '선릉',
        stations: stations,
        connections: connections,
      );

      expect(result.length, 1);
      expect(result[0].arrivalSeconds, isNotNull);
      // 역삼 → 선릉: 90초 (도착 상태, progress 0.0) - 경과 시간(~0초) 차감
      expect(result[0].arrivalSeconds, closeTo(90, 2));
      expect(result[0].isEstimated, true);
    });

    test('arrivalSeconds가 이미 있는 항목은 변경하지 않는다', () {
      final now = DateTime.now();
      final arrivals = [
        ArrivalInfo(
          subwayId: '1002',
          stationName: '선릉',
          trainLineNm: '2호선',
          direction: '상행',
          arrivalMessage: '역삼 도착',
          destination: '시청',
          trainType: '일반',
          arrivalSeconds: 45,
          receivedAt: now,
          currentStationName: '역삼',
          positionStatus: '도착',
          arrivalCode: 1,
        ),
      ];

      final result = enrichArrivalInfoList(
        arrivals: arrivals,
        targetStationName: '선릉',
        stations: stations,
        connections: connections,
      );

      expect(result.length, 1);
      expect(result[0].arrivalSeconds, 45);
      expect(result[0].isEstimated, false);
    });

    test('경로를 찾을 수 없으면 원본 그대로 반환', () {
      final now = DateTime.now();
      final arrivals = [
        ArrivalInfo(
          subwayId: '1002',
          stationName: '선릉',
          trainLineNm: '2호선',
          direction: '상행',
          arrivalMessage: '먼역 도착',
          destination: '시청',
          trainType: '일반',
          arrivalSeconds: null,
          receivedAt: now,
          currentStationName: '존재하지않는역',
          positionStatus: '도착',
          arrivalCode: 1,
        ),
      ];

      final result = enrichArrivalInfoList(
        arrivals: arrivals,
        targetStationName: '선릉',
        stations: stations,
        connections: connections,
      );

      expect(result.length, 1);
      expect(result[0].arrivalSeconds, isNull);
      expect(result[0].isEstimated, false);
    });

    test('혼합 리스트: null과 non-null 항목이 섞여있을 때', () {
      final now = DateTime.now();
      final arrivals = [
        ArrivalInfo(
          subwayId: '1002',
          stationName: '선릉',
          trainLineNm: '2호선',
          direction: '상행',
          arrivalMessage: '강남 도착',
          destination: '시청',
          trainType: '일반',
          arrivalSeconds: null,
          receivedAt: now,
          currentStationName: '강남',
          positionStatus: '도착',
          arrivalCode: 1,
        ),
        ArrivalInfo(
          subwayId: '1002',
          stationName: '선릉',
          trainLineNm: '2호선',
          direction: '상행',
          arrivalMessage: '역삼 진입',
          destination: '시청',
          trainType: '일반',
          arrivalSeconds: 30,
          receivedAt: now,
          currentStationName: '역삼',
          positionStatus: '진입',
          arrivalCode: 0,
        ),
      ];

      final result = enrichArrivalInfoList(
        arrivals: arrivals,
        targetStationName: '선릉',
        stations: stations,
        connections: connections,
      );

      expect(result.length, 2);
      // 첫 번째: 강남 → 선릉, 도착(progress 0.0) = 120 + 90 = 210 - 경과(~0)
      expect(result[0].arrivalSeconds, closeTo(210, 2));
      expect(result[0].isEstimated, true);
      // 두 번째: 기존값 유지
      expect(result[1].arrivalSeconds, 30);
      expect(result[1].isEstimated, false);
    });

    test('receivedAt 보정: 추정 후 receivedAt이 현재 시각으로 갱신된다', () {
      final pastTime = DateTime.now().subtract(const Duration(seconds: 10));
      final arrivals = [
        ArrivalInfo(
          subwayId: '1002',
          stationName: '선릉',
          trainLineNm: '2호선',
          direction: '상행',
          arrivalMessage: '역삼 도착',
          destination: '시청',
          trainType: '일반',
          arrivalSeconds: null,
          receivedAt: pastTime,
          currentStationName: '역삼',
          positionStatus: '도착',
          arrivalCode: 1,
        ),
      ];

      final beforeEnrich = DateTime.now();
      final result = enrichArrivalInfoList(
        arrivals: arrivals,
        targetStationName: '선릉',
        stations: stations,
        connections: connections,
      );
      final afterEnrich = DateTime.now();

      expect(result[0].isEstimated, true);
      // receivedAt이 현재 시각으로 갱신되었는지 확인
      expect(
        result[0].receivedAt.isAfter(pastTime) ||
            result[0].receivedAt.isAtSameMomentAs(pastTime),
        true,
      );
      expect(
        result[0].receivedAt.isAfter(beforeEnrich) ||
            result[0].receivedAt.isAtSameMomentAs(beforeEnrich),
        true,
      );
      expect(
        result[0].receivedAt.isBefore(afterEnrich) ||
            result[0].receivedAt.isAtSameMomentAs(afterEnrich),
        true,
      );
    });

    test('receivedAt 보정: 경과 시간만큼 추정값이 감소한다', () {
      // 10초 전 receivedAt → 추정값에서 ~10초 차감
      final pastTime = DateTime.now().subtract(const Duration(seconds: 10));
      final arrivals = [
        ArrivalInfo(
          subwayId: '1002',
          stationName: '선릉',
          trainLineNm: '2호선',
          direction: '상행',
          arrivalMessage: '역삼 도착',
          destination: '시청',
          trainType: '일반',
          arrivalSeconds: null,
          receivedAt: pastTime,
          currentStationName: '역삼',
          positionStatus: '도착',
          arrivalCode: 1,
        ),
      ];

      final result = enrichArrivalInfoList(
        arrivals: arrivals,
        targetStationName: '선릉',
        stations: stations,
        connections: connections,
      );

      // 역삼 → 선릉 추정: 90초, 경과 ~10초 → ~80초
      expect(result[0].arrivalSeconds, isNotNull);
      expect(result[0].arrivalSeconds!, closeTo(80, 2));
    });

    test('previousArrivals: 동일 역 정보면 이전 추정값을 재사용한다', () {
      final estimatedAt = DateTime.now().subtract(const Duration(seconds: 5));
      final newReceivedAt = DateTime.now();

      // 이전 enriched 결과 (추정값 90초, 5초 전에 추정됨)
      final previousArrivals = [
        ArrivalInfo(
          subwayId: '1002',
          stationName: '선릉',
          trainLineNm: '2호선',
          direction: '상행',
          arrivalMessage: '역삼 도착',
          destination: '시청',
          trainType: '일반',
          arrivalSeconds: 90,
          receivedAt: estimatedAt,
          currentStationName: '역삼',
          positionStatus: '도착',
          arrivalCode: 1,
          trainNo: 'T001',
          isEstimated: true,
        ),
      ];

      // 새 API 응답 (같은 열차, 같은 역, recptnDt만 갱신됨)
      final arrivals = [
        ArrivalInfo(
          subwayId: '1002',
          stationName: '선릉',
          trainLineNm: '2호선',
          direction: '상행',
          arrivalMessage: '역삼 도착',
          destination: '시청',
          trainType: '일반',
          arrivalSeconds: null,
          receivedAt: newReceivedAt,
          currentStationName: '역삼',
          positionStatus: '도착',
          arrivalCode: 1,
          trainNo: 'T001',
        ),
      ];

      final result = enrichArrivalInfoList(
        arrivals: arrivals,
        targetStationName: '선릉',
        stations: stations,
        connections: connections,
        previousArrivals: previousArrivals,
      );

      expect(result[0].arrivalSeconds, 90);
      expect(result[0].isEstimated, true);
      // receivedAt이 이전 추정 시점을 유지해야 카운트다운이 이어짐
      expect(result[0].receivedAt, estimatedAt);
    });

    test('previousArrivals: 역 위치 변경 시 재추정한다', () {
      final estimatedAt = DateTime.now().subtract(const Duration(seconds: 30));
      final newReceivedAt = DateTime.now();

      final previousArrivals = [
        ArrivalInfo(
          subwayId: '1002',
          stationName: '선릉',
          trainLineNm: '2호선',
          direction: '상행',
          arrivalMessage: '강남 도착',
          destination: '시청',
          trainType: '일반',
          arrivalSeconds: 210,
          receivedAt: estimatedAt,
          currentStationName: '강남',
          positionStatus: '도착',
          arrivalCode: 1,
          trainNo: 'T001',
          isEstimated: true,
        ),
      ];

      // 같은 열차이지만 역이 바뀜 (강남 → 역삼)
      final arrivals = [
        ArrivalInfo(
          subwayId: '1002',
          stationName: '선릉',
          trainLineNm: '2호선',
          direction: '상행',
          arrivalMessage: '역삼 도착',
          destination: '시청',
          trainType: '일반',
          arrivalSeconds: null,
          receivedAt: newReceivedAt,
          currentStationName: '역삼',
          positionStatus: '도착',
          arrivalCode: 1,
          trainNo: 'T001',
        ),
      ];

      final result = enrichArrivalInfoList(
        arrivals: arrivals,
        targetStationName: '선릉',
        stations: stations,
        connections: connections,
        previousArrivals: previousArrivals,
      );

      // 역이 변경되었으므로 새로 추정 (역삼 → 선릉: 90초)
      expect(result[0].arrivalSeconds, closeTo(90, 2));
      expect(result[0].isEstimated, true);
      // receivedAt이 현재 시각으로 갱신됨
      expect(result[0].receivedAt.isAfter(estimatedAt), true);
    });

    test('previousArrivals: 빈 리스트면 기존 동작과 동일하다', () {
      final now = DateTime.now();
      final arrivals = [
        ArrivalInfo(
          subwayId: '1002',
          stationName: '선릉',
          trainLineNm: '2호선',
          direction: '상행',
          arrivalMessage: '역삼 도착',
          destination: '시청',
          trainType: '일반',
          arrivalSeconds: null,
          receivedAt: now,
          currentStationName: '역삼',
          positionStatus: '도착',
          arrivalCode: 1,
          trainNo: 'T001',
        ),
      ];

      final result = enrichArrivalInfoList(
        arrivals: arrivals,
        targetStationName: '선릉',
        stations: stations,
        connections: connections,
        previousArrivals: [],
      );

      expect(result[0].arrivalSeconds, closeTo(90, 2));
      expect(result[0].isEstimated, true);
    });

    test('previousArrivals: positionStatus 변경 시 재추정한다', () {
      final estimatedAt = DateTime.now().subtract(const Duration(seconds: 10));

      final previousArrivals = [
        ArrivalInfo(
          subwayId: '1002',
          stationName: '선릉',
          trainLineNm: '2호선',
          direction: '상행',
          arrivalMessage: '역삼 도착',
          destination: '시청',
          trainType: '일반',
          arrivalSeconds: 90,
          receivedAt: estimatedAt,
          currentStationName: '역삼',
          positionStatus: '도착',
          arrivalCode: 1,
          trainNo: 'T001',
          isEstimated: true,
        ),
      ];

      // 같은 역이지만 positionStatus 변경 (도착 → 출발)
      final arrivals = [
        ArrivalInfo(
          subwayId: '1002',
          stationName: '선릉',
          trainLineNm: '2호선',
          direction: '상행',
          arrivalMessage: '역삼 출발',
          destination: '시청',
          trainType: '일반',
          arrivalSeconds: null,
          receivedAt: DateTime.now(),
          currentStationName: '역삼',
          positionStatus: '출발',
          arrivalCode: 0,
          trainNo: 'T001',
        ),
      ];

      final result = enrichArrivalInfoList(
        arrivals: arrivals,
        targetStationName: '선릉',
        stations: stations,
        connections: connections,
        previousArrivals: previousArrivals,
      );

      // positionStatus 변경 → 재추정
      expect(result[0].isEstimated, true);
      // 출발 상태 → progress가 달라지므로 값이 다름
      expect(result[0].arrivalSeconds, isNotNull);
    });

    test('arrivalMessage로 4순위 폴백 동작 확인', () {
      final now = DateTime.now();
      final arrivals = [
        ArrivalInfo(
          subwayId: '1002',
          stationName: '선릉',
          trainLineNm: '2호선',
          direction: '상행',
          arrivalMessage: '전역 출발',
          destination: '시청',
          trainType: '일반',
          arrivalSeconds: null,
          receivedAt: now,
          currentStationName: '',
          positionStatus: '',
          arrivalCode: 99,
        ),
      ];

      final result = enrichArrivalInfoList(
        arrivals: arrivals,
        targetStationName: '선릉',
        stations: stations,
        connections: connections,
      );

      expect(result[0].arrivalSeconds, isNotNull);
      expect(result[0].isEstimated, true);
      // 평균 구간: (120 + 90) / 2 = 105
      // count=1, 출발 → progress 0.15
      // 105 * (1.0 - 0.15) = 89.25 → 89
      expect(result[0].arrivalSeconds, closeTo(89, 2));
    });
  });
}
