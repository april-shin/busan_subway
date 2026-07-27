import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:seoul_subway/domain/entities/arrival_info.dart';
import 'package:seoul_subway/domain/entities/line_schedule.dart';
import 'package:seoul_subway/domain/entities/route_result.dart';
import 'package:seoul_subway/domain/entities/station.dart';
import 'package:seoul_subway/domain/repositories/arrival_repository.dart';
import 'package:seoul_subway/features/arrival_info/presentation/providers/arrival_providers.dart';
import 'package:seoul_subway/features/route_search/presentation/providers/timetable_providers.dart';
import 'package:seoul_subway/features/route_search/utils/departure_query_time.dart';
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
    Map<String, LineSchedule>? schedules,
  }) {
    return ProviderScope(
      overrides: [
        arrivalRepositoryProvider.overrideWithValue(mockRepo),
        if (schedules != null)
          lineSchedulesProvider.overrideWith((ref) async => schedules),
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

  group('Case F — 출발시각 선택', () {
    const periods = [
      TimePeriod(start: '05:00', end: '00:00', headwayMinutes: 5),
    ];

    /// 평일/주말을 동일하게 채운 스케줄.
    ///
    /// 화면의 기본 요일 타입은 `dayTypeOf(DateTime.now())` 라 테스트 실행 요일에
    /// 따라 달라진다. 평일·주말 데이터를 같게 두면 어느 요일에 돌려도 결과가
    /// 동일해져 테스트가 결정적이 된다.
    LineSchedule scheduleWith({
      List<int>? local,
      List<int>? express,
    }) {
      final day = DaySchedule(
        firstTrain: '05:00',
        lastTrain: '00:00',
        periods: periods,
        stationDepartures: local == null ? null : {station1.id: local},
        expressStationDepartures:
            express == null ? null : {station1.id: express},
      );
      return LineSchedule(lineId: '9', weekday: day, weekend: day);
    }

    /// 요약 헤더의 "HH:MM 출발" 텍스트를 찾는다.
    String? departureLabel(WidgetTester tester) {
      final re = RegExp(r'^\d{2}:\d{2}$');
      final times = tester
          .widgetList<Text>(find.byType(Text))
          .map((w) => w.data)
          .whereType<String>()
          .where(re.hasMatch)
          .toList();
      return times.isEmpty ? null : times.first;
    }

    /// 컴팩트 UI 진입점 — 출발 시각 옆 펼침 화살표. 이게 없으면 시각을 고를 수
    /// 없는 상태(시간표 미보유/로딩)다.
    final pickerAffordance = find.byIcon(Icons.expand_more);

    Future<void> openSheet(WidgetTester tester) async {
      await tester.tap(pickerAffordance.first);
      await tester.pumpAndSettle();
    }

    testWidgets('기본 상태에는 별도 컨트롤 줄 없이 출발 시각만 보인다',
        (tester) async {
      await tester.pumpWidget(buildApp(
        fastest: buildLocal(),
        schedules: {'9': scheduleWith(local: [480])},
      ));
      await tester.pumpAndSettle();

      // 시각을 고를 수 있다는 힌트는 있되,
      expect(pickerAffordance, findsOneWidget);
      // 기본 상태에서는 보조 줄(요일/리셋)이 헤더를 늘리지 않는다.
      expect(find.text('평일 시간표'), findsNothing);
      expect(find.text('주말 시간표'), findsNothing);
      expect(find.text('지금 출발로'), findsNothing);
      expect(find.text('선택한 시각에는 운행하지 않습니다'), findsNothing);
    });

    testWidgets('역별 시간표가 없으면 시각을 고를 수 없다 (힌트도 없음)',
        (tester) async {
      // 배차간격만 있고 stationDepartures 가 없는 경우.
      // 실데이터에서는 급행 미보유 노선/역이 여기 해당한다(완행 시간표는
      // 23개 노선 전부 보유).
      await tester.pumpWidget(buildApp(
        fastest: buildLocal(),
        schedules: {'9': scheduleWith()},
      ));
      await tester.pumpAndSettle();

      // 누를 수 없는 것을 누를 수 있어 보이게 하지 않는다.
      expect(pickerAffordance, findsNothing);
      // 출발 시각 자체는 그대로 표시된다.
      expect(departureLabel(tester), isNotNull);
    });

    testWidgets('시간표에서 고른 시각이 그대로 출발 시각이 되고 실시간은 무시된다',
        (tester) async {
      // 실시간은 2분 뒤 도착으로 응답 — 고정 시각을 고르면 무시되어야 한다.
      when(() => mockRepo.getArrivalInfo(station1.name)).thenAnswer(
        (_) async => [
          ArrivalInfo(
            subwayId: '1009',
            stationName: station1.name,
            trainLineNm: '개화행',
            direction: '상행',
            arrivalMessage: '전역 출발',
            destination: '개화',
            trainType: '일반',
            arrivalSeconds: 120,
            receivedAt: DateTime.now(),
          ),
        ],
      );

      await tester.pumpWidget(buildApp(
        fastest: buildLocal(),
        schedules: {'9': scheduleWith(local: [492])}, // 08:12
      ));
      await tester.pumpAndSettle();

      // 출발 시각을 눌러 시트를 연다.
      await openSheet(tester);

      // 시(08) 행에 분(12) 칩이 있다.
      expect(find.text('08'), findsOneWidget);
      await tester.tap(find.text('12'));
      await tester.pumpAndSettle();

      // 출발 시각이 실시간(now+2분)이 아니라 08:12 여야 한다.
      expect(departureLabel(tester), '08:12');
      // 어떤 요일 시간표인지와 되돌리는 길이 보조 줄에 나타난다.
      expect(
        find.text('평일 시간표').evaluate().length +
            find.text('주말 시간표').evaluate().length,
        1,
      );
      expect(find.text('지금 출발로'), findsOneWidget);
    });

    testWidgets('선택 시각은 탭을 전환해도 유지된다', (tester) async {
      // 급행 23:50 만 있고 완행은 08:00 이 막차인 스케줄.
      await tester.pumpWidget(buildApp(
        fastest: buildExpress(),
        fastestExpress: buildExpress(total: 180),
        fastestLocal: buildLocal(total: 300),
        schedules: {
          '9': scheduleWith(local: [480], express: [1430]), // 08:00 / 23:50
        },
      ));
      await tester.pumpAndSettle();

      // 급행 탭에서 23:50 선택.
      await openSheet(tester);
      await tester.tap(find.text('50'));
      await tester.pumpAndSettle();

      expect(departureLabel(tester), '23:50');

      // 완행 탭으로 전환해도 기준 시각이 유지된다 — 완행은 그 시각 이후
      // 열차가 없으므로 안내가 뜨고, 되돌리는 길도 계속 노출된다.
      await tester.tap(find.text('완행'));
      await tester.pumpAndSettle();

      expect(find.text('지금 출발로'), findsWidgets,
          reason: '탭을 바꿔도 선택 시각이 유지되어야 한다');
    });

    testWidgets('선택 시각에 운행 열차가 없으면 안내를 표시한다', (tester) async {
      // 급행 23:50 을 고른 뒤 완행 탭으로 가면, 완행 막차(08:00)가 이미 지나
      // 해당 시각에 탈 수 있는 완행 열차가 없다.
      await tester.pumpWidget(buildApp(
        fastest: buildExpress(),
        fastestExpress: buildExpress(total: 180),
        fastestLocal: buildLocal(total: 300),
        schedules: {
          '9': scheduleWith(local: [480], express: [1430]),
        },
      ));
      await tester.pumpAndSettle();

      await openSheet(tester);
      await tester.tap(find.text('50'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('완행'));
      await tester.pumpAndSettle();

      expect(find.text('선택한 시각에는 운행하지 않습니다'), findsOneWidget);
    });

    testWidgets('시트를 열면 기존 선택 시각의 시(hour) 행이 화면 안에 들어온다',
        (tester) async {
      // 회귀 가드: 지연 빌드(ListView.builder)로 그리면 목표 행이 viewport +
      // cacheExtent 밖일 때 마운트 자체가 안 돼 초기 스크롤이 조용히 무시된다.
      // 05시~23시 전 구간을 채워 목표(23시)가 확실히 화면 밖에서 시작하게 한다.
      final allHours = [for (var h = 5; h <= 23; h++) h * 60 + 50];
      await tester.pumpWidget(buildApp(
        fastest: buildLocal(),
        schedules: {'9': scheduleWith(local: allHours)},
      ));
      await tester.pumpAndSettle();

      // 먼저 23:50 을 선택해 두고,
      await openSheet(tester);
      await tester.dragUntilVisible(
        find.text('23'),
        find.byType(SingleChildScrollView),
        const Offset(0, -100),
      );
      // 마지막 '50' 칩 = 23시 행 (매 시 :50 만 채웠으므로).
      await tester.tap(find.text('50').last);
      await tester.pumpAndSettle();

      // 다시 열었을 때 23시 행이 화면 안에 있어야 한다.
      await openSheet(tester);

      final rowY = tester.getTopLeft(find.text('23')).dy;
      final screenHeight = tester.view.physicalSize.height /
          tester.view.devicePixelRatio;
      expect(rowY, lessThan(screenHeight),
          reason: '초기 스크롤이 동작해 목표 시(hour) 행이 화면 안에 있어야 한다');
      expect(rowY, greaterThanOrEqualTo(0));
    });

    testWidgets(
        '정확한 시간표가 없는 탭에서도 적용 중인 시각과 리셋 버튼이 유지되고 '
        '추정치임을 안내한다', (tester) async {
      // 최단시간=9호선(역별 시간표 있음), 최소환승=시간표 미보유 노선.
      // 실데이터의 급행 미보유 케이스를 합성 픽스처로 재현한다.
      final leastTransfer = RouteResult(
        segments: [
          RouteSegment(
            lineId: 'NOTT',
            lineName: '시간표없음선',
            stations: const [station1, station2],
            durationSeconds: 300,
            direction: '신방화 방면',
          ),
        ],
        totalTimeSeconds: 300,
        transferCount: 0,
        stationCount: 2,
      );

      await tester.pumpWidget(buildApp(
        fastest: buildLocal(),
        leastTransfer: leastTransfer,
        schedules: {
          '9': scheduleWith(local: [492]), // 08:12
          'NOTT': scheduleWith(), // 역별 시간표 없음 → 배차간격 폴백
        },
      ));
      await tester.pumpAndSettle();

      await openSheet(tester);
      await tester.tap(find.text('12'));
      await tester.pumpAndSettle();

      // 최소환승 탭(시간표 없음)으로 전환.
      await tester.tap(find.text('최소환승'));
      await tester.pumpAndSettle();

      // 이 탭은 08:12 열차가 없어 배차간격 추정(08:15)이 나온다. 그래도 어떤
      // 시각을 기준으로 잡은 결과인지 보이고 해제도 가능해야 한다
      // (여기서 상태가 사라지면 사용자가 맥락을 잃고 되돌릴 수도 없게 된다).
      expect(find.text('평일 08:12 기준'), findsWidgets);
      expect(find.text('지금 출발로'), findsWidgets);
      // 고를 수는 없는 탭이므로 진입 힌트는 없다.
      expect(pickerAffordance, findsNothing);
      // 배차간격 추정치를 실제 시간표처럼 보여주지 않는다.
      expect(find.text('이 경로는 정확한 시간표가 없어 예상 시각입니다'),
          findsOneWidget);
    });

    testWidgets('"지금" 리셋 버튼이 실시간 기준으로 되돌린다', (tester) async {
      await tester.pumpWidget(buildApp(
        fastest: buildLocal(),
        schedules: {'9': scheduleWith(local: [492])},
      ));
      await tester.pumpAndSettle();

      await openSheet(tester);
      await tester.tap(find.text('12'));
      await tester.pumpAndSettle();
      expect(find.text('지금 출발로'), findsOneWidget);

      await tester.tap(find.text('지금 출발로'));
      await tester.pumpAndSettle();

      // 보조 줄이 사라져 헤더가 다시 컴팩트해지고, 힌트만 남는다.
      expect(find.text('지금 출발로'), findsNothing);
      expect(find.text('평일 시간표'), findsNothing);
      expect(find.text('주말 시간표'), findsNothing);
      expect(pickerAffordance, findsOneWidget);
      expect(find.text('선택한 시각에는 운행하지 않습니다'), findsNothing);
    });

    testWidgets('시트가 화면의 출발 시각을 짚어주고 그 위치로 스크롤된다',
        (tester) async {
      // 24시간 전 구간을 매 시 :59 로 채운다. 몇 시에 돌리든 화면 출발 시각에
      // 대응하는 칩이 존재하게 해서 테스트가 시계에 따라 조용히 건너뛰지
      // 않도록 한다. 행이 24개라 목표 행은 스크롤 없이는 화면 밖이다.
      final allHours = [for (var h = 0; h <= 23; h++) h * 60 + 59];
      await tester.pumpWidget(buildApp(
        fastest: buildLocal(),
        schedules: {'9': scheduleWith(local: allHours)},
      ));
      await tester.pumpAndSettle();

      // 헤더에 떠 있는 출발 시각 — 시트는 바로 이걸 짚어야 한다.
      final headerDeparture = departureLabel(tester);
      expect(headerDeparture, isNotNull);

      await openSheet(tester);

      // (1) 시트가 화면과 같은 시각을 기준으로 삼는다.
      expect(find.text('현재 $headerDeparture 출발'), findsOneWidget,
          reason: '시트 기준이 화면 출발 시각과 어긋나면 안 된다');

      // (2) 그 시각의 행이 화면 안에 있어야 한다.
      final hourLabel = headerDeparture!.substring(0, 2);
      final rowY = tester.getTopLeft(find.text(hourLabel).last).dy;
      final screenHeight =
          tester.view.physicalSize.height / tester.view.devicePixelRatio;
      expect(rowY, inInclusiveRange(0, screenHeight),
          reason: '출발 시각 위치($hourLabel시 행)가 화면 안에 있어야 한다');
    });

    testWidgets('반대 요일을 골랐다 되돌리면 시트가 다시 오늘 요일로 열린다',
        (tester) async {
      // 회귀 가드: dayType 은 "지금 출발"에서 계산에 쓰이지 않아, 되돌릴 때
      // 함께 정리하지 않으면 남아 있다가 다음 열람에서 그 요일 탭으로 열린다.
      final todayType = dayTypeOf(DateTime.now());
      final otherLabel =
          todayType == DepartureDayType.weekday ? '주말' : '평일';

      await tester.pumpWidget(buildApp(
        fastest: buildLocal(),
        schedules: {'9': scheduleWith(local: [492])},
      ));
      await tester.pumpAndSettle();

      // 반대 요일로 토글한 뒤 시각을 고르고,
      await openSheet(tester);
      await tester.tap(find.text(otherLabel));
      await tester.pumpAndSettle();
      await tester.tap(find.text('12'));
      await tester.pumpAndSettle();
      expect(find.text('$otherLabel 시간표'), findsOneWidget);

      // "지금 출발로" 되돌린 다음 시트를 다시 열면,
      await tester.tap(find.text('지금 출발로'));
      await tester.pumpAndSettle();
      await openSheet(tester);

      // 반대 요일이 아니라 오늘 요일이 선택돼 있어야 한다.
      final selected = tester
          .widget<SegmentedButton<DepartureDayType>>(
              find.byType(SegmentedButton<DepartureDayType>))
          .selected;
      expect(selected, {todayType},
          reason: '되돌린 뒤에는 오늘($todayType) 기준으로 열려야 한다');
    });
  });
}
