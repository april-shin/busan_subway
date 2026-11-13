import 'package:flutter_test/flutter_test.dart';
import 'package:busan_subway/domain/entities/transfer_guide.dart';

void main() {
  group('TransferGuide', () {
    test('모든 필드가 지정된 JSON을 파싱한다', () {
      final json = {
        'doorSide': 'left',
        'car': 6,
        'door': 3,
        'note': '충무로 방면 가까움',
      };

      final guide = TransferGuide.fromJson(json);

      expect(guide.doorSide, DoorSide.left);
      expect(guide.car, 6);
      expect(guide.door, 3);
      expect(guide.note, '충무로 방면 가까움');
    });

    test('right 문 방향을 파싱한다', () {
      final json = {
        'doorSide': 'right',
        'car': 4,
        'door': 2,
      };

      final guide = TransferGuide.fromJson(json);

      expect(guide.doorSide, DoorSide.right);
      expect(guide.car, 4);
      expect(guide.door, 2);
      expect(guide.note, isNull);
    });

    test('일부 필드가 null인 JSON을 파싱한다 (car만)', () {
      final json = {
        'doorSide': null,
        'car': 5,
        'door': null,
        'note': null,
      };

      final guide = TransferGuide.fromJson(json);

      expect(guide.doorSide, isNull);
      expect(guide.car, 5);
      expect(guide.door, isNull);
      expect(guide.note, isNull);
    });

    test('모든 필드가 null인 JSON을 파싱한다', () {
      final json = <String, dynamic>{
        'doorSide': null,
        'car': null,
        'door': null,
        'note': null,
      };

      final guide = TransferGuide.fromJson(json);

      expect(guide.doorSide, isNull);
      expect(guide.car, isNull);
      expect(guide.door, isNull);
      expect(guide.note, isNull);
    });

    test('필드가 아예 없는 JSON도 전부 null로 파싱한다', () {
      final json = <String, dynamic>{};

      final guide = TransferGuide.fromJson(json);

      expect(guide.doorSide, isNull);
      expect(guide.car, isNull);
      expect(guide.door, isNull);
      expect(guide.note, isNull);
    });

    test('door만 지정된 케이스도 정상 파싱한다', () {
      final json = {
        'door': 1,
      };

      final guide = TransferGuide.fromJson(json);

      expect(guide.door, 1);
      expect(guide.doorSide, isNull);
      expect(guide.car, isNull);
    });

    test('doorSide만 지정된 케이스도 정상 파싱한다', () {
      final json = {
        'doorSide': 'left',
      };

      final guide = TransferGuide.fromJson(json);

      expect(guide.doorSide, DoorSide.left);
      expect(guide.car, isNull);
      expect(guide.door, isNull);
    });

    test('잘못된 doorSide 값은 예외를 던진다', () {
      final json = {
        'doorSide': 'invalid',
      };

      // json_serializable의 기본 enum 동작: 정의되지 않은 값은 ArgumentError.
      expect(() => TransferGuide.fromJson(json), throwsA(isA<ArgumentError>()));
    });

    test('copyWith로 불변 복사본을 만든다', () {
      const guide = TransferGuide(
        doorSide: DoorSide.left,
        car: 6,
        door: 3,
      );

      final modified = guide.copyWith(car: 7);

      expect(modified.car, 7);
      expect(modified.doorSide, DoorSide.left);
      expect(modified.door, 3);
      // 원본 불변 확인
      expect(guide.car, 6);
    });
  });
}
