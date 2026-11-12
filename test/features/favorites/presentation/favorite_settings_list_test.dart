import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:seoul_subway/core/constants/app_info.dart';
import 'package:seoul_subway/domain/entities/favorite_route.dart';
import 'package:seoul_subway/domain/entities/station.dart';
import 'package:seoul_subway/features/favorites/presentation/providers/favorite_routes_provider.dart';
import 'package:seoul_subway/features/favorites/presentation/widgets/favorite_settings_list.dart';
import 'package:seoul_subway/features/route_search/presentation/screens/station_picker_screen.dart';
import 'package:seoul_subway/features/settings/presentation/screens/settings_screen.dart';
import 'package:seoul_subway/features/subway_map/presentation/providers/subway_map_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
const hongdae = Station(
  id: '239',
  name: '홍대입구',
  lineId: '2',
  latitude: 37.55,
  longitude: 126.92,
);

FavoriteRoute fav(
  String d,
  String a, {
  List<String> w = const [],
  String alias = '',
}) => FavoriteRoute(departureId: d, arrivalId: a, waypointIds: w, alias: alias);

void main() {
  // 설정 화면이 앱 버전 문자열을 읽는다(main() 의 AppInfo.init 대응).
  setUpAll(() async {
    PackageInfo.setMockInitialValues(
      appName: 'test',
      packageName: 'test',
      version: '0.0.0',
      buildNumber: '0',
      buildSignature: '',
    );
    await AppInfo.init();
  });

  void store(List<Map<String, Object?>> entries) {
    SharedPreferences.setMockInitialValues({
      'pref_favorite_routes': json.encode(entries),
    });
  }

  /// 실제 라우트 구조(설정 → `/pick-station/:purpose`)를 그대로 쓴다 —
  /// picker 가 고른 역을 pop 결과로 돌려주는 배선까지 검증하기 위해서다.
  Widget harness({bool slowResolve = false}) {
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) => const SettingsScreen(),
          routes: [
            GoRoute(
              path: 'pick-station/:purpose',
              builder: (_, state) => StationPickerScreen(
                purpose: state.pathParameters['purpose']!,
              ),
            ),
          ],
        ),
      ],
    );
    return ProviderScope(
      overrides: [
        allStationsProvider.overrideWith(
          (ref) async => [gangnam, yeoksam, jamsil, hongdae],
        ),
        // resolve 재계산을 일부러 늦춰 변경 직후 AsyncLoading 프레임을 만든다.
        if (slowResolve)
          resolvedFavoriteRoutesProvider.overrideWith((ref) async {
            final result = await resolvedFavoriteRoutes(ref);
            await Future<void>.delayed(const Duration(milliseconds: 50));
            return result;
          }),
      ],
      child: MaterialApp.router(routerConfig: router),
    );
  }

  ProviderContainer containerOf(WidgetTester tester) =>
      ProviderScope.containerOf(
        tester.element(find.byType(FavoriteSettingsList)),
      );

  Future<List<FavoriteRoute>> saved(WidgetTester tester) =>
      containerOf(tester).read(favoriteRoutesProvider.future);

  Future<void> pickIn(WidgetTester tester, String row, String station) async {
    await tester.tap(find.text(row));
    await tester.pumpAndSettle();
    await tester.tap(find.text(station).last);
    await tester.pumpAndSettle();
  }

  testWidgets('저장 순서대로 별칭·경로를 보여 주고, 못 찾는 역 항목도 남겨 안내한다', (tester) async {
    store([
      {
        'd': '222',
        'a': '216',
        'w': ['221'],
        'n': '출근',
      },
      {'d': '216', 'a': 'gone'},
    ]);
    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();

    expect(find.text('즐겨찾기'), findsOneWidget);
    expect(find.text('출근'), findsOneWidget);
    expect(find.text('강남 → 역삼 → 잠실'), findsOneWidget);
    expect(find.text('잠실→?'), findsOneWidget);
    expect(find.text('찾을 수 없는 역이 있어 홈에 표시되지 않아요'), findsOneWidget);
    expect(find.text('2/5'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('출근')).dy,
      lessThan(tester.getTopLeft(find.text('잠실→?')).dy),
    );
  });

  testWidgets('추가: 역 선택 화면에서 출발·도착을 골라 저장하고 홈 선택은 건드리지 않는다', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();

    await tester.tap(find.text('즐겨찾기 추가'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);

    await pickIn(tester, '출발역을 선택하세요', '강남');
    expect(find.text('강남'), findsOneWidget); // 다이얼로그로 돌아옴
    await pickIn(tester, '도착역을 선택하세요', '잠실');
    await tester.enterText(find.byType(TextField), '출근');
    await tester.tap(find.text('저장'));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsNothing);
    expect(await saved(tester), [fav('222', '216', alias: '출근')]);
    expect(find.text('강남 → 잠실'), findsOneWidget);
    final selected = containerOf(tester).read(selectedStationsProvider);
    expect(selected.departure, isNull);
    expect(selected.arrival, isNull);
  });

  testWidgets('추가: 출발·도착을 다 고르기 전에는 저장할 수 없다', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();

    await tester.tap(find.text('즐겨찾기 추가'));
    await tester.pumpAndSettle();
    await pickIn(tester, '출발역을 선택하세요', '강남');

    final save = tester.widget<TextButton>(
      find.widgetWithText(TextButton, '저장'),
    );
    expect(save.onPressed, isNull);
  });

  testWidgets('5개가 차 있으면 추가를 막고 스낵바', (tester) async {
    store([
      for (var i = 0; i < maxFavoriteRoutes; i++) {'d': 's$i', 'a': '216'},
    ]);
    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('즐겨찾기 추가'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('즐겨찾기 추가'));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('즐겨찾기는 최대 5개까지예요'), findsOneWidget);
  });

  testWidgets('삭제: 확인 후 지운다', (tester) async {
    store([
      {'d': '222', 'a': '216', 'n': '출근'},
      {'d': '216', 'a': '222', 'n': '퇴근'},
    ]);
    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('삭제').first);
    await tester.pumpAndSettle();
    expect(find.text('"출근" 즐겨찾기를 삭제할까요?'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, '삭제'));
    await tester.pumpAndSettle();

    expect(find.text('출근'), findsNothing);
    expect(await saved(tester), [fav('216', '222', alias: '퇴근')]);
  });

  testWidgets('순서 변경: 손잡이를 끌어 옮기면 저장 순서가 바뀐다', (tester) async {
    store([
      {'d': '222', 'a': '216', 'n': '첫째'},
      {'d': '216', 'a': '222', 'n': '둘째'},
      {'d': '239', 'a': '222', 'n': '셋째'},
    ]);
    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();

    final handle = find.byIcon(Icons.drag_handle).first;
    final gesture = await tester.startGesture(tester.getCenter(handle));
    await tester.pump();
    // 행 두 칸 남짓 아래로(손잡이는 누르는 즉시 끌린다).
    final rowHeight = tester.getSize(find.byType(InkWell).first).height;
    for (var i = 0; i < 5; i++) {
      await gesture.moveBy(Offset(0, rowHeight * 0.5));
      await tester.pump(const Duration(milliseconds: 50));
    }
    await gesture.up();
    await tester.pumpAndSettle();

    expect([for (final f in await saved(tester)) f.alias], ['둘째', '셋째', '첫째']);
  });

  testWidgets('수정: 별칭만 바꾸면 경유역을 유지한다', (tester) async {
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
    expect(find.text('즐겨찾기 수정'), findsOneWidget);
    expect(find.textContaining('경유 역삼'), findsOneWidget);

    await tester.enterText(find.byType(TextField), '아침');
    await tester.tap(find.text('저장'));
    await tester.pumpAndSettle();

    expect(await saved(tester), [
      fav('222', '216', w: ['221'], alias: '아침'),
    ]);
  });

  testWidgets('수정: 도착을 바꾸면 경유역을 지우고 안내한다', (tester) async {
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
    await pickIn(tester, '잠실', '홍대입구');
    expect(find.textContaining('경유역(역삼)은 빠져요'), findsOneWidget);
    await tester.tap(find.text('저장'));
    await tester.pumpAndSettle();

    expect(await saved(tester), [fav('222', '239', alias: '출근')]);
  });

  testWidgets('수정: 다른 즐겨찾기와 경로가 겹치면 저장을 막고 안내한다', (tester) async {
    store([
      {'d': '222', 'a': '216', 'n': '출근'},
      {'d': '222', 'a': '239', 'n': '약속'},
    ]);
    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();

    await tester.tap(find.text('약속'));
    await tester.pumpAndSettle();
    await pickIn(tester, '홍대입구', '잠실');
    await tester.tap(find.text('저장'));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.text('이미 같은 경로의 즐겨찾기가 있어요'), findsOneWidget);
    expect(await saved(tester), [
      fav('222', '216', alias: '출근'),
      fav('222', '239', alias: '약속'),
    ]);
  });

  testWidgets('변경 직후 재계산 중에도 목록이 비지 않는다(H1)', (tester) async {
    store([
      {'d': '222', 'a': '216', 'n': '첫째'},
      {'d': '216', 'a': '222', 'n': '둘째'},
    ]);
    await tester.pumpWidget(harness(slowResolve: true));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('삭제').first);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, '삭제'));
    await tester.pump();
    expect(find.byType(ReorderableListView), findsOneWidget);
    expect(find.text('둘째'), findsOneWidget);
    expect(find.text('0/5'), findsNothing);

    await tester.pumpAndSettle();
    expect(find.text('첫째'), findsNothing);
    expect(find.text('1/5'), findsOneWidget);
  });

  testWidgets('수정: 별칭만 고쳐도 찾을 수 없는 경유 id 는 빼고 저장한다', (tester) async {
    store([
      {
        'd': '222',
        'a': '216',
        'w': ['gone', '221'],
        'n': '출근',
      },
    ]);
    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();
    expect(find.text('찾을 수 없는 역이 있어 홈에 표시되지 않아요'), findsOneWidget);

    await tester.tap(find.text('출근'));
    await tester.pumpAndSettle();
    expect(find.textContaining('찾을 수 없는 경유역은 저장할 때 빠져요'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '아침');
    await tester.tap(find.text('저장'));
    await tester.pumpAndSettle();

    expect(await saved(tester), [
      fav('222', '216', w: ['221'], alias: '아침'),
    ]);
    expect(find.text('찾을 수 없는 역이 있어 홈에 표시되지 않아요'), findsNothing);
  });
}
