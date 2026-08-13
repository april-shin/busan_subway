import 'package:flutter_test/flutter_test.dart';
import 'package:seoul_subway/core/utils/transfer_guide_key.dart';

void main() {
  group('buildTransferGuideKey', () {
    test('상행(up) 키를 조립한다', () {
      final key = buildTransferGuideKey(
        stationName: '사당',
        arrivalLineId: '2',
        isDown: false,
        destinationLineId: '4',
      );
      expect(key, '사당_2_up_4');
    });

    test('하행(down) 키를 조립한다', () {
      final key = buildTransferGuideKey(
        stationName: '사당',
        arrivalLineId: '2',
        isDown: true,
        destinationLineId: '4',
      );
      expect(key, '사당_2_down_4');
    });

    test('숫자가 아닌 노선 ID(경의중앙 등)도 동일 포맷으로 조립된다', () {
      final key = buildTransferGuideKey(
        stationName: '왕십리',
        arrivalLineId: '경의중앙',
        isDown: true,
        destinationLineId: '5',
      );
      expect(key, '왕십리_경의중앙_down_5');
    });

    test('동일 입력은 동일 키를 생성한다 (유틸 멱등성)', () {
      final key1 = buildTransferGuideKey(
        stationName: '종로3가',
        arrivalLineId: '1',
        isDown: false,
        destinationLineId: '3',
      );
      final key2 = buildTransferGuideKey(
        stationName: '종로3가',
        arrivalLineId: '1',
        isDown: false,
        destinationLineId: '3',
      );
      expect(key1, equals(key2));
    });

    group('v2 — 목적 방향(destIsDown)', () {
      test('destIsDown=false 면 5-tuple 키(_up)를 조립한다', () {
        final key = buildTransferGuideKey(
          stationName: '사당',
          arrivalLineId: '4',
          isDown: true,
          destinationLineId: '2',
          destIsDown: false,
        );
        expect(key, '사당_4_down_2_up');
      });

      test('destIsDown=true 면 5-tuple 키(_down)를 조립한다', () {
        final key = buildTransferGuideKey(
          stationName: '사당',
          arrivalLineId: '4',
          isDown: true,
          destinationLineId: '2',
          destIsDown: true,
        );
        expect(key, '사당_4_down_2_down');
      });

      test('destIsDown=null 이면 기존 4-tuple 키와 완전히 동일하다 (하위 호환)', () {
        final withNull = buildTransferGuideKey(
          stationName: '사당',
          arrivalLineId: '4',
          isDown: true,
          destinationLineId: '2',
          destIsDown: null,
        );
        final without = buildTransferGuideKey(
          stationName: '사당',
          arrivalLineId: '4',
          isDown: true,
          destinationLineId: '2',
        );
        expect(withNull, '사당_4_down_2');
        expect(withNull, equals(without));
      });

      test('목적 방향이 다르면 서로 다른 키가 된다 (사당 4→2 내선/외선 분리)', () {
        final inner = buildTransferGuideKey(
          stationName: '사당',
          arrivalLineId: '4',
          isDown: false,
          destinationLineId: '2',
          destIsDown: false,
        );
        final outer = buildTransferGuideKey(
          stationName: '사당',
          arrivalLineId: '4',
          isDown: false,
          destinationLineId: '2',
          destIsDown: true,
        );
        expect(inner, isNot(equals(outer)));
      });
    });
  });

  group('lookupTransferGuide — 2단 폴백 조회', () {
    test('구체 키(5-tuple)가 있으면 그것을 반환한다', () {
      final guides = {
        '사당_4_up_2_up': '내선 4-1',
        '사당_4_up_2_down': '외선 10-4',
        '사당_4_up_2': '폴백',
      };

      expect(
        lookupTransferGuide(
          guides,
          stationName: '사당',
          arrivalLineId: '4',
          isDown: false,
          destinationLineId: '2',
          destIsDown: false,
        ),
        '내선 4-1',
      );
      expect(
        lookupTransferGuide(
          guides,
          stationName: '사당',
          arrivalLineId: '4',
          isDown: false,
          destinationLineId: '2',
          destIsDown: true,
        ),
        '외선 10-4',
      );
    });

    test('구체 키가 없으면 폴백 키(4-tuple)로 재조회한다', () {
      final guides = {'을지로3가_2_up_3': '폴백만 등록'};

      expect(
        lookupTransferGuide(
          guides,
          stationName: '을지로3가',
          arrivalLineId: '2',
          isDown: false,
          destinationLineId: '3',
          destIsDown: true,
        ),
        '폴백만 등록',
      );
    });

    test('destIsDown 이 null 이면 폴백 키만 조회한다 (구체 키는 무시)', () {
      final guides = {
        '사당_4_up_2_up': '내선',
        '사당_4_up_2': '폴백',
      };

      expect(
        lookupTransferGuide(
          guides,
          stationName: '사당',
          arrivalLineId: '4',
          isDown: false,
          destinationLineId: '2',
        ),
        '폴백',
      );
    });

    test('destIsDown 이 null 이고 폴백 키도 없으면 null', () {
      final guides = {'사당_4_up_2_up': '내선'};

      expect(
        lookupTransferGuide(
          guides,
          stationName: '사당',
          arrivalLineId: '4',
          isDown: false,
          destinationLineId: '2',
        ),
        isNull,
      );
    });

    test('구체·폴백 둘 다 없으면 null', () {
      final guides = <String, String>{'다른역_2_up_3': 'x'};

      expect(
        lookupTransferGuide(
          guides,
          stationName: '사당',
          arrivalLineId: '4',
          isDown: false,
          destinationLineId: '2',
          destIsDown: true,
        ),
        isNull,
      );
    });
  });
}
