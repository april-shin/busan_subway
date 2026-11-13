import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:busan_subway/core/constants/api_constants.dart';
import 'package:busan_subway/domain/entities/arrival_info.dart';
import 'package:busan_subway/features/arrival_info/presentation/widgets/arrival_card.dart';

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

      // 30초 이하는 숫자 대신 "곧 도착"(지도 말풍선과 동일 임계).
      expect(find.text('곧 도착'), findsOneWidget);
      expect(find.text('30초'), findsNothing);
      final container = tester.widget<Container>(
        find.ancestor(
          of: find.text('곧 도착'),
          matching: find.byType(Container),
        ).first,
      );
      final decoration = container.decoration as BoxDecoration;
      expect(decoration.color, Colors.red[50]);
    });

    testWidgets('"곧 도착" 경계: 30초는 곧 도착, 31초는 숫자', (WidgetTester tester) async {
      ArrivalInfo at(int secs) => ArrivalInfo(
            subwayId: '1002',
            stationName: '강남',
            trainLineNm: '2호선 성수행',
            direction: '상행',
            arrivalMessage: '역삼 진입',
            destination: '시청',
            trainType: '일반',
            arrivalSeconds: secs,
            receivedAt: freshReceivedAt(),
            isEstimated: false,
          );

      await tester.pumpWidget(buildTestWidget(at(30)));
      expect(find.text('곧 도착'), findsOneWidget);

      await tester.pumpWidget(buildTestWidget(at(31)));
      expect(find.text('31초'), findsOneWidget);
      expect(find.text('곧 도착'), findsNothing);
    });

    testWidgets('추정값은 30초 이하여도 "곧 도착"으로 단정하지 않는다',
        (WidgetTester tester) async {
      await tester.pumpWidget(buildTestWidget(ArrivalInfo(
        subwayId: '1002',
        stationName: '강남',
        trainLineNm: '2호선 성수행',
        direction: '상행',
        arrivalMessage: '역삼 진입',
        destination: '시청',
        trainType: '일반',
        arrivalSeconds: 20,
        receivedAt: freshReceivedAt(),
        isEstimated: true,
      )));

      expect(find.text('약 20초'), findsOneWidget);
      expect(find.text('곧 도착'), findsNothing);
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

    testWidgets('경과 시간이 arrivalSeconds를 초과하면 "정보 없음" (0초 아님)',
        (WidgetTester tester) async {
      // 예정 시각이 이미 지난 값은 "곧 도착(0초)"이 아니라 알 수 없음이다.
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

      expect(find.text('0초'), findsNothing);
      expect(find.text('정보 없음'), findsOneWidget);
    });

    testWidgets('도착 상태(0초)는 데이터가 신선하면 "곧 도착"', (WidgetTester tester) async {
      await tester.pumpWidget(buildTestWidget(ArrivalInfo(
        subwayId: '1002',
        stationName: '강남',
        trainLineNm: '2호선 성수행',
        direction: '상행',
        arrivalMessage: '강남 도착',
        destination: '시청',
        trainType: '일반',
        arrivalSeconds: 0,
        receivedAt: DateTime.now().subtract(const Duration(seconds: 30)),
        isEstimated: false,
      )));

      expect(find.text('곧 도착'), findsOneWidget);
      expect(find.text('정보 없음'), findsNothing);
    });

    testWidgets('도착 상태(0초)라도 데이터가 grace 를 넘겨 낡으면 "정보 없음"',
        (WidgetTester tester) async {
      // GTX-A 수서(recptnDt 지연 817초)·서해선 대곡(777초) 실측 케이스.
      await tester.pumpWidget(buildTestWidget(ArrivalInfo(
        subwayId: '1032',
        stationName: '수서',
        trainLineNm: '수서행 - 수서방면',
        direction: '상행',
        arrivalMessage: '수서 도착',
        destination: '수서',
        trainType: '일반',
        arrivalSeconds: 0,
        receivedAt: DateTime.now().subtract(
          ApiConstants.arrivalStateGrace + const Duration(seconds: 30),
        ),
        isEstimated: false,
      )));

      expect(find.text('0초'), findsNothing);
      expect(find.text('정보 없음'), findsOneWidget);
    });
  });
}
