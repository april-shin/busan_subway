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
}
