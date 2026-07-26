import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seoul_subway/domain/entities/station.dart';
import 'package:seoul_subway/features/route_search/presentation/providers/recent_search_provider.dart';
import 'package:seoul_subway/features/route_search/presentation/screens/station_picker_screen.dart';
import 'package:seoul_subway/features/subway_map/presentation/providers/subway_map_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  // 종합운동장(2/9호선 환승), 여의도(5/9호선 환승), 잠실새내(2호선 단일).
  // stations.json 의 실제 레코드 순서를 모사: 같은 이름 역은 lineId 오름차순.
  final testStations = <Station>[
    const Station(
      id: '217',
      name: '잠실새내',
      lineId: '2',
      latitude: 37.51,
      longitude: 127.09,
    ),
    const Station(
      id: '218',
      name: '종합운동장',
      lineId: '2',
      latitude: 37.51,
      longitude: 127.07,
      isTransfer: true,
      transferLines: ['2', '9'],
    ),
    const Station(
      id: '517',
      name: '여의도',
      lineId: '5',
      latitude: 37.52,
      longitude: 126.92,
      isTransfer: true,
      transferLines: ['5', '9'],
    ),
    const Station(
      id: '915',
      name: '여의도',
      lineId: '9',
      latitude: 37.52,
      longitude: 126.92,
      isTransfer: true,
      transferLines: ['5', '9'],
    ),
    const Station(
      id: '930',
      name: '종합운동장',
      lineId: '9',
      latitude: 37.51,
      longitude: 127.07,
      isTransfer: true,
      transferLines: ['2', '9'],
    ),
  ];

  // 최근검색 섹션이 watch 하는 recentSearchProvider 는 SharedPreferences 를
  // 읽는다. 미설정 시 MissingPluginException 이 AsyncError 로 surface 되므로,
  // 기본값을 빈 값으로 고정해 "이력 없음(섹션 숨김)" 상태를 만든다.
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Widget buildHarness() {
    return ProviderScope(
      overrides: [
        allStationsProvider.overrideWith((ref) async => testStations),
      ],
      child: const MaterialApp(
        home: StationPickerScreen(purpose: 'departure'),
      ),
    );
  }

  /// 최근검색 쌍을 직접 주입하는 하네스(SharedPreferences 우회).
  Widget buildHarnessWithRecent({
    required String purpose,
    ({Station departure, Station arrival})? recent,
  }) {
    return ProviderScope(
      overrides: [
        allStationsProvider.overrideWith((ref) async => testStations),
        recentSearchStationsProvider.overrideWith((ref) async => recent),
      ],
      child: MaterialApp(
        home: StationPickerScreen(purpose: purpose),
      ),
    );
  }

  testWidgets('환승역은 중복 제거되어 1개만 표시된다', (tester) async {
    await tester.pumpWidget(buildHarness());
    await tester.pumpAndSettle();

    // 종합운동장은 2호선 + 9호선에 모두 등록되어 있지만 ListTile 1개만 보여야 함.
    expect(find.text('종합운동장'), findsOneWidget);
    expect(find.text('여의도'), findsOneWidget);
    expect(find.text('잠실새내'), findsOneWidget);
  });

  testWidgets('환승역에 소속 노선 뱃지가 모두 표시된다', (tester) async {
    await tester.pumpWidget(buildHarness());
    await tester.pumpAndSettle();

    // 종합운동장: 2호선 + 9호선 뱃지 둘 다 존재.
    expect(find.text('2호선'), findsWidgets);
    expect(find.text('9호선'), findsWidgets);
    // 여의도: 5호선 + 9호선 뱃지.
    expect(find.text('5호선'), findsWidgets);
  });

  testWidgets('환승역 탭 시 대표 Station이 selectedStations에 저장되고 '
      'transferLines가 보존된다', (tester) async {
    late ProviderContainer container;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          allStationsProvider.overrideWith((ref) async => testStations),
        ],
        child: Consumer(
          builder: (context, ref, _) {
            container = ProviderScope.containerOf(context);
            return const MaterialApp(
              home: StationPickerScreen(purpose: 'departure'),
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('종합운동장'));
    await tester.pumpAndSettle();

    final selected = container.read(selectedStationsProvider).departure;
    expect(selected, isNotNull);
    expect(selected!.name, '종합운동장');
    // transferLines 가 양쪽 노선을 모두 포함해야 이후 executeAll 에서
    // "양쪽 다 급행 지원 노선" 공유 판정이 가능하다.
    expect(selected.transferLines, containsAll(['2', '9']));
  });

  group('최근 검색 섹션', () {
    final recentPair = (departure: testStations[2], arrival: testStations[4]);

    testWidgets('출발역 선택 화면에서 이력이 있고 검색어가 비면 섹션이 노출된다',
        (tester) async {
      await tester.pumpWidget(
        buildHarnessWithRecent(purpose: 'departure', recent: recentPair),
      );
      await tester.pumpAndSettle();

      expect(find.text('최근 검색'), findsOneWidget);
      expect(find.byIcon(Icons.history), findsOneWidget);
      expect(find.byIcon(Icons.arrow_forward), findsOneWidget);
    });

    testWidgets('도착역 선택 화면에서도 섹션이 노출된다', (tester) async {
      await tester.pumpWidget(
        buildHarnessWithRecent(purpose: 'arrival', recent: recentPair),
      );
      await tester.pumpAndSettle();

      expect(find.text('최근 검색'), findsOneWidget);
    });

    testWidgets('검색어를 입력하면 섹션이 숨겨진다', (tester) async {
      await tester.pumpWidget(
        buildHarnessWithRecent(purpose: 'departure', recent: recentPair),
      );
      await tester.pumpAndSettle();
      expect(find.text('최근 검색'), findsOneWidget);

      await tester.enterText(find.byType(TextField), '여의');
      await tester.pumpAndSettle();

      expect(find.text('최근 검색'), findsNothing);
    });

    testWidgets("'home'(지도 시작점) purpose 에서는 섹션이 노출되지 않는다",
        (tester) async {
      await tester.pumpWidget(
        buildHarnessWithRecent(purpose: 'home', recent: recentPair),
      );
      await tester.pumpAndSettle();

      expect(find.text('최근 검색'), findsNothing);
    });

    testWidgets('이력이 없으면(null) 섹션이 노출되지 않는다', (tester) async {
      await tester.pumpWidget(
        buildHarnessWithRecent(purpose: 'departure', recent: null),
      );
      await tester.pumpAndSettle();

      expect(find.text('최근 검색'), findsNothing);
    });
  });

  group('SelectedStationsNotifier.setBoth', () {
    test('출발/도착을 한 번의 상태 전이로 동시에 설정한다', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      container
          .read(selectedStationsProvider.notifier)
          .setBoth(testStations[2], testStations[4]);

      final state = container.read(selectedStationsProvider);
      expect(state.departure?.name, '여의도');
      expect(state.arrival?.name, '종합운동장');
      expect(state.isComplete, isTrue);
    });
  });
}
