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
  });
}
