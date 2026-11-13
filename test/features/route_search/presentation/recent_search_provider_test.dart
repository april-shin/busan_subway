import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:busan_subway/domain/entities/station.dart';
import 'package:busan_subway/features/route_search/presentation/providers/recent_search_provider.dart';
import 'package:busan_subway/features/subway_map/presentation/providers/subway_map_providers.dart';
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
  const jamsilSaenae = Station(
    id: '217',
    name: '잠실새내',
    lineId: '2',
    latitude: 37.51,
    longitude: 127.09,
  );
  // 여의도의 9호선 레코드 — 5호선 레코드(517)와 같은 물리 역.
  const yeouido9 = Station(
    id: '915',
    name: '여의도',
    lineId: '9',
    latitude: 37.52,
    longitude: 126.92,
    isTransfer: true,
    transferLines: ['5', '9'],
  );
  final testStations = <Station>[
    yeouido,
    sportsComplex,
    jamsilSaenae,
    yeouido9,
  ];

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
    test('저장된 값이 없으면 build 는 빈 목록을 반환한다', () async {
      SharedPreferences.setMockInitialValues({});
      final container = makeContainer();

      final result = await container.read(recentSearchProvider.future);
      expect(result, isEmpty);
    });

    test('저장된 JSON 배열을 id 쌍 목록으로 로드한다', () async {
      SharedPreferences.setMockInitialValues({
        'pref_recent_search': '[{"d":"517","a":"930"},{"d":"930","a":"217"}]',
      });
      final container = makeContainer();

      final result = await container.read(recentSearchProvider.future);
      expect(result, [
        (departureId: '517', arrivalId: '930'),
        (departureId: '930', arrivalId: '217'),
      ]);
    });

    test('1건만 저장하던 시절의 단일 객체도 1건으로 로드한다', () async {
      SharedPreferences.setMockInitialValues({
        'pref_recent_search': '{"d":"517","a":"930"}',
      });
      final container = makeContainer();

      final result = await container.read(recentSearchProvider.future);
      expect(result, [(departureId: '517', arrivalId: '930')]);
    });

    test('손상된 JSON 은 빈 목록으로 처리한다', () async {
      SharedPreferences.setMockInitialValues({
        'pref_recent_search': 'not-a-json',
      });
      final container = makeContainer();

      final result = await container.read(recentSearchProvider.future);
      expect(result, isEmpty);
    });

    test('형식이 맞지 않는 항목은 건너뛴다', () async {
      SharedPreferences.setMockInitialValues({
        'pref_recent_search': '[1,{"d":1,"a":2},{"d":"517","a":"930"}]',
      });
      final container = makeContainer();

      final result = await container.read(recentSearchProvider.future);
      expect(result, [(departureId: '517', arrivalId: '930')]);
    });

    test('저장된 목록에 같은 쌍이 여러 번 있으면 한 번만 로드한다', () async {
      SharedPreferences.setMockInitialValues({
        'pref_recent_search': '[{"d":"517","a":"930"},{"d":"517","a":"930"}]',
      });
      final container = makeContainer();

      final result = await container.read(recentSearchProvider.future);
      expect(result, [(departureId: '517', arrivalId: '930')]);
    });

    test('record 는 prefs 에 저장하고 state 를 갱신한다(라운드트립)', () async {
      SharedPreferences.setMockInitialValues({});
      final container = makeContainer();
      await container.read(recentSearchProvider.future); // 초기 build

      await container.read(recentSearchProvider.notifier).record('517', '930');

      // state 즉시 갱신
      expect(container.read(recentSearchProvider).value, [
        (departureId: '517', arrivalId: '930'),
      ]);

      // prefs 에 실제 저장돼 재로드 시 유지
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('pref_recent_search'), '[{"d":"517","a":"930"}]');
    });

    test('record 는 새 검색을 맨 앞에 쌓는다', () async {
      SharedPreferences.setMockInitialValues({});
      final container = makeContainer();
      final notifier = container.read(recentSearchProvider.notifier);

      await notifier.record('517', '930');
      await notifier.record('930', '217');
      await notifier.record('217', '517');

      expect(container.read(recentSearchProvider).value, [
        (departureId: '217', arrivalId: '517'),
        (departureId: '930', arrivalId: '217'),
        (departureId: '517', arrivalId: '930'),
      ]);
    });

    test('record 는 같은 쌍을 중복으로 쌓지 않고 맨 앞으로 옮긴다', () async {
      SharedPreferences.setMockInitialValues({});
      final container = makeContainer();
      final notifier = container.read(recentSearchProvider.notifier);

      await notifier.record('517', '930');
      await notifier.record('930', '217');
      await notifier.record('517', '930');

      expect(container.read(recentSearchProvider).value, [
        (departureId: '517', arrivalId: '930'),
        (departureId: '930', arrivalId: '217'),
      ]);
    });

    test('방향이 반대인 쌍은 서로 다른 검색으로 본다', () async {
      SharedPreferences.setMockInitialValues({});
      final container = makeContainer();
      final notifier = container.read(recentSearchProvider.notifier);

      await notifier.record('517', '930');
      await notifier.record('930', '517');

      expect(container.read(recentSearchProvider).value, hasLength(2));
    });
  });

  group('recentSearchStations (resolve)', () {
    test('저장된 순서(최신순)대로 Station 쌍 목록을 반환한다', () async {
      SharedPreferences.setMockInitialValues({
        'pref_recent_search': '[{"d":"517","a":"930"},{"d":"930","a":"217"}]',
      });
      final container = makeContainer();

      final pairs = await container.read(recentSearchStationsProvider.future);
      expect(pairs, hasLength(2));
      expect(pairs[0].departure.name, '여의도');
      expect(pairs[0].arrival.name, '종합운동장');
      expect(pairs[1].departure.name, '종합운동장');
      expect(pairs[1].arrival.name, '잠실새내');
    });

    test('이력이 3건보다 많아도 최신 3건만 반환한다', () async {
      SharedPreferences.setMockInitialValues({
        'pref_recent_search':
            '[{"d":"517","a":"930"},{"d":"930","a":"217"},'
            '{"d":"217","a":"517"},{"d":"930","a":"517"}]',
      });
      final container = makeContainer();

      final pairs = await container.read(recentSearchStationsProvider.future);
      expect(pairs, hasLength(3));
      expect(pairs.last.departure.name, '잠실새내');
    });

    test('매칭되지 않는 id 가 낀 건만 건너뛴다(삭제/개명된 역)', () async {
      SharedPreferences.setMockInitialValues({
        'pref_recent_search': '[{"d":"517","a":"999"},{"d":"930","a":"217"}]',
      });
      final container = makeContainer();

      final pairs = await container.read(recentSearchStationsProvider.future);
      expect(pairs, hasLength(1));
      expect(pairs.single.departure.name, '종합운동장');
    });

    test('id 가 달라도 같은 물리 역 쌍이면 최신 1건만 남긴다', () async {
      // 여의도(9호선 레코드)→종합운동장, 여의도(5호선 레코드)→종합운동장 은
      // 화면에 똑같이 보인다.
      SharedPreferences.setMockInitialValues({
        'pref_recent_search': '[{"d":"915","a":"930"},{"d":"517","a":"930"}]',
      });
      final container = makeContainer();

      final pairs = await container.read(recentSearchStationsProvider.future);
      expect(pairs, hasLength(1));
      expect(pairs.single.departure.id, '915');
    });

    test('이력이 없으면 빈 목록을 반환한다', () async {
      SharedPreferences.setMockInitialValues({});
      final container = makeContainer();

      final pairs = await container.read(recentSearchStationsProvider.future);
      expect(pairs, isEmpty);
    });
  });
}
