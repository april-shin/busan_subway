import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seoul_subway/core/utils/route_branch.dart';
import 'package:seoul_subway/domain/entities/connection.dart';
import 'package:seoul_subway/domain/entities/station.dart';

/// 지선 분기 필터 검증.
///
/// 회귀 가드: 노선 ID와 방향(하행/외선)만으로 필터링하면 5호선 하행 "마천행"이
/// `천호 → 굽은다리` 경로에 섞여 지도에 표시된다. 마천행은 강동에서 갈라져
/// 굽은다리를 지나지 않으므로 제외돼야 한다.
void main() {
  group('trainPathCoversRoute', () {
    test('열차 경로가 탑승 구간을 그대로 포함하면 통과', () {
      expect(
        trainPathCoversRoute(
          routeStationIds: const ['538', '539', '540', '541'],
          trainPathStationIds: const ['538', '539', '540', '541', '542'],
        ),
        isTrue,
      );
    });

    test('다른 지선으로 갈라지면 제외', () {
      // 천호(538) → 강동(539) 이후 둔촌동(550)으로 분기하는 마천행.
      expect(
        trainPathCoversRoute(
          routeStationIds: const ['538', '539', '540', '541'],
          trainPathStationIds: const ['538', '539', '550', '551', '556'],
        ),
        isFalse,
      );
    });

    test('같은 지선에서 중간 종착하는 열차는 통과', () {
      // 천호 → 하남검단산 경로의 상일동행: 경로 앞부분은 태워준다.
      expect(
        trainPathCoversRoute(
          routeStationIds: const ['538', '539', '540', '541', '542'],
          trainPathStationIds: const ['538', '539', '540'],
        ),
        isTrue,
      );
    });

    test('급행처럼 정차역만 있는 탑승 구간도 통과 (부분수열 규칙)', () {
      expect(
        trainPathCoversRoute(
          routeStationIds: const ['901', '904', '907'],
          trainPathStationIds: const ['901', '902', '903', '904', '905', '906', '907'],
        ),
        isTrue,
      );
    });

    test('한쪽이 비어 있으면 판정 불가 → 통과', () {
      expect(
        trainPathCoversRoute(
          routeStationIds: const [],
          trainPathStationIds: const ['538', '539'],
        ),
        isTrue,
      );
      expect(
        trainPathCoversRoute(
          routeStationIds: const ['538', '539'],
          trainPathStationIds: const [],
        ),
        isTrue,
      );
    });
  });

  group('trainStaysOnRouteBranch (실제 노선 데이터)', () {
    late List<Station> stations;
    late List<Connection> connections;

    setUpAll(() async {
      TestWidgetsFlutterBinding.ensureInitialized();

      final stationsJson =
          await rootBundle.loadString('assets/json/stations.json');
      stations = (jsonDecode(stationsJson) as List)
          .map((e) => Station.fromJson(e as Map<String, dynamic>))
          .toList();

      final connectionsJson =
          await rootBundle.loadString('assets/json/connections.json');
      connections = (jsonDecode(connectionsJson) as List)
          .map((e) => Connection.fromJson(e as Map<String, dynamic>))
          .toList();
    });

    /// 노선 [lineId] 에서 이름이 [name] 인 역 ID 목록.
    List<String> idsFor(String name, String lineId) => [
          for (final s in stations)
            if (s.name == name && s.lineId == lineId) s.id,
        ];

    /// 노선 [lineId] 에서 이름 목록을 역 ID 목록으로 변환.
    List<String> routeIds(List<String> names, String lineId) =>
        [for (final n in names) idsFor(n, lineId).single];

    bool stays(String destination, List<String> routeNames) {
      return trainStaysOnRouteBranch(
        routeStationIds: routeIds(routeNames, '5'),
        destinationStationIds: idsFor(destination, '5'),
        lineId: '5',
        connections: connections,
        isDown: true,
      );
    }

    const cheonho = ['천호', '강동', '길동', '굽은다리'];

    test('천호 → 굽은다리 경로에서 마천행은 제외된다', () {
      expect(stays('마천', cheonho), isFalse);
    });

    test('천호 → 굽은다리 경로에서 하남검단산행·상일동행은 표시된다', () {
      expect(stays('하남검단산', cheonho), isTrue);
      expect(stays('상일동', cheonho), isTrue);
    });

    test('천호 → 둔촌동 경로에서는 마천행만 표시된다', () {
      const dunchon = ['천호', '강동', '둔촌동'];
      expect(stays('마천', dunchon), isTrue);
      expect(stays('하남검단산', dunchon), isFalse);
    });

    test('분기 이후 구간(길동 → 명일)은 지선이 하나뿐이라 모두 통과', () {
      expect(stays('하남검단산', const ['길동', '굽은다리', '명일']), isTrue);
    });

    test('행선지를 해석할 수 없으면 통과 (fail-open)', () {
      expect(
        trainStaysOnRouteBranch(
          routeStationIds: routeIds(cheonho, '5'),
          destinationStationIds: const [],
          lineId: '5',
          connections: connections,
          isDown: true,
        ),
        isTrue,
      );
    });
  });
}
