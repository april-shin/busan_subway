import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:busan_subway/domain/entities/favorite_route.dart';
import 'package:busan_subway/domain/entities/station.dart';
import 'package:busan_subway/features/favorites/presentation/providers/favorite_routes_provider.dart';
import 'package:busan_subway/features/route_search/presentation/providers/recent_search_provider.dart';
import 'package:busan_subway/features/subway_map/presentation/providers/subway_map_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _key = 'pref_favorite_routes';

class _MockPrefs extends Mock implements SharedPreferences {}

const gangnam = Station(
  id: '222',
  name: '강남',
  lineId: '2',
  latitude: 37.49,
  longitude: 127.02,
);
const yeoksam = Station(
  id: '221',
  name: '역삼',
  lineId: '2',
  latitude: 37.50,
  longitude: 127.03,
);
const seolleung = Station(
  id: '220',
  name: '선릉',
  lineId: '2',
  latitude: 37.50,
  longitude: 127.04,
);
const jamsil = Station(
  id: '216',
  name: '잠실',
  lineId: '2',
  latitude: 37.51,
  longitude: 127.10,
);

FavoriteRoute fav(
  String d,
  String a, {
  List<String> w = const [],
  String alias = '',
}) => FavoriteRoute(departureId: d, arrivalId: a, waypointIds: w, alias: alias);

