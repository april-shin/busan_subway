// 2호선 성수지선 — API 라벨 반전이 **지도 방향 게이트에 배선됐는지** 지키는 가드.
//
// 순수함수 테스트(`line_direction_api_label_test.dart`)는 `isApiLabelReversedOnRoute`
// 의 반환값까지만 본다. 그 값이 `liveTrainsProvider` 의 방향 게이트에 실제로 꽂혀
// 있는지는 여기서만 깨진다.
//
// 배경(2026-10-28 실측): 지선에서 API 라벨이 앱 규칙과 정반대다.
//   내선 | 현재=용두 → 조회=신설동 | 행선=신설동   (앱: 246→250 증가 = 하행)
// 반전이 없으면 탈 방향 열차가 전부 탈락하고 반대 방향 열차가 통과한다.
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seoul_subway/domain/entities/arrival_info.dart';
import 'package:seoul_subway/domain/entities/connection.dart';
import 'package:seoul_subway/domain/entities/station.dart';
import 'package:seoul_subway/features/arrival_info/presentation/providers/arrival_providers.dart';
import 'package:seoul_subway/features/subway_map/presentation/providers/live_train_provider.dart';
import 'package:seoul_subway/features/subway_map/presentation/providers/subway_map_providers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<Station> stations;
  late List<Connection> connections;

  setUpAll(() async {
    stations = (jsonDecode(await rootBundle.loadString('assets/json/stations.json')) as List)
        .map((e) => Station.fromJson(e as Map<String, dynamic>))
        .toList();
    connections = (jsonDecode(await rootBundle.loadString('assets/json/connections.json')) as List)
        .map((e) => Connection.fromJson(e as Map<String, dynamic>))
        .toList();
  });

  Station stationOf(String name) =>
      stations.firstWhere((s) => s.name == name && s.lineId == '2');

  /// 신답에서 용두로 다가오는 지선 열차.
  ArrivalInfo arrival({required String direction, required String destination}) =>
      ArrivalInfo(
        subwayId: '1002',
        stationName: '용두',
        trainLineNm: '2호선',
        direction: direction,
        arrivalMessage: '신답 출발',
        destination: destination,
        trainType: '일반',
        arrivalSeconds: 120,
        receivedAt: DateTime.now(),
        trainNo: '2900',
        currentStationName: '신답',
      );

  /// 용두 → 신설동 (지선). 앱 규칙상 하행.
  ProviderContainer containerWith(List<ArrivalInfo> arrivals) {
    final container = ProviderContainer(overrides: [
      allStationsProvider.overrideWith((ref) async => stations),
      allConnectionsProvider.overrideWith((ref) async => connections),
      arrivalInfoProvider('용두').overrideWith((ref) async => arrivals),
    ]);
    addTearDown(container.dispose);

    container
        .read(selectedStationsProvider.notifier)
        .setBoth(stationOf('용두'), stationOf('신설동'));
    container.read(activeRouteFilterProvider.notifier).state = ActiveRouteFilter(
      lineId: '2',
      isDown: true, // isDownBetween('246','250','2')
      routeStationIds: [stationOf('용두').id, stationOf('신설동').id],
    );
    return container;
  }

  test('실측 라벨 "내선" 지선 열차를 그린다', () async {
    // 반전이 배선돼 있지 않으면 "내선"(=상행)이 하행 경로와 안 맞아 전부 탈락한다.
    final trains = await containerWith([
      arrival(direction: '내선', destination: '신설동'),
    ]).read(liveTrainsProvider.future);
    expect(trains.map((t) => t.trainNo), ['2900'],
        reason: '비어 있으면 라벨 반전이 지도 방향 게이트에 안 걸린 것');
  });

  test('반대 방향("외선") 열차는 그리지 않는다', () async {
    final trains = await containerWith([
      arrival(direction: '외선', destination: '성수'),
    ]).read(liveTrainsProvider.future);
    expect(trains, isEmpty);
  });

  group('분기역 성수(211) — 본선 열차를 지선 경로에 그리지 않는다', () {
    /// 성수 → 용답 (지선 방향). 성수는 본선 순환에도 쓰여 지선 집합에 넣을 수
    /// 없으므로, 경로 단위로 반전을 걸면 본선 "내선" 열차까지 통과한다.
    /// 2호선은 행선지 지선 필터가 꺼져 있고 `findPathOnLine` 은 hop 상한이 없어,
    /// 통과하면 순환을 한 바퀴 도는 경로가 잡혀 성수 반대편에 붙박여 그려진다.
    ProviderContainer branchRouteWith(List<ArrivalInfo> arrivals) {
      final container = ProviderContainer(overrides: [
        allStationsProvider.overrideWith((ref) async => stations),
        allConnectionsProvider.overrideWith((ref) async => connections),
        arrivalInfoProvider('성수').overrideWith((ref) async => arrivals),
      ]);
      addTearDown(container.dispose);
      container
          .read(selectedStationsProvider.notifier)
          .setBoth(stationOf('성수'), stationOf('용답'));
      container.read(activeRouteFilterProvider.notifier).state =
          ActiveRouteFilter(
        lineId: '2',
        isDown: true, // isDownBetween('211','244','2')
        routeStationIds: [stationOf('성수').id, stationOf('용답').id],
      );
      return container;
    }

    ArrivalInfo at(String current, String direction, String destination) =>
        ArrivalInfo(
          subwayId: '1002',
          stationName: '성수',
          trainLineNm: '2호선',
          direction: direction,
          arrivalMessage: '$current 출발',
          destination: destination,
          trainType: '일반',
          arrivalSeconds: 120,
          receivedAt: DateTime.now(),
          trainNo: '3266',
          currentStationName: current,
        );

    test('뚝섬에서 오는 본선 "내선" 열차는 그리지 않는다', () async {
      // 접근 쌍 뚝섬(210)→성수(211) 은 본선이라 반전 구간이 아니다.
      final trains = await branchRouteWith([at('뚝섬', '내선', '성수')])
          .read(liveTrainsProvider.future);
      expect(trains, isEmpty,
          reason: '그려지면 순환 42정거장 경로로 성수 반대편에 붙박인다');
    });

    test('강변에서 오는 본선 "외선" 열차도 그리지 않는다', () async {
      final trains = await branchRouteWith([at('강변', '외선', '성수')])
          .read(liveTrainsProvider.future);
      expect(trains, isEmpty);
    });
  });
}
