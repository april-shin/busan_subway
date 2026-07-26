import 'package:flutter_test/flutter_test.dart';
import 'package:seoul_subway/core/utils/upstream_stations.dart';
import 'package:seoul_subway/domain/entities/connection.dart';

/// 두 역을 잇는 비환승 연결 하나를 만든다(양끝 id·노선).
Connection _c(String from, String to, String line) => Connection(
      fromStationId: from,
      toStationId: to,
      lineId: line,
      travelTimeSeconds: 120,
    );

void main() {
  group('departureUpstreamStationIds', () {
    // 선형 1호선: 101-102-103-104-105 (id 증가 = 하행)
    final line1 = [
      _c('101', '102', '1'),
      _c('102', '103', '1'),
      _c('103', '104', '1'),
      _c('104', '105', '1'),
    ];

    test('선형 노선: 경로 하행이면 상류는 상행 쪽 역들(하류 제외)', () {
      // 출발 103, 경로 103→104→105(하행). 상류 = 102, 101.
      final upstream = departureUpstreamStationIds(
        connections: line1,
        lineId: '1',
        departureId: '103',
        routeNextId: '104',
        routeStationIds: {'103', '104', '105'},
      );
      expect(upstream, {'102', '101'});
    });

    test('선형 노선: 경로 상행이면 상류는 하행 쪽 역들', () {
      // 출발 103, 경로 103→102→101(상행). 상류 = 104, 105.
      final upstream = departureUpstreamStationIds(
        connections: line1,
        lineId: '1',
        departureId: '103',
        routeNextId: '102',
        routeStationIds: {'103', '102', '101'},
      );
      expect(upstream, {'104', '105'});
    });

    test('출발역이 종착역이면 상류 없음', () {
      // 출발 101(하행 종착 반대 끝), 경로 101→102. 상류 = 없음.
      final upstream = departureUpstreamStationIds(
        connections: line1,
        lineId: '1',
        departureId: '101',
        routeNextId: '102',
        routeStationIds: {'101', '102'},
      );
      expect(upstream, isEmpty);
    });

    test('maxHops 로 상류 확장을 정거장 수로 제한한다', () {
      // 선형 1호선 101..112. 출발 108, 경로 하행(108→109..). 상류(상행/id 감소)를
      // maxHops=3 으로 제한 → 107,106,105 만. 104 이하(먼 상류)는 흐리게.
      final longLine = [
        for (var i = 101; i < 112; i++) _c('$i', '${i + 1}', '1'),
      ];
      final upstream = departureUpstreamStationIds(
        connections: longLine,
        lineId: '1',
        departureId: '108',
        routeNextId: '109',
        routeStationIds: {'108', '109', '110', '111', '112'},
        maxHops: 3,
      );
      expect(upstream, {'107', '106', '105'});
    });

    test('출발 노선 외 연결은 무시한다', () {
      final mixed = [
        ...line1,
        _c('900', '103', '9'), // 다른 노선
        _c('103', '901', '9'),
      ];
      final upstream = departureUpstreamStationIds(
        connections: mixed,
        lineId: '1',
        departureId: '103',
        routeNextId: '104',
        routeStationIds: {'103', '104', '105'},
      );
      expect(upstream, {'102', '101'});
    });

    // 2호선 순환: 201-202-203-204-205-206-(201) 루프
    final line2Loop = [
      _c('201', '202', '2'),
      _c('202', '203', '2'),
      _c('203', '204', '2'),
      _c('204', '205', '2'),
      _c('205', '206', '2'),
      _c('206', '201', '2'),
    ];

    test('순환 토폴로지: 무한 루프 없이 종료하고 경로역을 제외한다', () {
      // 출발 203, 경로 203→204→205(내선/상행). 상류는 외선/하행(id 감소) 쪽.
      // 순환 연결(206↔201)이 있어도 visited(경로역+출발역) 선점 덕분에
      // 경로 구간으로 되돌아 새지 않고 종료한다.
      final upstream = departureUpstreamStationIds(
        connections: line2Loop,
        lineId: '2',
        departureId: '203',
        routeNextId: '204',
        routeStationIds: {'203', '204', '205'},
      );
      // 경로역(203,204,205)은 결과에 포함되지 않는다(하류 유출·재유입 차단).
      expect(upstream.contains('203'), isFalse);
      expect(upstream.contains('204'), isFalse);
      expect(upstream.contains('205'), isFalse);
      // 상류 방향 역들만 수집.
      expect(upstream, {'202', '201'});
    });
  });
}
