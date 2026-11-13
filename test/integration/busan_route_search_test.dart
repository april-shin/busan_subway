// 부산 실데이터(assets/json)로 SearchRoute 를 끝까지 태우는 경로 검색 통합 테스트.
//
// 환승 0·1·2·3회 대표 경로, 이름이 다른 환승(벡스코), 경유지 포함 경로를 검증한다.
// 소요시간은 구간 travelTimeSeconds(사이트 값 − 정차 30초) + 정차 30초 + 환승시간
// (+ 배차간격/2 대기)의 합이라 데이터 갱신에 흔들리므로 **합리적 범위**만 단언한다.
import 'package:flutter_test/flutter_test.dart';
import 'package:busan_subway/data/local/local_data_source.dart';
import 'package:busan_subway/data/repositories/station_repository_impl.dart';
import 'package:busan_subway/domain/entities/route_result.dart';
import 'package:busan_subway/domain/usecases/search_route.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SearchRoute searchRoute;

  setUp(() {
    searchRoute = SearchRoute(
      stationRepository: StationRepositoryImpl(localDataSource: LocalDataSource()),
    );
  });

  List<String> lineIds(RouteResult r) => [for (final s in r.segments) s.lineId];
  int minutes(RouteResult r) => r.totalTimeSeconds ~/ 60;

  group('환승 0회', () {
    test('1호선 다대포해수욕장(95) → 노포(134): 단일 구간 40개역', () async {
      final r = await searchRoute.execute('95', '134');
      expect(r, isNotNull);
      expect(r!.transferCount, 0);
      expect(lineIds(r), ['1']);
      expect(r.segments.single.stations, hasLength(40));
      expect(r.segments.single.direction, '노포 방면');
      expect(r.transferDurations, isEmpty);
      expect(r.transferGuides, isEmpty);
      expect(minutes(r), inInclusiveRange(60, 95));
    });

    test('상행(노포 → 다대포해수욕장)도 같은 시간대로 나오고 방면이 반대다', () async {
      final r = await searchRoute.execute('134', '95');
      expect(r, isNotNull);
      expect(lineIds(r!), ['1']);
      expect(r.segments.single.direction, '다대포해수욕장 방면');
      final fwd = await searchRoute.execute('95', '134');
      expect((r.totalTimeSeconds - fwd!.totalTimeSeconds).abs(),
          lessThan(10 * 60));
    });
  });

  group('환승 1회', () {
    test('다대포해수욕장(1) → 장산(2): 서면에서 1→2 환승', () async {
      final r = await searchRoute.execute('95', '201');
      expect(r, isNotNull);
      expect(r!.transferCount, 1);
      expect(lineIds(r), ['1', '2']);
      expect(r.segments.first.stations.last.name, '서면');
      expect(r.segments.last.stations.first.name, '서면');
      expect(r.transferDurations.length, 1);
      expect(r.transferWalkDurations, [360], reason: 'transfer_times 서면_1_2');
      expect(r.transferDurations.single, greaterThanOrEqualTo(360));
      expect(minutes(r), inInclusiveRange(70, 110));
    });

    test('이름이 다른 환승: 센텀시티(2) → 센텀(동해선)은 벡스코(시립미술관)→벡스코 환승', () async {
      final r = await searchRoute.execute('206', '809');
      expect(r, isNotNull);
      expect(r!.transferCount, 1);
      expect(lineIds(r), ['2', '동해'],
          reason: "가짜 'transfer' 구간이 끼면 안 된다");
      expect(r.segments.first.stations.last.name, '벡스코(시립미술관)');
      expect(r.segments.last.stations.first.name, '벡스코');
      expect(r.transferWalkDurations, [360]);
      expect(minutes(r), inInclusiveRange(8, 20));
    });

    test('미남(4호선) → 태화강(동해선): 출발역이 환승역이라 3호선으로 시작해 거제에서 동해선 1회', () async {
      // 4호선 미남(401)은 3호선 미남(309)과 같은 역이라 출발지 후보에 3호선 노드가 포함된다.
      final r = await searchRoute.execute('401', '823');
      expect(r, isNotNull);
      expect(lineIds(r!), ['3', '동해'],
          reason: '출발역이 환승역이면 출발 노선을 고르는 환승은 구간으로 세지 않는다');
      expect(r.transferCount, 1);
      expect(minutes(r), inInclusiveRange(60, 100));
    });
  });

  group('환승 2회 이상', () {
    test('다대포해수욕장(1) → 가야대(부산김해): 서면·사상 환승 2회', () async {
      final r = await searchRoute.execute('95', '921');
      expect(r, isNotNull);
      expect(r!.transferCount, 2);
      expect(lineIds(r), ['1', '2', '부산김해']);
      expect(r.segments[0].stations.last.name, '서면');
      expect(r.segments[1].stations.last.name, '사상');
      expect(r.transferDurations, hasLength(2));
      expect(minutes(r), inInclusiveRange(90, 140));
    });

    test('양산(2) → 가야대(부산김해): 덕천(2→3)·대저(3→부산김해) 환승 2회', () async {
      final r = await searchRoute.execute('243', '921');
      expect(r, isNotNull);
      expect(r!.transferCount, 2);
      expect(lineIds(r), ['2', '3', '부산김해']);
      expect(minutes(r), inInclusiveRange(55, 100));
    });

    test('노포(1) → 가야대(부산김해): 동래·미남·대저 환승 3회', () async {
      final r = await searchRoute.execute('134', '921');
      expect(r, isNotNull);
      expect(r!.transferCount, 3);
      expect(lineIds(r), ['1', '4', '3', '부산김해']);
      expect(r.transferWalkDurations, [480, 360, 210]);
      expect(minutes(r), inInclusiveRange(60, 110));
    });

    test('모든 결과에서 transferGuides/Durations 길이 불변식이 성립한다', () async {
      for (final (a, b) in [('95', '201'), ('95', '921'), ('134', '921')]) {
        final r = await searchRoute.execute(a, b);
        expect(r!.transferDurations.length, r.transferCount);
        expect(r.transferWalkDurations.length, r.transferCount);
        expect(r.transferGuides.length, r.transferCount,
            reason: 'transfer_guides.json 이 비어 있으면 모두 null');
        expect(r.transferGuides.every((g) => g == null), isTrue);
      }
    });
  });

  group('경유지 포함', () {
    test('다대포해수욕장 → 노포 경유 장산(2호선): 최단이 아닌 우회지만 반드시 장산을 지난다', () async {
      final direct = await searchRoute.executeAll('95', '134');
      final via = await searchRoute.executeAll('95', '134', viaStationIds: ['201']);

      expect(via.fastest, isNotNull);
      final passed = {
        for (final s in via.fastest!.segments) ...s.stations.map((e) => e.name),
      };
      expect(passed, contains('장산'));
      expect(via.fastest!.transferCount, greaterThanOrEqualTo(2));
      expect(via.fastest!.totalTimeSeconds,
          greaterThan(direct.fastest!.totalTimeSeconds));
      expect(minutes(via.fastest!), inInclusiveRange(110, 170));
    });

    test('이미 최단경로상에 있는 경유역(부산진)은 결과를 바꾸지 않는다', () async {
      final direct = await searchRoute.executeAll('95', '134');
      final via = await searchRoute.executeAll('95', '134', viaStationIds: ['115']);
      expect(via.fastest!.totalTimeSeconds, direct.fastest!.totalTimeSeconds);
      expect(lineIds(via.fastest!), lineIds(direct.fastest!));
    });

    test('급행이 없어 fastestExpress/fastestLocal 은 항상 null 이다', () async {
      final all = await searchRoute.executeAll('95', '921');
      expect(all.fastest, isNotNull);
      expect(all.fastestExpress, isNull);
      expect(all.fastestLocal, isNull);
    });

    test('존재하지 않는 역 ID 는 null', () async {
      expect(await searchRoute.execute('95', 'zzz'), isNull);
      final all = await searchRoute.executeAll('nope', '134');
      expect(all.fastest, isNull);
    });
  });

  group('동명이역 (환승 아님)', () {
    test('좌천(1호선) → 좌천(동해선): 이름이 같아도 서로 다른 역이라 실제 이동 경로가 나와야 한다',
        () async {
      // 데이터상 1호선 좌천(116)과 동해선 좌천(816)은 별개 역(수십 km 거리)이다.
      // SearchRoute 가 이름으로 노드를 찾아 같은 이름이면 0초 단일 노드 경로를 만들어
      // 빈 결과(transferCount -1)가 나온다 — lib 결함 의심(보고 대상).
      final r = await searchRoute.execute('116', '816');
      expect(r, isNotNull);
      expect(r!.segments, isNotEmpty);
      expect(r.totalTimeSeconds, greaterThan(0));
      expect(r.transferCount, greaterThanOrEqualTo(1));
    });
  });
}
