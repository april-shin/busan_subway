// 2호선 까치산 노드 신설 회귀 가드.
//
// 까치산은 실제로 2호선(신정지선 종점)·5호선 환승역인데 `stations.json` 에
// 5호선 레코드(509)뿐이었고, `transferLines=['2','5']` 는 선언만 있었다.
// 환승 edge 는 `GraphBuilder._addTransferEdges` 가 **역명 일치**로만 만들기
// 때문에 한쪽 레코드가 없으면 어떤 edge 도 생성되지 않는다 — 금정(17e97af)·
// 가산디지털단지(1425)와 같은 부류의 마지막 잔여 건이었다.
//
// 증상: 2호선 신정지선이 신정네거리(249)에서 끊겨, 신정네거리→까치산이
// 33.0분/환승 1회(실제 1정거장 ~2.5분)로 계산됐다.
//
// 소요시간 150s 근거 — `data/inter_station.json`(서울시 공식 역간 소요시간)의
// 까치산 HM 2:30. 같은 지선의 도림천→양천구청 150s(HM 2:30)·양천구청→
// 신정네거리 180s(HM 3:00)가 앱 값과 정확히 일치해, 이 데이터가 앱과 같은
// **순수 주행(dwell 제외) 규약**임을 교차검증했다. 서교공 시간표 API(OA-101)는
// 현재 전 역 INFO-200 이라 편성 단위 실측은 불가했다(아래 시간표 공백 참조).
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seoul_subway/core/utils/line_direction.dart';
import 'package:seoul_subway/data/local/local_data_source.dart';
import 'package:seoul_subway/data/local/timetable_data_source.dart';
import 'package:seoul_subway/data/repositories/station_repository_impl.dart';
import 'package:seoul_subway/domain/entities/connection.dart';
import 'package:seoul_subway/domain/entities/station.dart';
import 'package:seoul_subway/domain/usecases/search_route.dart';

/// 까치산 2호선 (신설).
const _kkachisan2 = '251';

/// 까치산 5호선 (기존).
const _kkachisan5 = '509';

