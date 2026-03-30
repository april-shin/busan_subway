import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seoul_subway/domain/entities/arrival_info.dart';
import 'package:seoul_subway/features/arrival_info/presentation/widgets/arrival_card.dart';

void main() {
  // receivedAt를 현재 시각으로 설정하여 경과 시간 0초로 테스트
  DateTime freshReceivedAt() => DateTime.now();

  Widget buildTestWidget(ArrivalInfo arrival) {
    return MaterialApp(
      home: Scaffold(
        body: ArrivalCard(arrival: arrival),
      ),
    );
  }

  group('ArrivalCard', () {
    testWidgets('arrivalSeconds가 null이면 배지 미표시', (WidgetTester tester) async {
      await tester.pumpWidget(buildTestWidget(ArrivalInfo(
        subwayId: '1002',
        stationName: '강남',
        trainLineNm: '2호선 성수행',
        direction: '상행',
        arrivalMessage: '역삼 도착',
        destination: '시청',
        trainType: '일반',
        arrivalSeconds: null,
        receivedAt: freshReceivedAt(),
      )));

      expect(find.text('3분'), findsNothing);
      expect(find.text('약 3분'), findsNothing);
    });

    testWidgets('실제값일 때 기본 스타일로 표시', (WidgetTester tester) async {
      await tester.pumpWidget(buildTestWidget(ArrivalInfo(
        subwayId: '1002',
        stationName: '강남',
        trainLineNm: '2호선 성수행',
        direction: '상행',
        arrivalMessage: '역삼 도착',
        destination: '시청',
        trainType: '일반',
        arrivalSeconds: 180,
        receivedAt: freshReceivedAt(),
        isEstimated: false,
      )));

      expect(find.text('3분'), findsOneWidget);
      expect(find.text('0초'), findsOneWidget);
      expect(find.text('약 3분'), findsNothing);
    });

    testWidgets('추정값일 때 "약 N분" 형태로 표시', (WidgetTester tester) async {
      await tester.pumpWidget(buildTestWidget(ArrivalInfo(
        subwayId: '1002',
        stationName: '강남',
        trainLineNm: '2호선 성수행',
        direction: '상행',
        arrivalMessage: '역삼 도착',
        destination: '시청',
        trainType: '일반',
        arrivalSeconds: 180,
        receivedAt: freshReceivedAt(),
        isEstimated: true,
      )));

      expect(find.text('약 3분'), findsOneWidget);
      expect(find.text('0초'), findsNothing);
    });

    testWidgets('추정값: 주황색 배경 사용', (WidgetTester tester) async {
      await tester.pumpWidget(buildTestWidget(ArrivalInfo(
        subwayId: '1002',
        stationName: '강남',
        trainLineNm: '2호선 성수행',
        direction: '상행',
        arrivalMessage: '역삼 도착',
        destination: '시청',
        trainType: '일반',
        arrivalSeconds: 180,
        receivedAt: freshReceivedAt(),
        isEstimated: true,
      )));

      final container = tester.widget<Container>(
        find.ancestor(
          of: find.text('약 3분'),
          matching: find.byType(Container),
        ).first,
      );
      final decoration = container.decoration as BoxDecoration;
      expect(decoration.color, Colors.orange[50]);
    });

    testWidgets('실제값 1분 이내: 빨간색 배경 사용', (WidgetTester tester) async {
      await tester.pumpWidget(buildTestWidget(ArrivalInfo(
        subwayId: '1002',
        stationName: '강남',
        trainLineNm: '2호선 성수행',
        direction: '상행',
        arrivalMessage: '역삼 진입',
        destination: '시청',
        trainType: '일반',
        arrivalSeconds: 30,
        receivedAt: freshReceivedAt(),
        isEstimated: false,
      )));

      expect(find.text('30초'), findsOneWidget);
      final container = tester.widget<Container>(
        find.ancestor(
          of: find.text('30초'),
          matching: find.byType(Container),
        ).first,
      );
      final decoration = container.decoration as BoxDecoration;
      expect(decoration.color, Colors.red[50]);
    });

    testWidgets('추정값 1분 이내: 주황색 배경 (빨간색 아님)', (WidgetTester tester) async {
      await tester.pumpWidget(buildTestWidget(ArrivalInfo(
        subwayId: '1002',
        stationName: '강남',
        trainLineNm: '2호선 성수행',
        direction: '상행',
        arrivalMessage: '역삼 진입',
        destination: '시청',
        trainType: '일반',
        arrivalSeconds: 30,
        receivedAt: freshReceivedAt(),
        isEstimated: true,
      )));

      expect(find.text('약 30초'), findsOneWidget);
      final container = tester.widget<Container>(
        find.ancestor(
          of: find.text('약 30초'),
          matching: find.byType(Container),
        ).first,
      );
      final decoration = container.decoration as BoxDecoration;
      expect(decoration.color, Colors.orange[50]);
    });

    testWidgets('receivedAt 경과 시간만큼 카운트다운', (WidgetTester tester) async {
      // 10초 전에 받은 데이터: 180초 - 10초 = 170초 = 2분 50초
      final tenSecondsAgo = DateTime.now().subtract(const Duration(seconds: 10));
      await tester.pumpWidget(buildTestWidget(ArrivalInfo(
        subwayId: '1002',
        stationName: '강남',
        trainLineNm: '2호선 성수행',
        direction: '상행',
        arrivalMessage: '역삼 도착',
        destination: '시청',
        trainType: '일반',
        arrivalSeconds: 180,
        receivedAt: tenSecondsAgo,
        isEstimated: false,
      )));

      expect(find.text('2분'), findsOneWidget);
      expect(find.text('50초'), findsOneWidget);
    });

    testWidgets('경과 시간이 arrivalSeconds를 초과하면 0초', (WidgetTester tester) async {
      final longAgo = DateTime.now().subtract(const Duration(seconds: 100));
      await tester.pumpWidget(buildTestWidget(ArrivalInfo(
        subwayId: '1002',
        stationName: '강남',
        trainLineNm: '2호선 성수행',
        direction: '상행',
        arrivalMessage: '역삼 도착',
        destination: '시청',
        trainType: '일반',
        arrivalSeconds: 30,
        receivedAt: longAgo,
        isEstimated: false,
      )));

      expect(find.text('0초'), findsOneWidget);
    });
  });
}
