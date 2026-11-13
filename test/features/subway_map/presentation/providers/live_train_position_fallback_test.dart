// 도착정보 API 가 해당 (역, 노선) 을 제공하지 않을 때 열차위치 API 로 폴백하는지 검증.
//
// 배경: 5호선 천호는 도착정보 API 에 엔트리 자체가 없다 — 등록명 `천호(풍납토성)`
// 로 조회하면 8호선만 응답하고, 전체역 일괄 조회(`.../ALL`)에도 `1005000547` 이
// 없다(2026-07-31 실측). 이 상태에서 `천호 → 굽은다리` 경로를 열면 지도에 열차가
// 한 대도 안 나왔다.
//
// 폴백 조건이 "도착정보 0건" 이 아니라 **"해당 노선 0건"** 인 것이 핵심이다.
// 천호는 8호선이 정상 응답하므로 전체 건수는 0 이 아니다.
@Skip('부산 전환: FeatureFlags.realtimeEnabled 가 const false 라 liveTrainsProvider 가 항상 빈 목록 — 플래그를 켤 때 부산 픽스처로 복원(로직 자체는 유지)')
library;

import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:busan_subway/domain/entities/arrival_info.dart';
import 'package:busan_subway/domain/entities/connection.dart';
import 'package:busan_subway/domain/entities/station.dart';
import 'package:busan_subway/domain/repositories/arrival_repository.dart';
import 'package:busan_subway/features/arrival_info/presentation/providers/arrival_providers.dart';
import 'package:busan_subway/features/subway_map/presentation/providers/live_train_provider.dart';
import 'package:busan_subway/features/subway_map/presentation/providers/subway_map_providers.dart';

class MockArrivalRepository extends Mock implements ArrivalRepository {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<Station> stations;
  late List<Connection> connections;

  setUpAll(() async {
    registerFallbackValue(<Station>[]);
    registerFallbackValue(<Connection>[]);
    stations = (jsonDecode(
      await rootBundle.loadString('assets/json/stations.json'),
    ) as List)
        .map((e) => Station.fromJson(e as Map<String, dynamic>))
        .toList();
    connections = (jsonDecode(
      await rootBundle.loadString('assets/json/connections.json'),
    ) as List)
        .map((e) => Connection.fromJson(e as Map<String, dynamic>))
        .toList();
  });

  Station stationOf(String name, String lineId) =>
      stations.firstWhere((s) => s.name == name && s.lineId == lineId);

  /// 8호선 천호 도착정보 — 실제 API 가 천호에서 돌려주는 것(5호선은 없음).
  ArrivalInfo line8Arrival() => ArrivalInfo(
        subwayId: '1008',
        stationName: '천호',
        trainLineNm: '별내행',
        direction: '하행',
        arrivalMessage: '전역 도착',
        destination: '별내',
        trainType: '일반',
        arrivalSeconds: 60,
        receivedAt: DateTime.now(),
        currentStationName: '강동구청',
        trainNo: '8001',
      );

  /// 5호선 도착정보 — 폴백이 걸리지 않아야 하는 경우의 대조군.
  ArrivalInfo line5Arrival() => ArrivalInfo(
        subwayId: '1005',
        stationName: '천호',
        trainLineNm: '하남검단산행',
        direction: '하행',
        arrivalMessage: '전역 도착',
        destination: '하남검단산',
        trainType: '일반',
        arrivalSeconds: 90,
        receivedAt: DateTime.now(),
        currentStationName: '광나루',
        trainNo: '5555',
      );

  /// 위치 API 폴백이 돌려주는 5호선 열차(잔여초는 추정값).
  ArrivalInfo positionFallbackArrival() => ArrivalInfo(
        subwayId: '1005',
        stationName: '천호',
        trainLineNm: '하남검단산행',
        direction: '하행',
        arrivalMessage: '',
        destination: '하남검단산',
        trainType: '일반',
        arrivalSeconds: 120,
        receivedAt: DateTime.now(),
        currentStationName: '광나루',
        trainNo: '5133',
        positionStatus: '도착',
        arrivalCode: 1,
        isEstimated: true,
      );

