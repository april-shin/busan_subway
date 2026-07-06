// RouteSearchBar 회귀 가드 위젯 테스트.
//
// RouteSearchBar는 순수 StatelessWidget이며 Provider 의존이 없으므로
// MaterialApp만으로 격리 pump 가능하다. 콜백 배선은 mocktail의
// `_Callbacks` 스파이 클래스로 호출 여부/횟수를 검증한다.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:seoul_subway/domain/entities/station.dart';
import 'package:seoul_subway/features/home/presentation/widgets/search_bar_widget.dart';

/// VoidCallback(onDepartureTap/onArrivalTap/onSwap/onSearchRoute/
/// onClearDeparture/onClearArrival)의 호출 여부를 mocktail로 스파이하기 위한 래퍼.
class _Callbacks extends Mock {
  void call();
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

  Widget buildHarness({
    Station? departure,
    Station? arrival,
    VoidCallback? onDepartureTap,
    VoidCallback? onArrivalTap,
    VoidCallback? onSwap,
    VoidCallback? onSearchRoute,
    VoidCallback? onClearDeparture,
    VoidCallback? onClearArrival,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: RouteSearchBar(
          departure: departure,
          arrival: arrival,
          onDepartureTap: onDepartureTap,
          onArrivalTap: onArrivalTap,
          onSwap: onSwap,
          onSearchRoute: onSearchRoute,
          onClearDeparture: onClearDeparture,
          onClearArrival: onClearArrival,
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
}
