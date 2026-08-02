// 금정역 1호선↔4호선 환승 회귀 가드.
//
// 2026-07-31 까지 금정은 stations.json 에 4호선(435) 한 건뿐이었고, 그 레코드의
// `transferLines` 는 실제와 무관한 `['4','수인분당']` 이었다(수인분당선은 금정을
// 지나지 않는다). 1호선 결선도 명학(171)↔군포(172) 직결로 금정을 건너뛰었다.
// 그 상태의 증상:
//   1) 1호선 금정 노드가 없어 **1호선↔4호선 금정 환승 edge 가 생성되지 않았다**.
//      환승 edge 는 `GraphBuilder._addTransferEdges` 가 **역명 일치**로만 만들기
//      때문에, 한쪽 노선의 Station 레코드가 없으면 짝이 없어 아무 edge 도 안 생긴다
//      (경강선 판교·성남·이매와 같은 구조의 버그 — `gyeonggang_line_test.dart` 참조).
//   2) 그 결과 경부선 ↔ 안산선 경로가 금정을 못 쓰고 사당·서울역 등으로 크게
//      우회해 소요시간·환승횟수가 실제보다 나쁘게 나왔다.
//   3) `transfer_times.json` 에 실재하지 않는 `금정_4_수인분당` 키가 있었다.
//      이 파일은 `tool/build_transfer_times.dart` 가 stations.json 의
//      `transferLines` 로 필요 키 집합을 만들므로, 잘못된 소속이 그대로 키가 됐다.
//
// 역 ID: 1호선은 101~199 가 빈틈없이 소진돼 명학(171)~군포(172) 사이에 넣을 정수
// 번호가 없다. 그래서 "171.5" 를 뜻하는 `1715` 를 부여하고, 방향 판정(ID 증가 =
// 하행)은 `line_direction.dart` 의 1호선 rank 보정이 담당한다.
//
// 소요시간: getTrainSch(1호선 평일 상·하행) 실측 —
// `다음역 trainArvlTm − 현재역 trainDptreTm` (dwell 제외 = 앱 규약).
// 원본 캐시는 `data/timetables/1_금정_{상행,하행}.json`.
// ⚠ `tool/compute_travel_times.dart` 는 `trainDptreTm` 차이(= dwell 포함)로
// 산출하므로 재실행하면 이 값을 150/210 으로 바꾼다. 앱은 경로 총시간에
// 중간역 dwell 을 따로 더하므로(`core/constants/dwell_time.dart`) 그 값은 dwell
// 이중 가산이 된다. 아래 소요시간 어서션이 그 회귀를 잡는 가드다.
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seoul_subway/core/utils/headway_estimator.dart';
import 'package:seoul_subway/core/utils/line_direction.dart';
import 'package:seoul_subway/data/local/local_data_source.dart';
import 'package:seoul_subway/data/local/timetable_data_source.dart';
import 'package:seoul_subway/data/repositories/station_repository_impl.dart';
import 'package:seoul_subway/domain/entities/connection.dart';
import 'package:seoul_subway/domain/entities/station.dart';
import 'package:seoul_subway/domain/usecases/search_route.dart';
import 'package:seoul_subway/features/route_search/utils/departure_time_calculator.dart'
    show baseLineId;
import 'package:seoul_subway/graph/graph_builder.dart';

/// 1호선 금정 역 ID ("171.5" = 명학 171 ~ 군포 172 사이).
const _geumjeong1 = '1715';

