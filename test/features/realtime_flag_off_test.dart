import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:busan_subway/app.dart';
import 'package:busan_subway/core/constants/feature_flags.dart';
import 'package:busan_subway/domain/entities/arrival_info.dart';
import 'package:busan_subway/domain/entities/station.dart';
import 'package:busan_subway/domain/repositories/arrival_repository.dart';
import 'package:busan_subway/features/arrival_info/presentation/providers/arrival_providers.dart';
import 'package:busan_subway/features/subway_map/presentation/providers/live_train_provider.dart';
import 'package:busan_subway/features/subway_map/presentation/providers/subway_map_providers.dart';

class _MockArrivalRepository extends Mock implements ArrivalRepository {}

/// 실시간 기능 플래그 off 상태(부산 전환 시점 기본값) 동작.
///
/// `FeatureFlags.realtimeEnabled` 는 const 라 테스트에서 켤 수 없다. 이 파일은
/// "꺼져 있을 때 API 를 전혀 부르지 않고 빈 결과/redirect 로 동작한다"를 잠근다.
/// 플래그를 true 로 바꾸면 첫 테스트가 먼저 깨져 이 파일과 skip 된 실시간 테스트를
/// 되살려야 한다는 신호가 된다.
void main() {
  late _MockArrivalRepository repo;

  setUp(() {
    repo = _MockArrivalRepository();
    when(() => repo.getArrivalInfo(any()))
        .thenAnswer((_) async => <ArrivalInfo>[]);
    when(() => repo.getTrainPositionArrivals(
          lineId: any(named: 'lineId'),
          targetStationName: any(named: 'targetStationName'),
          stations: any(named: 'stations'),
          connections: any(named: 'connections'),
        )).thenAnswer((_) async => <ArrivalInfo>[]);
  });

  ProviderContainer makeContainer() {
    final c = ProviderContainer(overrides: [
      arrivalRepositoryProvider.overrideWithValue(repo),
    ]);
    addTearDown(c.dispose);
    return c;
  }

  test('플래그는 꺼져 있다 (켜면 skip 된 실시간 테스트를 복원할 것)', () {
    expect(FeatureFlags.realtimeEnabled, isFalse);
  });

  test('arrivalInfoProvider 는 빈 목록을 주고 리포지토리를 부르지 않는다', () async {
    final c = makeContainer();
    final result = await c.read(arrivalInfoProvider('서면').future);
    expect(result, isEmpty);
    verifyNever(() => repo.getArrivalInfo(any()));
  });

  test('liveTrainsProvider 는 경로가 선택돼 있어도 빈 목록이고 API 를 부르지 않는다', () async {
    const seomyeon = Station(
        id: '119', name: '서면', lineId: '1', latitude: 0, longitude: 0);
    const bujeon = Station(
        id: '120', name: '부전', lineId: '1', latitude: 0, longitude: 0);
    final c = makeContainer();
    c.read(selectedStationsProvider.notifier).setBoth(seomyeon, bujeon);
    c.read(activeRouteFilterProvider.notifier).state = const ActiveRouteFilter(
      lineId: '1',
      isDown: true,
      routeStationIds: ['119', '120'],
    );

    final trains = await c.read(liveTrainsProvider.future);
    expect(trains, isEmpty);
    verifyNever(() => repo.getArrivalInfo(any()));
    verifyNever(() => repo.getTrainPositionArrivals(
          lineId: any(named: 'lineId'),
          targetStationName: any(named: 'targetStationName'),
          stations: any(named: 'stations'),
          connections: any(named: 'connections'),
        ));
  });

  testWidgets('/arrivals/:stationName 딥링크는 홈(/)으로 redirect 된다', (tester) async {
    late BuildContext ctx;
    await tester.pumpWidget(MaterialApp(
      home: Builder(builder: (context) {
        ctx = context;
        return const SizedBox();
      }),
    ));

    final matchList = await router.routeInformationParser
        .parseRouteInformationWithDependencies(
      RouteInformation(
        uri: Uri.parse('/arrivals/${Uri.encodeComponent('서면')}'),
        state: RouteInformationState<void>(type: NavigatingType.go),
      ),
      ctx,
    );
    expect(matchList.uri.path, '/');
  });
}
