// ⛔ 실시간 열차 애니메이션 원칙 1 — "열차는 절대 뒤로 가지 않는다"
//
// `tool/build_map_html.dart` 의 `startTrainAnimation` 이 구현하는 단조 전진
// 로직의 **Dart 미러**다. JS 는 WebView 안에서만 돌아 단위 테스트가 불가능하므로,
// 원칙 2(`estimate_train_position.dart`)와 같은 방식으로 순수 함수를 이쪽에
// 복제해 회귀를 고정한다. 앱 런타임은 이 파일을 사용하지 않는다.
//
// JS 를 고치면 이 파일과 `test/core/utils/train_forward_guard_test.dart` 도
// 함께 고쳐야 한다. 두 구현이 어긋나면 테스트가 원칙을 지켜주지 못한다.
//
// 원칙 1은 두 층으로 구성된다.
//   (1) 위치 역산 입력의 stale 필터 — 별도 기준쌍(posBase*)을 두고, **API 원본
//       값이 실제로 바뀐 refresh 에서만** 보정한다. 값이 그대로면(recptnDt 만
//       갱신된 반복 보고) 이전 쌍을 유지해 남은시간이 벽시계와 함께 계속
//       줄어들게 한다 — 갱신하면 열차가 정지한다.
//   (2) 경로상 위치의 단조 전진 backstop — "경로 끝까지 남은 거리"가 지금까지의
//       최소값보다 커지는 target 은 폐기하고 최전진 지점을 유지한다. (1)에서
//       보정을 채택해 목표가 뒤로 가도 아이콘은 이 층이 붙잡는다.
//
// 원칙 1-a(표시용 숫자)도 (1)과 같은 stale 필터를 쓴다 — `TrainDisplayBase`.
// 표시 기준쌍은 경로와 무관하므로 `pathEndKey` 리셋이 없다는 점만 다르다.

import 'dart:math' as math;

/// 기준 시각 대비 남은시간(초). JS `remainingFromReceivedAt` 미러.
///
/// 경과시간에 0 하한을 둔다 — 일부 노선은 `recptnDt` 를 미래로 보내는데, 그대로
/// 빼면 남은시간이 부풀어 도착역에 붙박이 열차가 생긴다.
double remainingFromReceivedAt({
  required double baseArrival,
  required int receivedAtMs,
  required int nowMs,
}) {
  final elapsed = math.max(0, (nowMs - receivedAtMs) / 1000);
  return math.max(0, baseArrival - elapsed).toDouble();
}

/// 말풍선 표시용 기준쌍. JS `adoptDisplayBase` 미러 (원칙 1-a).
///
/// API 가 같은 `arrivalSeconds` 를 `recptnDt` 만 바꿔 반복 보고할 때(2호선 사당
/// 정차 구간 등) 새 `recptnDt` 를 채택하면 경과시간이 리셋돼 카운트다운이
/// "감소 → 원위치" 톱니파를 그린다. 원본 값이 바뀐 refresh 에서만 채택해
/// 같은 원본값 안에서는 매끄럽게 이어지게 한다.
///
/// 값을 깎는 clamp 가 아니다 — 원본이 바뀌어 늘어났다면 늘어난 대로 채택한다.
class TrainDisplayBase {
  double? baseArrival;
  int? baseReceivedAtMs;

  /// 직전 응답의 API 원본 남은시간. 이 값이 바뀌었을 때만 기준쌍을 채택한다.
  /// JS `trainState.lastDisplayRawArrival` 미러 — 위치용 `lastRawArrival` 과는
  /// 별개 필드다(JS trainState 에는 둘이 공존한다). 혼동 주의.
  double? lastDisplayRawArrival;

  /// API refresh 1회분 반영 (JS: `adoptDisplayBase`).
  void onRefresh({
    required double arrivalSeconds,
    required int receivedAtMs,
  }) {
    if (baseArrival == null || lastDisplayRawArrival != arrivalSeconds) {
      baseArrival = arrivalSeconds;
      baseReceivedAtMs = receivedAtMs;
    }
    lastDisplayRawArrival = arrivalSeconds;
  }

  /// 말풍선에 표시할 남은시간(초). JS: `realRemaining`.
  double displayRemaining(int nowMs) => remainingFromReceivedAt(
        baseArrival: baseArrival ?? 0,
        receivedAtMs: baseReceivedAtMs ?? nowMs,
        nowMs: nowMs,
      );
}

/// 열차 한 대의 단조 전진 상태. JS `trainState` 의 원칙 1 관련 필드 미러.
class TrainForwardGuard {
  /// 위치 역산 전용 기준쌍(표시용 `arrivalSeconds`/`recptnDt` 와 분리).
  double? posBaseArrival;
  int? posBaseReceivedAtMs;

  /// 직전 응답의 API 원본 남은시간. 이 값이 바뀌었을 때만 기준쌍을 보정한다.
  double? lastRawArrival;

  /// 지금까지 기록한 "경로 끝까지 남은 거리"의 최소값(= 최전진 지점).
  double? minDistToEnd;

  /// 경로 끝점(목표역) 식별자. 바뀌면 전진 기억이 무의미해 리셋한다.
  String? pathEndKey;

