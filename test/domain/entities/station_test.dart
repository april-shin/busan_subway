import 'package:flutter_test/flutter_test.dart';
import 'package:busan_subway/domain/entities/station.dart';

void main() {
  group('Station', () {
    test('creates with required fields and defaults', () {
      const station = Station(
        id: '216',
        name: '강남',
        lineId: '2',
        latitude: 37.49,
        longitude: 127.02,
      );

      expect(station.id, '216');
      expect(station.name, '강남');
      expect(station.isTransfer, false);
      expect(station.transferLines, isEmpty);
      expect(station.svgX, 0);
      expect(station.svgY, 0);
    });

    test('creates transfer station', () {
      const station = Station(
        id: '216',
        name: '강남',
        lineId: '2',
        latitude: 37.49,
        longitude: 127.02,
        isTransfer: true,
        transferLines: ['2', '신분당'],
      );

      expect(station.isTransfer, true);
      expect(station.transferLines, ['2', '신분당']);
    });

    test('fromJson parses correctly', () {
      final json = {
        'id': '216',
        'name': '강남',
        'lineId': '2',
        'latitude': 37.49,
        'longitude': 127.02,
        'svgX': 100.0,
        'svgY': 200.0,
        'isTransfer': true,
        'transferLines': ['2', '신분당'],
      };

      final station = Station.fromJson(json);

      expect(station.id, '216');
      expect(station.svgX, 100.0);
      expect(station.svgY, 200.0);
      expect(station.isTransfer, true);
    });

    test('toJson serializes correctly', () {
      const station = Station(
        id: '216',
        name: '강남',
        lineId: '2',
        latitude: 37.49,
        longitude: 127.02,
      );

      final json = station.toJson();

      expect(json['id'], '216');
      expect(json['name'], '강남');
      expect(json['lineId'], '2');
    });

    test('equality works for same values', () {
      const station1 = Station(
        id: '216',
        name: '강남',
        lineId: '2',
        latitude: 37.49,
        longitude: 127.02,
      );
      const station2 = Station(
        id: '216',
        name: '강남',
        lineId: '2',
        latitude: 37.49,
        longitude: 127.02,
      );

      expect(station1, equals(station2));
    });

    test('copyWith creates modified copy', () {
      const station = Station(
        id: '216',
        name: '강남',
        lineId: '2',
        latitude: 37.49,
        longitude: 127.02,
      );

      final modified = station.copyWith(name: '역삼');

      expect(modified.name, '역삼');
      expect(modified.id, '216');
    });
  });
}
