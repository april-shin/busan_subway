import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:seoul_subway/domain/entities/route_result.dart';
import 'package:seoul_subway/domain/entities/station.dart';
import 'package:seoul_subway/domain/repositories/arrival_repository.dart';
import 'package:seoul_subway/features/arrival_info/presentation/providers/arrival_providers.dart';
import 'package:seoul_subway/features/route_search/presentation/screens/route_result_screen.dart';

class _MockArrivalRepository extends Mock implements ArrivalRepository {}

void main() {
  const station1 = Station(
    id: '901',
    name: '김포공항',
    lineId: '9',
    latitude: 37.56,
    longitude: 126.80,
  );
  const station2 = Station(
    id: '902',
    name: '공항시장',
    lineId: '9',
    latitude: 37.56,
    longitude: 126.81,
  );
  const station3 = Station(
    id: '903',
    name: '신방화',
    lineId: '9',
    latitude: 37.56,
    longitude: 126.82,
  );

  late _MockArrivalRepository mockRepo;

  setUp(() {
    mockRepo = _MockArrivalRepository();
    when(() => mockRepo.getArrivalInfo(any())).thenAnswer((_) async => []);
  });

  /// 기본 단일 RouteResult — 완행 9호선 시각 시나리오.
  RouteResult buildLocal({int total = 300, String lineId = '9'}) {
    return RouteResult(
      segments: [
        RouteSegment(
          lineId: lineId,
          lineName: '9호선',
          stations: const [station1, station2, station3],
          durationSeconds: total,
          direction: '신방화 방면',
        ),
      ],
      totalTimeSeconds: total,
      transferCount: 0,
      stationCount: 3,
    );
  }

  /// 가상 급행 RouteResult — 첫 세그먼트가 `9E`.
  RouteResult buildExpress({int total = 180}) {
    return RouteResult(
      segments: [
        RouteSegment(
          lineId: '9E',
          lineName: '9호선',
          stations: const [station1, station3],
          durationSeconds: total,
          direction: '신방화 방면',
        ),
      ],
      totalTimeSeconds: total,
      transferCount: 0,
      stationCount: 2,
    );
  }

  Widget buildApp({
    required RouteResult fastest,
    RouteResult? leastTransfer,
    RouteResult? fastestExpress,
    RouteResult? fastestLocal,
  }) {
    return ProviderScope(
      overrides: [
        arrivalRepositoryProvider.overrideWithValue(mockRepo),
      ],
      child: MaterialApp(
        home: RouteResultScreen(
          fastest: fastest,
          leastTransfer: leastTransfer,
          fastestExpress: fastestExpress,
          fastestLocal: fastestLocal,
          departureStationName: station1.name,
        ),
      ),
    );
  }

  group('Case C — 단일 경로 (탭 없음)', () {
    testWidgets('탭과 토글이 모두 부재', (tester) async {
      final route = buildLocal();
      await tester.pumpWidget(buildApp(fastest: route));
      await tester.pump(const Duration(milliseconds: 50));

      // 탭 라벨 부재
      expect(find.text('최단시간'), findsNothing);
      expect(find.text('최소환승'), findsNothing);
      // 모드 탭/토글 모두 부재
      expect(find.text('급행'), findsNothing);
      expect(find.text('완행'), findsNothing);
    });
  });

  group('Case A — 환승 트레이드오프 (최단시간/최소환승)', () {
    testWidgets('탭 라벨이 "최단시간/최소환승"이고 모드 토글은 없다',
        (tester) async {
      final fastest = buildLocal(total: 180);
      final leastTransfer = buildLocal(total: 240);

      await tester.pumpWidget(buildApp(
        fastest: fastest,
        leastTransfer: leastTransfer,
      ));
      await tester.pump(const Duration(milliseconds: 50));

      // 환승 탭 라벨 존재
      expect(find.text('최단시간'), findsOneWidget);
      expect(find.text('최소환승'), findsOneWidget);
      // 모드 탭은 없어야 한다
      expect(find.text('급행'), findsNothing);
      expect(find.text('완행'), findsNothing);
    });

    testWidgets('fastestExpress/fastestLocal 함께 전달돼도 환승 탭이 우선',
        (tester) async {
      // 우선순위: leastTransfer가 있으면 환승 트레이드오프가 우선.
      final fastest = buildLocal(total: 180);
      final leastTransfer = buildLocal(total: 240);
      final fastestExpress = buildExpress(total: 120);
      final fastestLocal = buildLocal(total: 220);

      await tester.pumpWidget(buildApp(
        fastest: fastest,
        leastTransfer: leastTransfer,
        fastestExpress: fastestExpress,
        fastestLocal: fastestLocal,
      ));
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('최단시간'), findsOneWidget);
      expect(find.text('최소환승'), findsOneWidget);
      expect(find.text('완행'), findsNothing);
    });
  });

  group('Case B — 모드 트레이드오프 (급행/완행)', () {
    testWidgets('탭 라벨이 "급행/완행"이고 급행이 왼쪽에 위치',
        (tester) async {
      final fastestExpress = buildExpress(total: 180);
      final fastestLocal = buildLocal(total: 300);
      final fastest = fastestExpress; // 둘 중 더 빠른 쪽이 fastest

      await tester.pumpWidget(buildApp(
        fastest: fastest,
        fastestExpress: fastestExpress,
        fastestLocal: fastestLocal,
      ));
      await tester.pump(const Duration(milliseconds: 50));

      // 환승 탭 라벨 부재
      expect(find.text('최단시간'), findsNothing);
      expect(find.text('최소환승'), findsNothing);

      // 모드 탭 라벨 존재 — '급행' 텍스트는 탭 라벨 + 세그먼트 배지에 두 번 등장 가능.
      expect(find.text('완행'), findsOneWidget);
      expect(find.text('급행'), findsWidgets);

      // 급행 탭이 완행 탭보다 왼쪽에 위치 (급행 기본값)
      final expressTab = find.text('급행').first;
      final localTab = find.text('완행');
      final expressX = tester.getTopLeft(expressTab).dx;
      final localX = tester.getTopLeft(localTab).dx;
      expect(expressX, lessThan(localX),
          reason: '급행 탭이 완행 탭보다 왼쪽에 위치');
    });

    testWidgets('급행 탭은 가상 급행 노선(`9E`) 시간을 표시', (tester) async {
      // 급행 단독: 3분(180초), 완행 단독: 5분(300초)
      final fastestExpress = buildExpress(total: 180);
      final fastestLocal = buildLocal(total: 300);

      await tester.pumpWidget(buildApp(
        fastest: fastestExpress,
        fastestExpress: fastestExpress,
        fastestLocal: fastestLocal,
      ));
      await tester.pump(const Duration(milliseconds: 50));

      // 기본은 좌측 탭(급행) — 3분 노출
      expect(find.textContaining('3분'), findsWidgets);

      // 완행 탭으로 전환 (TabBarView lazy 빌드 + 애니메이션 완료 대기)
      await tester.tap(find.text('완행'));
      await tester.pumpAndSettle();

      // 완행 탭: 5분 노출
      expect(find.textContaining('5분'), findsWidgets);
    });

    testWidgets('두 모드 시간이 같으면 단일 탭으로 폴백', (tester) async {
      final express = buildExpress(total: 200);
      final local = buildLocal(total: 200);

      await tester.pumpWidget(buildApp(
        fastest: express,
        fastestExpress: express,
        fastestLocal: local,
      ));
      await tester.pump(const Duration(milliseconds: 50));

      // 시간이 같으므로 모드 트레이드오프로 판정되지 않음 → 단일 탭
      expect(find.text('완행'), findsNothing);
      // '급행' 라벨이 있다면 탭이 아니라 세그먼트 배지(왼쪽 first 세그먼트가 9E 패턴)
      // → 탭이 없을 때는 라벨 텍스트가 1회만 등장.
      expect(find.text('급행'), findsOneWidget);
    });
  });
}
