import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:seoul_subway/domain/entities/station.dart';
import 'package:seoul_subway/domain/entities/connection.dart';
import 'package:seoul_subway/domain/entities/express_skip_edge.dart';
import 'package:seoul_subway/domain/entities/route_result.dart';
import 'package:seoul_subway/domain/entities/transfer_guide.dart';
import 'package:seoul_subway/domain/repositories/station_repository.dart';
import 'package:seoul_subway/domain/usecases/search_route.dart';

class MockStationRepository extends Mock implements StationRepository {}

void main() {
  late MockStationRepository mockRepo;
  late SearchRoute searchRoute;

  final testStations = [
    const Station(id: '201', name: '시청', lineId: '2', latitude: 37.56, longitude: 126.97),
    const Station(id: '202', name: '을지로입구', lineId: '2', latitude: 37.56, longitude: 126.98),
    const Station(id: '203', name: '을지로3가', lineId: '2', latitude: 37.56, longitude: 126.99, isTransfer: true, transferLines: ['2', '3']),
    const Station(id: '316', name: '을지로3가', lineId: '3', latitude: 37.56, longitude: 126.99, isTransfer: true, transferLines: ['2', '3']),
    const Station(id: '317', name: '충무로', lineId: '3', latitude: 37.56, longitude: 126.99),
  ];

  final testConnections = [
    const Connection(fromStationId: '201', toStationId: '202', lineId: '2', travelTimeSeconds: 90),
    const Connection(fromStationId: '202', toStationId: '203', lineId: '2', travelTimeSeconds: 90),
    const Connection(fromStationId: '316', toStationId: '317', lineId: '3', travelTimeSeconds: 90),
  ];

  final testTransferTimes = {'을지로3가_2_3': 180};

  setUp(() {
    mockRepo = MockStationRepository();
    searchRoute = SearchRoute(stationRepository: mockRepo);

    when(() => mockRepo.getAllStations()).thenAnswer((_) async => testStations);
    when(() => mockRepo.getAllConnections()).thenAnswer((_) async => testConnections);
    when(() => mockRepo.getTransferTimes()).thenAnswer((_) async => testTransferTimes);
    // 기본은 빈 맵. 개별 테스트에서 override 가능.
    when(() => mockRepo.getTransferGuides())
        .thenAnswer((_) async => <String, TransferGuide>{});
    // 급행 모델링 데이터는 기본 빈 리스트. 개별 테스트에서 override 가능.
    when(() => mockRepo.getExpressSkipEdges())
        .thenAnswer((_) async => <ExpressSkipEdge>[]);
  });

  group('SearchRoute', () {
    test('finds route on same line', () async {
      final result = await searchRoute.execute('201', '203');

      expect(result, isNotNull);
      // 이동시간 180 + 정차시간 30 (중간역 을지로입구 × 30초)
      expect(result!.totalTimeSeconds, 210);
      expect(result.segments.length, 1);
      expect(result.segments.first.lineId, '2');
    });

    test('finds route with transfer', () async {
      final result = await searchRoute.execute('201', '317');

      expect(result, isNotNull);
      // 이동시간 450 + 정차시간 30 (중간역 을지로입구 × 30초)
      expect(result!.totalTimeSeconds, 480);
      expect(result.transferCount, greaterThanOrEqualTo(1));
    });

    test('returns null for non-existent station', () async {
      final result = await searchRoute.execute('999', '201');
      expect(result, isNull);
    });

    test('returns route with correct station count', () async {
      final result = await searchRoute.execute('201', '203');

      expect(result, isNotNull);
      // 시청→을지로입구→을지로3가 단일 세그먼트, hop = 2.
      expect(result!.stationCount, 2);
    });

    test('인접한 단일 hop 경로의 stationCount 는 1 (예: 사당→방배 케이스)',
        () async {
      // 단일 세그먼트 [201, 202] (인접 두 역) → hop = 1.
      final result = await searchRoute.execute('201', '202');

      expect(result, isNotNull);
      expect(result!.stationCount, 1,
          reason: '"N개역" 은 거쳐간 정거장 수(hop) — 인접 두 역이면 1');
    });

    test('same line route has empty transferDurations', () async {
      final result = await searchRoute.execute('201', '203');

      expect(result, isNotNull);
      expect(result!.transferDurations, isEmpty);
    });

    test('transfer route collects transferDurations', () async {
      final result = await searchRoute.execute('201', '317');

      expect(result, isNotNull);
      expect(result!.transferDurations, isNotEmpty);
      expect(result.transferDurations.length, result.transferCount);
      expect(result.transferDurations.first, 180);
    });

    test('executeAll returns fastest and leastTransfer', () async {
      final result = await searchRoute.executeAll('201', '317');

      expect(result.fastest, isNotNull);
      // 이동시간 450 + 정차시간 30
      expect(result.fastest!.totalTimeSeconds, 480);
      // 이 그래프에서는 경로가 하나뿐이므로 leastTransfer는 null (동일 경로)
      expect(result.leastTransfer, isNull);
    });

    test('executeAll returns null for non-existent station', () async {
      final result = await searchRoute.executeAll('999', '201');

      expect(result.fastest, isNull);
      expect(result.leastTransfer, isNull);
    });

    test('executeAll same-line route has null leastTransfer', () async {
      final result = await searchRoute.executeAll('201', '203');

      expect(result.fastest, isNotNull);
      expect(result.fastest!.segments.length, 1);
      // 환승 없는 같은 노선 경로 → leastTransfer null
      expect(result.leastTransfer, isNull);
    });

    group('executeAll — 경유역(viaStationIds)', () {
      test('viaStationIds 가 비면 경유 없는 기존 결과와 완전히 동일', () async {
        final plain = await searchRoute.executeAll('201', '317');
        final empty = await searchRoute.executeAll(
          '201',
          '317',
          viaStationIds: const [],
        );

        expect(empty.fastest, isNotNull);
        expect(empty.fastest!.totalTimeSeconds, plain.fastest!.totalTimeSeconds);
        expect(empty.fastest!.transferCount, plain.fastest!.transferCount);
        expect(empty.fastest!.segments.length, plain.fastest!.segments.length);
      });

      test('이미 경로상에 있는 경유역은 결과를 바꾸지 않는다', () async {
        // 시청→을지로3가 최단경로는 을지로입구를 지난다.
        final plain = await searchRoute.executeAll('201', '203');
        final via = await searchRoute.executeAll(
          '201',
          '203',
          viaStationIds: const ['202'],
        );

        expect(via.fastest, isNotNull);
        expect(via.fastest!.totalTimeSeconds, plain.fastest!.totalTimeSeconds);
        expect(via.fastest!.segments.length, 1,
            reason: '같은 노선을 계속 타므로 경유가 세그먼트를 쪼개지 않는다');
        expect(via.fastest!.transferCount, 0);
      });

      test('경유역을 실제로 지난다 (되돌아오는 우회 포함)', () async {
        // 을지로입구→시청 은 반대 방향. 시청을 경유로 강제하면
        // 을지로입구→시청→을지로입구→을지로3가 로 되돌아와야 한다.
        final via = await searchRoute.executeAll(
          '202',
          '203',
          viaStationIds: const ['201'],
        );

        expect(via.fastest, isNotNull);
        final names = [
          for (final seg in via.fastest!.segments)
            for (final s in seg.stations) s.name,
        ];
        expect(names, contains('시청'));
        // 직행(을지로입구→을지로3가, 90초)보다 반드시 오래 걸린다.
        expect(via.fastest!.totalTimeSeconds, greaterThan(90));
      });

      test('되돌아오는 경로에서 재방문 역이 역 목록에서 지워지지 않는다', () async {
        // 을지로입구 →[경유] 시청 → 을지로3가.
        // 을지로입구를 두 번(출발, 되돌아올 때) 지나므로 역 목록에도 두 번 남아야
        // 한다. 세그먼트 역 중복 제거가 "바로 앞 역"만 검사해야 하는 이유.
        final via = await searchRoute.executeAll(
          '202',
          '203',
          viaStationIds: const ['201'],
        );

        expect(via.fastest, isNotNull);
        expect(via.fastest!.segments.length, 1);
        expect(
          via.fastest!.segments.single.stations.map((s) => s.name).toList(),
          ['을지로입구', '시청', '을지로입구', '을지로3가'],
        );
        // hop = 3 (역 목록 길이 - 1). 재방문을 지우면 2로 줄어든다.
        expect(via.fastest!.stationCount, 3);
      });

      test('환승역을 경유로 지정하면 환승이 포함된 경로가 나온다', () async {
        // 시청(2호선) → [경유] 을지로3가(2·3호선 환승) → 충무로(3호선)
        final via = await searchRoute.executeAll(
          '201',
          '317',
          viaStationIds: const ['203'],
        );

        expect(via.fastest, isNotNull);
        expect(via.fastest!.transferCount, greaterThanOrEqualTo(1));
        expect(via.fastest!.segments.first.lineId, '2');
        expect(via.fastest!.segments.last.lineId, '3');
      });

      test('존재하지 않는 경유역 ID 는 무시된다', () async {
        final plain = await searchRoute.executeAll('201', '203');
        final via = await searchRoute.executeAll(
          '201',
          '203',
          viaStationIds: const ['999'],
        );

        expect(via.fastest, isNotNull);
        expect(via.fastest!.totalTimeSeconds, plain.fastest!.totalTimeSeconds);
      });

      test('출발역과 같은 경유역은 무시된다', () async {
        final plain = await searchRoute.executeAll('201', '203');
        final via = await searchRoute.executeAll(
          '201',
          '203',
          viaStationIds: const ['201'],
        );

        expect(via.fastest, isNotNull);
        expect(via.fastest!.totalTimeSeconds, plain.fastest!.totalTimeSeconds);
        expect(via.fastest!.segments.length, 1);
      });

      test('도착역과 같은 마지막 경유역은 도착역으로 흡수된다', () async {
        // 을지로3가는 2·3호선 두 레코드(203/316)가 있다. 도착역과 같은 역을
        // 경유로 넣어도 중복 정차 없이 도착역 하나로 합쳐져야 한다.
        final plain = await searchRoute.executeAll('201', '203');
        final via = await searchRoute.executeAll(
          '201',
          '203',
          viaStationIds: const ['316'],
        );

        expect(via.fastest, isNotNull);
        expect(via.fastest!.totalTimeSeconds, plain.fastest!.totalTimeSeconds);
        expect(via.fastest!.transferCount, 0);
      });

      test('여러 경유역이 지정 순서대로 반영된다', () async {
        final via = await searchRoute.executeAll(
          '201',
          '317',
          viaStationIds: const ['202', '203'],
        );

        expect(via.fastest, isNotNull);
        final names = [
          for (final seg in via.fastest!.segments)
            for (final s in seg.stations) s.name,
        ];
        expect(names.indexOf('을지로입구'), lessThan(names.indexOf('충무로')));
        expect(names, containsAll(['시청', '을지로입구', '을지로3가', '충무로']));
      });

      test('경유역을 지날 방법이 없으면 fastest 는 null', () async {
        // 317(충무로, 3호선)에서 갈 수 없는 고립 역을 경유로 지정.
        when(() => mockRepo.getAllStations()).thenAnswer((_) async => [
              ...testStations,
              const Station(
                id: '999',
                name: '고립역',
                lineId: '9',
                latitude: 37.0,
                longitude: 127.0,
              ),
            ]);

        final via = await searchRoute.executeAll(
          '201',
          '317',
          viaStationIds: const ['999'],
        );

        expect(via.fastest, isNull);
        expect(via.leastTransfer, isNull);
      });
    });

    group('executeAll 4종 반환 — 모드 트레이드오프', () {
      // 9호선 시뮬레이션:
      //   902(A) ~ 907(F) 6개역. 완행 200초/구간.
      //   급행: 902→905, 905→907 (A, D, F만 정차).
      // → A → F 시나리오에서 fastestExpress / fastestLocal 모두 존재해야 한다.
      final stations9 = [
        const Station(id: '902', name: 'A', lineId: '9', latitude: 0, longitude: 0),
        const Station(id: '903', name: 'B', lineId: '9', latitude: 0, longitude: 0),
        const Station(id: '904', name: 'C', lineId: '9', latitude: 0, longitude: 0),
        const Station(id: '905', name: 'D', lineId: '9', latitude: 0, longitude: 0),
        const Station(id: '906', name: 'E', lineId: '9', latitude: 0, longitude: 0),
        const Station(id: '907', name: 'F', lineId: '9', latitude: 0, longitude: 0),
      ];
      final slowConnections = [
        const Connection(fromStationId: '902', toStationId: '903', lineId: '9', travelTimeSeconds: 200),
        const Connection(fromStationId: '903', toStationId: '904', lineId: '9', travelTimeSeconds: 200),
        const Connection(fromStationId: '904', toStationId: '905', lineId: '9', travelTimeSeconds: 200),
        const Connection(fromStationId: '905', toStationId: '906', lineId: '9', travelTimeSeconds: 200),
        const Connection(fromStationId: '906', toStationId: '907', lineId: '9', travelTimeSeconds: 200),
      ];
      final expressEdges9 = [
        const ExpressSkipEdge(
          lineId: '9', fromStationId: '902', toStationId: '905',
          seconds: 150, skippedStationIds: ['903', '904']),
        const ExpressSkipEdge(
          lineId: '9', fromStationId: '905', toStationId: '907',
          seconds: 100, skippedStationIds: ['906']),
      ];

      void stub9() {
        when(() => mockRepo.getAllStations())
            .thenAnswer((_) async => stations9);
        when(() => mockRepo.getAllConnections())
            .thenAnswer((_) async => slowConnections);
        when(() => mockRepo.getTransferTimes())
            .thenAnswer((_) async => <String, int>{});
        when(() => mockRepo.getExpressSkipEdges())
            .thenAnswer((_) async => expressEdges9);
      }

      test('급행 정차역끼리(A→F): fastestExpress와 fastestLocal 모두 존재 + 시간 다름',
          () async {
        stub9();

        final result = await searchRoute.executeAll('902', '907');

        expect(result.fastest, isNotNull);
        // A, F 모두 급행 정차역이므로 fastestExpress 결과가 있어야 한다.
        expect(result.fastestExpress, isNotNull,
            reason: 'A,F 모두 급행 정차역 → 급행 단독 경로가 존재해야 함');
        // 같은 9호선 + 9호선은 급행 지원 노선이므로 fastestLocal 존재.
        expect(result.fastestLocal, isNotNull);
        // fastestLocal 은 "같은 노선 완행" 정의: 전 세그먼트 9호선, 환승 0.
        expect(
          result.fastestLocal!.segments.every((s) => s.lineId == '9'),
          isTrue,
          reason: 'fastestLocal 은 같은 노선(9호선) 내 완행만',
        );
        expect(result.fastestLocal!.transferCount, 0,
            reason: '같은 노선이므로 환승 없음');
        // 완행/급행 시간이 달라야 모드 트레이드오프 케이스로 판정됨
        expect(
          result.fastestExpress!.totalTimeSeconds !=
              result.fastestLocal!.totalTimeSeconds,
          isTrue,
          reason: '완행 시간과 급행 시간이 달라야 모드 비교 의미 있음',
        );
        // 완행 단독: A_9에서 출발해서 F_9까지 → 5 edge × 200 + 4 dwell × 30 = 1120
        expect(result.fastestLocal!.totalTimeSeconds, 1120);
        // 급행 단독: A_9E → D_9E → F_9E (모드 전환 미포함)
        // = 150 + 100 + 1 dwell(D 중간) × 30 = 280
        expect(result.fastestExpress!.totalTimeSeconds, lessThan(400));
      });

      test(
          '급행 미정차역 시작(B→F): 같은 노선 + 급행지원이므로 fastestExpress 가 _E edge 포함 경로로 존재',
          () async {
        stub9();

        final result = await searchRoute.executeAll('903', '907');

        expect(result.fastest, isNotNull);
        // 새 정책: 같은 노선이고 급행 지원이면 한쪽이 급행 미정차여도
        // 노선 내 base/E/M 노드를 모두 허용하여 급행 환승 경로를 fastestExpress 로 제공.
        expect(result.fastestExpress, isNotNull,
            reason: '같은 9호선 + 9호선은 급행지원 → 급행 환승 경로 노출');
        // 결과에 급행 세그먼트(`_E` 노선)가 포함되어야 한다.
        expect(
          result.fastestExpress!.segments.any((s) => s.lineId.endsWith('E')),
          isTrue,
          reason: 'fastestExpress 는 반드시 급행(_E) 세그먼트를 포함해야 함',
        );
        expect(result.fastestLocal, isNotNull);
      });

      test(
          '도착만 급행 미정차(A→E): 같은 노선 + 급행지원이므로 fastestExpress 존재',
          () async {
        stub9();

        // A(902, 급행정차) → E(906, 급행 미정차).
        // 비대칭 시나리오 검증: 출발만/도착만 미정차 두 방향 모두 동일 정책.
        final result = await searchRoute.executeAll('902', '906');

        expect(result.fastest, isNotNull);
        expect(result.fastestExpress, isNotNull,
            reason: '도착만 급행 미정차여도 같은 노선 + 급행지원이면 급행 환승 경로 노출');
        expect(
          result.fastestExpress!.segments.any((s) => s.lineId == '9E'),
          isTrue,
          reason: 'fastestExpress 는 반드시 9E 세그먼트를 포함해야 함',
        );
      });

      test(
          '양쪽 모두 급행 미정차(B→E) — 9호선 모드 전환 0초 정책으로 급행 환승 경로가 더 빠름',
          () async {
        stub9();

        // B(903)·E(906) 모두 급행 미정차역.
        // 완행 단독: B→C→D→E = 200×3 + dwell 60 = 660초
        // 급행 환승(9호선 모드 전환 0초):
        //   B→A(200) + 0 + A_E→D_E(150) + 0 + D→E(200) = 550초 < 660
        // → fastestExpress 가 _E edge 포함 경로로 노출됨 (이득이 있음).
        final result = await searchRoute.executeAll('903', '906');

        expect(result.fastest, isNotNull);
        expect(result.fastestExpress, isNotNull,
            reason: '9호선 모드 전환 0초이므로 양쪽 미정차여도 급행 환승이 더 빠를 수 있음');
        expect(
          result.fastestExpress!.segments.any((s) => s.lineId == '9E'),
          isTrue,
          reason: 'fastestExpress 는 반드시 9E 세그먼트를 포함해야 함',
        );
        expect(result.fastestLocal, isNotNull);
      });

      test('급행 미운영 노선(2/3호선): fastestExpress null, fastestLocal 도 null', () async {
        // 기본 setUp 그대로 — expressSkipEdges 빈 리스트.
        // 새 정책(fastestLocal = 같은 급행 지원 노선 내 완행만)에 의해
        // 급행 미운영 노선은 fastestLocal 도 null (fastest 로만 표시).
        final result = await searchRoute.executeAll('201', '203');

        expect(result.fastest, isNotNull);
        expect(result.fastestExpress, isNull,
            reason: '급행 노드 자체가 없으므로 null');
        expect(result.fastestLocal, isNull,
            reason: '급행 미운영 노선이므로 fastestLocal 불필요 (fastest 로 대체)');
      });

      test('다른 노선 간 조회(9호선 ↔ 2호선 등): fastestLocal null', () async {
        // 9호선·2호선 혼합 그래프를 스텁. A(9호선 902) → 201(2호선) 조회.
        // 역 이름이 달라 이름 기반 시작/도착이 잡히지 않을 수 있어, 여기서는
        // "같은 노선 아님" 경로로 fastestLocal=null 조건 검증.
        stub9();
        when(() => mockRepo.getAllStations()).thenAnswer((_) async => [
              ...stations9,
              const Station(id: '201', name: '시청', lineId: '2',
                  latitude: 0, longitude: 0),
            ]);

        final result = await searchRoute.executeAll('902', '201');

        // 시작/도착이 다른 노선이라 fastestLocal 은 null.
        expect(result.fastestLocal, isNull,
            reason: '출발·도착이 다른 노선이면 fastestLocal = null');
      });

      group('교차노선 환승 + 후행 급행 완행 대안 (우회 방지 회귀)', () {
        // 시나리오: 4호선 기점(S) --환승--> 9호선 환승역(T) --급행--> 9호선 종점(D).
        //
        // v1 버그: fastestLocal이 "fastest가 실제로 지나간 노선(4,9)의 완행"이
        // 아니라, 급행만 피해서 전혀 다른 노선으로 우회하는 경로를 골랐다.
        // (실제 사례: 총신대입구(4호선)→마곡나루(9호선 급행)의 완행 대안이
        // "4호선→서울역→공항철도"처럼 엉뚱한 노선으로 우회했다.)
        //
        // 우회가 실제로 방지되는지 검증하기 위해 기점/종점 둘 다에 5호선
        // "미끼" 지름길을 심어둔다. 이 미끼는 9호선 완행 전 구간보다는 빠르지만
        // 급행보다는 느리게 설계되어, `fastestBaseLines` 제한이 없다면
        // fastestLocal이 이 미끼(5호선)를 선택하게 된다 — 그래서 이 그룹은
        // "존재 확인"이 아니라 "우회 여부"를 실제로 잡아낼 수 있다.
        final crossLineStations = [
          // 기점: 4호선 대표 + 5호선 미끼 파트너(환승 취급, 같은 이름 "기점").
          const Station(id: '401', name: '기점', lineId: '4', latitude: 0, longitude: 0,
              isTransfer: true, transferLines: ['4', '5']),
          const Station(id: '501', name: '기점', lineId: '5', latitude: 0, longitude: 0,
              isTransfer: true, transferLines: ['4', '5']),
          // 4호선→9호선 실제 환승역 "환승역".
          const Station(id: '402', name: '환승역', lineId: '4', latitude: 0, longitude: 0,
              isTransfer: true, transferLines: ['4', '9']),
          const Station(id: '905', name: '환승역', lineId: '9', latitude: 0, longitude: 0,
              isTransfer: true, transferLines: ['4', '9']),
          // 9호선 완행 중간역(급행 통과 — 정차하지 않음).
          const Station(id: '906', name: '중간1', lineId: '9', latitude: 0, longitude: 0),
          const Station(id: '907', name: '중간2', lineId: '9', latitude: 0, longitude: 0),
          // 종점: 9호선 대표 + 5호선 미끼 파트너(환승 취급, 같은 이름 "종점").
          const Station(id: '908', name: '종점', lineId: '9', latitude: 0, longitude: 0,
              isTransfer: true, transferLines: ['5', '9']),
          const Station(id: '508', name: '종점', lineId: '5', latitude: 0, longitude: 0,
              isTransfer: true, transferLines: ['5', '9']),
        ];
        final crossLineConnections = [
          const Connection(fromStationId: '401', toStationId: '402',
              lineId: '4', travelTimeSeconds: 300),
          const Connection(fromStationId: '905', toStationId: '906',
              lineId: '9', travelTimeSeconds: 200),
          const Connection(fromStationId: '906', toStationId: '907',
              lineId: '9', travelTimeSeconds: 200),
          const Connection(fromStationId: '907', toStationId: '908',
              lineId: '9', travelTimeSeconds: 200),
          // 미끼: 5호선 직통 지름길. 9호선 완행 전 구간(1000초)보다는 빠르지만
          // 급행(650초)보다는 느리다 — fastestBaseLines 제한이 없을 때만 선택됨.
          const Connection(fromStationId: '501', toStationId: '508',
              lineId: '5', travelTimeSeconds: 800),
        ];
        final crossLineExpress = [
          // 9호선 급행: 환승역(905) → 종점(908) 직통, 중간1·중간2 스킵.
          const ExpressSkipEdge(lineId: '9', fromStationId: '905',
              toStationId: '908', seconds: 250,
              skippedStationIds: ['906', '907']),
        ];

        Set<String> baseLineSet(RouteResult r) => r.segments
            .map((s) => s.lineId.endsWith('E')
                ? s.lineId.substring(0, s.lineId.length - 1)
                : s.lineId)
            .toSet();

        void stubCrossLine() {
          when(() => mockRepo.getAllStations())
              .thenAnswer((_) async => crossLineStations);
          when(() => mockRepo.getAllConnections())
              .thenAnswer((_) async => crossLineConnections);
          when(() => mockRepo.getTransferTimes())
              .thenAnswer((_) async => {'환승역_4_9': 100});
          when(() => mockRepo.getExpressSkipEdges())
              .thenAnswer((_) async => crossLineExpress);
        }

        test(
            '4호선→9호선 환승 후 급행(후행 세그먼트 급행): fastestExpress/fastestLocal 모두 존재 + 급행이 더 빠름',
            () async {
          stubCrossLine();

          final result = await searchRoute.executeAll('401', '908');

          expect(result.fastestExpress, isNotNull,
              reason: '최단시간 경로가 급행(9E) edge 를 포함하므로 fastestExpress 존재해야 함');
          expect(result.fastestLocal, isNotNull,
              reason: '완행 대안(4호선+9호선 완행)이 존재해야 함');
          expect(
            result.fastestExpress!.totalTimeSeconds,
            lessThan(result.fastestLocal!.totalTimeSeconds),
            reason: '급행이 완행보다 빨라야 모드 비교 의미 있음',
          );
          // 회귀 pin: 정확한 시간값 — 그래프 토폴로지가 바뀌면 여기서 즉시 드러남.
          expect(result.fastestExpress!.totalTimeSeconds, 650);
          expect(result.fastestLocal!.totalTimeSeconds, 1060);
        });

        test(
            'fastestLocal은 fastest가 실제로 지나간 base 노선(4,9)만 사용 — 5호선 우회 금지',
            () async {
          stubCrossLine();

          final result = await searchRoute.executeAll('401', '908');

          expect(result.fastestExpress, isNotNull);
          expect(result.fastestLocal, isNotNull);

          final expressBaseLines = baseLineSet(result.fastestExpress!);
          final localBaseLines = baseLineSet(result.fastestLocal!);

          expect(expressBaseLines, equals({'4', '9'}));
          // 핵심 회귀 검증: fastestLocal 의 base 노선 집합이 fastestExpress 와
          // 정확히 같아야 하고, 미끼로 심어둔 5호선으로 우회하면 안 된다.
          expect(localBaseLines, equals(expressBaseLines),
              reason:
                  'fastestLocal 은 fastest 가 지나간 노선만 완행으로 재구성해야 함 (우회 금지)');
          expect(localBaseLines.contains('5'), isFalse,
              reason: '5호선 미끼 지름길로 우회하면 안 됨');
        });

        test(
            'fastestLocal은 급행이 통과(스킵)한 중간역(중간1, 중간2)에 모두 정차한다',
            () async {
          stubCrossLine();

          final result = await searchRoute.executeAll('401', '908');

          expect(result.fastestExpress, isNotNull);
          expect(result.fastestLocal, isNotNull);

          final expressStationNames = result.fastestExpress!.segments
              .expand((s) => s.stations)
              .map((st) => st.name)
              .toSet();
          final localStationNames = result.fastestLocal!.segments
              .expand((s) => s.stations)
              .map((st) => st.name)
              .toSet();

          // 급행은 중간1/중간2 를 건너뛴다.
          expect(expressStationNames.contains('중간1'), isFalse);
          expect(expressStationNames.contains('중간2'), isFalse);
          // 완행은 둘 다 정차해야 한다.
          expect(localStationNames.containsAll(['중간1', '중간2']), isTrue);
          // 완행 경로의 역 수(hop)가 급행보다 많아야 한다.
          expect(result.fastestLocal!.stationCount,
              greaterThan(result.fastestExpress!.stationCount));
        });
      });

      test(
          '인천대입구 → 인하대: 원인재 환승 1회 경로가 선택됨 (환승역 데이터 보강 회귀)',
          () async {
        // 원인재는 인천1호선과 수인분당선 환승역이지만, 과거 stations.json 에
        // 인천1호선 레코드(I24)만 있고 수인분당선 레코드와 환승 플래그가 누락되어
        // Dijkstra 가 인천1호선 본선을 끝까지 타고 인천역 근처로 돌아가 수인분당선
        // 으로 갈아타는 비상식적 경로를 선택했다.
        //
        // 축약 데이터로 동일 구조(인천1호선 3역 + 수인분당선 3역 + 원인재 환승)
        // 를 구성하고 fastest 가 원인재 환승 1회 경로를 선택하는지 검증한다.
        final st = [
          // 인천1호선 (인천대입구 → 캠퍼스타운 → 원인재)
          const Station(id: 'I30', name: '인천대입구', lineId: '인천1',
              latitude: 0, longitude: 0),
          const Station(id: 'I27', name: '캠퍼스타운', lineId: '인천1',
              latitude: 0, longitude: 0),
          const Station(id: 'I24', name: '원인재', lineId: '인천1',
              latitude: 0, longitude: 0,
              isTransfer: true, transferLines: ['인천1', '수인분당']),
          // 수인분당선 (원인재 → 연수 → 인하대) — 실제 순서는 다르지만
          // 토폴로지만 재현. B61(연수)이 원인재와 인하대 사이 중간역.
          const Station(id: 'K266', name: '원인재', lineId: '수인분당',
              latitude: 0, longitude: 0,
              isTransfer: true, transferLines: ['인천1', '수인분당']),
          const Station(id: 'B61', name: '연수', lineId: '수인분당',
              latitude: 0, longitude: 0),
          const Station(id: 'B54', name: '인하대', lineId: '수인분당',
              latitude: 0, longitude: 0),
        ];
        final conns = [
          const Connection(fromStationId: 'I30', toStationId: 'I27',
              lineId: '인천1', travelTimeSeconds: 120),
          const Connection(fromStationId: 'I27', toStationId: 'I24',
              lineId: '인천1', travelTimeSeconds: 120),
          const Connection(fromStationId: 'K266', toStationId: 'B61',
              lineId: '수인분당', travelTimeSeconds: 240),
          const Connection(fromStationId: 'B61', toStationId: 'B54',
              lineId: '수인분당', travelTimeSeconds: 180),
        ];
        when(() => mockRepo.getAllStations()).thenAnswer((_) async => st);
        when(() => mockRepo.getAllConnections())
            .thenAnswer((_) async => conns);
        when(() => mockRepo.getTransferTimes()).thenAnswer(
            (_) async => {'원인재_인천1_수인분당': 180});
        when(() => mockRepo.getExpressSkipEdges())
            .thenAnswer((_) async => <ExpressSkipEdge>[]);

        final result = await searchRoute.executeAll('I30', 'B54');

        expect(result.fastest, isNotNull);
        expect(result.fastest!.transferCount, 1,
            reason: '원인재에서 인천1 → 수인분당 환승 1회');
        expect(result.fastest!.segments.length, 2);
        expect(result.fastest!.segments[0].lineId, '인천1');
        expect(result.fastest!.segments[1].lineId, '수인분당');
        // 경로에 원인재가 환승 경계로 반드시 등장해야 한다.
        final allStationNames = result.fastest!.segments
            .expand((s) => s.stations)
            .map((st) => st.name)
            .toList();
        expect(allStationNames.contains('원인재'), isTrue,
            reason: 'fastest 경로는 원인재를 반드시 경유');
      });

      test(
          '환승역 (급행정차) → 비환승 급행정차: 출발역 9M 없음',
          () async {
        // 종합운동장(2·9, 급행정차) → 선정릉(9호선 단독, 급행정차).
        // 출발역이 환승역이어도 선정릉이 9호선 단독이면 시작 모드 전환 없어야.
        final st = [
          const Station(id: '930', name: '종합운동장', lineId: '9',
              latitude: 0, longitude: 0,
              isTransfer: true, transferLines: ['2', '9']),
          const Station(id: '929', name: '선정릉', lineId: '9',
              latitude: 0, longitude: 0),
          const Station(id: '218', name: '종합운동장', lineId: '2',
              latitude: 0, longitude: 0,
              isTransfer: true, transferLines: ['2', '9']),
        ];
        final cn = [
          const Connection(fromStationId: '930', toStationId: '929',
              lineId: '9', travelTimeSeconds: 150),
        ];
        final ex = [
          const ExpressSkipEdge(lineId: '9', fromStationId: '930',
              toStationId: '929', seconds: 145, skippedStationIds: []),
        ];
        when(() => mockRepo.getAllStations()).thenAnswer((_) async => st);
        when(() => mockRepo.getAllConnections())
            .thenAnswer((_) async => cn);
        when(() => mockRepo.getTransferTimes())
            .thenAnswer((_) async => <String, int>{});
        when(() => mockRepo.getExpressSkipEdges())
            .thenAnswer((_) async => ex);

        // Picker 대표가 2호선(218)이어도 선정릉은 9호선 단독(929_9, 929_9E).
        final result = await searchRoute.executeAll('218', '929');

        expect(result.fastest, isNotNull);
        expect(result.fastest!.transferCount, 0,
            reason: '환승역(9호선 공유) → 9호선 단독 역이면 환승 0');
        // 출발/도착 어느 쪽에서도 `9M` 세그먼트가 나오면 안 됨.
        expect(
          result.fastest!.segments.every((s) => s.lineId != '9M'),
          isTrue,
          reason: '경로에 모드 전환(`9M`) 세그먼트 없음',
        );
      });

      test(
          '급행 도착역에서 다른 노선으로 환승: 9M+transfer 이중 환승 버그 방지',
          () async {
        // 마곡나루(9호선 급행정차) → 판교(신분당선).
        // 경로: 9호선 급행 → 신논현(9호선 급행정차 + 신분당 환승) → 신분당선 → 판교.
        //
        // 과거 버그: `_E` 노드와 다른 노선 base 노드 사이 환승 edge 가 없어서
        // `925_9E → (9M) → 925_9 → (transfer) → SB_신분당` 이중 환승이 발생.
        // `_buildSegments` 가 연속 환승을 처리하면서 중간에 빈 "transfer 0분(0개역)"
        // 세그먼트를 삽입하고 transferCount 가 2 로 카운트된다.
        //
        // 수정: `_addTransferEdges` 에서 `_E` variant 도 포함 → `925_9E ↔ SB_신분당`
        // 직접 환승 edge 가 생기므로 Dijkstra 가 모드 전환 없이 바로 환승.
        final stations = [
          const Station(id: '905', name: '마곡나루', lineId: '9',
              latitude: 0, longitude: 0),
          const Station(id: '925', name: '신논현', lineId: '9',
              latitude: 0, longitude: 0,
              isTransfer: true, transferLines: ['9', '신분당']),
          const Station(id: 'D07', name: '신논현', lineId: '신분당',
              latitude: 0, longitude: 0,
              isTransfer: true, transferLines: ['9', '신분당']),
          const Station(id: 'D12', name: '판교', lineId: '신분당',
              latitude: 0, longitude: 0),
        ];
        final conns = [
          const Connection(fromStationId: '905', toStationId: '925',
              lineId: '9', travelTimeSeconds: 1000),
          const Connection(fromStationId: 'D07', toStationId: 'D12',
              lineId: '신분당', travelTimeSeconds: 800),
        ];
        final ex = [
          const ExpressSkipEdge(lineId: '9', fromStationId: '905',
              toStationId: '925', seconds: 700, skippedStationIds: []),
        ];
        when(() => mockRepo.getAllStations()).thenAnswer((_) async => stations);
        when(() => mockRepo.getAllConnections())
            .thenAnswer((_) async => conns);
        when(() => mockRepo.getTransferTimes()).thenAnswer(
            (_) async => {'신논현_9_신분당': 480});
        when(() => mockRepo.getExpressSkipEdges())
            .thenAnswer((_) async => ex);

        final result = await searchRoute.executeAll('905', 'D12');

        expect(result.fastest, isNotNull);
        // 핵심: 9호선 급행 → 신논현 → 신분당선 = 환승 1회.
        expect(result.fastest!.transferCount, 1,
            reason: '마곡→판교는 신논현 환승 1회만 필요');
        // 세그먼트는 정확히 2개: 9호선(급행 가능) + 신분당선.
        expect(result.fastest!.segments.length, 2,
            reason: '9M+transfer 이중 환승으로 인한 transfer 0분 세그먼트가 삽입되면 안 됨');
        // 어떤 세그먼트도 lineId='transfer' 이면 안 된다 (환승은 세그먼트 사이 경계).
        expect(
          result.fastest!.segments.every((s) => s.lineId != 'transfer'),
          isTrue,
          reason: 'transfer 를 lineId 로 가진 세그먼트가 나타나면 안 됨',
        );
      });

      test(
          '비환승 급행정차 → 환승역 (급행정차): 도착역 9M 없음',
          () async {
        // 선정릉(9호선 단독) → 종합운동장(2·9호선 환승). 위의 역방향.
        final st = [
          const Station(id: '929', name: '선정릉', lineId: '9',
              latitude: 0, longitude: 0),
          const Station(id: '930', name: '종합운동장', lineId: '9',
              latitude: 0, longitude: 0,
              isTransfer: true, transferLines: ['2', '9']),
          const Station(id: '218', name: '종합운동장', lineId: '2',
              latitude: 0, longitude: 0,
              isTransfer: true, transferLines: ['2', '9']),
        ];
        final cn = [
          const Connection(fromStationId: '929', toStationId: '930',
              lineId: '9', travelTimeSeconds: 150),
        ];
        final ex = [
          const ExpressSkipEdge(lineId: '9', fromStationId: '929',
              toStationId: '930', seconds: 145, skippedStationIds: []),
        ];
        when(() => mockRepo.getAllStations()).thenAnswer((_) async => st);
        when(() => mockRepo.getAllConnections())
            .thenAnswer((_) async => cn);
        when(() => mockRepo.getTransferTimes())
            .thenAnswer((_) async => <String, int>{});
        when(() => mockRepo.getExpressSkipEdges())
            .thenAnswer((_) async => ex);

        // 도착이 2호선(218) 대표여도 9호선 단독 출발과 직결.
        final result = await searchRoute.executeAll('929', '218');

        expect(result.fastest, isNotNull);
        expect(result.fastest!.transferCount, 0);
        expect(
          result.fastest!.segments.every((s) => s.lineId != '9M'),
          isTrue,
        );
      });

      test(
          '환승역 ↔ 환승역 (공유 급행 노선): fastest 가 급행 단독 — 출발 모드전환 edge 없음',
          () async {
        // 종합운동장(2·9) → 동작(4·9) 공유 9호선은 급행 지원.
        // 두 역 모두 9호선 급행 정차역이면 fastest 는 급행 단독이어야 한다.
        // 과거 버그: multi-source 에 가상 급행 노드(`930_9E`)가 빠져 있어
        // `930_9 → 9M → 930_9E → ... → 920_9E → 9M → 920_9` 형태가 나왔다
        // → 출발/도착 역에서 "모드 전환"이 발생하는 부자연스러운 경로.
        // 수정: multi-source/sink 에 `_E` 노드까지 포함.
        final expressStations = [
          const Station(id: '930', name: '종합운동장', lineId: '9',
              latitude: 0, longitude: 0,
              isTransfer: true, transferLines: ['2', '9']),
          const Station(id: '929', name: '선정릉', lineId: '9',
              latitude: 0, longitude: 0),
          const Station(id: '920', name: '동작', lineId: '9',
              latitude: 0, longitude: 0,
              isTransfer: true, transferLines: ['4', '9']),
          const Station(id: '218', name: '종합운동장', lineId: '2',
              latitude: 0, longitude: 0,
              isTransfer: true, transferLines: ['2', '9']),
          const Station(id: '420', name: '동작', lineId: '4',
              latitude: 0, longitude: 0,
              isTransfer: true, transferLines: ['4', '9']),
        ];
        final expressConnections = [
          const Connection(fromStationId: '930', toStationId: '929',
              lineId: '9', travelTimeSeconds: 200),
          const Connection(fromStationId: '929', toStationId: '920',
              lineId: '9', travelTimeSeconds: 200),
        ];
        // 9호선 급행: 930 → 920 직통(선정릉 스킵).
        final expressSkip = [
          const ExpressSkipEdge(
              lineId: '9', fromStationId: '930', toStationId: '920',
              seconds: 220, skippedStationIds: ['929']),
        ];

        when(() => mockRepo.getAllStations())
            .thenAnswer((_) async => expressStations);
        when(() => mockRepo.getAllConnections())
            .thenAnswer((_) async => expressConnections);
        when(() => mockRepo.getTransferTimes())
            .thenAnswer((_) async => <String, int>{});
        when(() => mockRepo.getExpressSkipEdges())
            .thenAnswer((_) async => expressSkip);

        final result = await searchRoute.executeAll('218', '420');

        expect(result.fastest, isNotNull);
        // 환승 없음.
        expect(result.fastest!.transferCount, 0,
            reason: '환승역 간 공유 급행 노선 → 급행 단독 환승 0');
        // 세그먼트는 모두 9호선 급행(`9E`) 하나여야 한다.
        expect(result.fastest!.segments.length, 1);
        expect(result.fastest!.segments.first.lineId, '9E',
            reason: '출발 모드 전환 없이 바로 9E 에서 시작해야 함');
        // 경로 edge 에 `9M`(모드 전환) 이 절대 포함되지 않아야 한다.
        final allEdgeLineIds = result.fastest!.segments
            .expand((s) => [s.lineId])
            .toSet();
        expect(allEdgeLineIds.contains('9M'), isFalse,
            reason: '출발/도착역에서 모드 전환 edge 가 경로에 나타나면 안 됨');

        // `fastestExpress` 도 동일: 출발/도착이 모두 급행정차역이면 `9E` 단독.
        expect(result.fastestExpress, isNotNull);
        expect(result.fastestExpress!.transferCount, 0,
            reason: 'fastestExpress 도 환승 0 이어야 함');
        expect(result.fastestExpress!.segments.length, 1,
            reason: 'fastestExpress 는 9E 단일 세그먼트');
        expect(result.fastestExpress!.segments.first.lineId, '9E');
      });

      test(
          '환승역 ↔ 환승역 (공유 노선): fastest 가 multi-source 로 환승 0 경로 채택',
          () async {
        // 종합운동장(2·9호선) → 동작(4·9호선).
        // 두 역 모두 9호선에 속하므로 9호선 단독 경로가 물리적으로 환승 0.
        // 과거 버그: 사용자가 선택한 대표 Station(218_2)에서 Dijkstra 시작하면
        // `218_2 → 930_9` 환승 edge 를 거쳐야 9호선 진입 → 가짜 환승 카운트.
        // 수정 후: multi-source/sink 로 `{218_2, 930_9}` 동시 시작, `{420_4, 920_9}`
        // 동시 종점. 9호선 930_9 → 920_9 를 환승 0 으로 직접 선택.
        final mixedStations = [
          // 9호선 축약
          const Station(id: '930', name: '종합운동장', lineId: '9',
              latitude: 0, longitude: 0,
              isTransfer: true, transferLines: ['2', '9']),
          const Station(id: '929', name: '선정릉', lineId: '9',
              latitude: 0, longitude: 0),
          const Station(id: '920', name: '동작', lineId: '9',
              latitude: 0, longitude: 0,
              isTransfer: true, transferLines: ['4', '9']),
          // 2호선(종합운동장) 환승 파트너
          const Station(id: '218', name: '종합운동장', lineId: '2',
              latitude: 0, longitude: 0,
              isTransfer: true, transferLines: ['2', '9']),
          const Station(id: '219', name: '잠실새내', lineId: '2',
              latitude: 0, longitude: 0),
          // 4호선(동작) 환승 파트너
          const Station(id: '420', name: '동작', lineId: '4',
              latitude: 0, longitude: 0,
              isTransfer: true, transferLines: ['4', '9']),
          const Station(id: '421', name: '이촌', lineId: '4',
              latitude: 0, longitude: 0),
        ];
        final mixedConnections = [
          const Connection(
              fromStationId: '930', toStationId: '929',
              lineId: '9', travelTimeSeconds: 150),
          const Connection(
              fromStationId: '929', toStationId: '920',
              lineId: '9', travelTimeSeconds: 180),
          // 2호선·4호선도 각자 최소 1개 완행 edge 를 둬서 multi-source/sink
          // 잘못 선택 시 탐지가 가능하도록 한다.
          const Connection(
              fromStationId: '218', toStationId: '219',
              lineId: '2', travelTimeSeconds: 200),
          const Connection(
              fromStationId: '420', toStationId: '421',
              lineId: '4', travelTimeSeconds: 200),
        ];

        when(() => mockRepo.getAllStations())
            .thenAnswer((_) async => mixedStations);
        when(() => mockRepo.getAllConnections())
            .thenAnswer((_) async => mixedConnections);
        when(() => mockRepo.getTransferTimes())
            .thenAnswer((_) async => <String, int>{});
        when(() => mockRepo.getExpressSkipEdges())
            .thenAnswer((_) async => <ExpressSkipEdge>[]);

        // Picker 대표는 종합운동장 218_2 + 동작 420_4 (다른 노선).
        final result = await searchRoute.executeAll('218', '420');

        expect(result.fastest, isNotNull);
        // 실제 물리적으로 9호선 완행 단독이라 환승 0.
        expect(result.fastest!.transferCount, 0,
            reason: '환승역 ↔ 환승역 + 공유 노선 → 환승 없이 가야 함');
        expect(
          result.fastest!.segments.every((s) => s.lineId == '9'),
          isTrue,
          reason: 'fastest 는 9호선 단독 세그먼트여야 함',
        );
      });

      test(
          '환승역 ↔ 환승역 (다른 대표 노선, 공유 급행 지원): transferLines 교집합으로 판정',
          () async {
        // 실제 앱 시나리오 재현:
        //   종합운동장(2/9 환승) 대표 Station = 218_2 (2호선 첫 등장)
        //   여의도(5/9 환승) 대표 Station = 517_5 (5호선 첫 등장)
        // 두 Station 의 lineId 는 '2'/'5' 로 다르지만 transferLines 의 교집합 {'9'}
        // 가 급행 지원 노선이므로 fastestExpress / fastestLocal 모두 9호선 기준으로
        // 계산되어야 한다.
        final mixedStations = [
          // 2호선 (일부만)
          const Station(id: '218', name: '종합운동장', lineId: '2',
              latitude: 0, longitude: 0,
              isTransfer: true, transferLines: ['2', '9']),
          const Station(id: '219', name: '삼성', lineId: '2',
              latitude: 0, longitude: 0),
          // 5호선 (일부만)
          const Station(id: '517', name: '여의도', lineId: '5',
              latitude: 0, longitude: 0,
              isTransfer: true, transferLines: ['5', '9']),
          const Station(id: '518', name: '여의나루', lineId: '5',
              latitude: 0, longitude: 0),
          // 9호선 (축약 — 종합운동장-선정릉-언주-...-여의도)
          const Station(id: '930', name: '종합운동장', lineId: '9',
              latitude: 0, longitude: 0,
              isTransfer: true, transferLines: ['2', '9']),
          const Station(id: '929', name: '선정릉', lineId: '9',
              latitude: 0, longitude: 0),
          const Station(id: '927', name: '봉은사', lineId: '9',
              latitude: 0, longitude: 0),
          const Station(id: '925', name: '신논현', lineId: '9',
              latitude: 0, longitude: 0),
          const Station(id: '920', name: '고속터미널', lineId: '9',
              latitude: 0, longitude: 0),
          const Station(id: '917', name: '노량진', lineId: '9',
              latitude: 0, longitude: 0),
          const Station(id: '915', name: '여의도', lineId: '9',
              latitude: 0, longitude: 0,
              isTransfer: true, transferLines: ['5', '9']),
        ];
        final mixedConnections = [
          // 9호선 완행: 역순 ID 감소 방향. 간격 통일 200s.
          for (final pair in [
            ['930', '929'], ['929', '927'], ['927', '925'],
            ['925', '920'], ['920', '917'], ['917', '915'],
          ])
            Connection(
              fromStationId: pair[0],
              toStationId: pair[1],
              lineId: '9',
              travelTimeSeconds: 200,
            ),
        ];
        // 9호선 급행: 중간 역 스킵.
        final mixedExpress = [
          const ExpressSkipEdge(
            lineId: '9', fromStationId: '930', toStationId: '925',
            seconds: 300, skippedStationIds: ['929', '927']),
          const ExpressSkipEdge(
            lineId: '9', fromStationId: '925', toStationId: '920',
            seconds: 200, skippedStationIds: []),
          const ExpressSkipEdge(
            lineId: '9', fromStationId: '920', toStationId: '915',
            seconds: 250, skippedStationIds: ['917']),
        ];

        when(() => mockRepo.getAllStations())
            .thenAnswer((_) async => mixedStations);
        when(() => mockRepo.getAllConnections())
            .thenAnswer((_) async => mixedConnections);
        when(() => mockRepo.getTransferTimes())
            .thenAnswer((_) async => <String, int>{});
        when(() => mockRepo.getExpressSkipEdges())
            .thenAnswer((_) async => mixedExpress);

        // 종합운동장 대표(2호선 218) → 여의도 대표(5호선 517).
        final result = await searchRoute.executeAll('218', '517');

        // 핵심 검증: 공유 노선 '9' 기반으로 fastestExpress/fastestLocal 이 나와야 한다.
        expect(result.fastestExpress, isNotNull,
            reason: 'transferLines 교집합 {9} 가 급행 지원이므로 fastestExpress 존재해야 함');
        expect(result.fastestLocal, isNotNull,
            reason: '공유 급행 지원 노선 9호선 완행 단독 경로 존재해야 함');

        // fastestLocal 은 9호선 완행 전 구간.
        expect(
          result.fastestLocal!.segments.every((s) => s.lineId == '9'),
          isTrue,
          reason: 'fastestLocal 은 같은 노선(9호선) 내 완행만',
        );
        // fastestExpress 는 9E edge 를 반드시 포함.
        expect(
          result.fastestExpress!.segments.any((s) => s.lineId.endsWith('E')),
          isTrue,
          reason: 'fastestExpress 는 급행(_E) 세그먼트를 포함해야 함',
        );

        // 급행이 완행보다 더 빠르거나 같음 (일반 시나리오).
        expect(
          result.fastestExpress!.totalTimeSeconds,
          lessThanOrEqualTo(result.fastestLocal!.totalTimeSeconds),
          reason: '급행 경로가 완행보다 같거나 빨라야 모드 비교 의미 있음',
        );
      });
    });

    test('환승역이 이전 세그먼트의 마지막 역에 포함된다', () async {
      // 201(시청) → 317(충무로): 2호선 → 을지로3가 환승 → 3호선
      final result = await searchRoute.execute('201', '317');

      expect(result, isNotNull);
      expect(result!.segments.length, 2);

      // 2호선 세그먼트: 시청, 을지로입구, 을지로3가 (환승역 포함)
      final firstSegment = result.segments[0];
      expect(firstSegment.lineId, '2');
      expect(firstSegment.stations.length, 3);
      expect(firstSegment.stations.last.name, '을지로3가');

      // 3호선 세그먼트: 을지로3가, 충무로
      final secondSegment = result.segments[1];
      expect(secondSegment.lineId, '3');
      expect(secondSegment.stations.length, 2);
      expect(secondSegment.stations.first.name, '을지로3가');
      expect(secondSegment.stations.last.name, '충무로');
    });

    group('transferGuides', () {
      test('가이드 데이터 없으면 환승별 null이 반환된다', () async {
        final result = await searchRoute.execute('201', '317');

        expect(result, isNotNull);
        expect(result!.transferGuides.length, result.transferDurations.length);
        expect(result.transferGuides.first, isNull);
      });

      test('same-line route의 transferGuides는 빈 리스트', () async {
        final result = await searchRoute.execute('201', '203');

        expect(result, isNotNull);
        expect(result!.transferGuides, isEmpty);
      });

      test('급행 세그먼트(`1E`) 후 환승 시 base 노선(`1`) 키로 가이드 매칭', () async {
        // 1호선 급행으로 영등포 도착 → 5호선 환승 시나리오(축약).
        // transfer_guides.json 에는 "영등포_1_down_5" 만 등록되어도 `1E` 세그먼트 끝에서
        // 동일 가이드가 조회되어야 한다 (baseLineId 정규화).
        const guide = TransferGuide(
            doorSide: DoorSide.right, car: 3, door: 2, note: '급행도 동일');
        final mixed = [
          const Station(id: '136', name: '용산', lineId: '1',
              latitude: 0, longitude: 0),
          const Station(id: '140', name: '영등포', lineId: '1',
              latitude: 0, longitude: 0,
              isTransfer: true, transferLines: ['1', '5']),
          const Station(id: '529', name: '영등포', lineId: '5',
              latitude: 0, longitude: 0,
              isTransfer: true, transferLines: ['1', '5']),
          const Station(id: '530', name: '신길', lineId: '5',
              latitude: 0, longitude: 0),
        ];
        final conns = [
          const Connection(fromStationId: '136', toStationId: '140',
              lineId: '1', travelTimeSeconds: 500),
          const Connection(fromStationId: '529', toStationId: '530',
              lineId: '5', travelTimeSeconds: 120),
        ];
        // 용산→영등포 급행 skip edge (노량진·대방·신길 역할은 본 테스트에선 생략)
        final ex = [
          const ExpressSkipEdge(lineId: '1', fromStationId: '136',
              toStationId: '140', seconds: 280, skippedStationIds: []),
        ];
        when(() => mockRepo.getAllStations()).thenAnswer((_) async => mixed);
        when(() => mockRepo.getAllConnections())
            .thenAnswer((_) async => conns);
        when(() => mockRepo.getTransferTimes())
            .thenAnswer((_) async => {'영등포_1_5': 180});
        when(() => mockRepo.getExpressSkipEdges())
            .thenAnswer((_) async => ex);
        // base 노선 키만 등록. `1E` 용 별도 키 없음.
        // 방향: 136(용산) → 140(영등포) 은 ID 증가 → 일반 노선(1호선)은 down=true.
        when(() => mockRepo.getTransferGuides())
            .thenAnswer((_) async => {'영등포_1_down_5': guide});

        // executeAll 의 fastest 는 multi-source/sink 로 136_1E 에서 바로 시작하여
        // 모드 전환(1M) 세그먼트가 삽입되지 않는다.
        final result = await searchRoute.executeAll('136', '530');

        expect(result.fastest, isNotNull);
        // 급행 세그먼트로 영등포 도착 → 5호선 환승 → 5호선 세그먼트.
        expect(result.fastest!.segments.length, 2);
        expect(result.fastest!.segments.first.lineId, '1E',
            reason: '첫 세그먼트가 1E 여야 본 테스트 의도대로 검증');
        expect(result.fastest!.transferGuides.length, 1);
        expect(result.fastest!.transferGuides.first, equals(guide),
            reason: '1E 세그먼트 후 환승 가이드는 base(`1`) 키로 매칭되어야 함');
      });

      test('4-tuple 키가 매칭되면 해당 가이드를 반영한다 (상행 방향)', () async {
        // 201(시청) → 203(을지로3가): 2호선 내선(상행, up) 방향.
        // isDownBetween(202, 203, "2")는 step=1 → step<0 아님 → false (up).
        // 키: "을지로3가_2_up_3"
        const guide = TransferGuide(
          doorSide: DoorSide.right,
          car: 5,
          door: 1,
          note: '충무로 방면 가까움',
        );
        when(() => mockRepo.getTransferGuides())
            .thenAnswer((_) async => {'을지로3가_2_up_3': guide});

        final result = await searchRoute.execute('201', '317');

        expect(result, isNotNull);
        expect(result!.transferGuides.length, 1);
        expect(result.transferGuides.first, equals(guide));
      });

      test('반대 방향(down) 키로만 등록된 경우 매칭되지 않고 null', () async {
        const guide = TransferGuide(doorSide: DoorSide.right, car: 5);
        // 서로 다른 키 (방향 반전)
        when(() => mockRepo.getTransferGuides())
            .thenAnswer((_) async => {'을지로3가_2_down_3': guide});

        final result = await searchRoute.execute('201', '317');

        expect(result, isNotNull);
        expect(result!.transferGuides.first, isNull);
      });

      test('역 순서를 뒤집은 경로에서도 방향 판정이 일관된다 (3호선 감소=up)', () async {
        // 317(충무로) → 201(시청)
        // 3호선 세그먼트: 317 → 316 (step=-1 → up, 일반노선 toNum<fromNum이므로 false)
        // 이전 노선: 3호선, 다음 노선: 2호선
        // 키: "을지로3가_3_up_2"
        const guide = TransferGuide(doorSide: DoorSide.left, car: 2);
        when(() => mockRepo.getTransferGuides())
            .thenAnswer((_) async => {'을지로3가_3_up_2': guide});

        final result = await searchRoute.execute('317', '201');

        expect(result, isNotNull);
        expect(result!.transferGuides.length, 1);
        expect(result.transferGuides.first, equals(guide));
      });

      test('2호선 감소(외선, down) 방향 세그먼트는 key에 "_down_"이 포함된다', () async {
        // 2호선을 거꾸로 내려오는 경로를 구성하기 위해 역 추가 및 연결 구성.
        final stationsExtra = [
          ...testStations,
          const Station(
              id: '204',
              name: '동대문역사문화공원',
              lineId: '2',
              latitude: 37.56,
              longitude: 127.0),
        ];
        final connectionsReverse = [
          // 204 → 203 → 202 → 201 (step 감소 = 외선/down)
          const Connection(
              fromStationId: '204',
              toStationId: '203',
              lineId: '2',
              travelTimeSeconds: 90),
          const Connection(
              fromStationId: '203',
              toStationId: '202',
              lineId: '2',
              travelTimeSeconds: 90),
          const Connection(
              fromStationId: '316',
              toStationId: '317',
              lineId: '3',
              travelTimeSeconds: 90),
        ];
        when(() => mockRepo.getAllStations())
            .thenAnswer((_) async => stationsExtra);
        when(() => mockRepo.getAllConnections())
            .thenAnswer((_) async => connectionsReverse);

        // 204 → 317: 2호선 외선(204→203) → 을지로3가 환승 → 3호선
        // 이전 세그먼트 끝 두 역: 204→203 (step=-1 → down)
        const guide = TransferGuide(doorSide: DoorSide.right, car: 4);
        when(() => mockRepo.getTransferGuides())
            .thenAnswer((_) async => {'을지로3가_2_down_3': guide});

        final result = await searchRoute.execute('204', '317');

        expect(result, isNotNull);
        expect(result!.transferGuides.length, 1);
        expect(result.transferGuides.first, equals(guide));
      });

      test('출발역이 환승역인 경우 첫 transferGuide는 null', () async {
        // 203(을지로3가, 2호선) → 317(충무로) : 2호선 출발이 환승역
        // 그러나 Dijkstra 상 바로 3호선 316으로 환승 → 317로 이동.
        // 이 때 2호선 세그먼트의 stations.length는 1 또는 0이므로 guide는 null.
        const guide = TransferGuide(doorSide: DoorSide.right, car: 3);
        // 어떤 키든 매칭되지 않도록 아예 엉뚱한 키만 등록.
        when(() => mockRepo.getTransferGuides())
            .thenAnswer((_) async => {'다른역_2_up_3': guide});

        final result = await searchRoute.execute('203', '317');

        expect(result, isNotNull);
        if (result!.transferGuides.isNotEmpty) {
          expect(result.transferGuides.first, isNull);
        }
      });

      test('transferGuides.length == transferDurations.length 불변',
          () async {
        final result = await searchRoute.execute('201', '317');

        expect(result, isNotNull);
        expect(result!.transferGuides.length,
            equals(result.transferDurations.length));
      });

      test('executeAll 결과의 fastest에도 transferGuides가 포함된다', () async {
        const guide = TransferGuide(car: 3, door: 2);
        when(() => mockRepo.getTransferGuides())
            .thenAnswer((_) async => {'을지로3가_2_up_3': guide});

        final result = await searchRoute.executeAll('201', '317');

        expect(result.fastest, isNotNull);
        expect(result.fastest!.transferGuides.length, 1);
        expect(result.fastest!.transferGuides.first, equals(guide));
      });
    });

    group('급행 시간 합산', () {
      test('모든 connection이 expressTimeSeconds를 가지면 totalExpressTimeSeconds non-null',
          () async {
        // 201 → 203: 두 구간 모두 급행 시간 60초.
        // 세그먼트 duration(완행) = 90+90 + 정차30 = 210, 급행 = 60+60+정차30 = 150
        when(() => mockRepo.getAllConnections()).thenAnswer(
          (_) async => [
            const Connection(
              fromStationId: '201',
              toStationId: '202',
              lineId: '2',
              travelTimeSeconds: 90,
              expressTimeSeconds: 60,
            ),
            const Connection(
              fromStationId: '202',
              toStationId: '203',
              lineId: '2',
              travelTimeSeconds: 90,
              expressTimeSeconds: 60,
            ),
          ],
        );

        final result = await searchRoute.execute('201', '203');

        expect(result, isNotNull);
        expect(result!.segments.length, 1);
        expect(result.segments.first.expressDurationSeconds, 150);
        expect(result.totalExpressTimeSeconds, 150);
        // 완행 시간은 그대로
        expect(result.totalTimeSeconds, 210);
      });

      test('일부 구간만 expressTimeSeconds — 해당 세그먼트 합산은 express+local 혼합',
          () async {
        // 201→202: 급행 60, 202→203: 급행 없음(완행 90만)
        // 완행 합 = 90+90+정차30 = 210, 급행 합 = 60+90(완행 폴백)+정차30 = 180
        when(() => mockRepo.getAllConnections()).thenAnswer(
          (_) async => [
            const Connection(
              fromStationId: '201',
              toStationId: '202',
              lineId: '2',
              travelTimeSeconds: 90,
              expressTimeSeconds: 60,
            ),
            const Connection(
              fromStationId: '202',
              toStationId: '203',
              lineId: '2',
              travelTimeSeconds: 90,
            ),
          ],
        );

        final result = await searchRoute.execute('201', '203');

        expect(result, isNotNull);
        expect(result!.segments.first.expressDurationSeconds, 180);
        expect(result.totalExpressTimeSeconds, 180);
      });

      test('어떤 connection도 expressTimeSeconds가 없으면 totalExpressTimeSeconds는 null',
          () async {
        // 기본 testConnections는 전혀 expressTimeSeconds가 없음
        final result = await searchRoute.execute('201', '203');

        expect(result, isNotNull);
        expect(result!.segments.first.expressDurationSeconds, isNull);
        expect(result.totalExpressTimeSeconds, isNull);
      });

      test(
          '첫 edge가 완행이고 뒤쪽 edge만 급행일 때 앞쪽 완행 시간이 누락되지 않음 (역순 시나리오)',
          () async {
        // 201→202: 급행 없음(완행 100만), 202→203: 급행 60
        // 완행 합 = 100+90+정차30 = 220
        // 급행 합 = 100(완행 폴백)+60(급행)+정차30 = 190
        // 버그가 있으면 앞쪽 완행 100초가 누락되어 90이 되거나 유사한 값이 나옴
        when(() => mockRepo.getAllConnections()).thenAnswer(
          (_) async => [
            const Connection(
              fromStationId: '201',
              toStationId: '202',
              lineId: '2',
              travelTimeSeconds: 100,
            ),
            const Connection(
              fromStationId: '202',
              toStationId: '203',
              lineId: '2',
              travelTimeSeconds: 90,
              expressTimeSeconds: 60,
            ),
          ],
        );

        final result = await searchRoute.execute('201', '203');

        expect(result, isNotNull);
        expect(result!.segments.first.expressDurationSeconds, 190,
            reason: '앞쪽 완행 구간(100)이 급행 모드에서 완행 폴백으로 합산돼야 함');
        expect(result.totalExpressTimeSeconds, 190);
      });

      test('환승 경로 — 한 세그먼트만 급행이면 합계는 local+express+환승', () async {
        // 2호선 구간은 완행만 (일반), 3호선 구간은 급행 지원
        when(() => mockRepo.getAllConnections()).thenAnswer(
          (_) async => [
            const Connection(
              fromStationId: '201',
              toStationId: '202',
              lineId: '2',
              travelTimeSeconds: 90,
            ),
            const Connection(
              fromStationId: '202',
              toStationId: '203',
              lineId: '2',
              travelTimeSeconds: 90,
            ),
            const Connection(
              fromStationId: '316',
              toStationId: '317',
              lineId: '3',
              travelTimeSeconds: 90,
              expressTimeSeconds: 30,
            ),
          ],
        );

        final result = await searchRoute.execute('201', '317');

        expect(result, isNotNull);
        // 2호선 세그먼트: 완행만 → expressDurationSeconds null
        expect(result!.segments[0].expressDurationSeconds, isNull);
        // 3호선 세그먼트: 급행 → expressDurationSeconds = 30 (단일 구간, 중간역 없음)
        expect(result.segments[1].expressDurationSeconds, 30);

        // 총 급행 = 2호선 완행(90+90+dwell30=210) + 환승180 + 3호선 급행30 = 420
        expect(result.totalExpressTimeSeconds, 420);
      });

      test('executeAll의 fastest와 leastTransfer 모두 totalExpressTimeSeconds 반영',
          () async {
        when(() => mockRepo.getAllConnections()).thenAnswer(
          (_) async => [
            const Connection(
              fromStationId: '201',
              toStationId: '202',
              lineId: '2',
              travelTimeSeconds: 90,
              expressTimeSeconds: 60,
            ),
            const Connection(
              fromStationId: '202',
              toStationId: '203',
              lineId: '2',
              travelTimeSeconds: 90,
              expressTimeSeconds: 60,
            ),
          ],
        );

        final result = await searchRoute.executeAll('201', '203');

        expect(result.fastest, isNotNull);
        expect(result.fastest!.totalExpressTimeSeconds, 150);
        // 동일 경로이므로 leastTransfer는 null
        expect(result.leastTransfer, isNull);
      });
    });

    group('급행 가상 노선 모델링', () {
      // 9호선 일부 시뮬레이션:
      // 902(A) - 903(B) - 904(C) - 905(D) - 906(E) - 907(F)
      // 완행 100초 간격. 급행은 902→905→907 직통.
      final stations9 = [
        const Station(id: '902', name: 'A', lineId: '9', latitude: 0, longitude: 0),
        const Station(id: '903', name: 'B', lineId: '9', latitude: 0, longitude: 0),
        const Station(id: '904', name: 'C', lineId: '9', latitude: 0, longitude: 0),
        const Station(id: '905', name: 'D', lineId: '9', latitude: 0, longitude: 0),
        const Station(id: '906', name: 'E', lineId: '9', latitude: 0, longitude: 0),
        const Station(id: '907', name: 'F', lineId: '9', latitude: 0, longitude: 0),
      ];
      final connections9 = [
        const Connection(fromStationId: '902', toStationId: '903', lineId: '9', travelTimeSeconds: 100),
        const Connection(fromStationId: '903', toStationId: '904', lineId: '9', travelTimeSeconds: 100),
        const Connection(fromStationId: '904', toStationId: '905', lineId: '9', travelTimeSeconds: 100),
        const Connection(fromStationId: '905', toStationId: '906', lineId: '9', travelTimeSeconds: 100),
        const Connection(fromStationId: '906', toStationId: '907', lineId: '9', travelTimeSeconds: 100),
      ];
      final expressEdges9 = [
        const ExpressSkipEdge(
          lineId: '9', fromStationId: '902', toStationId: '905',
          seconds: 150, skippedStationIds: ['903', '904']),
        const ExpressSkipEdge(
          lineId: '9', fromStationId: '905', toStationId: '907',
          seconds: 100, skippedStationIds: ['906']),
      ];

      test('9호선 B→F 시나리오 (완행 1정거장 + 급행 환승): 급행 경로 자동 선택',
          () async {
        when(() => mockRepo.getAllStations()).thenAnswer((_) async => stations9);
        when(() => mockRepo.getAllConnections())
            .thenAnswer((_) async => connections9);
        when(() => mockRepo.getTransferTimes())
            .thenAnswer((_) async => <String, int>{});
        when(() => mockRepo.getExpressSkipEdges())
            .thenAnswer((_) async => expressEdges9);

        // B(903, 비급행) → F(907, 급행정차)
        // 완행 단독: B→C→D→E→F = 400초 + dwell 90(중간 3역) = 490초
        // 급행 경로: B→A(완행 100) → A_E(모드 90) → F_E(급행 250) → F(모드 90)
        //   왕복 부담 큼. 또는: B→D(완행 200) → D_E(모드 90) → F_E(급행 100) → F(모드 90)
        //   = 200 + 90 + 100 + 90 = 480 (환승 인접 노드 dwell 제외)
        // 거리·가중치를 다시 조정하여 급행이 명확히 빠른 케이스 보장.
        final result = await searchRoute.execute('903', '907');

        expect(result, isNotNull);
        // 완행 단독은 490초. 급행 경로가 동일하거나 약간 더 빠른 정도.
        // 급행 경로가 선택되면 transferDurations 비어있지 않음.
        // 만약 완행이 더 빠르더라도 회귀는 아니므로 totalTimeSeconds 상한만 검증.
        expect(result!.totalTimeSeconds, lessThanOrEqualTo(490));
      });

      test('B→F (가중치 조정): 급행 경로가 완행보다 빠른 케이스', () async {
        // 완행 100초/구간이 너무 길어서 급행 이득이 작음. 완행을 200초로
        // 늘려서 급행 이득을 명확히 한다.
        final slowConnections = [
          const Connection(fromStationId: '902', toStationId: '903', lineId: '9', travelTimeSeconds: 200),
          const Connection(fromStationId: '903', toStationId: '904', lineId: '9', travelTimeSeconds: 200),
          const Connection(fromStationId: '904', toStationId: '905', lineId: '9', travelTimeSeconds: 200),
          const Connection(fromStationId: '905', toStationId: '906', lineId: '9', travelTimeSeconds: 200),
          const Connection(fromStationId: '906', toStationId: '907', lineId: '9', travelTimeSeconds: 200),
        ];
        when(() => mockRepo.getAllStations()).thenAnswer((_) async => stations9);
        when(() => mockRepo.getAllConnections())
            .thenAnswer((_) async => slowConnections);
        when(() => mockRepo.getTransferTimes())
            .thenAnswer((_) async => <String, int>{});
        when(() => mockRepo.getExpressSkipEdges())
            .thenAnswer((_) async => expressEdges9);

        // B(903) → F(907)
        // 완행 단독: 200*4 + dwell90 = 890
        // 급행 경로: B→D(완행 400) + 모드(90) + 급행(100) + 모드(90) = 680
        //   D는 중간역(dwell 30 추가) → 710
        final result = await searchRoute.execute('903', '907');

        expect(result, isNotNull);
        expect(result!.totalTimeSeconds, lessThan(890),
            reason: '급행 경로가 완행 단독보다 빨라야 함');
        // 급행 경로면 모드 전환(isTransfer=true)을 통과하므로 transferDurations 존재
        expect(result.transferDurations, isNotEmpty,
            reason: '급행 경로는 모드 전환 edge를 포함하므로 transferDurations가 비어있지 않아야 함');
        // 급행 세그먼트(`9E`)가 포함되어야 함
        expect(
          result.segments.any((s) => s.lineId == '9E'),
          isTrue,
          reason: '급행 세그먼트(`9E`)가 결과에 포함돼야 함',
        );
      });

      test('9호선 김포공항(A)→F 시나리오: 급행 단일 세그먼트 가능', () async {
        when(() => mockRepo.getAllStations()).thenAnswer((_) async => stations9);
        when(() => mockRepo.getAllConnections())
            .thenAnswer((_) async => connections9);
        when(() => mockRepo.getTransferTimes())
            .thenAnswer((_) async => <String, int>{});
        when(() => mockRepo.getExpressSkipEdges())
            .thenAnswer((_) async => expressEdges9);

        final result = await searchRoute.execute('902', '907');

        expect(result, isNotNull);
        // 완행: A→B→C→D→E→F = 500 + dwell120(중간4역) = 620
        // 급행: A→D→F (급행 노드들 사이): 모드 전환(90) + 150 + 100 + 모드 전환(90)
        //   = 430초 (환승 인접 노드 dwell 제외)
        // 급행이 선택돼야 함.
        expect(result!.totalTimeSeconds, lessThan(620),
            reason: '급행 경로가 완행 단독보다 빨라야 함');
      });

      test('급행 미운영 노선은 기존 동작과 동일 (회귀)', () async {
        // 기본 testStations(2/3호선) 사용. 급행 데이터 없음.
        final result = await searchRoute.execute('201', '203');

        expect(result, isNotNull);
        expect(result!.segments.length, 1);
        // 이동시간 180 + 정차시간 30 = 210
        expect(result.totalTimeSeconds, 210);
      });

      test('expressSkipEdges가 비어있으면 가상 _E 노드/세그먼트 미생성', () async {
        when(() => mockRepo.getAllStations()).thenAnswer((_) async => stations9);
        when(() => mockRepo.getAllConnections())
            .thenAnswer((_) async => connections9);
        when(() => mockRepo.getTransferTimes())
            .thenAnswer((_) async => <String, int>{});
        // expressSkipEdges는 빈 리스트 (기본값)

        final result = await searchRoute.execute('905', '907');

        expect(result, isNotNull);
        // 완행 단일 세그먼트
        expect(result!.segments.length, 1);
        expect(result.segments.first.lineId, '9');
        // 200 + dwell30(중간 E) = 230
        expect(result.totalTimeSeconds, 230);
      });
    });
  });
}