  /// API refresh 1회분 반영 (JS: `startTrainAnimation` 진입부).
  ///
  /// **입력은 API 원본이 아니라 [TrainDisplayBase] 가 고른 표시 기준쌍이다** —
  /// JS 도 `trainState.baseArrival`/`baseReceivedAt` 을 넘긴다. 원본을 넣으면
  /// stale streak 중 `pathEndKey` 리셋이 일어날 때 위치가 새 `recptnDt` 를 물어
  /// 표시보다 뒤처진다. 편의 래퍼는 [onRefreshFrom] 을 쓸 것.
  ///
  /// 끝점이 바뀌면 기억을 리셋한 뒤, **값이 직전 응답과 달라졌을 때만** 기준쌍을
  /// 보정한다. 값이 같으면 stale 반복 보고이므로 이전 쌍을 유지한다
  /// (갱신하면 남은시간이 원복돼 열차가 정지한다).
  void onRefresh({
    required double arrivalSeconds,
    required int receivedAtMs,
    required String pathEndKey,
  }) {
    if (this.pathEndKey != pathEndKey) {
      this.pathEndKey = pathEndKey;
      minDistToEnd = null;
      posBaseArrival = null;
      posBaseReceivedAtMs = null;
      lastRawArrival = null;
    }

    if (posBaseArrival == null || lastRawArrival != arrivalSeconds) {
      posBaseArrival = arrivalSeconds;
      posBaseReceivedAtMs = receivedAtMs;
    }
    lastRawArrival = arrivalSeconds;
  }

  /// 표시 기준쌍을 그대로 물려 [onRefresh] 를 부르는 래퍼. JS 의 상속 구조
  /// (`startTrainAnimation` 입력 = `trainState.base*`)를 그대로 모사한다.
  ///
  /// [display] 는 같은 refresh 에서 이미 `onRefresh` 를 마친 상태여야 한다
  /// (JS 도 `showTrains` 가 `adoptDisplayBase` 를 먼저 부른다).
  void onRefreshFrom(TrainDisplayBase display, {required String pathEndKey}) {
    onRefresh(
      arrivalSeconds: display.baseArrival ?? 0,
      receivedAtMs: display.baseReceivedAtMs ?? 0,
      pathEndKey: pathEndKey,
    );
  }

  /// 매 frame 위치 역산에 넣을 남은시간(초). JS: `posRemaining`.
  ///
  /// 기준쌍이 null 인 상태는 **도달 불가**다 — JS 는 `pathEndKey` 리셋 블록과
  /// 기준쌍 선택 블록이 같은 동기 구간에 붙어 있어 `step()` 이 null 을 보지
  /// 못한다. (그 상태를 강제로 만들면 JS 는 `elapsed = now/1000` 이 되어 0 을,
  /// 이 미러는 `posBaseArrival` 을 돌려주므로 값이 다르다. 도달 불가라 맞추지
  /// 않았다 — JS 에서 리셋/선택 순서를 바꾸면 이 전제가 깨진다.)
  double positionRemaining(int nowMs) => remainingFromReceivedAt(
        baseArrival: posBaseArrival ?? 0,
        receivedAtMs: posBaseReceivedAtMs ?? nowMs,
        nowMs: nowMs,
      );

  /// 단조 전진 backstop. 원칙 2·3 을 거쳐 나온 [targetLen]을 받아 실제로 채택할
  /// 길이를 돌려준다 (경로 시작점 기준 거리, px).
  ///
  /// 뒤로 가는 target 이면 최전진 지점의 길이를 대신 돌려주고, 전진했을 때만
  /// 기억을 갱신한다. NaN 이 들어오면 기억을 오염시키지 않고 최전진 지점을 유지.
  ///
  /// JS 는 이 길이를 `pointAtLength()` 로 좌표화하며 양끝을 클램프한다
  /// (`len<=0`→path[0], `len>=total`→끝점). 미러는 길이까지만 다루므로 그
  /// 클램프는 검증 범위 밖이다 — 다만 `pathTotalLen < minDistToEnd` 면 가드가
  /// 항상 accept 로 빠져 음수 길이가 나올 수 없다.
  double guardedTargetLen({
    required double targetLen,
    required double pathTotalLen,
  }) {
    final distToEnd = pathTotalLen - targetLen;
    if (distToEnd.isNaN || distToEnd.isInfinite) {
      return minDistToEnd == null ? targetLen : pathTotalLen - minDistToEnd!;
    }
    if (minDistToEnd != null && distToEnd > minDistToEnd!) {
      return pathTotalLen - minDistToEnd!;
    }
    minDistToEnd = distToEnd;
    return targetLen;
  }

  /// 단일 점 path("현재역 == 목표역") 진입 시 상태 동기화.
  ///
  /// **실제 도착(arrivalSeconds<=0)일 때만** 최전진(distToEnd=0)으로 고정한다.
  /// 양수인데도 고정하면 '진입' 오보고 한 번으로 열차가 목표역에 영구 고정된다
  /// (끝점이 같아 pathEndKey 리셋도 타지 않아 회복 경로가 없다).
  void onSinglePointPath({
    required String pathEndKey,
    required int nowMs,
    required double arrivalSeconds,
  }) {
    if (arrivalSeconds > 0) return; // 아이콘도 전진 기억도 건드리지 않는다
    this.pathEndKey = pathEndKey;
    minDistToEnd = 0;
    posBaseArrival = 0;
    posBaseReceivedAtMs = nowMs;
    lastRawArrival = 0;
  }
}
