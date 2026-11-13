import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:busan_subway/domain/entities/transfer_guide.dart';
import 'package:busan_subway/features/route_search/presentation/widgets/transfer_row.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(
        home: Scaffold(
          body: Directionality(
            textDirection: TextDirection.ltr,
            child: child,
          ),
        ),
      );

  group('TransferRow', () {
    testWidgets('guide == null이면 "환승 도보 N분"만 렌더된다', (tester) async {
      await tester.pumpWidget(
        wrap(const TransferRow(transferMinutes: 3, guide: null)),
      );

      expect(find.textContaining('환승 도보 3분'), findsOneWidget);
      expect(find.textContaining('빠른 환승'), findsNothing);
      expect(find.textContaining('내리는문'), findsNothing);
    });

    testWidgets(
        'doorSide + car + door 모두 있으면 "환승 도보 2분 · 빠른 환승 6-3 · 내리는문 왼쪽" 렌더',
        (tester) async {
      const guide = TransferGuide(
        doorSide: DoorSide.left,
        car: 6,
        door: 3,
      );

      await tester.pumpWidget(
        wrap(const TransferRow(transferMinutes: 2, guide: guide)),
      );

      expect(
        find.textContaining('환승 도보 2분 · 빠른 환승 6-3 · 내리는문 왼쪽'),
        findsOneWidget,
      );
    });

    testWidgets('doorSide=right + car + door이면 "내리는문 오른쪽" 렌더', (tester) async {
      const guide = TransferGuide(
        doorSide: DoorSide.right,
        car: 5,
        door: 1,
      );

      await tester.pumpWidget(
        wrap(const TransferRow(transferMinutes: 1, guide: guide)),
      );

      expect(
        find.textContaining('환승 도보 1분 · 빠른 환승 5-1 · 내리는문 오른쪽'),
        findsOneWidget,
      );
    });

    testWidgets('car만 있으면 "환승 도보 N분 · 6번 칸"만 렌더', (tester) async {
      const guide = TransferGuide(car: 6);

      await tester.pumpWidget(
        wrap(const TransferRow(transferMinutes: 2, guide: guide)),
      );

      expect(find.textContaining('환승 도보 2분 · 6번 칸'), findsOneWidget);
      expect(find.textContaining('내리는문'), findsNothing);
    });

    testWidgets('door만 있으면 "환승 도보 N분 · 3번 문" 렌더', (tester) async {
      const guide = TransferGuide(door: 3);

      await tester.pumpWidget(
        wrap(const TransferRow(transferMinutes: 2, guide: guide)),
      );

      expect(find.textContaining('환승 도보 2분 · 3번 문'), findsOneWidget);
    });

    testWidgets('doorSide만 있으면 "환승 도보 N분 · 내리는문 왼쪽" 렌더', (tester) async {
      const guide = TransferGuide(doorSide: DoorSide.left);

      await tester.pumpWidget(
        wrap(const TransferRow(transferMinutes: 2, guide: guide)),
      );

      expect(find.textContaining('환승 도보 2분 · 내리는문 왼쪽'), findsOneWidget);
      expect(find.textContaining('빠른 환승'), findsNothing);
    });

    testWidgets('모든 필드가 null인 guide는 기본 UI와 동일', (tester) async {
      const guide = TransferGuide();

      await tester.pumpWidget(
        wrap(const TransferRow(transferMinutes: 4, guide: guide)),
      );

      expect(find.textContaining('환승 도보 4분'), findsOneWidget);
      expect(find.textContaining('빠른 환승'), findsNothing);
      expect(find.textContaining('내리는문'), findsNothing);
    });

    testWidgets('transferMinutes==0 이면 "같은 승강장 환승" 으로 표시 (9호선 모드 전환 등)',
        (tester) async {
      await tester.pumpWidget(
        wrap(const TransferRow(transferMinutes: 0, guide: null)),
      );

      expect(find.textContaining('같은 승강장 환승'), findsOneWidget);
      expect(find.textContaining('환승 도보'), findsNothing,
          reason: '0분일 때는 "환승 도보 0분" 대신 "같은 승강장 환승" 노출');
    });

    testWidgets('transferMinutes==0 + guide 있으면 "같은 승강장 환승 · 빠른 환승 X-Y" 렌더',
        (tester) async {
      const guide = TransferGuide(
        doorSide: DoorSide.right,
        car: 4,
        door: 2,
      );

      await tester.pumpWidget(
        wrap(const TransferRow(transferMinutes: 0, guide: guide)),
      );

      expect(
        find.textContaining('같은 승강장 환승 · 빠른 환승 4-2 · 내리는문 오른쪽'),
        findsOneWidget,
      );
    });

    testWidgets('note가 있으면 본문 뒤에 회색 보조 텍스트로 렌더', (tester) async {
      const guide = TransferGuide(
        doorSide: DoorSide.right,
        car: 6,
        door: 3,
        note: '충무로 방면 가까움',
      );

      await tester.pumpWidget(
        wrap(const TransferRow(transferMinutes: 2, guide: guide)),
      );

      expect(find.textContaining('충무로 방면 가까움'), findsOneWidget);
    });
  });
}
