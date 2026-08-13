import 'package:flutter_test/flutter_test.dart';
import 'package:seoul_subway/core/constants/api_constants.dart';
import 'package:seoul_subway/core/utils/live_arrival_seconds.dart';
import 'package:seoul_subway/domain/entities/arrival_info.dart';

/// 지도와 도착정보 화면이 **같은 규칙으로** "알 수 없음"을 판정하는지 고정한다.
///
/// 규칙이 두 벌로 갈라져 있던 탓에 카드가 "정보 없음"으로 판정한 열차가 지도에서는
/// 추정값을 달고 그려지던 불일치가 있었다(2026-08-13 총신대입구(이수) 제보).
/// 이 테스트가 깨지면 그 불일치가 되살아난 것이다.
///
/// 제보 케이스 자체의 상태는 아래 셋 중 **null**(enrich 가 `corrected <= 0` 으로
/// 포기)이다 — 0/grace 초과였다면 지도도 같은 쌍을 넘겨받아 "곧 도착"이 됐을 뿐
/// "1분 후"가 나올 수 없다. 배선 검증은
/// `test/features/subway_map/presentation/providers/live_train_unknown_gate_test.dart`.
void main() {
  final base = DateTime(2026, 8, 13, 12, 0, 0);

  ArrivalInfo at({required int? seconds, required int agoSeconds}) => ArrivalInfo(
        subwayId: '1007',
        stationName: '총신대입구(이수)',
        trainLineNm: '도봉산행 - 내방방면',
        direction: '상행',
        arrivalMessage: '총신대입구(이수) 도착',
        destination: '도봉산',
        trainType: '일반',
        arrivalSeconds: seconds,
        receivedAt: base.subtract(Duration(seconds: agoSeconds)),
      );

  group('알 수 없음 판정', () {
    test('arrivalSeconds 가 null 이면 알 수 없음', () {
      expect(liveArrivalSeconds(at(seconds: null, agoSeconds: 0), now: base),
          isNull);
    });

    test('양수는 경과분을 차감한 잔여초', () {
      expect(liveArrivalSeconds(at(seconds: 180, agoSeconds: 40), now: base),
          140);
    });

    test('양수여도 경과가 값을 넘기면 0 이 아니라 알 수 없음', () {
      // 0 으로 클램프하면 GTX-A 처럼 recptnDt 지연이 큰 노선에서 전 열차가
      // "곧 도착"으로 보인다.
      expect(liveArrivalSeconds(at(seconds: 60, agoSeconds: 120), now: base),
          isNull);
      expect(liveArrivalSeconds(at(seconds: 60, agoSeconds: 60), now: base),
          isNull, reason: '정확히 소진된 경우도 알 수 없음');
    });

    test('0(역에 있음)은 grace 이내에서만 유효', () {
      final grace = ApiConstants.arrivalStateGrace.inSeconds;
      expect(liveArrivalSeconds(at(seconds: 0, agoSeconds: grace), now: base),
          0);
      expect(
          liveArrivalSeconds(at(seconds: 0, agoSeconds: grace + 1), now: base),
          isNull,
          reason: '이미 떠난 열차');
    });

    test('미래 recptnDt 여도 잔여초가 부풀지 않는다 (경과 0 하한)', () {
      expect(liveArrivalSeconds(at(seconds: 100, agoSeconds: -147), now: base),
          100);
    });
  });
}
