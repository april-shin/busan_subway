import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seoul_subway/domain/entities/station.dart';
import 'package:seoul_subway/features/route_search/presentation/providers/recent_search_provider.dart';
import 'package:seoul_subway/features/subway_map/presentation/providers/subway_map_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  const yeouido = Station(
    id: '517',
    name: '여의도',
    lineId: '5',
    latitude: 37.52,
    longitude: 126.92,
    isTransfer: true,
    transferLines: ['5', '9'],
  );
  const sportsComplex = Station(
    id: '930',
    name: '종합운동장',
    lineId: '9',
    latitude: 37.51,
    longitude: 127.07,
    isTransfer: true,
    transferLines: ['2', '9'],
  );
  final testStations = <Station>[yeouido, sportsComplex];

  ProviderContainer makeContainer() {
    final container = ProviderContainer(
      overrides: [
        allStationsProvider.overrideWith((ref) async => testStations),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  group('RecentSearch', () {
    test('저장된 값이 없으면 build 는 null 을 반환한다', () async {
      SharedPreferences.setMockInitialValues({});
      final container = makeContainer();

      final result = await container.read(recentSearchProvider.future);
      expect(result, isNull);
    });

    test('저장된 JSON 을 id 쌍으로 로드한다', () async {
      SharedPreferences.setMockInitialValues({
        'pref_recent_search': '{"d":"517","a":"930"}',
      });
      final container = makeContainer();

      final result = await container.read(recentSearchProvider.future);
      expect(result, isNotNull);
      expect(result!.departureId, '517');
      expect(result.arrivalId, '930');
    });

    test('손상된 JSON 은 null 로 처리한다', () async {
      SharedPreferences.setMockInitialValues({
        'pref_recent_search': 'not-a-json',
      });
      final container = makeContainer();

      final result = await container.read(recentSearchProvider.future);
      expect(result, isNull);
    });

    test('Map 이 아닌 JSON(배열)은 null 로 처리한다', () async {
      SharedPreferences.setMockInitialValues({
        'pref_recent_search': '[1,2]',
      });
      final container = makeContainer();

      final result = await container.read(recentSearchProvider.future);
      expect(result, isNull);
    });

    test('값 타입이 String 이 아니면 null 로 처리한다', () async {
      SharedPreferences.setMockInitialValues({
        'pref_recent_search': '{"d":1,"a":2}',
      });
      final container = makeContainer();

      final result = await container.read(recentSearchProvider.future);
      expect(result, isNull);
    });

    test('record 는 prefs 에 저장하고 state 를 갱신한다(라운드트립)', () async {
      SharedPreferences.setMockInitialValues({});
      final container = makeContainer();
      await container.read(recentSearchProvider.future); // 초기 build

      await container.read(recentSearchProvider.notifier).record('517', '930');

      // state 즉시 갱신
      final state = container.read(recentSearchProvider).value;
      expect(state, isNotNull);
      expect(state!.departureId, '517');
      expect(state.arrivalId, '930');

      // prefs 에 실제 저장돼 재로드 시 유지
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('pref_recent_search'), '{"d":"517","a":"930"}');
    });
  });

  group('recentSearchStations (resolve)', () {
    test('두 id 가 모두 존재하면 Station 쌍을 반환한다', () async {
      SharedPreferences.setMockInitialValues({
        'pref_recent_search': '{"d":"517","a":"930"}',
      });
      final container = makeContainer();

      final pair = await container.read(recentSearchStationsProvider.future);
      expect(pair, isNotNull);
      expect(pair!.departure.name, '여의도');
      expect(pair.arrival.name, '종합운동장');
    });

    test('id 중 하나라도 매칭되지 않으면 null 을 반환한다(삭제/개명된 역)',
        () async {
      SharedPreferences.setMockInitialValues({
        'pref_recent_search': '{"d":"517","a":"999"}',
      });
      final container = makeContainer();

      final pair = await container.read(recentSearchStationsProvider.future);
      expect(pair, isNull);
    });

    test('이력이 없으면 null 을 반환한다', () async {
      SharedPreferences.setMockInitialValues({});
      final container = makeContainer();

      final pair = await container.read(recentSearchStationsProvider.future);
      expect(pair, isNull);
    });
  });
}
