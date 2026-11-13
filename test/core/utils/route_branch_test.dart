import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:busan_subway/core/utils/route_branch.dart';
import 'package:busan_subway/domain/entities/connection.dart';
import 'package:busan_subway/domain/entities/station.dart';

/// 구간 완주 판정 검증 (지선 분기 / 중간 종착 / 완주).
///
/// 회귀 가드 1(서울 5호선 마천 분기 사례 — 부산 데이터엔 분기가 없어 순수 판정 테스트로만 남김): 노선 ID와 방향(하행/외선)만으로 필터링하면 5호선 하행 "마천행"이
/// `천호 → 굽은다리` 경로에 섞여 지도에 표시된다. 마천행은 강동에서 갈라져
/// 굽은다리를 지나지 않으므로 [RouteCoverage.diverged] 여야 한다.
///
/// 회귀 가드 2: 갈라지지 않더라도 하차역 **앞에서** 운행을 끝내는 중간 종착
/// 열차는 그 열차만으로 하차역에 닿지 못한다. `내방 → 장암` 경로의 7호선 상행
/// "도봉산행"이 대표 사례로, [RouteCoverage.earlyTerminus] 여야 한다.
///
/// 두 값의 구분이 중요한 이유 — 경로 결과의 출발 시각은 `full` 만 후보로 쓰고,
/// 지도는 둘 다 유령(흐림)으로 남긴다. 즉 `full` 이냐 아니냐가 화면 동작을
/// 가르므로, 분기·중간종착을 `full` 로 잘못 판정하지 않는 것이 이 테스트의 핵심이다.
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

    // 1호선 하행(다대포해수욕장 → 노포 방면, ID 증가).
    RouteCoverage coverage(String destination, List<String> routeNames) =>
        coverageOn(destination, routeNames, lineId: '1', isDown: true);

    const seomyeonToYeonsan = ['서면', '부전', '양정', '시청', '연산'];

    test('부산은 지선이 없어 diverged 가 나오지 않는다', () {
      for (final dest in ['노포', '범어사', '부산대', '연산', '서면']) {
        expect(coverage(dest, seomyeonToYeonsan),
            isNot(RouteCoverage.diverged),
            reason: dest);
      }
    });

    test('서면 → 연산 경로에서 노포행·연산행은 완주', () {
      expect(coverage('노포', seomyeonToYeonsan), RouteCoverage.full);
      expect(coverage('연산', seomyeonToYeonsan), RouteCoverage.full);
    });

    test('서면 → 연산 경로에서 하차역 앞에서 끝나는 부전행·시청행은 중간 종착', () {
      expect(coverage('부전', seomyeonToYeonsan), RouteCoverage.earlyTerminus);
      expect(coverage('시청', seomyeonToYeonsan), RouteCoverage.earlyTerminus);
    });

    test('하차역이 중간 종착역까지면 그 열차도 완주', () {
      expect(coverage('시청', const ['서면', '부전', '양정', '시청']),
          RouteCoverage.full);
    });

    test('4호선(미남 → 안평, 하행) 도 같은 규칙', () {
      RouteCoverage line4(String destination, List<String> names) =>
          coverageOn(destination, names, lineId: '4', isDown: true);
      const route = ['미남', '동래', '수안', '낙민'];
      expect(line4('안평', route), RouteCoverage.full);
      expect(line4('수안', route), RouteCoverage.earlyTerminus);
    });

    test('상행(ID 감소)도 판정한다 — 1호선 노포 → 서면', () {
      RouteCoverage up(String destination) => coverageOn(
            destination,
            const ['동래', '교대', '연산', '시청', '양정', '부전', '서면'],
            lineId: '1',
            isDown: false,
          );
      expect(up('다대포해수욕장'), RouteCoverage.full);
      expect(up('연산'), RouteCoverage.earlyTerminus);
    });

    test('행선지를 해석할 수 없으면 완주로 간주 (fail-open)', () {
      expect(
        classifyDestinationCoverage(
          routeStationIds: routeIds(seomyeonToYeonsan, '1'),
          destinationStationIds: const [],
          lineId: '1',
          connections: connections,
          isDown: true,
        ),
        RouteCoverage.full,
      );
    });

    test('makeDestinationBranchFilter 는 완주 열차만 통과시킨다', () {
      final filter = makeDestinationBranchFilter(
        routeStationIds: routeIds(seomyeonToYeonsan, '1'),
        lineId: '1',
        isDown: true,
        stations: stations,
        connections: connections,
      );
      expect(filter('노포'), isTrue);
      expect(filter('연산'), isTrue);
      expect(filter('부전'), isFalse, reason: '중간 종착');
    });

    test('2호선도 예외 없이 판정한다 (부산 2호선은 순환이 아닌 선형)', () {
      const route = ['서면', '부암', '가야', '동의대'];
      expect(coverageOn('가야', route, lineId: '2', isDown: true),
          RouteCoverage.earlyTerminus);
      final filter = makeDestinationBranchFilter(
        routeStationIds: routeIds(route, '2'),
        lineId: '2',
        isDown: true,
        stations: stations,
        connections: connections,
      );
      expect(filter('양산'), isTrue);
      expect(filter('가야'), isFalse);
    });
  });
}
