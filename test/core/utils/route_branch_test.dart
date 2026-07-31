import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seoul_subway/core/utils/route_branch.dart';
import 'package:seoul_subway/domain/entities/connection.dart';
import 'package:seoul_subway/domain/entities/station.dart';

/// 구간 완주 판정 검증 (지선 분기 / 중간 종착 / 완주).
///
/// 회귀 가드 1: 노선 ID와 방향(하행/외선)만으로 필터링하면 5호선 하행 "마천행"이
/// `천호 → 굽은다리` 경로에 섞여 지도에 표시된다. 마천행은 강동에서 갈라져
/// 굽은다리를 지나지 않으므로 [RouteCoverage.diverged] 여야 한다.
///
/// 회귀 가드 2: 갈라지지 않더라도 하차역 **앞에서** 운행을 끝내는 중간 종착
/// 열차는 그 열차만으로 하차역에 닿지 못한다. `내방 → 장암` 경로의 7호선 상행
/// "도봉산행"이 대표 사례로, [RouteCoverage.earlyTerminus] 여야 한다.
///
/// 두 값의 구분이 중요한 이유 — 경로 결과의 출발 시각은 `full` 만 쓰지만,
/// 지도는 `earlyTerminus` 를 유령(흐림)으로 남기고 `diverged` 만 제거한다.
void main() {
  group('classifyTrainPathCoverage', () {
    test('열차 경로가 탑승 구간을 그대로 포함하면 완주', () {
      expect(
        classifyTrainPathCoverage(
          routeStationIds: const ['538', '539', '540', '541'],
          trainPathStationIds: const ['538', '539', '540', '541', '542'],
        ),
        RouteCoverage.full,
      );
    });

    test('다른 지선으로 갈라지면 diverged', () {
      // 천호(538) → 강동(539) 이후 둔촌동(550)으로 분기하는 마천행.
      expect(
        classifyTrainPathCoverage(
          routeStationIds: const ['538', '539', '540', '541'],
          trainPathStationIds: const ['538', '539', '550', '551', '556'],
        ),
        RouteCoverage.diverged,
      );
    });

    test('같은 선로라도 하차역 앞에서 끝나면 earlyTerminus', () {
      // 천호 → 하남검단산 경로의 상일동행: 앞부분만 태워주고 끝난다.
      expect(
        classifyTrainPathCoverage(
          routeStationIds: const ['538', '539', '540', '541', '542'],
          trainPathStationIds: const ['538', '539', '540'],
        ),
        RouteCoverage.earlyTerminus,
      );
    });

    test('하차역이 열차 종착역이면 완주', () {
      expect(
        classifyTrainPathCoverage(
          routeStationIds: const ['538', '539', '540'],
          trainPathStationIds: const ['538', '539', '540'],
        ),
        RouteCoverage.full,
      );
    });

    test('급행처럼 정차역만 있는 탑승 구간도 완주 (부분수열 규칙)', () {
      expect(
        classifyTrainPathCoverage(
          routeStationIds: const ['901', '904', '907'],
          trainPathStationIds: const [
            '901',
            '902',
            '903',
            '904',
            '905',
            '906',
            '907'
          ],
        ),
        RouteCoverage.full,
      );
    });

    test('한쪽이 비어 있으면 판정 불가 → 완주로 간주 (fail-open)', () {
      expect(
        classifyTrainPathCoverage(
          routeStationIds: const [],
          trainPathStationIds: const ['538', '539'],
        ),
        RouteCoverage.full,
      );
      expect(
        classifyTrainPathCoverage(
          routeStationIds: const ['538', '539'],
          trainPathStationIds: const [],
        ),
        RouteCoverage.full,
      );
    });
  });

  group('trainPathCoversRoute (완주 여부 축약)', () {
    test('중간 종착·지선 분기 둘 다 false', () {
      expect(
        trainPathCoversRoute(
          routeStationIds: const ['538', '539', '540', '541', '542'],
          trainPathStationIds: const ['538', '539', '540'],
        ),
        isFalse,
      );
      expect(
        trainPathCoversRoute(
          routeStationIds: const ['538', '539', '540', '541'],
          trainPathStationIds: const ['538', '539', '550', '551'],
        ),
        isFalse,
      );
      expect(
        trainPathCoversRoute(
          routeStationIds: const ['538', '539', '540'],
          trainPathStationIds: const ['538', '539', '540', '541'],
        ),
        isTrue,
      );
    });
  });

  group('classifyDestinationCoverage (실제 노선 데이터)', () {
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

    RouteCoverage coverageOn(
      String destination,
      List<String> routeNames, {
      required String lineId,
      required bool isDown,
    }) {
      return classifyDestinationCoverage(
        routeStationIds: routeIds(routeNames, lineId),
        destinationStationIds: idsFor(destination, lineId),
        lineId: lineId,
        connections: connections,
        isDown: isDown,
      );
    }

    // 5호선 하행(천호 → 마천/하남검단산 방면).
    RouteCoverage coverage(String destination, List<String> routeNames) =>
        coverageOn(destination, routeNames, lineId: '5', isDown: true);

    const cheonho = ['천호', '강동', '길동', '굽은다리'];

    test('천호 → 굽은다리 경로에서 마천행은 분기(diverged)', () {
      expect(coverage('마천', cheonho), RouteCoverage.diverged);
    });

    test('천호 → 굽은다리 경로에서 하남검단산행·상일동행은 완주', () {
      // 둘 다 굽은다리를 지난 뒤 종착하므로 구간을 완주시켜 준다.
      expect(coverage('하남검단산', cheonho), RouteCoverage.full);
      expect(coverage('상일동', cheonho), RouteCoverage.full);
    });

    test('천호 → 하남검단산 경로에서 상일동행은 중간 종착', () {
      const geomdansan = ['천호', '강동', '길동', '굽은다리', '명일', '고덕', '상일동', '강일'];
      expect(coverage('하남검단산', geomdansan), RouteCoverage.full);
      expect(coverage('상일동', geomdansan), RouteCoverage.earlyTerminus);
    });

    test('천호 → 둔촌동 경로에서는 마천행만 완주한다', () {
      const dunchon = ['천호', '강동', '둔촌동'];
      expect(coverage('마천', dunchon), RouteCoverage.full);
      expect(coverage('하남검단산', dunchon), RouteCoverage.diverged);
    });

    test('분기 이후 구간(길동 → 명일)은 지선이 하나뿐이라 모두 완주', () {
      expect(coverage('하남검단산', const ['길동', '굽은다리', '명일']), RouteCoverage.full);
    });

    test('7호선 내방 → 장암 경로에서 도봉산행은 중간 종착', () {
      // 도봉산(702)은 장암(701) 바로 앞 역이라 지선 분기가 아니지만,
      // 도봉산행만 타서는 장암에 닿지 못한다 → 경로 결과에서는 제외, 지도에서는 유령.
      // 중간 역은 생략한다 — 판정이 "부분수열" 규칙이라 결과가 같다.
      const naebangToGangnamgu = ['내방', '고속터미널', '반포', '논현', '학동', '강남구청'];
      RouteCoverage line7(String destination, List<String> names) =>
          coverageOn(destination, names, lineId: '7', isDown: false);

      expect(
        line7('도봉산', const [...naebangToGangnamgu, '도봉산', '장암']),
        RouteCoverage.earlyTerminus,
      );
      expect(
        line7('장암', const [...naebangToGangnamgu, '도봉산', '장암']),
        RouteCoverage.full,
      );
      // 하차역이 도봉산까지면 도봉산행도 완주시켜 준다.
      expect(
        line7('도봉산', const [...naebangToGangnamgu, '도봉산']),
        RouteCoverage.full,
      );
    });

    test('행선지를 해석할 수 없으면 완주로 간주 (fail-open)', () {
      expect(
        classifyDestinationCoverage(
          routeStationIds: routeIds(cheonho, '5'),
          destinationStationIds: const [],
          lineId: '5',
          connections: connections,
          isDown: true,
        ),
        RouteCoverage.full,
      );
    });

    test('makeDestinationBranchFilter 는 완주 열차만 통과시킨다', () {
      final filter = makeDestinationBranchFilter(
        routeStationIds:
            routeIds(const ['천호', '강동', '길동', '굽은다리', '명일'], '5'),
        lineId: '5',
        isDown: true,
        stations: stations,
        connections: connections,
      );
      expect(filter('하남검단산'), isTrue);
      expect(filter('마천'), isFalse, reason: '지선 분기');
      expect(filter('강동'), isFalse, reason: '중간 종착');
    });
  });
}