  ({ProviderContainer container, MockArrivalRepository repo}) setUpContainer({
    required List<ArrivalInfo> stationArrivals,
    List<ArrivalInfo> positionArrivals = const [],
  }) {
    final repo = MockArrivalRepository();
    when(() => repo.getTrainPositionArrivals(
          lineId: any(named: 'lineId'),
          targetStationName: any(named: 'targetStationName'),
          stations: any(named: 'stations'),
          connections: any(named: 'connections'),
        )).thenAnswer((_) async => positionArrivals);

    final container = ProviderContainer(
      overrides: [
        allStationsProvider.overrideWith((ref) async => stations),
        allConnectionsProvider.overrideWith((ref) async => connections),
        arrivalInfoProvider('천호').overrideWith((ref) async => stationArrivals),
        arrivalRepositoryProvider.overrideWithValue(repo),
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
    return (container: container, repo: repo);
  }

  test('해당 노선 도착정보가 없으면 위치 API 폴백으로 열차를 그린다', () async {
    final setup = setUpContainer(
      stationArrivals: [line8Arrival()], // 8호선만 옴 = 5호선 0건
      positionArrivals: [positionFallbackArrival()],
    );

    final trains = await setup.container.read(liveTrainsProvider.future);

    expect(trains.map((t) => t.trainNo), ['5133'],
        reason: '폴백 열차가 지도에 나와야 한다');
    expect(trains.single.lineId, '5');
    expect(trains.single.isGhost, isFalse, reason: '굽은다리까지 완주하는 열차');

    verify(() => setup.repo.getTrainPositionArrivals(
          lineId: '5',
          targetStationName: '천호',
          stations: any(named: 'stations'),
          connections: any(named: 'connections'),
        )).called(1);
  });

  test('도착정보에 해당 노선이 있으면 위치 API 를 호출하지 않는다', () async {
    // 15초마다 도는 프로바이더라 불필요한 호출은 일일 호출 한도를 깎는다.
    final setup = setUpContainer(
      stationArrivals: [line8Arrival(), line5Arrival()],
      positionArrivals: [positionFallbackArrival()],
    );

    final trains = await setup.container.read(liveTrainsProvider.future);

    expect(trains.map((t) => t.trainNo), ['5555'], reason: '도착정보 기반 열차');
    verifyNever(() => setup.repo.getTrainPositionArrivals(
          lineId: any(named: 'lineId'),
          targetStationName: any(named: 'targetStationName'),
          stations: any(named: 'stations'),
          connections: any(named: 'connections'),
        ));
  });

  test('폴백도 비어 있으면 열차 없이 조용히 끝난다', () async {
    final setup = setUpContainer(
      stationArrivals: [line8Arrival()],
      positionArrivals: const [],
    );

    final trains = await setup.container.read(liveTrainsProvider.future);
    expect(trains, isEmpty);
  });

  test('폴백 호출이 실패해도 예외를 올리지 않는다', () async {
    final repo = MockArrivalRepository();
    when(() => repo.getTrainPositionArrivals(
          lineId: any(named: 'lineId'),
          targetStationName: any(named: 'targetStationName'),
          stations: any(named: 'stations'),
          connections: any(named: 'connections'),
        )).thenThrow(Exception('네트워크 오류'));

    final container = ProviderContainer(
      overrides: [
        allStationsProvider.overrideWith((ref) async => stations),
        allConnectionsProvider.overrideWith((ref) async => connections),
        arrivalInfoProvider('천호')
            .overrideWith((ref) async => [line8Arrival()]),
        arrivalRepositoryProvider.overrideWithValue(repo),
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

    await expectLater(container.read(liveTrainsProvider.future), completes);
    expect(await container.read(liveTrainsProvider.future), isEmpty);
  });
}
