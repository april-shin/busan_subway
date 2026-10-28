// 2호선 성수지선 — API 라벨 반전이 **출발 시각 후보 필터에 배선됐는지** 지키는 가드.
//
// 순수함수 테스트(`line_direction_api_label_test.dart`)는 `isApiLabelReversedOnRoute`
// 가 옳은 값을 돌려주는 것까지만 본다. 그 값이 실제로 `_getRealtimeDeparture` 의
// 라벨 비교에 꽂혀 있는지는 여기서만 깨진다 — `routeStationIds` 인자를 호출부에서
// 빼먹으면 조용히 종전 동작(기본값 `const []`)으로 되돌아간다.
//
// 배경: 성수지선은 앱 규칙(ID 증가 = 하행)과 API 라벨이 반대다(2026-10-28 실측).
// 반전이 없으면 **반대 방향 열차의 남은시간**이 출발 시각이 된다 — 시간표 폴백이
// 아니라 틀린 실시간 값이라 더 나쁘다.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seoul_subway/domain/entities/arrival_info.dart';
import 'package:seoul_subway/domain/entities/route_result.dart';
import 'package:seoul_subway/domain/entities/station.dart';
import 'package:seoul_subway/features/route_search/utils/departure_time_calculator.dart';

void main() {
  final now = DateTime(2026, 10, 28, 15, 0, 0); // 수요일

  const yongdu = Station(
      id: '246', name: '용두', lineId: '2', latitude: 37.57, longitude: 127.03);
  const sinseoldong = Station(
      id: '250', name: '신설동', lineId: '2', latitude: 37.57, longitude: 127.02);
  const sindap = Station(
      id: '245', name: '신답', lineId: '2', latitude: 37.57, longitude: 127.04);
  const seongsu = Station(
      id: '211', name: '성수', lineId: '2', latitude: 37.54, longitude: 127.05);
  const ttukseom = Station(
      id: '210', name: '뚝섬', lineId: '2', latitude: 37.54, longitude: 127.04);
  const yongdap = Station(
      id: '244', name: '용답', lineId: '2', latitude: 37.56, longitude: 127.05);

  /// 용두 → 신설동 (지선, 앱 규칙상 하행).
  final route = RouteResult(
    segments: [
      RouteSegment(
        lineId: '2',
        lineName: '2호선',
        stations: const [yongdu, sinseoldong],
        durationSeconds: 120,
        direction: '신설동 방면',
      ),
    ],
    totalTimeSeconds: 120,
    transferCount: 0,
    stationCount: 2,
  );

  /// 신답에서 용두로 다가오는 지선 열차.
  ArrivalInfo arrival({required String direction, required int seconds}) =>
      ArrivalInfo(
        subwayId: '1002',
        stationName: '용두',
        trainLineNm: '2호선',
        direction: direction,
        arrivalMessage: '신답 출발',
        destination: direction == '내선' ? '신설동' : '성수',
        trainType: '일반',
        arrivalSeconds: seconds,
        receivedAt: now,
        currentStationName: '신답',
      );

  DateTime departureWith(List<ArrivalInfo> arrivals) =>
      computeDepartureTimeDetailed(
        arrivalAsync: AsyncValue.data(arrivals),
        routeResult: route,
        now: now,
        stations: const [yongdu, sinseoldong, sindap, seongsu, ttukseom],
      ).departure;

  test('실측 라벨 "내선" 열차를 탑승 후보로 고른다', () {
    // 반전이 배선돼 있지 않으면 "내선"(=상행)이 하행 경로와 안 맞아 탈락하고,
    // 더 빠른 "외선" 열차(반대 방향)가 선택된다 → 60초.
    final d = departureWith([
      arrival(direction: '내선', seconds: 300),
      arrival(direction: '외선', seconds: 60),
    ]);
    expect(d.difference(now).inSeconds, 300,
        reason: '반대 방향(외선) 열차의 60초가 선택되면 라벨 반전이 안 걸린 것');
  });

  test('반대 방향(외선)만 있으면 실시간을 쓰지 않는다', () {
    final detailed = computeDepartureTimeDetailed(
      arrivalAsync: AsyncValue.data([arrival(direction: '외선', seconds: 60)]),
      routeResult: route,
      now: now,
    );
    expect(detailed.source, isNot(DepartureSource.realtime));
  });

  test('대조군: 본선 구간은 반전 없이 종전대로 — 내선이 상행이다', () {
    const siCheong = Station(
        id: '201', name: '시청', lineId: '2', latitude: 37.56, longitude: 126.97);
    const euljiro = Station(
        id: '202',
        name: '을지로입구',
        lineId: '2',
        latitude: 37.56,
        longitude: 126.98);
    // 201 → 202 는 ID 증가 = 내선/상행(isDown=false). "내선" 라벨이 그대로 맞는다.
    final mainLine = RouteResult(
      segments: [
        RouteSegment(
          lineId: '2',
          lineName: '2호선',
          stations: const [siCheong, euljiro],
          durationSeconds: 120,
          direction: '을지로입구 방면',
        ),
      ],
      totalTimeSeconds: 120,
      transferCount: 0,
      stationCount: 2,
    );
    final d = computeDepartureTimeDetailed(
      arrivalAsync: AsyncValue.data([
        ArrivalInfo(
          subwayId: '1002',
          stationName: '시청',
          trainLineNm: '2호선',
          direction: '내선',
          arrivalMessage: '곧 도착',
          destination: '성수',
          trainType: '일반',
          arrivalSeconds: 240,
          receivedAt: now,
        ),
      ]),
      routeResult: mainLine,
      now: now,
    ).departure;
    expect(d.difference(now).inSeconds, 240);
  });

  group('분기역 성수(211) — 본선 열차가 지선 출발시각으로 새지 않는다', () {
    // 성수는 본선 순환에도 쓰여 지선 집합에 넣을 수 없다. 그래서 경로 단위로
    // 반전을 걸면 본선 "내선" 열차까지 뒤집혀 후보가 되고, 본선이 훨씬 자주 와서
    // **거의 항상** 본선 열차가 "가장 빠른 열차" 로 뽑힌다 — 고치려던 증상이
    // 그대로 재현된다. 열차별 접근 쌍으로 걸러야 한다.
    final branchRoute = RouteResult(
      segments: [
        RouteSegment(
          lineId: '2',
          lineName: '2호선',
          stations: const [seongsu, yongdap],
          durationSeconds: 120,
          direction: '용답 방면',
        ),
      ],
      totalTimeSeconds: 120,
      transferCount: 0,
      stationCount: 2,
    );

    test('뚝섬에서 오는 본선 "내선" 열차는 후보가 아니다', () {
      final detailed = computeDepartureTimeDetailed(
        arrivalAsync: AsyncValue.data([
          ArrivalInfo(
            subwayId: '1002',
            stationName: '성수',
            trainLineNm: '2호선',
            direction: '내선',
            arrivalMessage: '뚝섬 출발',
            destination: '성수',
            trainType: '일반',
            arrivalSeconds: 60,
            receivedAt: now,
            currentStationName: '뚝섬', // 본선 — 접근 쌍 210→211 은 반전 구간이 아니다
          ),
        ]),
        routeResult: branchRoute,
        now: now,
        stations: const [yongdu, sinseoldong, sindap, seongsu, ttukseom, yongdap],
      );
      expect(detailed.source, isNot(DepartureSource.realtime),
          reason: '본선 열차의 60초가 지선 출발시각이 되면 과잉 반전이다');
    });
  });
}
