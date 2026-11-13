// RouteSearchBar 회귀 가드 위젯 테스트.
//
// RouteSearchBar는 순수 StatelessWidget이며 Provider 의존이 없으므로
// MaterialApp만으로 격리 pump 가능하다. 콜백 배선은 mocktail의
// `_Callbacks` 스파이 클래스로 호출 여부/횟수를 검증한다.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:busan_subway/domain/entities/station.dart';
import 'package:busan_subway/features/home/presentation/widgets/search_bar_widget.dart';

/// VoidCallback(onDepartureTap/onArrivalTap/onSwap/onSearchRoute/
/// onClearDeparture/onClearArrival)의 호출 여부를 mocktail로 스파이하기 위한 래퍼.
class _Callbacks extends Mock {
  void call();
}

/// 경유역 콜백(onWaypointTap/onWaypointClear)은 슬롯 index를 받으므로
/// 별도 스파이로 어떤 index로 호출됐는지까지 검증한다.
class _IndexCallbacks extends Mock {
  void call(int index);
}

void main() {
  const departureStation = Station(
    id: '216',
    name: '강남',
    lineId: '2',
    latitude: 37.497,
    longitude: 127.027,
  );
  const arrivalStation = Station(
    id: '217',
    name: '역삼',
    lineId: '2',
    latitude: 37.500,
    longitude: 127.036,
  );

  const waypointStation = Station(
    id: '219',
    name: '삼성',
    lineId: '2',
    latitude: 37.508,
    longitude: 127.063,
  );
  const waypointStation2 = Station(
    id: '226',
    name: '사당',
    lineId: '2',
    latitude: 37.476,
    longitude: 126.981,
  );

  Widget buildHarness({
    Station? departure,
    Station? arrival,
    List<Station?> waypoints = const [],
    VoidCallback? onDepartureTap,
    VoidCallback? onArrivalTap,
    VoidCallback? onSwap,
    VoidCallback? onSearchRoute,
    VoidCallback? onClearDeparture,
    VoidCallback? onClearArrival,
    void Function(int index)? onWaypointTap,
    void Function(int index)? onWaypointClear,
    void Function(int index)? onAddSlotAt,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: RouteSearchBar(
          departure: departure,
          arrival: arrival,
          waypoints: waypoints,
          onDepartureTap: onDepartureTap,
          onArrivalTap: onArrivalTap,
          onSwap: onSwap,
          onSearchRoute: onSearchRoute,
          onClearDeparture: onClearDeparture,
          onClearArrival: onClearArrival,
          onWaypointTap: onWaypointTap,
          onWaypointClear: onWaypointClear,
          onAddSlotAt: onAddSlotAt,
        ),
      ),
    );
  }

  group('필드별 취소(X) 노출 조건', () {
    testWidgets('역이 선택돼 있어도 취소 콜백이 null이면 X를 노출하지 않는다',
        (tester) async {
      await tester.pumpWidget(
        buildHarness(
          departure: departureStation,
          arrival: arrivalStation,
        ),
      );

      expect(find.byIcon(Icons.close), findsNothing);
    });

    testWidgets('취소 콜백이 있어도 역이 미선택이면 X를 노출하지 않는다',
        (tester) async {
      final onClearDeparture = _Callbacks();
      final onClearArrival = _Callbacks();

      await tester.pumpWidget(
        buildHarness(
          onClearDeparture: onClearDeparture.call,
          onClearArrival: onClearArrival.call,
        ),
      );

      expect(find.byIcon(Icons.close), findsNothing);
    });

    testWidgets('출발역 선택 + onClearDeparture 주어지면 출발 필드에 X를 노출하고 '
        '탭 시 출발만 취소한다', (tester) async {
      final onClearDeparture = _Callbacks();

      await tester.pumpWidget(
        buildHarness(
          departure: departureStation,
          onClearDeparture: onClearDeparture.call,
        ),
      );

      expect(find.byIcon(Icons.close), findsOneWidget);

      await tester.tap(find.byIcon(Icons.close));
      await tester.pump();

      verify(onClearDeparture.call).called(1);
    });

    testWidgets('도착역 선택 + onClearArrival 주어지면 도착 필드에 X를 노출하고 '
        '탭 시 도착만 취소한다', (tester) async {
      final onClearArrival = _Callbacks();

      await tester.pumpWidget(
        buildHarness(
          arrival: arrivalStation,
          onClearArrival: onClearArrival.call,
        ),
      );

      expect(find.byIcon(Icons.close), findsOneWidget);

      await tester.tap(find.byIcon(Icons.close));
      await tester.pump();

      verify(onClearArrival.call).called(1);
    });

    testWidgets('출발/도착 모두 선택 시 필드별 X가 각각 노출되고 독립적으로 취소된다',
        (tester) async {
      final onClearDeparture = _Callbacks();
      final onClearArrival = _Callbacks();

      await tester.pumpWidget(
        buildHarness(
          departure: departureStation,
          arrival: arrivalStation,
          onClearDeparture: onClearDeparture.call,
          onClearArrival: onClearArrival.call,
        ),
      );

      expect(find.byIcon(Icons.close), findsNWidgets(2));

      // 첫 X(출발 필드) 탭 → 출발만 취소, 도착 취소는 호출되지 않는다.
      await tester.tap(find.byIcon(Icons.close).first);
      await tester.pump();

      verify(onClearDeparture.call).called(1);
      verifyNever(onClearArrival.call);
    });

    testWidgets('X 탭은 필드 탭(역 선택 이동)을 트리거하지 않는다', (tester) async {
      final onClearDeparture = _Callbacks();
      final onDepartureTap = _Callbacks();

      await tester.pumpWidget(
        buildHarness(
          departure: departureStation,
          onDepartureTap: onDepartureTap.call,
          onClearDeparture: onClearDeparture.call,
        ),
      );

      await tester.tap(find.byIcon(Icons.close));
      await tester.pump();

      verify(onClearDeparture.call).called(1);
      verifyNever(onDepartureTap.call);
    });
  });

  group('search 버튼 토글', () {
    testWidgets('onSearchRoute가 null이면 검색 버튼을 노출하지 않는다', (tester) async {
      await tester.pumpWidget(buildHarness(onSearchRoute: null));

      expect(find.byIcon(Icons.search), findsNothing);
    });

    testWidgets('onSearchRoute가 주어지면 검색 버튼을 노출하고 탭 시 콜백을 호출한다',
        (tester) async {
      final onSearchRoute = _Callbacks();

      await tester.pumpWidget(buildHarness(onSearchRoute: onSearchRoute.call));

      expect(find.byIcon(Icons.search), findsOneWidget);

      await tester.tap(find.byIcon(Icons.search));
      await tester.pump();

      verify(onSearchRoute.call).called(1);
    });
  });

  group('swap 배선', () {
    testWidgets('swap_vert 아이콘 탭 시 onSwap이 호출된다', (tester) async {
      final onSwap = _Callbacks();

      await tester.pumpWidget(buildHarness(onSwap: onSwap.call));

      await tester.tap(find.byIcon(Icons.swap_vert));
      await tester.pump();

      verify(onSwap.call).called(1);
    });
  });

  group('출발/도착 필드 탭', () {
    testWidgets('출발 필드 탭 시 onDepartureTap이 호출된다', (tester) async {
      final onDepartureTap = _Callbacks();

      await tester.pumpWidget(
        buildHarness(onDepartureTap: onDepartureTap.call),
      );

      await tester.tap(find.text('출발역을 선택하세요'));
      await tester.pump();

      verify(onDepartureTap.call).called(1);
    });

    testWidgets('도착 필드 탭 시 onArrivalTap이 호출된다', (tester) async {
      final onArrivalTap = _Callbacks();

      await tester.pumpWidget(
        buildHarness(onArrivalTap: onArrivalTap.call),
      );

      await tester.tap(find.text('도착역을 선택하세요'));
      await tester.pump();

      verify(onArrivalTap.call).called(1);
    });
  });

  group('표시 상태', () {
    testWidgets('출발/도착이 null이면 placeholder 문구를 노출한다', (tester) async {
      await tester.pumpWidget(buildHarness());

      expect(find.text('출발역을 선택하세요'), findsOneWidget);
      expect(find.text('도착역을 선택하세요'), findsOneWidget);
    });

    testWidgets('station이 주어지면 역 이름을 노출하고 placeholder는 사라진다',
        (tester) async {
      await tester.pumpWidget(
        buildHarness(departure: departureStation, arrival: arrivalStation),
      );

      expect(find.text('강남'), findsOneWidget);
      expect(find.text('역삼'), findsOneWidget);
      expect(find.text('출발역을 선택하세요'), findsNothing);
      expect(find.text('도착역을 선택하세요'), findsNothing);
    });
  });

  group('경유역', () {
    testWidgets('waypoints 가 비면 경유 필드를 그리지 않는다', (tester) async {
      await tester.pumpWidget(buildHarness());

      expect(find.byIcon(Icons.adjust), findsNothing);
    });

    testWidgets('waypoints 를 순서대로 출발/도착 사이에 그린다', (tester) async {
      await tester.pumpWidget(
        buildHarness(
          departure: departureStation,
          arrival: arrivalStation,
          waypoints: const [waypointStation, waypointStation2],
        ),
      );

      expect(find.byIcon(Icons.adjust), findsNWidgets(2));
      expect(find.text('삼성'), findsOneWidget);
      expect(find.text('사당'), findsOneWidget);

      // 세로 배치 순서: 출발(강남) → 경유1(삼성) → 경유2(사당) → 도착(역삼)
      double dy(String name) => tester.getTopLeft(find.text(name)).dy;
      expect(dy('강남'), lessThan(dy('삼성')));
      expect(dy('삼성'), lessThan(dy('사당')));
      expect(dy('사당'), lessThan(dy('역삼')));
    });

    testWidgets('경유 필드 탭 시 해당 index 로 onWaypointTap 이 호출된다',
        (tester) async {
      final onWaypointTap = _IndexCallbacks();

      await tester.pumpWidget(
        buildHarness(
          waypoints: const [waypointStation, waypointStation2],
          onWaypointTap: onWaypointTap.call,
        ),
      );

      await tester.tap(find.text('사당'));
      await tester.pump();

      verify(() => onWaypointTap.call(1)).called(1);
      verifyNever(() => onWaypointTap.call(0));
    });

    testWidgets('경유 필드의 X 탭 시 해당 index 로 onWaypointClear 만 호출된다',
        (tester) async {
      final onWaypointTap = _IndexCallbacks();
      final onWaypointClear = _IndexCallbacks();

      await tester.pumpWidget(
        buildHarness(
          waypoints: const [waypointStation, waypointStation2],
          onWaypointTap: onWaypointTap.call,
          onWaypointClear: onWaypointClear.call,
        ),
      );

      expect(find.byIcon(Icons.close), findsNWidgets(2));

      await tester.tap(find.byIcon(Icons.close).first);
      await tester.pump();

      verify(() => onWaypointClear.call(0)).called(1);
      verifyNever(() => onWaypointTap.call(0));
    });

  });

  group('빈 경유지 칸', () {
    testWidgets('빈 칸(null)은 안내 문구와 함께 그려진다', (tester) async {
      await tester.pumpWidget(
        buildHarness(
          departure: departureStation,
          arrival: arrivalStation,
          waypoints: const [null],
        ),
      );

      expect(find.byIcon(Icons.adjust), findsOneWidget);
      expect(find.text('경유역을 선택하세요'), findsOneWidget);
    });

    testWidgets('빈 칸도 X 로 지울 수 있다 (출발/도착과 다른 점)', (tester) async {
      final onWaypointClear = _IndexCallbacks();

      await tester.pumpWidget(
        buildHarness(
          // 출발·도착은 미선택 + 취소 콜백 없음 → X 없음.
          waypoints: const [null],
          onWaypointClear: onWaypointClear.call,
        ),
      );

      expect(find.byIcon(Icons.close), findsOneWidget);

      await tester.tap(find.byIcon(Icons.close));
      await tester.pump();

      verify(() => onWaypointClear.call(0)).called(1);
    });

    testWidgets('빈 칸을 탭하면 그 index 로 onWaypointTap 이 호출된다',
        (tester) async {
      final onWaypointTap = _IndexCallbacks();

      await tester.pumpWidget(
        buildHarness(
          waypoints: const [waypointStation, null],
          onWaypointTap: onWaypointTap.call,
        ),
      );

      await tester.tap(find.text('경유역을 선택하세요'));
      await tester.pump();

      verify(() => onWaypointTap.call(1)).called(1);
      verifyNever(() => onWaypointTap.call(0));
    });

    testWidgets('채워진 칸과 빈 칸이 섞여도 순서대로 그려진다', (tester) async {
      await tester.pumpWidget(
        buildHarness(
          departure: departureStation,
          arrival: arrivalStation,
          waypoints: const [waypointStation, null, waypointStation2],
        ),
      );

      double dy(Finder f) => tester.getTopLeft(f).dy;
      expect(dy(find.text('강남')), lessThan(dy(find.text('삼성'))));
      expect(
        dy(find.text('삼성')),
        lessThan(dy(find.text('경유역을 선택하세요'))),
      );
      expect(
        dy(find.text('경유역을 선택하세요')),
        lessThan(dy(find.text('사당'))),
      );
      expect(dy(find.text('사당')), lessThan(dy(find.text('역삼'))));
    });
  });

  group('경유 추가(+) 버튼', () {
    testWidgets('onAddSlotAt 가 null 이면 어떤 필드에도 + 를 그리지 않는다',
        (tester) async {
      await tester.pumpWidget(
        buildHarness(
          departure: departureStation,
          arrival: arrivalStation,
          waypoints: const [waypointStation],
          onAddSlotAt: null,
        ),
      );

      expect(find.byIcon(Icons.add), findsNothing);
    });

    testWidgets('출발 필드에는 + 가 없고 경유·도착 필드에만 있다', (tester) async {
      final onInsert = _IndexCallbacks();

      await tester.pumpWidget(
        buildHarness(
          departure: departureStation,
          arrival: arrivalStation,
          waypoints: const [waypointStation, waypointStation2],
          onAddSlotAt: onInsert.call,
        ),
      );

      // 경유 2개 + 도착 1개 = 3개. 출발 필드는 제외.
      expect(find.byIcon(Icons.add), findsNWidgets(3));

      // 첫 + 는 출발(강남) 아래·첫 경유(삼성) 행에 있어야 한다.
      final firstAddY = tester.getTopLeft(find.byIcon(Icons.add).first).dy;
      expect(firstAddY, greaterThan(tester.getTopLeft(find.text('강남')).dy));
    });

    testWidgets('경유 필드의 + 는 그 아래(index+1)에 삽입을 요청한다', (tester) async {
      final onInsert = _IndexCallbacks();

      await tester.pumpWidget(
        buildHarness(
          departure: departureStation,
          arrival: arrivalStation,
          waypoints: const [waypointStation, waypointStation2],
          onAddSlotAt: onInsert.call,
        ),
      );

      // 첫 경유(삼성, index 0)의 + → 그 아래(index 1)에 삽입.
      // 삼성 위(index 0)가 아니어야 한다.
      await tester.tap(find.byIcon(Icons.add).first);
      await tester.pump();

      verify(() => onInsert.call(1)).called(1);
      verifyNever(() => onInsert.call(0));
    });

    testWidgets('마지막 경유 필드의 + 와 도착 필드의 + 는 같은 자리를 요청한다',
        (tester) async {
      final onInsert = _IndexCallbacks();

      await tester.pumpWidget(
        buildHarness(
          departure: departureStation,
          arrival: arrivalStation,
          waypoints: const [waypointStation, waypointStation2],
          onAddSlotAt: onInsert.call,
        ),
      );

      // 마지막 경유(사당, index 1) 아래 = 도착 위 = index 2. 두 + 가 같은 위치를
      // 가리키는 것이 정상이다(사이에 다른 정차역이 없으므로).
      await tester.tap(find.byIcon(Icons.add).at(1));
      await tester.pump();
      verify(() => onInsert.call(2)).called(1);

      await tester.tap(find.byIcon(Icons.add).last);
      await tester.pump();
      verify(() => onInsert.call(2)).called(1);
    });

    testWidgets('도착 필드의 + 는 맨 뒤(waypoints.length)에 삽입을 요청한다',
        (tester) async {
      final onInsert = _IndexCallbacks();

      await tester.pumpWidget(
        buildHarness(
          departure: departureStation,
          arrival: arrivalStation,
          waypoints: const [waypointStation, waypointStation2],
          onAddSlotAt: onInsert.call,
        ),
      );

      // 마지막 + 가 도착 필드의 것.
      await tester.tap(find.byIcon(Icons.add).last);
      await tester.pump();

      verify(() => onInsert.call(2)).called(1);
    });

    testWidgets('경유역이 없으면 도착 필드의 + 만 있고 index 0 을 요청한다',
        (tester) async {
      final onInsert = _IndexCallbacks();

      await tester.pumpWidget(
        buildHarness(
          departure: departureStation,
          arrival: arrivalStation,
          onAddSlotAt: onInsert.call,
        ),
      );

      expect(find.byIcon(Icons.add), findsOneWidget);

      await tester.tap(find.byIcon(Icons.add));
      await tester.pump();

      verify(() => onInsert.call(0)).called(1);
    });

    testWidgets('역이 선택되지 않은 도착 필드에도 + 를 노출한다', (tester) async {
      final onInsert = _IndexCallbacks();

      await tester.pumpWidget(
        buildHarness(onAddSlotAt: onInsert.call),
      );

      // 도착역 미선택 → X 는 없지만 + 는 있어야 한다.
      expect(find.byIcon(Icons.close), findsNothing);
      expect(find.byIcon(Icons.add), findsOneWidget);
    });

    testWidgets('+ 탭은 필드 탭(역 선택 이동)을 트리거하지 않는다', (tester) async {
      final onInsert = _IndexCallbacks();
      final onArrivalTap = _Callbacks();

      await tester.pumpWidget(
        buildHarness(
          arrival: arrivalStation,
          onArrivalTap: onArrivalTap.call,
          onAddSlotAt: onInsert.call,
        ),
      );

      await tester.tap(find.byIcon(Icons.add));
      await tester.pump();

      verify(() => onInsert.call(0)).called(1);
      verifyNever(onArrivalTap.call);
    });

    testWidgets('+ 와 X 가 함께 있을 때 + 가 X 좌측이다', (tester) async {
      final onInsert = _IndexCallbacks();
      final onClearArrival = _Callbacks();

      await tester.pumpWidget(
        buildHarness(
          arrival: arrivalStation,
          onClearArrival: onClearArrival.call,
          onAddSlotAt: onInsert.call,
        ),
      );

      final addX = tester.getCenter(find.byIcon(Icons.add)).dx;
      final closeX = tester.getCenter(find.byIcon(Icons.close)).dx;
      expect(addX, lessThan(closeX));
    });

    testWidgets('+ 와 X 는 같은 진한 회색을 쓴다', (tester) async {
      final onInsert = _IndexCallbacks();
      final onClearArrival = _Callbacks();

      await tester.pumpWidget(
        buildHarness(
          arrival: arrivalStation,
          onClearArrival: onClearArrival.call,
          onAddSlotAt: onInsert.call,
        ),
      );

      Color? colorOf(IconData icon) =>
          tester.widget<Icon>(find.byIcon(icon)).color;

      // 두 액션은 색으로 구분하지 않는다 — 모양(+/×)과 위치로만 구분.
      expect(colorOf(Icons.add), colorOf(Icons.close));
      // grey 500(#9E9E9E) 처럼 흐린 톤으로 되돌아가지 않도록 값을 고정한다.
      expect(colorOf(Icons.add), const Color(0xFF616161));
    });
  });
}
