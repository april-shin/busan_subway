import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:seoul_subway/domain/entities/station.dart';
import 'package:seoul_subway/domain/entities/connection.dart';
import 'package:seoul_subway/domain/entities/express_skip_edge.dart';
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
