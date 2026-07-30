// "0초"와 "알 수 없음"의 구분 회귀 가드.
//
// 배경(2026-07-30 실측): GTX-A 는 `barvlDt` 를 단 한 건도 주지 않고(0/14),
// `recptnDt` 가 최대 817초 지연되며, 종착역(운정중앙·서울역·수서·동탄)에서는
// API 가 "그 역에 있는 열차"만 보고해 `arvlMsg3` == 조회역이 3/3 이 된다.
// 세 조건이 겹쳐 도착정보가 전 건 "0초"로 표시됐다. 서해선 대곡(지연 777초)도 동일.
//
// 근본 원인은 파이프라인이 "모르는 값"을 0 으로 뭉갠 것이었다:
//   (1) 현재역 == 조회역이면 arvlCd 무시하고 0 (이미 출발한 열차까지 0초)
//   (2) 추정값 − 경과시간 이 음수면 0 으로 클램프
// 이제 세 상태를 구분한다 — 양수: 잔여초 / 0: "역에 있음" 상태 / null: 알 수 없음.
import 'package:flutter_test/flutter_test.dart';
import 'package:seoul_subway/core/utils/enrich_arrival_info.dart';
import 'package:seoul_subway/core/utils/estimate_arrival_seconds.dart';
import 'package:seoul_subway/domain/entities/arrival_info.dart';
import 'package:seoul_subway/domain/entities/connection.dart';
import 'package:seoul_subway/domain/entities/station.dart';

void main() {
  // GTX-A 남부 구간 일부 (수서 → 성남 → 구성 → 동탄), 구간 300초.
  final stations = [
    const Station(
      id: 'G06',
      name: '수서',
      lineId: 'GTX-A',
      latitude: 37.4873,
      longitude: 127.1017,
      svgX: 2048,
      svgY: 1200,
    ),
    const Station(
      id: 'G07',
      name: '성남',
      lineId: 'GTX-A',
      latitude: 37.42,
      longitude: 127.126,
      svgX: 1836,
      svgY: 1248,
    ),
    const Station(
      id: 'G08',
      name: '구성',
      lineId: 'GTX-A',
      latitude: 37.2994,
      longitude: 127.0956,
      svgX: 1500,
      svgY: 1368,
    ),
  ];
  final connections = [
    const Connection(
      fromStationId: 'G06',
      toStationId: 'G07',
      lineId: 'GTX-A',
      travelTimeSeconds: 300,
    ),
    const Connection(
      fromStationId: 'G07',
      toStationId: 'G08',
      lineId: 'GTX-A',
      travelTimeSeconds: 300,
    ),
  ];

  ArrivalInfo gtxArrival({
    required String currentStationName,
    required String positionStatus,
    required int? arrivalCode,
    required int lagSeconds,
    int? arrivalSeconds,
    String arrivalMessage = '',
  }) =>
      ArrivalInfo(
        subwayId: '1032',
        stationName: '수서',
        trainLineNm: '동탄행 - 성남방면',
        direction: '하행',
        arrivalMessage: arrivalMessage,
        destination: '동탄',
        trainType: '일반',
        arrivalSeconds: arrivalSeconds,
        receivedAt: DateTime.now().subtract(Duration(seconds: lagSeconds)),
        currentStationName: currentStationName,
        positionStatus: positionStatus,
        arrivalCode: arrivalCode,
        trainNo: '0101',
      );

  group('estimateArrivalSeconds: 현재역 == 조회역', () {
    int? estimate({required int? arrivalCode, String positionStatus = ''}) =>
        estimateArrivalSeconds(
          currentStationName: '수서',
          targetStationName: '수서',
          lineId: 'GTX-A',
          positionStatus: positionStatus,
          arrivalCode: arrivalCode,
          stations: stations,
          connections: connections,
        );

    test('도착(1)·진입(0)·전역진입(4)·전역도착(5)은 0 — "역에 있음" 상태', () {
      for (final code in [1, 0, 4, 5]) {
        expect(estimate(arrivalCode: code), 0, reason: 'arvlCd=$code');
      }
    });

    test('출발(2)·전역출발(3)은 null — 조회역을 이미 떠난 열차', () {
      for (final code in [2, 3]) {
        expect(estimate(arrivalCode: code), isNull, reason: 'arvlCd=$code');
      }
    });

    test('코드 없음/99 는 positionStatus 로 판단 (출발만 null)', () {
      expect(estimate(arrivalCode: null, positionStatus: '출발'), isNull);
      expect(estimate(arrivalCode: 99, positionStatus: '출발'), isNull);
      expect(estimate(arrivalCode: null, positionStatus: '도착'), 0);
      // 정보가 전혀 없으면 기존 동작(0) 유지 — 다른 노선 회귀 방지.
      expect(estimate(arrivalCode: null, positionStatus: ''), 0);
    });
  });

  group('enrichArrivalInfoList: 0 과 null 구분', () {
    List<ArrivalInfo> enrich(ArrivalInfo a) => enrichArrivalInfoList(
          arrivals: [a],
          targetStationName: '수서',
          stations: stations,
          connections: connections,
        );

    test('추정값이 경과시간보다 작으면 0 이 아니라 알 수 없음', () {
      // 구성 → 수서: 추정 약 600초. recptnDt 지연 900초 → 만료.
      final result = enrich(gtxArrival(
        currentStationName: '구성',
        positionStatus: '',
        arrivalCode: 5,
        lagSeconds: 900,
        arrivalMessage: '전역 도착',
      ));

      expect(result[0].arrivalSeconds, isNull);
      expect(result[0].isEstimated, false);
    });

    test('추정값이 경과시간보다 크면 잔여초가 남는다', () {
      final result = enrich(gtxArrival(
        currentStationName: '구성',
        positionStatus: '',
        arrivalCode: 5,
        lagSeconds: 60,
        arrivalMessage: '전역 도착',
      ));

      expect(result[0].arrivalSeconds, isNotNull);
      expect(result[0].arrivalSeconds! > 0, true);
      expect(result[0].isEstimated, true);
    });

    test('"역에 있음"(추정 0)은 기준 시각을 보존해 통과 — 표시 단계가 신선도 판단', () {
      final arrival = gtxArrival(
        currentStationName: '수서',
        positionStatus: '',
        arrivalCode: 0, // 진입
        lagSeconds: 500,
        arrivalMessage: '수서 진입',
      );
      final result = enrich(arrival);

      expect(result[0].arrivalSeconds, 0);
      // 0 은 카운트다운이 아니므로 receivedAt 을 now 로 갱신하지 않는다.
      expect(result[0].receivedAt, arrival.receivedAt);
    });

    test('출발한 열차는 0초를 만들지 않는다 (GTX 종착역 전 건 0초 회귀)', () {
      final result = enrich(gtxArrival(
        currentStationName: '수서',
        positionStatus: '',
        arrivalCode: 2, // 수서 출발 — 이미 떠났다
        lagSeconds: 428,
        arrivalMessage: '수서 출발',
      ));

      expect(result[0].arrivalSeconds, isNull);
    });

    test('API 제공값(arrivalSeconds != null)은 그대로 통과', () {
      final result = enrich(gtxArrival(
        currentStationName: '성남',
        positionStatus: '',
        arrivalCode: 99,
        lagSeconds: 10,
        arrivalSeconds: 240,
      ));

      expect(result[0].arrivalSeconds, 240);
      expect(result[0].isEstimated, false);
    });
  });
}
