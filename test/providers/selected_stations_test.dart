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

    /// 경유지 칸을 이름 목록으로. 빈 칸은 null 로 남는다.
    List<String?> names() =>
        notifier.state.waypoints.map((s) => s?.name).toList();

    test('초기 상태는 경유지 없음 + 추가 가능', () {
      expect(notifier.state.waypoints, isEmpty);
      expect(notifier.state.canAddWaypoint, true);
      expect(notifier.state.waypointStationIds, isEmpty);
    });

    test('addWaypoint 는 순서대로 추가하고 true 를 반환한다', () {
      expect(notifier.addWaypoint(yeoksam), true);
      expect(notifier.addWaypoint(samseong), true);

      expect(names(), ['역삼', '삼성']);
    });

    test('상한($maxWaypoints)에 도달하면 addWaypoint 는 false + 상태 불변', () {
      for (var i = 0; i < maxWaypoints; i++) {
        expect(notifier.addWaypoint(yeoksam), true);
      }
      expect(notifier.state.canAddWaypoint, false);

      expect(notifier.addWaypoint(samseong), false);
      expect(notifier.state.waypoints.length, maxWaypoints);
      expect(names().last, '역삼');
    });

    group('빈 칸(+ 버튼)', () {
      test('insertWaypointSlot 은 빈 칸을 그 자리에 끼워 넣는다', () {
        notifier.addWaypoint(yeoksam);
        notifier.addWaypoint(samseong);

        expect(notifier.insertWaypointSlot(1), true);
        expect(names(), ['역삼', null, '삼성']);
      });

      test('insertWaypointSlot(0) 은 맨 앞(출발역 직후)에 넣는다', () {
        notifier.addWaypoint(yeoksam);

        expect(notifier.insertWaypointSlot(0), true);
        expect(names(), [null, '역삼']);
      });

      test('insertWaypointSlot(길이) 는 맨 뒤(도착역 직전)에 넣는다', () {
        notifier.addWaypoint(yeoksam);

        expect(notifier.insertWaypointSlot(1), true);
        expect(names(), ['역삼', null]);
      });

      test('범위 밖 index 는 false + 상태 불변', () {
        notifier.addWaypoint(yeoksam);

        expect(notifier.insertWaypointSlot(-1), false);
        expect(notifier.insertWaypointSlot(2), false);
        expect(names(), ['역삼']);
      });

      test('빈 칸도 상한에 포함된다', () {
        for (var i = 0; i < maxWaypoints; i++) {
          expect(notifier.insertWaypointSlot(0), true);
        }
        expect(notifier.state.canAddWaypoint, false);
        expect(notifier.insertWaypointSlot(0), false);
        expect(notifier.state.waypoints.length, maxWaypoints);
      });

      test('빈 칸은 waypointStationIds 에서 제외된다', () {
        notifier.addWaypoint(yeoksam);
        notifier.insertWaypointSlot(0);
        notifier.addWaypoint(samseong); // 빈 칸(index 0)을 채운다

        expect(names(), ['삼성', '역삼']);
        expect(notifier.state.waypointStationIds, ['219', '217']);
      });

      test('빈 칸이 남아 있으면 그 칸만 경로 계산에서 빠진다', () {
        notifier.addWaypoint(yeoksam);
        notifier.insertWaypointSlot(1); // 뒤에 빈 칸

        expect(names(), ['역삼', null]);
        expect(notifier.state.waypointStationIds, ['217']);
      });
    });

    group('addWaypoint 의 빈 칸 우선 채우기 (지도 툴팁 "경유")', () {
      test('빈 칸이 있으면 뒤에 덧붙이지 않고 첫 빈 칸을 채운다', () {
        notifier.insertWaypointSlot(0);

        expect(notifier.addWaypoint(yeoksam), true);
        expect(names(), ['역삼'], reason: '칸이 미아로 남으면 안 된다');
      });

      test('빈 칸이 여러 개면 앞쪽부터 채운다', () {
        notifier.insertWaypointSlot(0);
        notifier.insertWaypointSlot(1);
        notifier.addWaypoint(yeoksam);

        expect(names(), ['역삼', null]);
      });

      test('상한에 도달했어도 빈 칸이 있으면 채울 수 있다', () {
        for (var i = 0; i < maxWaypoints; i++) {
          notifier.insertWaypointSlot(0);
        }
        expect(notifier.state.canAddWaypoint, false);

        expect(notifier.addWaypoint(yeoksam), true);
        expect(names(), ['역삼', null, null]);
      });
    });

    test('setWaypoint 로 범위 안 칸을 교체한다', () {
      notifier.addWaypoint(yeoksam);
      notifier.addWaypoint(samseong);
      notifier.setWaypoint(0, sadang);

      expect(names(), ['사당', '삼성']);
    });

    test('setWaypoint 로 빈 칸을 채운다', () {
      notifier.insertWaypointSlot(0);
      notifier.setWaypoint(0, sadang);

      expect(names(), ['사당']);
    });

    test('setWaypoint 의 범위 밖 index 는 무시된다', () {
      notifier.addWaypoint(yeoksam);
      notifier.setWaypoint(-1, samseong);
      notifier.setWaypoint(1, samseong);
      notifier.setWaypoint(5, samseong);

      expect(names(), ['역삼'],
          reason: '칸이 없는 index 는 추가가 아니라 무시다');
    });

    test('removeWaypointAt 는 해당 칸만 제거한다 (빈 칸 포함)', () {
      notifier.addWaypoint(yeoksam);
      notifier.insertWaypointSlot(0);
      expect(names(), [null, '역삼']);

      notifier.removeWaypointAt(0);
      expect(names(), ['역삼']);
    });

    test('removeWaypointAt 의 범위 밖 index 는 무시된다', () {
      notifier.addWaypoint(yeoksam);
      notifier.removeWaypointAt(3);
      notifier.removeWaypointAt(-1);

      expect(notifier.state.waypoints.length, 1);
    });

    test('setDeparture/setArrival 은 경유지를 보존한다', () {
      notifier.addWaypoint(yeoksam);
      notifier.setDeparture(gangnam);
      notifier.setArrival(seoul);

      expect(names(), ['역삼']);
      expect(notifier.state.isComplete, true);
    });

    test('swap 은 경유 순서를 뒤집는다 (빈 칸 위치도 함께)', () {
      notifier.setDeparture(gangnam);
      notifier.setArrival(seoul);
      notifier.addWaypoint(yeoksam);
      notifier.addWaypoint(samseong);
      notifier.insertWaypointSlot(2);
      notifier.swap();

      expect(notifier.state.departure?.name, '서울역');
      expect(notifier.state.arrival?.name, '강남');
      expect(
        names(),
        [null, '삼성', '역삼'],
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
