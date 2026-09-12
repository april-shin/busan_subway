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
    // 동명이역: 5호선 양평(서울 영등포구) ↔ 경의중앙선 양평(경기 양평군), 약 53km.
    // 이름만으로 중복 제거하면 뒤쪽(K50)이 사라져 검색으로 선택할 수 없다.
    const Station(
      id: '513',
      name: '양평',
      lineId: '5',
      latitude: 37.5273,
      longitude: 126.8874,
    ),
    const Station(
      id: 'K50',
      name: '양평',
      lineId: '경의중앙',
      latitude: 37.4895,
      longitude: 127.4879,
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

  group('초성 검색', () {
    testWidgets('초성만 입력해도 해당 역이 걸린다', (tester) async {
      await tester.pumpWidget(buildHarness());
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'ㅈㅅㅅㄴ');
      await tester.pumpAndSettle();

      expect(find.text('잠실새내'), findsOneWidget);
      expect(find.text('여의도'), findsNothing);
      expect(find.text('종합운동장'), findsNothing);
    });

    testWidgets('완성형 검색은 기존과 동일하게 동작한다', (tester) async {
      await tester.pumpWidget(buildHarness());
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), '여의');
      await tester.pumpAndSettle();

      expect(find.text('여의도'), findsOneWidget);
      expect(find.text('잠실새내'), findsNothing);
    });

    testWidgets('조합 중 종성이 흡수돼도 목록이 비지 않는다', (tester) async {
      await tester.pumpWidget(buildHarness());
      await tester.pumpAndSettle();

      // '여의도' 를 치는 도중 ㄷ 이 앞 글자 '의' 의 종성으로 흡수된 상태.
      // IME 는 이때 'ㄷ' 이 아니라 '여읟' 을 내보낸다.
      await tester.enterText(find.byType(TextField), '여읟');
      await tester.pumpAndSettle();

      expect(find.text('여의도'), findsOneWidget);
      expect(find.text('검색 결과가 없습니다'), findsNothing);
    });

    testWidgets('겹받침으로 흡수된 조합 중 상태도 복구된다', (tester) async {
      await tester.pumpWidget(buildHarness());
      await tester.pumpAndSettle();

      // '잠실새내' 를 치는 도중 ㅅ 이 '실' 의 종성 ㄹ 과 겹쳐 ㄽ 이 된 상태.
      await tester.enterText(find.byType(TextField), '잠싨');
      await tester.pumpAndSettle();

      expect(find.text('잠실새내'), findsOneWidget);
    });

    testWidgets('매칭이 없으면 안내 문구가 그대로 보인다', (tester) async {
      await tester.pumpWidget(buildHarness());
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'ㅋㅋㅋ');
      await tester.pumpAndSettle();

      expect(find.text('검색 결과가 없습니다'), findsOneWidget);
    });
  });

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

  group('동명이역(양평)', () {
    testWidgets('이름이 같아도 멀리 떨어진 두 역은 각각 표시된다', (tester) async {
      await tester.pumpWidget(buildHarness());
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), '양평');
      await tester.pumpAndSettle();

      // 검색어를 담은 TextField 도 '양평' 텍스트를 갖고 있으므로 목록 항목만 센다.
      expect(
        find.descendant(
          of: find.byType(ListTile),
          matching: find.text('양평'),
        ),
        findsNWidgets(2),
      );
      // 노선 뱃지로 구분된다.
      expect(find.text('5호선'), findsOneWidget);
      expect(find.text('경의중앙선'), findsOneWidget);
    });

    testWidgets('경의중앙선 양평을 탭하면 K50 이 선택된다', (tester) async {
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

      await tester.enterText(find.byType(TextField), '양평');
      await tester.pumpAndSettle();

      // 경의중앙선 뱃지가 붙은 항목(두 번째)을 탭.
      await tester.tap(find.text('경의중앙선'));
      await tester.pumpAndSettle();

      final selected = container.read(selectedStationsProvider).departure;
      expect(selected?.id, 'K50');
      expect(selected?.lineId, '경의중앙');
    });
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
