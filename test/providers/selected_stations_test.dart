import 'package:flutter_test/flutter_test.dart';
import 'package:seoul_subway/domain/entities/station.dart';
import 'package:seoul_subway/features/subway_map/presentation/providers/subway_map_providers.dart';

void main() {
  late SelectedStationsNotifier notifier;

  const gangnam = Station(
    id: '216',
    name: '강남',
    lineId: '2',
    latitude: 37.49,
    longitude: 127.02,
  );

  const seoul = Station(
    id: '150',
    name: '서울역',
    lineId: '1',
    latitude: 37.55,
    longitude: 126.97,
  );

  setUp(() {
    notifier = SelectedStationsNotifier();
  });

  group('SelectedStationsNotifier', () {
    test('initial state has no selections', () {
      expect(notifier.state.departure, isNull);
      expect(notifier.state.arrival, isNull);
      expect(notifier.state.isComplete, false);
    });

    test('setDeparture updates departure only', () {
      notifier.setDeparture(gangnam);

      expect(notifier.state.departure?.name, '강남');
      expect(notifier.state.arrival, isNull);
      expect(notifier.state.isComplete, false);
    });

    test('setArrival updates arrival only', () {
      notifier.setArrival(seoul);

      expect(notifier.state.departure, isNull);
      expect(notifier.state.arrival?.name, '서울역');
      expect(notifier.state.isComplete, false);
    });

    test('isComplete is true when both are set', () {
      notifier.setDeparture(gangnam);
      notifier.setArrival(seoul);

      expect(notifier.state.isComplete, true);
    });

    test('swap exchanges departure and arrival', () {
      notifier.setDeparture(gangnam);
      notifier.setArrival(seoul);
      notifier.swap();

      expect(notifier.state.departure?.name, '서울역');
      expect(notifier.state.arrival?.name, '강남');
    });

    test('swap with partial selection', () {
      notifier.setDeparture(gangnam);
      notifier.swap();

      expect(notifier.state.departure, isNull);
      expect(notifier.state.arrival?.name, '강남');
    });

    test('clear resets both selections', () {
      notifier.setDeparture(gangnam);
      notifier.setArrival(seoul);
      notifier.clear();

      expect(notifier.state.departure, isNull);
      expect(notifier.state.arrival, isNull);
      expect(notifier.state.isComplete, false);
    });

    test('setDeparture preserves arrival', () {
      notifier.setArrival(seoul);
      notifier.setDeparture(gangnam);

      expect(notifier.state.departure?.name, '강남');
      expect(notifier.state.arrival?.name, '서울역');
    });

    test('setDeparture to null clears departure', () {
      notifier.setDeparture(gangnam);
      notifier.setDeparture(null);

      expect(notifier.state.departure, isNull);
    });
  });

  group('SelectedStationsNotifier — 경유역', () {
    const yeoksam = Station(
      id: '217',
      name: '역삼',
      lineId: '2',
      latitude: 37.50,
      longitude: 127.03,
    );
    const samseong = Station(
      id: '219',
      name: '삼성',
      lineId: '2',
      latitude: 37.51,
      longitude: 127.06,
    );
    const sadang = Station(
      id: '226',
      name: '사당',
      lineId: '2',
      latitude: 37.47,
      longitude: 126.98,
    );

    test('초기 상태는 경유역 없음 + 추가 가능', () {
      expect(notifier.state.waypoints, isEmpty);
      expect(notifier.state.canAddWaypoint, true);
    });

    test('addWaypoint 는 순서대로 추가하고 true 를 반환한다', () {
      expect(notifier.addWaypoint(yeoksam), true);
      expect(notifier.addWaypoint(samseong), true);

      expect(
        notifier.state.waypoints.map((s) => s.name).toList(),
        ['역삼', '삼성'],
      );
    });

    test('상한($maxWaypoints)에 도달하면 addWaypoint 는 false + 상태 불변', () {
      for (var i = 0; i < maxWaypoints; i++) {
        expect(notifier.addWaypoint(yeoksam), true);
      }
      expect(notifier.state.canAddWaypoint, false);

      expect(notifier.addWaypoint(samseong), false);
      expect(notifier.state.waypoints.length, maxWaypoints);
      expect(notifier.state.waypoints.last.name, '역삼');
    });

    test('insertWaypoint 는 그 자리에 끼워 넣고 이후 경유역을 밀어낸다', () {
      notifier.addWaypoint(yeoksam);
      notifier.addWaypoint(samseong);

      expect(notifier.insertWaypoint(1, sadang), true);
      expect(
        notifier.state.waypoints.map((s) => s.name).toList(),
        ['역삼', '사당', '삼성'],
      );
    });

    test('insertWaypoint(0) 은 맨 앞(출발역 직후)에 넣는다', () {
      notifier.addWaypoint(yeoksam);

      expect(notifier.insertWaypoint(0, sadang), true);
      expect(notifier.state.waypoints.map((s) => s.name).toList(),
          ['사당', '역삼']);
    });

    test('insertWaypoint(길이) 는 맨 뒤(도착역 직전)에 넣는다', () {
      notifier.addWaypoint(yeoksam);

      expect(notifier.insertWaypoint(1, sadang), true);
      expect(notifier.state.waypoints.map((s) => s.name).toList(),
          ['역삼', '사당']);
    });

    test('insertWaypoint 의 범위 밖 index 는 false + 상태 불변', () {
      notifier.addWaypoint(yeoksam);

      expect(notifier.insertWaypoint(-1, sadang), false);
      expect(notifier.insertWaypoint(2, sadang), false);
      expect(notifier.state.waypoints.map((s) => s.name).toList(), ['역삼']);
    });

    test('상한 도달 시 insertWaypoint 는 false + 상태 불변', () {
      for (var i = 0; i < maxWaypoints; i++) {
        notifier.addWaypoint(yeoksam);
      }

      expect(notifier.insertWaypoint(0, sadang), false);
      expect(notifier.state.waypoints.length, maxWaypoints);
      expect(notifier.state.waypoints.first.name, '역삼');
    });

    test('setWaypoint 로 범위 안 슬롯을 교체한다', () {
      notifier.addWaypoint(yeoksam);
      notifier.addWaypoint(samseong);
      notifier.setWaypoint(0, sadang);

      expect(
        notifier.state.waypoints.map((s) => s.name).toList(),
        ['사당', '삼성'],
      );
    });

    test('setWaypoint(index == 길이) 는 맨 뒤에 추가한다', () {
      notifier.addWaypoint(yeoksam);
      notifier.setWaypoint(1, samseong);

      expect(
        notifier.state.waypoints.map((s) => s.name).toList(),
        ['역삼', '삼성'],
      );
    });

    test('setWaypoint 의 범위 밖 index 는 무시된다', () {
      notifier.addWaypoint(yeoksam);
      notifier.setWaypoint(-1, samseong);
      notifier.setWaypoint(5, samseong);

      expect(notifier.state.waypoints.map((s) => s.name).toList(), ['역삼']);
    });

    test('removeWaypointAt 는 해당 슬롯만 제거한다', () {
      notifier.addWaypoint(yeoksam);
      notifier.addWaypoint(samseong);
      notifier.removeWaypointAt(0);

      expect(notifier.state.waypoints.map((s) => s.name).toList(), ['삼성']);
    });

    test('removeWaypointAt 의 범위 밖 index 는 무시된다', () {
      notifier.addWaypoint(yeoksam);
      notifier.removeWaypointAt(3);
      notifier.removeWaypointAt(-1);

      expect(notifier.state.waypoints.length, 1);
    });

    test('setDeparture/setArrival 은 경유역을 보존한다', () {
      notifier.addWaypoint(yeoksam);
      notifier.setDeparture(gangnam);
      notifier.setArrival(seoul);

      expect(notifier.state.waypoints.map((s) => s.name).toList(), ['역삼']);
      expect(notifier.state.isComplete, true);
    });

    test('swap 은 경유 순서를 뒤집는다', () {
      notifier.setDeparture(gangnam);
      notifier.setArrival(seoul);
      notifier.addWaypoint(yeoksam);
      notifier.addWaypoint(samseong);
      notifier.swap();

      expect(notifier.state.departure?.name, '서울역');
      expect(notifier.state.arrival?.name, '강남');
      expect(
        notifier.state.waypoints.map((s) => s.name).toList(),
        ['삼성', '역삼'],
        reason: '여정을 거꾸로 타면 경유 순서도 반대가 된다',
      );
    });

    test('setBoth 은 경유역을 초기화한다 (이력 탭은 출발/도착만 복원)', () {
      notifier.addWaypoint(yeoksam);
      notifier.setBoth(gangnam, seoul);

      expect(notifier.state.waypoints, isEmpty);
      expect(notifier.state.isComplete, true);
    });

    test('clear 는 경유역까지 모두 비운다', () {
      notifier.setDeparture(gangnam);
      notifier.setArrival(seoul);
      notifier.addWaypoint(yeoksam);
      notifier.clear();

      expect(notifier.state.departure, isNull);
      expect(notifier.state.arrival, isNull);
      expect(notifier.state.waypoints, isEmpty);
    });
  });
}
