import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:busan_subway/domain/entities/favorite_route.dart';
import 'package:busan_subway/domain/entities/route_result.dart';
import 'package:busan_subway/domain/entities/station.dart';
import 'package:busan_subway/domain/repositories/arrival_repository.dart';
import 'package:busan_subway/features/arrival_info/presentation/providers/arrival_providers.dart';
import 'package:busan_subway/features/favorites/presentation/providers/favorite_routes_provider.dart';
import 'package:busan_subway/features/favorites/presentation/widgets/favorite_star_button.dart';
import 'package:busan_subway/features/route_search/presentation/screens/route_result_screen.dart';
import 'package:busan_subway/features/subway_map/presentation/providers/subway_map_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _MockArrivalRepository extends Mock implements ArrivalRepository {}

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
  Widget harness() => const ProviderScope(
    child: MaterialApp(
      home: _StarHost(
        child: FavoriteStarButton(
          departure: gangnam,
          arrival: jamsil,
          waypoints: [yeoksam],
        ),
      ),
    ),
  );

  ProviderContainer containerOf(WidgetTester tester) =>
      ProviderScope.containerOf(
        tester.element(find.byType(FavoriteStarButton)),
      );

  testWidgets('미등록이면 빈 별 → 별칭 입력 후 경유역까지 등록 → 채워진 별', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.star_border_rounded), findsOneWidget);
    await tester.tap(find.byIcon(Icons.star_border_rounded));
    await tester.pumpAndSettle();

    expect(find.text('즐겨찾기 추가'), findsWidgets);
    // 비워 두면 쓰일 기본 이름은 힌트로만 보여 준다(잘리던 안내 문구는 없앴다).
    expect(find.text('강남→잠실'), findsOneWidget);
    expect(find.textContaining('비워 두면'), findsNothing);
    await tester.enterText(find.byType(TextField), '  출근길  ');
    await tester.tap(find.text('추가'));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.star_rounded), findsOneWidget);
    final list = await containerOf(tester).read(favoriteRoutesProvider.future);
    expect(list, [
      const FavoriteRoute(
        departureId: '222',
        arrivalId: '216',
        waypointIds: ['221'],
        alias: '출근길',
      ),
    ]);
  });

  testWidgets('별칭은 10자까지만 입력된다', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.star_border_rounded));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '가나다라마바사아자차카타');
    await tester.tap(find.text('추가'));
    await tester.pumpAndSettle();

    final list = await containerOf(tester).read(favoriteRoutesProvider.future);
    expect(list.single.alias, '가나다라마바사아자차');
  });

  testWidgets('다이얼로그를 취소하면 등록하지 않는다', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.star_border_rounded));
    await tester.pumpAndSettle();
    await tester.tap(find.text('취소'));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.star_border_rounded), findsOneWidget);
    expect(
      await containerOf(tester).read(favoriteRoutesProvider.future),
      isEmpty,
    );
  });

  testWidgets('등록된 경로면 채워진 별, 탭하면 해제', (tester) async {
    SharedPreferences.setMockInitialValues({
      'pref_favorite_routes': json.encode([
        {
          'd': '222',
          'a': '216',
          'w': ['221'],
          'n': '출근',
        },
      ]),
    });
    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.star_rounded));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.star_border_rounded), findsOneWidget);
    expect(
      await containerOf(tester).read(favoriteRoutesProvider.future),
      isEmpty,
    );
  });

  testWidgets('경유역이 다르면 같은 출발·도착이어도 빈 별', (tester) async {
    SharedPreferences.setMockInitialValues({
      'pref_favorite_routes': json.encode([
        {'d': '222', 'a': '216'},
      ]),
    });
    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.star_border_rounded), findsOneWidget);
  });

  testWidgets('5개가 차 있으면 다이얼로그 없이 스낵바로 막는다', (tester) async {
    SharedPreferences.setMockInitialValues({
      'pref_favorite_routes': json.encode([
        for (var i = 0; i < maxFavoriteRoutes; i++) {'d': 's$i', 'a': '216'},
      ]),
    });
    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.star_border_rounded));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('즐겨찾기는 최대 5개까지예요'), findsOneWidget);
    expect(
      await containerOf(tester).read(favoriteRoutesProvider.future),
      hasLength(maxFavoriteRoutes),
    );
  });

  group('경로 결과 화면 배선', () {
    late _MockArrivalRepository arrivalRepo;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      arrivalRepo = _MockArrivalRepository();
      when(() => arrivalRepo.getArrivalInfo(any())).thenAnswer((_) async => []);
    });

    final route = RouteResult(
      segments: [
        RouteSegment(
          lineId: '2',
          lineName: '2호선',
          stations: const [gangnam, yeoksam, jamsil],
          durationSeconds: 300,
          direction: '잠실 방면',
        ),
      ],
      totalTimeSeconds: 300,
      transferCount: 0,
      stationCount: 3,
    );

    Future<void> pumpResult(
      WidgetTester tester, {
      SelectedStations? searched,
      void Function(SelectedStationsNotifier)? currentSelection,
    }) async {
      final container = ProviderContainer(
        overrides: [arrivalRepositoryProvider.overrideWithValue(arrivalRepo)],
      );
      addTearDown(container.dispose);
      currentSelection?.call(container.read(selectedStationsProvider.notifier));
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: RouteResultScreen(
              fastest: route,
              departureStationName: gangnam.name,
              searchedStations: searched,
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 50));
    }

    testWidgets('계산에 쓴 출발·경유·도착으로 별 버튼을 단다', (tester) async {
      await pumpResult(
        tester,
        searched: const SelectedStations(
          departure: gangnam,
          arrival: jamsil,
          waypoints: [yeoksam, null],
        ),
      );

      final button = tester.widget<FavoriteStarButton>(
        find.byType(FavoriteStarButton),
      );
      expect(button.departure, gangnam);
      expect(button.arrival, jamsil);
      expect(button.waypoints, [yeoksam]); // 빈 칸 제외
    });

    testWidgets('현재 선택이 달라도(재계산 중 진입) 계산 시점 선택을 쓴다(M3)', (tester) async {
      await pumpResult(
        tester,
        searched: const SelectedStations(departure: gangnam, arrival: jamsil),
        // 지도에서 경유역을 막 추가해 재계산 중인 상태.
        currentSelection: (n) =>
            n.setRoute(gangnam, jamsil, waypoints: [yeoksam]),
      );

      final button = tester.widget<FavoriteStarButton>(
        find.byType(FavoriteStarButton),
      );
      expect(button.waypoints, isEmpty);
    });

    testWidgets('계산 선택이 없으면 별 버튼이 없다', (tester) async {
      await pumpResult(tester);
      expect(find.byType(FavoriteStarButton), findsNothing);
    });

    testWidgets('계산 선택이 미완성이면 별 버튼이 없다', (tester) async {
      await pumpResult(
        tester,
        searched: const SelectedStations(departure: gangnam),
      );
      expect(find.byType(FavoriteStarButton), findsNothing);
    });
  });
}

/// 별 버튼을 AppBar 에 다는 최소 화면.
class _StarHost extends StatelessWidget {
  final Widget child;

  const _StarHost({required this.child});

  @override
  Widget build(BuildContext context) {
    return Scaffold(appBar: AppBar(actions: [child]));
  }
}
