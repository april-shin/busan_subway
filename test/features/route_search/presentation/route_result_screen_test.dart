import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:seoul_subway/domain/entities/arrival_info.dart';
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

  group('Case D — 로드 후 freeze (도착정보 refresh 무시)', () {
    // 화면에 렌더된 모든 "HH:MM" 시각 텍스트를 수집한다.
    // (요약 헤더의 출발/도착 시각 + 타임라인의 구간별 시각 포함)
    List<String> visibleTimes(WidgetTester tester) {
      final re = RegExp(r'^\d{2}:\d{2}$');
      return tester
          .widgetList<Text>(find.byType(Text))
          .map((w) => w.data)
          .whereType<String>()
          .where(re.hasMatch)
          .toList()
        ..sort();
    }

    // 9호선(subwayId 1009) 실시간 도착정보. arrivalSeconds를 크게 벌려
    // freeze가 깨질 경우 출발/도착 HH:MM이 명확히 달라지도록 한다.
    //
    // direction은 `buildLocal()`의 세그먼트 방향과 일치해야 실시간 보정이
    // 적용된다. station1~3(id 901→903) 세그먼트는 `isDownDirection`이 false
    // (상행)이므로, `_getRealtimeDeparture`의 방향 필터를 통과하도록 '상행'을
    // 사용한다. (방향이 어긋나면 실시간 값이 필터링돼 `now` 폴백으로만 표시되어
    // arrivalSeconds 차이가 시각에 반영되지 않아 테스트가 무의미해진다.)
    ArrivalInfo arrival(int seconds) => ArrivalInfo(
          subwayId: '1009',
          stationName: station1.name,
          trainLineNm: '개화행',
          direction: '상행',
          arrivalMessage: '전역 출발',
          destination: '개화',
          trainType: '일반',
          arrivalSeconds: seconds,
          receivedAt: DateTime.now(),
        );

    testWidgets(
        '초기 로드 후 arrivalInfoProvider를 invalidate하고 다른 도착정보를 '
        '반환해도 표시된 시각이 최초 값에서 변하지 않는다', (tester) async {
      // 최초: 곧 도착(2분) → 이후 refresh: 훨씬 나중 도착(60분).
      // freeze가 동작하면 초기 2분 기반 시각이 그대로 유지되어야 한다.
      when(() => mockRepo.getArrivalInfo(station1.name))
          .thenAnswer((_) async => [arrival(120)]);

      late ProviderContainer container;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            arrivalRepositoryProvider.overrideWithValue(mockRepo),
          ],
          child: Consumer(
            builder: (context, ref, _) {
              container = ProviderScope.containerOf(context);
              return MaterialApp(
                home: RouteResultScreen(
                  fastest: buildLocal(),
                  departureStationName: station1.name,
                ),
              );
            },
          ),
        ),
      );
      // 최초 도착정보 확정까지 대기 (로딩 → 실제 시각 전환).
      await tester.pumpAndSettle();

      final before = visibleTimes(tester);
      // 실시간 도착정보가 반영되어 실제 시각이 표시돼야 함 (요구사항 2).
      expect(before, isNotEmpty,
          reason: '로드 후 출발/도착 시각이 표시되어야 한다');
      expect(find.text('실시간 정보 조회중...'), findsNothing);

      // 지도 화면 등 외부에서 발생하는 refresh를 모사:
      // repository 반환값을 바꾸고 provider를 invalidate한다.
      when(() => mockRepo.getArrivalInfo(station1.name))
          .thenAnswer((_) async => [arrival(3600)]);
      container.invalidate(arrivalInfoProvider(station1.name));
      await tester.pumpAndSettle();

      // freeze: 최초 확정값이 그대로 유지되어야 한다 (요구사항 1, 핵심 버그 수정).
      final after = visibleTimes(tester);
      expect(after, equals(before),
          reason: 'refresh 후에도 표시 시각이 최초 값과 동일해야 한다');
    });
  });

  group('Case E — 환승 라벨은 도보시간만 (회귀 가드)', () {
    // 2세그먼트 경로(9호선 → 2호선 환승). 동작 4→9 실측을 본떠
    //   - 도보(transferWalk) = 370초  → ceil(370/60) = 7분
    //   - 대기 포함(transferDuration) = 370 + 300 = 670초 → ceil = 12분
    // 환승 라벨은 반드시 "환승 도보 7분"이어야 하며, 대기 합산값(12/11분)이
    // 라벨로 새어 나오면 안 된다. 반면 총소요시간(소요 N분)에는 대기가 포함된다.
    const walkSeconds = 370; // 도보만
    const waitSeconds = 300; // 열차 대기
    const transferTotalSeconds = walkSeconds + waitSeconds; // 도보+대기

    // 2호선 세그먼트용 역들(환승역 stationB2에서 갈아탄다).
    const stationB1 = Station(
      id: '222',
      name: '사당',
      lineId: '2',
      latitude: 37.47,
      longitude: 126.98,
    );
    const stationB2 = Station(
      id: '223',
      name: '방배',
      lineId: '2',
      latitude: 37.48,
      longitude: 126.99,
    );

    RouteResult buildTransferRoute() {
      return const RouteResult(
        segments: [
          RouteSegment(
            lineId: '9',
            lineName: '9호선',
            stations: [station1, station2, station3],
            durationSeconds: 300,
            direction: '신방화 방면',
          ),
          RouteSegment(
            lineId: '2',
            lineName: '2호선',
            stations: [stationB1, stationB2],
            durationSeconds: 180,
            direction: '방배 방면',
          ),
        ],
        // 총소요시간·출발계산은 대기 포함(transferDurations) 사용 → 불변.
        totalTimeSeconds: 300 + transferTotalSeconds + 180,
        transferCount: 1,
        stationCount: 3,
        transferDurations: [transferTotalSeconds], // 도보+대기(라우팅/총시간용)
        transferWalkDurations: [walkSeconds], // 도보만(라벨 전용)
        transferGuides: [null],
      );
    }

    testWidgets('환승 행은 도보시간(7분)만 표시하고 대기 합산(12/11분)은 표시하지 않는다',
        (tester) async {
      await tester.pumpWidget(buildApp(fastest: buildTransferRoute()));
      await tester.pump(const Duration(milliseconds: 50));

      // 라벨은 도보시간만: ceil(370/60) = 7분.
      expect(find.textContaining('환승 도보 7분'), findsOneWidget,
          reason: '환승 라벨은 도보시간(370초→7분)만 표시해야 한다');

      // 대기가 합산된 값이 라벨로 노출되면 안 된다.
      // ceil(670/60)=12, 과거 버그 리포트의 11분도 함께 방어.
      expect(find.textContaining('환승 도보 12분'), findsNothing,
          reason: '도보+대기(670초) 합산값이 환승 라벨에 새어나오면 안 된다');
      expect(find.textContaining('환승 도보 11분'), findsNothing,
          reason: '버그 리포트의 11분(도보+대기)이 라벨에 나오면 안 된다');
    });

    testWidgets('총소요시간(소요 N분)에는 환승 대기가 포함되어 도보만 값보다 크다',
        (tester) async {
      final route = buildTransferRoute();
      await tester.pumpWidget(buildApp(fastest: route));
      await tester.pump(const Duration(milliseconds: 50));

      // (1) 데이터 불변식: totalTimeSeconds는 대기 포함(transferDurations=670) 유지.
      expect(route.totalTimeSeconds, 300 + transferTotalSeconds + 180,
          reason: 'totalTimeSeconds는 대기 포함으로 불변이어야 한다');

      // (2) 화면 렌더: "소요 N분" 칩의 N을 파싱한다.
      //   - 대기 포함 이동시간 총초 = 300 + 670 + 180 = 1150초.
      //   - 실시간 mock이 비어 있어 출발 시각은 스케줄/폴백 기준이며, 총소요시간은
      //     이동시간(대기 포함)에서 파생되므로 최소 18분(=1150s 내림) 이상이어야 한다.
      //   - 만약 라벨처럼 대기를 도보(370)로 대체해 총합을 계산했다면
      //     300+370+180=850초 → 약 14분으로 줄어든다. 18분 미만이면 회귀.
      final re = RegExp(r'소요 (\d+)분');
      final chip = tester
          .widgetList<Text>(find.byType(Text))
          .map((w) => w.data)
          .whereType<String>()
          .firstWhere((s) => re.hasMatch(s));
      final minutes = int.parse(re.firstMatch(chip)!.group(1)!);
      expect(minutes, greaterThanOrEqualTo(18),
          reason: '총소요시간은 환승 대기 포함(≥18분)이어야 한다. '
              '도보만으로 축소(약 14분)되면 회귀.');
    });
  });
}
