// 5호선 마천 지선 분기 회귀 가드.
//
// 5호선은 강동(539)에서 두 지선으로 갈라진다.
//   - 하남 방면: 강동 → 길동(540) → 굽은다리(541) → … → 하남검단산(549)
//   - 마천 방면: 강동 → 둔촌동(550) → … → 마천(556)
//
// 역 목록이 하남검단산 다음에 둔촌동~마천을 잇달아 나열하므로, 생성기의 자동
// 인접 연결은 하남검단산(549)→둔촌동(550) 이라는 존재하지 않는 연결을 만든다.
// 이를 방치하면:
//   - 천호→마천 경로가 하남검단산을 돌아가는 19역 경로로 뽑힌다(실제 8역).
//   - 5호선이 지선 없는 일직선이 되어, 실시간 열차의 지선 판정이 불가능해진다
//     (마천행이 굽은다리를 "지난다"고 판단 → 천호→굽은다리 경로 지도에 마천행 표시).
//
// 수정 지점: assets/json/connections.json + tool/generate_station_data.dart 의
// `lineId == '5'` 지선 처리 블록.
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seoul_subway/data/local/local_data_source.dart';
import 'package:seoul_subway/data/local/timetable_data_source.dart';
import 'package:seoul_subway/data/repositories/station_repository_impl.dart';
import 'package:seoul_subway/domain/entities/connection.dart';
import 'package:seoul_subway/domain/usecases/search_route.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<Connection> connections;

  setUpAll(() async {
    final connectionsJson =
        await rootBundle.loadString('assets/json/connections.json');
    connections = (jsonDecode(connectionsJson) as List)
        .map((e) => Connection.fromJson(e as Map<String, dynamic>))
        .toList();
  });

  bool hasEdge(String a, String b) => connections.any((c) =>
      c.lineId == '5' &&
      !c.isTransfer &&
      ((c.fromStationId == a && c.toStationId == b) ||
          (c.fromStationId == b && c.toStationId == a)));

  test('마천 지선은 강동(539)에서 분기한다', () {
    expect(hasEdge('539', '550'), isTrue, reason: '강동↔둔촌동 연결이 있어야 한다');
    expect(hasEdge('549', '550'), isFalse,
        reason: '하남검단산↔둔촌동은 존재하지 않는 연결이다');
  });

  test('강동은 3방향(천호·길동·둔촌동) 분기역이다', () {
    final neighbors = <String>{};
    for (final c in connections) {
      if (c.lineId != '5' || c.isTransfer) continue;
      if (c.fromStationId == '539') neighbors.add(c.toStationId);
      if (c.toStationId == '539') neighbors.add(c.fromStationId);
    }
    expect(neighbors, {'538', '540', '550'});
  });

  test('천호 → 마천 경로가 하남 방면을 돌아가지 않는다', () async {
    final repo = StationRepositoryImpl(localDataSource: LocalDataSource());
    final search = SearchRoute(
      stationRepository: repo,
      timetableDataSource: TimetableDataSource(),
    );

    final result = await search.execute('538', '556');
    expect(result, isNotNull);

    final names = [
      for (final seg in result!.segments)
        for (final s in seg.stations) s.name,
    ];
    expect(names, containsAllInOrder(['천호', '강동', '둔촌동', '마천']));
    expect(names, isNot(contains('굽은다리')));
    expect(names, isNot(contains('하남검단산')));
  });
}
