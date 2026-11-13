// 지도 실시간 열차의 유령(흐림) 표시 회귀 가드.
//
// 노선·방향이 같아도 탑승 구간을 완주하지 못하는 열차가 두 종류 있다:
//  - 지선 분기 — `천호 → 굽은다리` 경로의 5호선 하행 "마천행"(강동에서 갈라짐)
//  - 중간 종착 — 하차역 앞에서 운행을 끝내는 열차
//
// 정책: 둘 다 **지도에서 지우지 않고** `isGhost` 로 남긴다. 아이콘이 그려지는
// 구간(현재역 → 출발역)에서는 실제로 같은 선로를 달리기 때문이다 — 갈라지거나
// 멈추는 지점은 출발역 이후라 화면에 나오지 않는다. 완주하는 열차만 `isGhost`
// 가 false 여야 한다.
//
// (경로 결과의 출발 시각은 반대로 `full` 만 후보로 쓴다 —
// departure_branch_filter_test.dart 가 그쪽을 지킨다.)
@Skip('부산 전환: FeatureFlags.realtimeEnabled 가 const false 라 liveTrainsProvider 가 항상 빈 목록 — 플래그를 켤 때 부산 픽스처로 복원(로직 자체는 유지)')
library;

import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:busan_subway/domain/entities/arrival_info.dart';
import 'package:busan_subway/domain/entities/connection.dart';
import 'package:busan_subway/domain/entities/station.dart';
import 'package:busan_subway/features/arrival_info/presentation/providers/arrival_providers.dart';
import 'package:busan_subway/features/subway_map/presentation/providers/live_train_provider.dart';
import 'package:busan_subway/features/subway_map/presentation/providers/subway_map_providers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<Station> stations;
  late List<Connection> connections;

  setUpAll(() async {
    final stationsJson =
        await rootBundle.loadString('assets/json/stations.json');
    stations = (jsonDecode(stationsJson) as List)
        .map((e) => Station.fromJson(e as Map<String, dynamic>))
        .toList();

    final connectionsJson =
        await rootBundle.loadString('assets/json/connections.json');
    connections = (jsonDecode(connectionsJson) as List)
        .map((e) => Connection.fromJson(e as Map<String, dynamic>))
        .toList();
  });

  Station stationOf(String name, String lineId) => stations.firstWhere(
        (s) => s.name == name && s.lineId == lineId,
      );

  /// 천호로 접근 중인 5호선 하행 열차. 위치는 광나루(천호 직전)로 둬서
  /// 현재역 → 출발역 경로 탐색이 성공하게 한다.
  ArrivalInfo arrivalOf({
    required String destination,
    required String trainNo,
    int arrivalSeconds = 60,
  }) {
    return ArrivalInfo(
      subwayId: '1005', // 5호선
      stationName: '천호',
      trainLineNm: '$destination행',
      direction: '하행',
      arrivalMessage: '곧 도착',
      destination: destination,
      trainType: '일반',
      arrivalSeconds: arrivalSeconds,
      receivedAt: DateTime.now(),
      trainNo: trainNo,
      currentStationName: '광나루',
    );
  }

  /// `천호 → 굽은다리` 경로가 활성인 상태의 컨테이너.
  ProviderContainer containerWith(List<ArrivalInfo> arrivals) {
    final container = ProviderContainer(
      overrides: [
        allStationsProvider.overrideWith((ref) async => stations),
        allConnectionsProvider.overrideWith((ref) async => connections),
        arrivalInfoProvider('천호').overrideWith((ref) async => arrivals),
      ],
    );
    addTearDown(container.dispose);

    container.read(selectedStationsProvider.notifier).setBoth(
          stationOf('천호', '5'),
          stationOf('굽은다리', '5'),
        );
    container.read(activeRouteFilterProvider.notifier).state = ActiveRouteFilter(
      lineId: '5',
      isDown: true,
      routeStationIds: [
        for (final n in ['천호', '강동', '길동', '굽은다리']) stationOf(n, '5').id,
      ],
    );
    return container;
  }

  test('지선으로 갈라지는 마천행도 지우지 않고 유령으로 남긴다', () async {
    final container = containerWith([
      arrivalOf(destination: '마천', trainNo: '5001'),
      arrivalOf(destination: '하남검단산', trainNo: '5002', arrivalSeconds: 180),
    ]);

    final trains = await container.read(liveTrainsProvider.future);

    final macheon = trains.where((t) => t.trainNo == '5001');
    expect(macheon, hasLength(1), reason: '마천행이 지도에서 사라지면 안 된다');
    expect(macheon.single.isGhost, isTrue, reason: '완주하지 못하므로 흐리게');

    final hanam = trains.where((t) => t.trainNo == '5002');
    expect(hanam, hasLength(1));
    expect(hanam.single.isGhost, isFalse, reason: '굽은다리까지 완주하므로 실선');
  });

  test('행선지가 같은 열차가 여러 대여도 판정이 일관된다', () async {
    final container = containerWith([
      arrivalOf(destination: '마천', trainNo: '5001'),
      arrivalOf(destination: '마천', trainNo: '5003', arrivalSeconds: 300),
    ]);

    final trains = await container.read(liveTrainsProvider.future);

    expect(trains.map((t) => t.trainNo), containsAll(['5001', '5003']));
    expect(trains.every((t) => t.isGhost), isTrue);
  });

  test('2호선은 행선지가 하차역 앞이어도 유령으로 그리지 않는다', () async {
    // 강남 → 삼성(외선, ID 감소 방향). 행선지 "선릉" 은 하차역 앞이라 일반
    // 판정이면 중간 종착(유령)이지만, 2호선은 판정에서 제외한다.
    final container = ProviderContainer(
      overrides: [
        allStationsProvider.overrideWith((ref) async => stations),
        allConnectionsProvider.overrideWith((ref) async => connections),
        arrivalInfoProvider('강남').overrideWith(
          (ref) async => [
            ArrivalInfo(
              subwayId: '1002', // 2호선
              stationName: '강남',
              trainLineNm: '선릉행',
              direction: '외선',
              arrivalMessage: '곧 도착',
              destination: '선릉',
              trainType: '일반',
              arrivalSeconds: 60,
              receivedAt: DateTime.now(),
              trainNo: '2001',
              currentStationName: '교대',
            ),
          ],
        ),
      ],
    );
    addTearDown(container.dispose);

    container.read(selectedStationsProvider.notifier).setBoth(
          stationOf('강남', '2'),
          stationOf('삼성', '2'),
        );
    container.read(activeRouteFilterProvider.notifier).state = ActiveRouteFilter(
      lineId: '2',
      isDown: true,
      routeStationIds: [
        for (final n in ['강남', '역삼', '선릉', '삼성']) stationOf(n, '2').id,
      ],
    );

    final trains = await container.read(liveTrainsProvider.future);

    final train = trains.where((t) => t.trainNo == '2001');
    expect(train, hasLength(1), reason: '2호선 열차가 지도에서 사라지면 안 된다');
    expect(train.single.isGhost, isFalse, reason: '2호선은 유령 판정 제외');
  });
}
