import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:seoul_subway/domain/entities/station.dart';
import 'package:seoul_subway/domain/entities/connection.dart';
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
      expect(result!.stationCount, greaterThanOrEqualTo(2));
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
  });
}
