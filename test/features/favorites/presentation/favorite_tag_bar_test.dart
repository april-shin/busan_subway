import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:seoul_subway/domain/entities/favorite_route.dart';
import 'package:seoul_subway/domain/entities/station.dart';
import 'package:seoul_subway/domain/repositories/station_repository.dart';
import 'package:seoul_subway/features/favorites/presentation/providers/favorite_routes_provider.dart';
import 'package:seoul_subway/features/favorites/presentation/widgets/favorite_tag_bar.dart';
import 'package:seoul_subway/features/home/presentation/screens/home_screen.dart';
import 'package:seoul_subway/features/home/presentation/widgets/search_bar_widget.dart';
import 'package:seoul_subway/features/subway_map/presentation/providers/subway_map_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _MockStationRepository extends Mock implements StationRepository {}

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
const jamsil = Station(
  id: '216',
  name: '잠실',
  lineId: '2',
  latitude: 37.51,
  longitude: 127.10,
);

void main() {
  late _MockStationRepository repo;

  setUp(() {
    repo = _MockStationRepository();
    // 경로 계산은 이 테스트의 관심사가 아니다 — 실패시켜 스낵바로 끝낸다.
    when(() => repo.getAllStations()).thenThrow(Exception('테스트'));
  });

  void store(List<Map<String, Object?>> entries) {
    SharedPreferences.setMockInitialValues({
      'pref_favorite_routes': json.encode(entries),
    });
  }

  Widget harness({SharedPreferences? prefs, bool slowResolve = false}) =>
      ProviderScope(
        overrides: [
          allStationsProvider.overrideWith(
            (ref) async => [gangnam, yeoksam, jamsil],
          ),
          stationRepositoryProvider.overrideWithValue(repo),
          if (prefs != null)
            favoritePreferencesProvider.overrideWith((ref) async => prefs),
          if (slowResolve) _slowResolvedOverride(),
        ],
        child: const MaterialApp(
          home: Scaffold(body: RouteSearchBar(footer: FavoriteTagBar())),
        ),
      );

  ProviderContainer containerOf(WidgetTester tester) =>
      ProviderScope.containerOf(tester.element(find.byType(FavoriteTagBar)));

  testWidgets('즐겨찾기가 없으면 태그 줄을 그리지 않는다', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.star_rounded), findsNothing);
    expect(find.byType(SingleChildScrollView), findsNothing);
  });

  testWidgets('별칭, 없으면 출발→도착으로 저장 순서대로 표시하고 못 찾는 역은 숨긴다', (tester) async {
    store([
      {'d': '222', 'a': '216', 'n': '출근'},
      {'d': '216', 'a': '222'},
      {'d': '222', 'a': 'gone', 'n': '폐역'},
    ]);
    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();

    expect(find.text('출근'), findsOneWidget);
    expect(find.text('잠실→강남'), findsOneWidget);
    expect(find.text('폐역'), findsNothing);
    expect(
      tester.getTopLeft(find.text('출근')).dx,
      lessThan(tester.getTopLeft(find.text('잠실→강남')).dx),
    );
    // 도착역 칸 아래.
    expect(
      tester.getTopLeft(find.text('출근')).dy,
      greaterThan(tester.getTopLeft(find.text('도착역을 선택하세요')).dy),
    );
  });

  testWidgets('태그를 탭하면 출발·경유·도착을 한 번에 설정하고 결과 화면으로는 가지 않는다', (tester) async {
    store([
      {
        'd': '222',
        'a': '216',
        'w': ['221'],
        'n': '출근',
      },
    ]);
    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();

    await tester.tap(find.text('출근'));
    await tester.pumpAndSettle();

    final selected = containerOf(tester).read(selectedStationsProvider);
    expect(selected.departure, gangnam);
    expect(selected.waypoints, [yeoksam]);
    expect(selected.arrival, jamsil);
    // 선택까지만 — 경로 계산·결과 화면 이동(searchAndNavigateToResult)은 하지
    // 않는다. 했다면 이 하네스에서는 실패 스낵바가 뜬다.
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('길게 누르면 확인 후 삭제한다', (tester) async {
    store([
      {'d': '222', 'a': '216', 'n': '출근'},
      {'d': '216', 'a': '222', 'n': '퇴근'},
    ]);
    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();

    // 취소하면 그대로.
    await tester.longPress(find.text('출근'));
    await tester.pumpAndSettle();
    expect(find.text('"출근" 즐겨찾기를 삭제할까요?'), findsOneWidget);
    await tester.tap(find.text('취소'));
    await tester.pumpAndSettle();
    expect(find.text('출근'), findsOneWidget);

    await tester.longPress(find.text('출근'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('삭제'));
    await tester.pumpAndSettle();

    expect(find.text('출근'), findsNothing);
    expect(find.text('퇴근'), findsOneWidget);
    final list = await containerOf(tester).read(favoriteRoutesProvider.future);
    expect(list.single.alias, '퇴근');
    // 탭이 아니었으므로 출발/도착은 건드리지 않는다.
    expect(
      containerOf(tester).read(selectedStationsProvider).departure,
      isNull,
    );
  });

  testWidgets('삭제 직후 재계산 중에도 태그 줄이 비지 않는다(H1)', (tester) async {
    store([
      {'d': '222', 'a': '216', 'n': '출근'},
      {'d': '216', 'a': '222', 'n': '퇴근'},
    ]);
    await tester.pumpWidget(harness(slowResolve: true));
    await tester.pumpAndSettle();

    await tester.longPress(find.text('출근'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('삭제'));
    // 상태는 바뀌었고 resolve 는 아직 재계산 중(AsyncLoading)인 프레임.
    await tester.pump();
    expect(find.byType(SingleChildScrollView), findsOneWidget);
    expect(find.text('퇴근'), findsOneWidget);

    await tester.pumpAndSettle();
    expect(find.text('출근'), findsNothing);
    expect(find.text('퇴근'), findsOneWidget);
  });

  testWidgets('태그 줄은 카드 가운데가 아니라 입력칸과 같은 왼쪽에서 시작한다(M1)', (tester) async {
    store([
      {'d': '222', 'a': '216', 'n': '출근'},
    ]);
    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();

    final tagLeft = tester
        .getTopLeft(
          find.ancestor(of: find.text('출근'), matching: find.byType(InkWell)),
        )
        .dx;
    final fieldIconLeft = tester.getTopLeft(find.byIcon(Icons.place)).dx;
    // 카드 안쪽 왼쪽 가장자리(입력칸 시작) ≤ 태그 시작 < 입력칸 아이콘.
    expect(tagLeft, lessThan(fieldIconLeft));
    expect(
      tagLeft,
      lessThan(tester.getSize(find.byType(RouteSearchBar)).width / 4),
    );
  });

  testWidgets('저장에 실패하면 스낵바로 알리고 태그는 남는다(L2)', (tester) async {
    final prefs = _MockPrefs();
    when(() => prefs.getString('pref_favorite_routes')).thenReturn(
      json.encode([
        {'d': '222', 'a': '216', 'n': '출근'},
      ]),
    );
    when(
      () => prefs.setString('pref_favorite_routes', any()),
    ).thenThrow(Exception('디스크'));
    await tester.pumpWidget(harness(prefs: prefs));
    await tester.pumpAndSettle();

    await tester.longPress(find.text('출근'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('삭제'));
    await tester.pumpAndSettle();

    expect(find.text('즐겨찾기를 저장하지 못했어요'), findsOneWidget);
    expect(find.text('출근'), findsOneWidget);
  });

  testWidgets('홈 화면에서 출발·도착이 선택된 상태에도 태그 줄이 보인다', (tester) async {
    // 지도(WebView) 로딩을 막으려 역 목록은 영원히 pending 으로 두고, 태그가
    // 쓰는 resolve 결과만 직접 주입한다(widget_test.dart 와 같은 우회).
    final container = ProviderContainer(
      overrides: [
        allStationsProvider.overrideWith(
          (ref) => Completer<List<Station>>().future,
        ),
        resolvedFavoriteRoutesProvider.overrideWith(
          (ref) async => const [
            ResolvedFavoriteRoute(
              route: FavoriteRoute(
                departureId: '222',
                arrivalId: '216',
                alias: '출근',
              ),
              departure: gangnam,
              arrival: jamsil,
            ),
          ],
        ),
      ],
    );
    addTearDown(container.dispose);
    container.read(selectedStationsProvider.notifier).setBoth(jamsil, gangnam);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: HomeScreen()),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.byType(FavoriteTagBar), findsOneWidget);
    expect(find.text('출근'), findsOneWidget);
    // 선택된 역이 검색바에 그대로 있고, 태그는 그 아래.
    expect(
      tester.getTopLeft(find.text('출근')).dy,
      greaterThan(tester.getTopLeft(find.text('강남').first).dy),
    );
  });
}

/// resolve 재계산을 일부러 늦춘다 — 변경 직후 프로바이더가 AsyncLoading(이전 값
/// 보유)인 프레임을 결정적으로 만들기 위해서다. 실제 계산은 원본 함수 그대로.
Override _slowResolvedOverride() =>
    resolvedFavoriteRoutesProvider.overrideWith((ref) async {
      final result = await resolvedFavoriteRoutes(ref);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      return result;
    });