/// 신정네거리.
const _sinjeong = '249';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Map<String, Station> byId;
  late List<Connection> line2Conns;

  setUpAll(() async {
    final stations = await LocalDataSource().loadStations();
    byId = {for (final s in stations) '${s.id}_${s.lineId}': s};

    final raw = await rootBundle.loadString('assets/json/connections.json');
    line2Conns = (jsonDecode(raw) as List)
        .map((e) => Connection.fromJson(e as Map<String, dynamic>))
        .where((c) => c.lineId == '2' && !c.isTransfer)
        .toList();
  });

  Connection? edgeBetween(String a, String b) {
    for (final c in line2Conns) {
      if (c.fromStationId == a && c.toStationId == b) return c;
      if (c.fromStationId == b && c.toStationId == a) return c;
    }
    return null;
  }

  group('까치산 2호선 노드', () {
    test('레코드가 존재하고 5호선과 좌표를 공유한다', () {
      final two = byId['${_kkachisan2}_2'];
      final five = byId['${_kkachisan5}_5'];
      expect(two, isNotNull, reason: '2호선 까치산 노드가 사라졌다');
      expect(five, isNotNull);
      expect(two!.name, '까치산');
      expect(two.isTransfer, isTrue);
      expect(two.transferLines, containsAll(<String>['2', '5']));
      // 환승 쌍은 좌표를 공유한다(금정 1715/435, 가산 1425/738 선례).
      expect(two.svgX, five!.svgX);
      expect(two.svgY, five.svgY);
      expect(two.latitude, five.latitude);
    });

    test('신정지선이 까치산까지 이어진다 (신정네거리 단절 해소)', () {
      final edge = edgeBetween(_sinjeong, _kkachisan2);
      expect(edge, isNotNull, reason: '신정네거리 ↔ 까치산 연결이 없다');
      expect(
        edge!.travelTimeSeconds,
        150,
        reason: '공식 inter_station.json HM 2:30 실측 고정값과 다르다. '
            '서교공 OA-101 편성 실측으로 대체했다면 근거를 이 파일 헤더에 갱신할 것.',
      );
    });

    test('성수지선 종점과 붙지 않는다 (생성기 자동 인접의 함정)', () {
      // 생성기 나열 순서상 까치산(251) 다음이 신설동(250, 성수지선 종점)이라
      // 자동 인접이 만들어질 수 있다. generate_station_data.dart 의 제거
      // 블록이 251→250 으로 갱신됐는지를 산출물 쪽에서 고정한다.
      expect(edgeBetween(_kkachisan2, '250'), isNull,
          reason: '까치산(신정지선)과 신설동(성수지선)은 인접이 아니다');
    });

    test('2↔5 환승 시간이 등록돼 있다 (역명 일치로 edge 생성)', () async {
      final raw =
          await rootBundle.loadString('assets/json/transfer_times.json');
      final times = (jsonDecode(raw) as Map).cast<String, dynamic>();
      expect(times['까치산_2_5'], isNotNull,
          reason: '두 레코드가 다 있어야 환승 edge 가 생성된다');
    });

    test('방향 판별 — 신정지선 공식이 까치산까지 연장된다', () {
      // 신정지선은 본선 공식(작은 step)을 그대로 탄다. 249→251 도 같은 극성.
      final toKkachisan = isDownBetween(_sinjeong, _kkachisan2, '2');
      final fromKkachisan = isDownBetween(_kkachisan2, _sinjeong, '2');
      expect(toKkachisan, isNot(fromKkachisan),
          reason: '왕복 방향이 같게 판정되면 안 된다');
      // 지선 안에서 같은 진행 방향은 같은 판정이어야 한다.
      expect(toKkachisan, isDownBetween('248', _sinjeong, '2'),
          reason: '양천구청→신정네거리와 신정네거리→까치산은 같은 진행 방향이다');
    });

    test('신정네거리 → 까치산이 직결 1구간이 된다 (33분 우회 해소)', () async {
      final repo = StationRepositoryImpl(localDataSource: LocalDataSource());
      final sr = SearchRoute(
        stationRepository: repo,
        timetableDataSource: TimetableDataSource(),
      );
      final route = await sr.execute(_sinjeong, _kkachisan2);
      expect(route, isNotNull);
      expect(route!.transferCount, 0, reason: '환승 없이 1구간이어야 한다');
      expect(route.totalTimeSeconds, lessThanOrEqualTo(300),
          reason: '종전 33.0분 우회가 남아 있다');
    });

    test('5호선 화곡 → 2호선 양천구청이 까치산 환승을 쓴다', () async {
      final repo = StationRepositoryImpl(localDataSource: LocalDataSource());
      final sr = SearchRoute(
        stationRepository: repo,
        timetableDataSource: TimetableDataSource(),
      );
      final route = await sr.execute('508', '248'); // 화곡 → 양천구청
      expect(route, isNotNull);
      // 종전에는 까치산 환승이 불가능해 영등포구청 등 원거리 환승으로 우회했다.
      expect(route!.totalTimeSeconds, lessThanOrEqualTo(15 * 60),
          reason: '까치산 환승이 안 잡히면 15분을 훌쩍 넘는 우회가 된다');
      final names = [
        for (final seg in route.segments) ...seg.stations.map((s) => s.name),
      ];
      expect(names, contains('까치산'));
    });

    test('2호선 역별 시간표는 아직 공백이다 (배차간격 폴백, 알려진 한계)', () async {
      // 서교공 SearchSTNTimeTableByIDService(OA-101)가 현재 전 역 INFO-200 을
      // 반환해(정상 수집됐던 양천구청 0248 로 대조 확인) 까치산 시간표를 받을 수
      // 없다. 금정(17e97af)과 같은 공백 패턴 — 출발시각 선택이 비활성이고
      // 배차간격 폴백으로 계산된다(크래시 없음).
      //
      // API 가 복구되면 `dart run tool/build_metro_timetable.dart --lines=2` 로
      // 채우고 이 테스트를 반대 방향 가드("공백 해소")로 전환할 것 —
      // 금정의 전례: geumjeong_transfer_test.dart 참조.
      final schedules = await TimetableDataSource().loadSchedules();
      final t = schedules['2']!.weekday.stationDepartures;
      expect(t, isNotNull);
      expect(t!.containsKey(_sinjeong), isTrue,
          reason: '신정네거리는 시간표가 있다 (2026-07 수집분)');
      expect(t.containsKey(_kkachisan2), isFalse,
          reason: '까치산 시간표가 채워졌다면 이 테스트를 반대 가드로 교체하라');
    });
  });
}