/// 4호선 금정 역 ID.
const _geumjeong4 = '435';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<Station> stations;
  late List<Connection> connections;
  late List<Map<String, dynamic>> lines;
  late Map<String, int> transferTimes;

  setUpAll(() async {
    stations = (jsonDecode(
                await rootBundle.loadString('assets/json/stations.json'))
            as List)
        .map((e) => Station.fromJson(e as Map<String, dynamic>))
        .toList();
    connections = (jsonDecode(
                await rootBundle.loadString('assets/json/connections.json'))
            as List)
        .map((e) => Connection.fromJson(e as Map<String, dynamic>))
        .toList();
    lines = (jsonDecode(await rootBundle.loadString('assets/json/lines.json'))
            as List)
        .cast<Map<String, dynamic>>();
    transferTimes = (jsonDecode(
            await rootBundle.loadString('assets/json/transfer_times.json'))
        as Map<String, dynamic>).cast<String, int>();
  });

  test('금정이 1호선·4호선 두 레코드로 등록되어 있다', () {
    final byId = {for (final s in stations) s.id: s};
    final one = byId[_geumjeong1];
    final four = byId[_geumjeong4];

    expect(one, isNotNull, reason: '1호선 금정($_geumjeong1) 레코드가 없다');
    expect(four, isNotNull);
    expect(one!.name, '금정');
    expect(four!.name, '금정');
    expect(one.lineId, '1');
    expect(four.lineId, '4');

    // 같은 물리 역이므로 좌표·위경도가 일치해야 한다.
    expect(one.svgX, four.svgX);
    expect(one.svgY, four.svgY);
    expect(one.latitude, four.latitude);
    expect(one.longitude, four.longitude);
    expect((one.svgX, one.svgY), (816.0, 1352.0),
        reason: 'SVG 원본의 금정 circle 좌표');

    // 환승 edge 생성 조건: 양쪽 모두 isTransfer + 정확한 소속 노선.
    expect(one.isTransfer, isTrue);
    expect(four.isTransfer, isTrue);
    expect(one.transferLines, ['1', '4']);
    expect(four.transferLines, ['1', '4'],
        reason: '수인분당선은 금정을 지나지 않는다');

    // 이름이 금정인 레코드는 이 둘뿐이어야 한다(중복 노드 방지).
    expect(stations.where((s) => s.name == '금정').map((s) => s.id).toSet(),
        {_geumjeong1, _geumjeong4});
  });

  test('1호선 경부선이 명학 - 금정 - 군포 순서로 이어진다', () {
    Connection? edge(String a, String b) => connections
        .cast<Connection?>()
        .firstWhere(
          (c) =>
              c!.lineId == '1' &&
              !c.isTransfer &&
              ((c.fromStationId == a && c.toStationId == b) ||
                  (c.fromStationId == b && c.toStationId == a)),
          orElse: () => null,
        );

    expect(edge('171', '172'), isNull,
        reason: '명학↔군포 직결은 금정을 건너뛴다');

    // getTrainSch 실측 (평일 상·하행 n=220, 편차 0).
    final myeonghak = edge('171', _geumjeong1);
    expect(myeonghak, isNotNull, reason: '명학↔금정 연결이 없다');
    expect(myeonghak!.travelTimeSeconds, 120);

    final gunpo = edge(_geumjeong1, '172');
    expect(gunpo, isNotNull, reason: '금정↔군포 연결이 없다');
    expect(gunpo!.travelTimeSeconds, 180);
    // 구 급행 모델(`expressTimeSeconds`)은 전 노선에서 제거됐다 — 급행은 가상
    // 노선 `1E` 의 skip edge 가 단독으로 담당한다. 잔재 검사는
    // `test/data/connections_no_express_asset_test.dart`.

    // lines.json 의 역 순서에도 반영되어야 UI 노선도 순서가 맞는다.
    final line1Ids = (lines.firstWhere((l) => l['id'] == '1')['stationIds']
            as List)
        .cast<String>();
    expect(
      line1Ids.sublist(line1Ids.indexOf('170'), line1Ids.indexOf('173') + 1),
      ['170', '171', _geumjeong1, '172', '173'],
    );
  });

  test('transfer_times 키가 금정_1_4 이다', () {
    expect(transferTimes.containsKey('금정_1_4'), isTrue);
    expect(transferTimes.containsKey('금정_4_수인분당'), isFalse,
        reason: '실재하지 않는 환승쌍이다');
    // 코레일 관할이라 서울교통공사 공식 CSV 에 없어 생성기 기본값 180 이 적용된다.
    expect(transferTimes['금정_1_4'], 180);
  });

  test('1호선 방향 규칙: 금정 rank 보정 후에도 ID 증가 = 하행', () {
    // 금정(1715)은 명학(171)과 군포(172) 사이 → rank 171.5.
    expect(isDownBetween('171', _geumjeong1, '1'), isTrue,
        reason: '명학 → 금정 은 하행(천안 방면)');
    expect(isDownBetween(_geumjeong1, '172', '1'), isTrue,
        reason: '금정 → 군포 은 하행');
    expect(isDownBetween('172', _geumjeong1, '1'), isFalse,
        reason: '군포 → 금정 은 상행');
    expect(isDownBetween(_geumjeong1, '171', '1'), isFalse,
        reason: '금정 → 명학 은 상행');
    expect(isDownBetween('170', _geumjeong1, '1'), isTrue);
    expect(isDownBetween('173', _geumjeong1, '1'), isFalse);

    // 가상 급행 노선(`1E`)도 base 규칙으로 정규화된다.
    expect(isDownBetween('170', _geumjeong1, '1E'), isTrue);
    expect(isDownBetween(_geumjeong1, '170', '1E'), isFalse);

    // 기존 1호선 방향 판정은 그대로 (rank 보정이 일반 규칙을 깨지 않는다).
    expect(isDownBetween('133', '134', '1'), isTrue);
    expect(isDownBetween('172', '173', '1'), isTrue);
    expect(isDownBetween('173', '172', '1'), isFalse);
    expect(isDownBetween('199', '101', '1'), isFalse);
  });

  test('그래프에 금정 1호선↔4호선 환승 edge 가 생성된다', () {
    final graph = GraphBuilder().build(
      stations: stations,
      connections: connections,
      transferTimes: transferTimes,
    );

    final node1 = '${_geumjeong1}_1';
    final node4 = '${_geumjeong4}_4';
    expect(graph.containsNode(node1), isTrue);
    expect(graph.containsNode(node4), isTrue);

    bool hasTransfer(String from, String to) => graph
        .getNeighbors(from)
        .any((e) => e.toNodeId == to && e.isTransfer);

    expect(hasTransfer(node1, node4), isTrue,
        reason: '1호선 → 4호선 금정 환승 edge 가 없다');
    expect(hasTransfer(node4, node1), isTrue,
        reason: '4호선 → 1호선 금정 환승 edge 가 없다');
  });

  test('경부선 → 안산선 경로가 금정 환승 1회로 계산된다', () async {
    // 명학은 금정 바로 북쪽 인접역이라 급행·모드전환이 끼어들지 않아
    // `transferCount == 1` 을 정확히 고정할 수 있는 조합이다.
    // (수원 등 남부 역은 급행을 타게 되고 금정이 급행 통과역이라 모드전환까지
    //  끼어들어 환승이 3회가 된다 — 아래 별도 테스트에서 다룬다.)
    final route = await SearchRoute(
      stationRepository:
          StationRepositoryImpl(localDataSource: LocalDataSource()),
      timetableDataSource: TimetableDataSource(),
    ).execute('171', '436'); // 명학(1호선) → 산본(4호선)

    expect(route, isNotNull);
    expect(route!.transferCount, 1,
        reason: '회귀 당시엔 사당 등으로 우회해 환승이 늘어났다');
    expect(route.segments.length, 2);

    // 환승 지점 = 앞 세그먼트의 종착역 = 뒤 세그먼트의 시작역 = 금정.
    expect(route.segments.first.stations.last.name, '금정');
    expect(route.segments.last.stations.first.name, '금정');
    expect(route.segments.last.stations.last.name, '산본');

    // 명학 → 금정(120s) + 환승(180s) + 금정 → 산본. 우회 경로는 1시간을 넘는다.
    expect(route.totalTimeSeconds, lessThan(1200));
  });

  test('경부선 남부(수원) → 안산선 경로가 금정에서 4호선으로 갈아탄다', () async {
    // 사용자가 지목한 회귀 시나리오. 회귀 당시엔 금정 환승 edge 가 없어
    // 사당(2·4)·서울역 등으로 크게 우회했다.
    final route = await SearchRoute(
      stationRepository:
          StationRepositoryImpl(localDataSource: LocalDataSource()),
      timetableDataSource: TimetableDataSource(),
    ).execute('177', '436'); // 수원(1호선) → 산본(4호선)

    expect(route, isNotNull);

    // 마지막 세그먼트: 금정에서 4호선으로 갈아타 산본까지.
    final last = route!.segments.last;
    expect(last.lineId, '4');
    expect(last.stations.first.name, '금정');
    expect(last.stations.last.name, '산본');

    // 그 직전 세그먼트는 1호선 계열(완행 `1` 또는 급행 `1E`)이고 금정에서 끝난다.
    final prev = route.segments[route.segments.length - 2];
    expect(baseLineId(prev.lineId), '1');
    expect(prev.stations.last.name, '금정');

    // 1호선↔4호선 환승은 금정 한 번뿐 — 다른 환승역을 경유하지 않는다.
    expect(
      route.segments.where((s) => baseLineId(s.lineId) == '4').length,
      1,
    );
    // 4호선 앞은 전부 1호선 계열(완행 `1`/급행 `1E`/모드전환 `1M`)이다.
    expect(
      route.segments
          .take(route.segments.length - 1)
          .every((s) => baseLineId(s.lineId) == '1' || s.lineId == '1M'),
      isTrue,
    );
    // 금정은 급행 통과역이라 급행으로 바로 내릴 수 없다. 실제 경로는
    // `1M(모드전환) → 1E 급행 수원→군포 → 완행 군포→금정 → 4호선` 으로
    // 세그먼트가 4개(환승 3회)까지 늘어난다. 우회 회귀의 가드는 위의
    // "금정에서 갈아탄다" 어서션이므로 여기서는 상한만 둔다.
    expect(route.transferCount, lessThanOrEqualTo(3));
    // 우회 경로(사당 경유)는 1시간을 넘었다.
    expect(route.totalTimeSeconds, lessThan(2400));
  });

  test('배차간격 반영 그래프에도 금정 두 노드가 모두 존재한다', () async {
    final repo = StationRepositoryImpl(localDataSource: LocalDataSource());
    final graph = GraphBuilder().build(
      stations: await repo.getAllStations(),
      connections: await repo.getAllConnections(),
      transferTimes: await repo.getTransferTimes(),
      expressSkipEdges: await repo.getExpressSkipEdges(),
      headwaySeconds:
          buildHeadwayMap(await TimetableDataSource().loadSchedules()),
    );
    expect(graph.getNodeIdsForStation('금정').toSet(),
        containsAll({'${_geumjeong1}_1', '${_geumjeong4}_4'}));
    // 금정은 경부선 급행 통과역이라 가상 급행 노드는 만들어지지 않는다.
    expect(graph.containsNode('${_geumjeong1}_1E'), isFalse);
  });

  test('1호선 금정은 역별 시간표가 없어 배차간격 폴백으로 계산된다 (알려진 공백)', () async {
    // `line_schedules.json` 의 1호선 t/tE 는 서울교통공사
    // SearchSTNTimeTableByIDService(`tool/build_metro_timetable.dart`)가 만든다.
    // 이 생성기는 역 단위 병합이라 안전하지만 `--lines=1` 재실행 시 100개 역의
    // 시각이 오늘 API 값으로 함께 갱신돼 금정과 무관한 변동이 섞인다. 그래서
    // 금정 시간표 보강은 별건으로 남겼다. 그 결과 금정에서 1호선을 타는 경로만
    // "출발 시각 선택"이 비활성이고 배차간격 폴백으로 계산된다(크래시 없음).
    //
    // 후속 작업으로 시간표를 채우면 이 테스트가 실패한다 — 그때 삭제할 것.
    final schedules = await TimetableDataSource().loadSchedules();
    final t = schedules['1']!.weekday.stationDepartures;
    expect(t, isNotNull);
    expect(t!.containsKey('171'), isTrue, reason: '명학은 시간표가 있다');
    expect(t.containsKey('172'), isTrue, reason: '군포는 시간표가 있다');
    expect(t.containsKey(_geumjeong1), isFalse,
        reason: '금정 시간표가 채워졌다면 이 테스트를 삭제하라');
  });

  test('금정은 경부선 급행 통과역이라 skip edge 가 함께 건너뛴다', () async {
    // 급행 정차 판별의 유일한 유효 신호는 "통과역엔 레코드 자체가 없다" 다
    // (커밋 86b313e). 실제 급행 3편성 K1902·K1904(상행)·K1945(하행) 기준으로
    // `data/timetables/1_금정_{상행,하행}.json` 에는 이 편성 레코드가 하나도
    // 없다 — 명학·당정·구로와 같은 통과역이다. 대조로 군포·안양·의왕·금천구청은
    // 세 편성 모두 레코드를 갖는다.
    //
    // ⚠ `trainArvlTm` 채움 여부는 급행 지표가 **아니다**. 금정은 etrnYn=Y 268편
    // 전부 채워져 있어 정차역처럼 보이지만, 같은 지표로 정차역 세마·진위가
    // 0.4% 이고 통과역 명학·당정도 0.4% 다.
    final edges = await StationRepositoryImpl(localDataSource: LocalDataSource())
        .getExpressSkipEdges();
    final line1 = edges.where((e) => e.lineId == '1').toList();

    // 금정은 급행 정차역이 아니므로 skip edge 의 끝점이 될 수 없다.
    expect(
      line1.where((e) =>
          e.fromStationId == _geumjeong1 || e.toStationId == _geumjeong1),
      isEmpty,
      reason: '금정은 급행 정차역이 아니다',
    );

    // 안양(170) → 군포(172) 급행이 명학과 금정을 함께 건너뛴다. 금정을
    // `skippedStationIds` 에 넣지 않으면 지도 급행 하이라이트가 끊긴다
    // (`subway_map_viewer.dart` 의 `_expressSkippedIndex`).
    final anyangToGunpo = line1.singleWhere(
        (e) => e.fromStationId == '170' && e.toStationId == '172');
    expect(anyangToGunpo.skippedStationIds, ['171', _geumjeong1]);
  });
}
