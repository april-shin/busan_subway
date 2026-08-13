import 'dart:math';

import '../constants/api_constants.dart';
import '../../domain/entities/arrival_info.dart';

/// 표시 시점 기준의 잔여초. `null` 이면 **알 수 없음**(0초와 구분).
///
/// [ArrivalInfo.arrivalSeconds] 의 세 상태를 표시 규칙으로 옮긴다:
/// - 양수 → `receivedAt` 기준 경과분을 차감한 잔여초. 차감 결과가 0 이하이면 예정
///   시각이 이미 지난 것이므로 "0초"가 아니라 알 수 없음이다.
/// - 0("그 역에 있음" 상태) → 데이터 경과가 [ApiConstants.arrivalStateGrace] 이내일
///   때만 0초. 그 이상 낡았으면 이미 떠난 열차이므로 알 수 없음.
/// - null → 알 수 없음.
///
/// 예전에는 `max(0, seconds - elapsed)` 로 모든 만료·무효 값을 0초로 뭉개, 갱신이
/// 수 분 지연되는 노선(GTX-A·서해선)에서 전 열차가 "0초"로 보였다.
///
/// **두 화면이 이 함수를 공유해야 한다.**
/// - 도착정보 화면(`arrival_card.dart`): 반환값을 그대로 뱃지에 표시하고,
///   null 이면 "정보 없음".
/// - 지도(`live_train_provider.dart`): null 이면 그 열차를 **그리지 않는다**.
///   지도는 잔여초를 직접 쓰지 않고 `(arrivalSeconds, receivedAt)` 쌍을 JS 에
///   넘겨 매 frame 재계산하므로(원칙 1), 반환값은 **유효성 판정에만** 쓴다.
///
/// 규칙이 두 벌로 갈라져 있던 탓에, 도착정보 화면이 "정보 없음"으로 판정한 열차가
/// 지도에서는 계속 카운트다운되는 불일치가 있었다(2026-08-13 총신대입구 제보).
/// 지도의 JS 는 `max(0, ...)` 로 바닥을 0 에 붙여, 만료된 데이터로도 "곧 도착"을
/// **단언**한다 — "모름" 이라는 상태가 없기 때문이다.
/// 새 표시 지점이 생기면 규칙을 복제하지 말고 이 함수를 부를 것.
int? liveArrivalSeconds(ArrivalInfo arrival, {DateTime? now}) {
  final seconds = arrival.arrivalSeconds;
  if (seconds == null) return null;

  // 시계 오차·미래 recptnDt 로 음수 경과가 나오면 카운트다운이 부풀지 않도록 0 하한.
  final elapsed = max(
    0,
    (now ?? DateTime.now()).difference(arrival.receivedAt).inSeconds,
  );

  if (seconds > 0) {
    final remaining = seconds - elapsed;
    return remaining > 0 ? remaining : null;
  }

  // seconds == 0: 잔여초가 아닌 "역에 있음" 상태 → 신선할 때만 유효.
  return elapsed <= ApiConstants.arrivalStateGrace.inSeconds ? 0 : null;
}
