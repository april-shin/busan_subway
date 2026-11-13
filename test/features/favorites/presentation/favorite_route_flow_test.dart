import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:busan_subway/domain/repositories/arrival_repository.dart';
import 'package:busan_subway/features/arrival_info/presentation/providers/arrival_providers.dart';
import 'package:busan_subway/features/favorites/presentation/widgets/favorite_star_button.dart';
import 'package:busan_subway/features/favorites/presentation/widgets/favorite_tag_bar.dart';
import 'package:busan_subway/features/home/presentation/widgets/search_bar_widget.dart';
import 'package:busan_subway/features/route_search/presentation/screens/route_result_screen.dart';
import 'package:busan_subway/features/route_search/presentation/utils/route_result_navigator.dart';
import 'package:busan_subway/features/subway_map/presentation/providers/subway_map_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _MockArrivalRepository extends Mock implements ArrivalRepository {}

/// 종단 흐름: 홈 태그 탭(선택만) → 검색 버튼 → (번들 JSON 으로) 실제 경로 계산 → `/route-result`
/// 이동 → 그 화면의 별이 경유역 포함 경로로 채워져 있다.
///
/// 역·노선 데이터는 실제 에셋(`assets/json`)을 쓰고, 네트워크인 실시간 도착만
/// 모킹한다. `/route-result` 의 extra 는 `lib/app.dart` 와 같은
/// [RouteResultExtra] typedef 로 받는다(라우터 자체는 이 테스트 전용 사본이다).
void main() {
  testWidgets('태그 탭(선택만) → 검색 버튼 → 경로 결과 화면 → 같은 즐겨찾기라 채워진 별', (tester) async {
    SharedPreferences.setMockInitialValues({
      // 강남(222) → 역삼(221) 경유 → 잠실(216), 2호선 실제 id.
      'pref_favorite_routes': json.encode([
        {
          'd': '222',
          'a': '216',
          'w': ['221'],
          'n': '출근',
        },
      ]),
    });
    // 결과 화면 하단 배너 광고의 플랫폼 채널 — 테스트에는 구현이 없다.
    // null(사이즈 계산 실패)을 돌려주면 광고 위젯은 조용히 미노출로 남는다.
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/google_mobile_ads'),
      (_) async => null,
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/google_mobile_ads'),
        null,
      ),
    );
    final arrivalRepo = _MockArrivalRepository();
    when(() => arrivalRepo.getArrivalInfo(any())).thenAnswer((_) async => []);

    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          // HomeScreen 과 같은 배선: 선택이 완성되면 검색 버튼이 나타난다.
          builder: (_, _) => Scaffold(
            body: Consumer(
              builder: (context, ref, _) {
                final selected = ref.watch(selectedStationsProvider);
                return RouteSearchBar(
                  departure: selected.departure,
                  arrival: selected.arrival,
                  waypoints: selected.waypoints,
                  onSearchRoute: selected.isComplete
                      ? () => searchAndNavigateToResult(context, ref)
                      : null,
                  footer: const FavoriteTagBar(),
                );
              },
            ),
          ),
          routes: [
            GoRoute(
              path: 'route-result',
              builder: (_, state) {
                final extra = state.extra;
                if (extra is RouteResultExtra) {
                  return RouteResultScreen(
                    fastest: extra.fastest,
                    leastTransfer: extra.leastTransfer,
                    fastestExpress: extra.fastestExpress,
                    fastestLocal: extra.fastestLocal,
                    departureStationName: extra.departureStationName,
                    searchedStations: extra.searchedStations,
                  );
                }
                return const Text('잘못된 경로입니다');
              },
            ),
          ],
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [arrivalRepositoryProvider.overrideWithValue(arrivalRepo)],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    // 번들 JSON 로드는 실제 비동기 I/O 라 runAsync 안에서 기다린다.
    Future<void> settleIo(bool Function() done) async {
      for (var i = 0; i < 100 && !done(); i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)),
        );
        await tester.pump();
      }
    }

    await settleIo(() => find.text('출근').evaluate().isNotEmpty);
    expect(find.text('출근'), findsOneWidget);

    // 태그 탭은 선택까지만 한다 — 결과 화면으로는 가지 않는다.
    await tester.tap(find.text('출근'));
    await tester.pump();
    expect(find.byType(RouteResultScreen), findsNothing);

    // 검색 버튼으로 결과 화면에 가면, 그 선택(경유역 포함)의 별이 채워져 있다.
    await tester.tap(find.byIcon(Icons.search));
    await settleIo(() => find.byType(RouteResultScreen).evaluate().isNotEmpty);
    await settleIo(() => find.byType(FavoriteStarButton).evaluate().isNotEmpty);
    Finder starIcon(IconData icon) => find.descendant(
      of: find.byType(FavoriteStarButton),
      matching: find.byIcon(icon),
    );
    await settleIo(() => starIcon(Icons.star_rounded).evaluate().isNotEmpty);

    expect(find.byType(RouteResultScreen), findsOneWidget);
    final button = tester.widget<FavoriteStarButton>(
      find.byType(FavoriteStarButton),
    );
    expect(button.departure.id, '222');
    expect(button.waypoints.map((s) => s.id), ['221']);
    expect(button.arrival.id, '216');
    expect(starIcon(Icons.star_rounded), findsOneWidget);
    expect(starIcon(Icons.star_border_rounded), findsNothing);

    // 광고 재시도 타이머 등 남은 작업을 정리한다.
    await tester.pumpWidget(const SizedBox());
  });
}