void main() {
  ProviderContainer makeContainer() {
    final container = ProviderContainer(
      overrides: [
        allStationsProvider.overrideWith(
          (ref) async => [gangnam, yeoksam, seolleung, jamsil],
        ),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  Future<List<Object?>> stored() async {
    final prefs = await SharedPreferences.getInstance();
    return json.decode(prefs.getString(_key)!) as List<Object?>;
  }

  group('로드', () {
    test('저장된 값이 없으면 빈 목록', () async {
      SharedPreferences.setMockInitialValues({});
      final c = makeContainer();
      expect(await c.read(favoriteRoutesProvider.future), isEmpty);
    });

    test('손상된 JSON 이면 빈 목록(앱이 죽지 않는다)', () async {
      SharedPreferences.setMockInitialValues({_key: 'not-a-json'});
      final c = makeContainer();
      expect(await c.read(favoriteRoutesProvider.future), isEmpty);
    });

    test('배열이 아니면 빈 목록', () async {
      SharedPreferences.setMockInitialValues({_key: '{"d":"222","a":"216"}'});
      final c = makeContainer();
      expect(await c.read(favoriteRoutesProvider.future), isEmpty);
    });

    test('형식이 틀린 항목만 건너뛰고 순서를 유지한다', () async {
      SharedPreferences.setMockInitialValues({
        _key: json.encode([
          1,
          {'d': 1, 'a': '216'},
          {
            'd': '222',
            'a': '216',
            'w': ['221'],
            'n': '출근',
          },
          {'d': '222', 'a': '216', 'w': 'x'},
          {
            'd': '222',
            'a': '216',
            'w': [3],
          },
          {'d': '222', 'a': '216', 'n': 5},
          {'d': '216', 'a': '222'},
        ]),
      });
      final c = makeContainer();
      expect(await c.read(favoriteRoutesProvider.future), [
        fav('222', '216', w: ['221'], alias: '출근'),
        fav('216', '222'),
      ]);
    });

    test('같은 경로가 여러 번이면 앞쪽 하나만, 최대 5개까지', () async {
      SharedPreferences.setMockInitialValues({
        _key: json.encode([
          {'d': '222', 'a': '216'},
          {'d': '222', 'a': '216', 'n': '중복'},
          for (var i = 0; i < 6; i++) {'d': 'x$i', 'a': '216'},
        ]),
      });
      final c = makeContainer();
      final list = await c.read(favoriteRoutesProvider.future);
      expect(list, hasLength(maxFavoriteRoutes));
      expect(list.first, fav('222', '216'));
    });
  });

  group('add', () {
    test('성공하면 맨 뒤에 추가하고 경유역·별칭(trim)까지 저장한다', () async {
      SharedPreferences.setMockInitialValues({});
      final c = makeContainer();
      final n = c.read(favoriteRoutesProvider.notifier);

      expect(await n.add(fav('222', '216')), FavoriteSaveResult.success);
      expect(
        await n.add(fav('222', '216', w: ['221', '220'], alias: ' 출근 ')),
        FavoriteSaveResult.success,
      );

      expect(await c.read(favoriteRoutesProvider.future), [
        fav('222', '216'),
        fav('222', '216', w: ['221', '220'], alias: '출근'),
      ]);
      expect(await stored(), [
        {'d': '222', 'a': '216', 'w': <String>[], 'n': ''},
        {
          'd': '222',
          'a': '216',
          'w': ['221', '220'],
          'n': '출근',
        },
      ]);
    });

    test('저장한 경유역은 새로 로드해도 그대로 복원된다', () async {
      SharedPreferences.setMockInitialValues({});
      final c1 = makeContainer();
      await c1
          .read(favoriteRoutesProvider.notifier)
          .add(fav('222', '216', w: ['221', '220'], alias: '출근'));

      final c2 = makeContainer();
      expect(await c2.read(favoriteRoutesProvider.future), [
        fav('222', '216', w: ['221', '220'], alias: '출근'),
      ]);
    });

    test('출발·경유·도착이 모두 같으면 별칭이 달라도 duplicate', () async {
      SharedPreferences.setMockInitialValues({});
      final c = makeContainer();
      final n = c.read(favoriteRoutesProvider.notifier);
      await n.add(fav('222', '216', w: ['221']));

      expect(
        await n.add(fav('222', '216', w: ['221'], alias: '다른 이름')),
        FavoriteSaveResult.duplicate,
      );
      // 경유역이 다르면 다른 즐겨찾기다.
      expect(await n.add(fav('222', '216')), FavoriteSaveResult.success);
      expect(
        await n.add(fav('222', '216', w: ['220'])),
        FavoriteSaveResult.success,
      );
    });

    test('5개가 차 있으면 full 을 돌려주고 밀어내지 않는다', () async {
      SharedPreferences.setMockInitialValues({});
      final c = makeContainer();
      final n = c.read(favoriteRoutesProvider.notifier);
      for (var i = 0; i < maxFavoriteRoutes; i++) {
        expect(await n.add(fav('s$i', '216')), FavoriteSaveResult.success);
      }

      expect(await n.add(fav('222', '216')), FavoriteSaveResult.full);
      final list = await c.read(favoriteRoutesProvider.future);
      expect(list, hasLength(maxFavoriteRoutes));
      expect(list.first, fav('s0', '216'));
    });
  });

  test('remove 는 같은 경로 항목을 지우고, 없으면 notFound', () async {
    SharedPreferences.setMockInitialValues({});
    final c = makeContainer();
    final n = c.read(favoriteRoutesProvider.notifier);
    await n.add(fav('222', '216', alias: '출근'));
    await n.add(fav('216', '222'));

    expect(await n.remove(fav('222', '216')), FavoriteSaveResult.success);
    expect(await c.read(favoriteRoutesProvider.future), [fav('216', '222')]);
    expect(await n.remove(fav('222', '216')), FavoriteSaveResult.notFound);
    expect(await stored(), hasLength(1));
  });

  test('move 는 순서를 바꾸고 저장 순서에도 반영한다', () async {
    SharedPreferences.setMockInitialValues({});
    final c = makeContainer();
    final n = c.read(favoriteRoutesProvider.notifier);
    await n.add(fav('a', '1'));
    await n.add(fav('b', '1'));
    await n.add(fav('c', '1'));

    await n.move(0, 2);
    expect(await c.read(favoriteRoutesProvider.future), [
      fav('b', '1'),
      fav('c', '1'),
      fav('a', '1'),
    ]);
    expect([for (final e in await stored()) (e as Map)['d']], ['b', 'c', 'a']);

    // 범위 밖은 무시.
    await n.move(0, 9);
    expect((await c.read(favoriteRoutesProvider.future)).first, fav('b', '1'));
  });

  group('replace', () {
    test('별칭과 경로를 같은 자리에서 바꾼다', () async {
      SharedPreferences.setMockInitialValues({});
      final c = makeContainer();
      final n = c.read(favoriteRoutesProvider.notifier);
      await n.add(fav('222', '216', alias: '출근'));
      await n.add(fav('216', '222'));

      expect(
        await n.replace(fav('222', '216'), fav('222', '220', alias: ' 운동 ')),
        FavoriteSaveResult.success,
      );
      expect(await c.read(favoriteRoutesProvider.future), [
        fav('222', '220', alias: '운동'),
        fav('216', '222'),
      ]);
    });

    test('자기 자신과 같은 경로는 중복이 아니다(별칭만 수정)', () async {
      SharedPreferences.setMockInitialValues({});
      final c = makeContainer();
      final n = c.read(favoriteRoutesProvider.notifier);
      await n.add(fav('222', '216'));

      expect(
        await n.replace(fav('222', '216'), fav('222', '216', alias: '새 이름')),
        FavoriteSaveResult.success,
      );
    });

    test('다른 즐겨찾기와 경로가 겹치면 저장하지 않고 duplicate', () async {
      SharedPreferences.setMockInitialValues({});
      final c = makeContainer();
      final n = c.read(favoriteRoutesProvider.notifier);
      await n.add(fav('222', '216'));
      await n.add(fav('216', '222'));

      expect(
        await n.replace(fav('216', '222'), fav('222', '216', alias: 'x')),
        FavoriteSaveResult.duplicate,
      );
      expect(await c.read(favoriteRoutesProvider.future), [
        fav('222', '216'),
        fav('216', '222'),
      ]);
    });

    test('대상이 없으면 notFound', () async {
      SharedPreferences.setMockInitialValues({});
      final c = makeContainer();
      expect(
        await c
            .read(favoriteRoutesProvider.notifier)
            .replace(fav('222', '216'), fav('216', '222')),
        FavoriteSaveResult.notFound,
      );
    });
  });

  group('resolvedFavoriteRoutes', () {
    test('id 를 Station 으로 resolve 하고, 못 찾는 역은 null + 미완성', () async {
      SharedPreferences.setMockInitialValues({
        _key: json.encode([
          {
            'd': '222',
            'a': '216',
            'w': ['221'],
            'n': '',
          },
          {'d': '222', 'a': 'gone', 'n': '폐역'},
          {
            'd': '222',
            'a': '216',
            'w': ['gone'],
          },
        ]),
      });
      final c = makeContainer();
      final list = await c.read(resolvedFavoriteRoutesProvider.future);

      expect(list, hasLength(3));
      expect(list[0].departure, gangnam);
      expect(list[0].waypoints, [yeoksam]);
      expect(list[0].arrival, jamsil);
      expect(list[0].isComplete, isTrue);
      expect(list[0].label, '강남→잠실');

      expect(list[1].arrival, isNull);
      expect(list[1].isComplete, isFalse);
      expect(list[1].label, '폐역');

      expect(list[2].waypoints, [null]);
      expect(list[2].isComplete, isFalse);
    });
  });

  test('최근 검색 저장값과 서로 영향을 주지 않는다', () async {
    SharedPreferences.setMockInitialValues({
      'pref_recent_search': '[{"d":"222","a":"216"}]',
    });
    final c = makeContainer();
    await c.read(favoriteRoutesProvider.notifier).add(fav('216', '222'));

    expect(await c.read(recentSearchProvider.future), [
      (departureId: '222', arrivalId: '216'),
    ]);
  });

  test('SelectedStationsNotifier.setRoute 는 출발·경유·도착을 한 번에 설정한다', () {
    final c = makeContainer();
    final states = <SelectedStations>[];
    c.listen(selectedStationsProvider, (_, next) => states.add(next));
    final n = c.read(selectedStationsProvider.notifier);
    n.setBoth(seolleung, gangnam);
    n.insertWaypointSlot(0);
    states.clear();

    n.setRoute(gangnam, jamsil, waypoints: [yeoksam, seolleung]);

    expect(states, hasLength(1));
    final s = states.single;
    expect(s.departure, gangnam);
    expect(s.arrival, jamsil);
    expect(s.waypoints, [yeoksam, seolleung]);
  });

  group('동시 호출(M2 회귀)', () {
    test('초기 로드 중 add 2회를 동시에 불러도 둘 다 남는다', () async {
      SharedPreferences.setMockInitialValues({});
      final c = makeContainer();
      final n = c.read(favoriteRoutesProvider.notifier);

      final results = await Future.wait([
        n.add(fav('222', '216', alias: 'A')),
        n.add(fav('216', '222', alias: 'B')),
      ]);

      expect(results, [FavoriteSaveResult.success, FavoriteSaveResult.success]);
      expect(await c.read(favoriteRoutesProvider.future), [
        fav('222', '216', alias: 'A'),
        fav('216', '222', alias: 'B'),
      ]);
      expect(await stored(), hasLength(2));
    });

    test('로드 후 await 없이 add, add, remove 를 이어 불러도 순서대로 반영된다', () async {
      SharedPreferences.setMockInitialValues({});
      final c = makeContainer();
      await c.read(favoriteRoutesProvider.future);
      final n = c.read(favoriteRoutesProvider.notifier);

      final results = await Future.wait([
        n.add(fav('1', '9')),
        n.add(fav('3', '9')),
        n.remove(fav('1', '9')),
      ]);

      expect(results, [
        FavoriteSaveResult.success,
        FavoriteSaveResult.success,
        FavoriteSaveResult.success,
      ]);
      expect(await c.read(favoriteRoutesProvider.future), [fav('3', '9')]);
      expect([for (final e in await stored()) (e as Map)['d']], ['3']);
    });

    test('동시 add 로 5개 상한을 넘지 못한다', () async {
      SharedPreferences.setMockInitialValues({});
      final c = makeContainer();
      final n = c.read(favoriteRoutesProvider.notifier);

      final results = await Future.wait([
        for (var i = 0; i < maxFavoriteRoutes + 2; i++) n.add(fav('s$i', '9')),
      ]);

      expect(
        results.where((r) => r == FavoriteSaveResult.success),
        hasLength(maxFavoriteRoutes),
      );
      expect(results.last, FavoriteSaveResult.full);
      expect(
        await c.read(favoriteRoutesProvider.future),
        hasLength(maxFavoriteRoutes),
      );
    });
  });

  group('저장 실패(L2)', () {
    ProviderContainer containerWith(SharedPreferences prefs) {
      final c = ProviderContainer(
        overrides: [
          favoritePreferencesProvider.overrideWith((ref) async => prefs),
        ],
      );
      addTearDown(c.dispose);
      return c;
    }

    _MockPrefs prefsWith({
      required Object Function() onSet,
      List<Map<String, Object?>> initial = const [
        {'d': '222', 'a': '216', 'n': '출근'},
      ],
    }) {
      final prefs = _MockPrefs();
      when(() => prefs.getString(_key)).thenReturn(json.encode(initial));
      when(() => prefs.setString(_key, any())).thenAnswer((_) async {
        final r = onSet();
        if (r is bool) return r;
        throw r;
      });
      return prefs;
    }

    test('setString 이 예외를 던지면 saveFailed + 상태 롤백(미처리 예외 없음)', () async {
      final c = containerWith(prefsWith(onSet: () => Exception('디스크')));
      final n = c.read(favoriteRoutesProvider.notifier);

      expect(await n.add(fav('216', '222')), FavoriteSaveResult.saveFailed);
      expect(await n.remove(fav('222', '216')), FavoriteSaveResult.saveFailed);
      expect(
        await n.replace(fav('222', '216'), fav('222', '221')),
        FavoriteSaveResult.saveFailed,
      );
      expect(await c.read(favoriteRoutesProvider.future), [
        fav('222', '216', alias: '출근'),
      ]);
    });

    test('setString 이 false 를 돌려줘도 saveFailed + 롤백', () async {
      final c = containerWith(
        prefsWith(
          onSet: () => false,
          initial: const [
            {'d': '222', 'a': '216', 'n': '출근'},
            {'d': '216', 'a': '222', 'n': '퇴근'},
          ],
        ),
      );
      final n = c.read(favoriteRoutesProvider.notifier);

      expect(await n.move(0, 1), FavoriteSaveResult.saveFailed);
      expect(
        [for (final f in await c.read(favoriteRoutesProvider.future)) f.alias],
        ['출근', '퇴근'],
      );
    });

    test('로드가 실패한 상태에서도 연산이 죽지 않는다', () async {
      // riverpod 3 기본 재시도(지수 백오프)를 끄고 실패 상태를 바로 만든다.
      final c = ProviderContainer(
        retry: (_, _) => null,
        overrides: [
          favoritePreferencesProvider.overrideWith(
            (ref) async => throw Exception('플러그인 없음'),
          ),
        ],
      );
      addTearDown(c.dispose);
      final n = c.read(favoriteRoutesProvider.notifier);

      expect(await n.add(fav('216', '222')), FavoriteSaveResult.saveFailed);
      expect(await n.remove(fav('216', '222')), FavoriteSaveResult.notFound);
    });
  });

  test('로드 시 저장된 별칭을 trim + 10자로 정리한다(L3)', () async {
    SharedPreferences.setMockInitialValues({
      _key: json.encode([
        {'d': '222', 'a': '216', 'n': '  가나다라마바사아자차카타파하  '},
        {'d': '216', 'a': '222', 'n': '   '},
      ]),
    });
    final c = makeContainer();
    final list = await c.read(favoriteRoutesProvider.future);
    expect(list[0].alias, '가나다라마바사아자차');
    expect(list[1].alias, '');
  });

  test('공백만 입력한 별칭은 빈 별칭 → 출발→도착 으로 표시된다', () async {
    SharedPreferences.setMockInitialValues({});
    final c = makeContainer();
    await c
        .read(favoriteRoutesProvider.notifier)
        .add(fav('222', '216', alias: '    '));
    final list = await c.read(resolvedFavoriteRoutesProvider.future);
    expect(list.single.route.alias, '');
    expect(list.single.label, '강남→잠실');
  });

  test('못 찾는 역이 든 항목도 5개 한도에 포함된다', () async {
    SharedPreferences.setMockInitialValues({
      _key: json.encode([
        {'d': '222', 'a': 'gone'},
        for (var i = 0; i < maxFavoriteRoutes - 1; i++)
          {
            'd': '222',
            'a': '216',
            'w': ['s$i'],
          },
      ]),
    });
    final c = makeContainer();
    final resolved = await c.read(resolvedFavoriteRoutesProvider.future);
    expect(resolved.where((f) => f.isComplete), isEmpty);
    expect(
      await c.read(favoriteRoutesProvider.notifier).add(fav('216', '222')),
      FavoriteSaveResult.full,
    );
  });
}
