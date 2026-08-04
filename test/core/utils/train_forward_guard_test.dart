import 'package:flutter_test/flutter_test.dart';
import 'package:seoul_subway/core/utils/train_forward_guard.dart';

/// [원칙 1] "열차는 절대 뒤로 가지 않는다" 회귀 가드.
///
/// `tool/build_map_html.dart` 의 JS 구현을 미러한
/// `lib/core/utils/train_forward_guard.dart` 를 검증한다. 이 테스트가 깨지면
/// 스펙이 바뀐 게 아니라 **원칙 위반**을 먼저 의심한다.
void main() {
  // 경로: A(0px) ─100px─ B ─100px─ C(끝=목표역), 세그먼트당 60초.
  const totalLen = 200.0;
  const endKey = '300,100';

  /// 남은시간 → 3-way 클램프까지 마친 targetLen(경로 시작점 기준 px).
  /// 세그먼트 [60,60] 을 뒤에서부터 역산(원칙 2)한 결과를 길이로 환산한 것.
  double targetLenFor(double remaining) {
    if (remaining <= 0) return totalLen;
    if (remaining <= 60) return 100 + (60 - remaining) / 60 * 100; // B-C
    if (remaining <= 120) return (120 - remaining) / 60 * 100; // A-B
    return 0; // outOfPath → A 에 클램프
  }

  double posOf(TrainForwardGuard g, int nowMs) => g.guardedTargetLen(
        targetLen: targetLenFor(g.positionRemaining(nowMs)),
        pathTotalLen: totalLen,
      );

  group('[원칙 1] 위치 역산 입력의 stale 필터 (값이 바뀔 때만 보정)', () {
    test('API 가 같은 arrivalSeconds 를 반복 보고해도 열차는 계속 전진한다', () {
      // 신분당선 등 arvlMsg2 라운딩으로 recptnDt 만 갱신되는 패턴.
      // 이 케이스가 과거 단조 감소 clamp 의 존재 이유였고, 제거 후에도
      // **위치는** 계속 전진해야 한다 (멈추면 원칙 위반이 아니라 UX 붕괴).
      final g = TrainForwardGuard();
      var now = 0;
      g.onRefresh(
          arrivalSeconds: 120, receivedAtMs: now, pathEndKey: endKey);

      final positions = <double>[];
      for (var cycle = 0; cycle < 4; cycle++) {
        now += 15000; // 15초 refresh 주기
        // 매번 동일한 120초를 "지금 측정한 값"으로 재보고
        g.onRefresh(
            arrivalSeconds: 120, receivedAtMs: now, pathEndKey: endKey);
        positions.add(posOf(g, now));
      }

      // 15초마다 25px(=100px/60s × 15s)씩 전진해야 한다.
      expect(positions, [
        closeTo(25, 0.001),
        closeTo(50, 0.001),
        closeTo(75, 0.001),
        closeTo(100, 0.001),
      ]);

      // 표시용 숫자는 원본 그대로 원복된다 — 이것이 새 원칙 1이 허용하는 부분.
      expect(
        remainingFromReceivedAt(
            baseArrival: 120, receivedAtMs: now, nowMs: now),
        120,
      );
    });

    test('값이 바뀐 응답은 뒤로 가는 보정이어도 채택한다 (아이콘은 백스톱이 붙잡음)', () {
      // 실제 지연 등으로 API 가 정직하게 더 큰 값을 주는 경우. 추정치가 실제보다
      // 앞서 달리지 않도록 기준쌍은 보정하되, 화면상 후퇴는 백스톱이 막는다.
      final g = TrainForwardGuard();
      g.onRefresh(
          arrivalSeconds: 120, receivedAtMs: 0, pathEndKey: endKey);
      final before = posOf(g, 30000); // 90초 남음 → A-B 의 50%

      g.onRefresh(
          arrivalSeconds: 180,
          receivedAtMs: 30000,
          pathEndKey: endKey);

      expect(g.positionRemaining(30000), 180, reason: '보정은 채택된다');
      expect(posOf(g, 30000), before, reason: '그래도 아이콘은 뒤로 가지 않는다');
      // 새 기준(180초@30s)으로 90초 넘게 흘러 남은시간이 90 아래로 내려가야
      // 최전진 지점을 넘어 전진이 재개된다.
      expect(posOf(g, 115000), before, reason: '아직 최전진 지점 이전 → 정지 유지');
      expect(posOf(g, 130000), greaterThan(before), reason: '넘어서면 전진 재개');
    });

    test('더 이른 도착을 가리키는 응답은 즉시 채택한다', () {
      final g = TrainForwardGuard();
      g.onRefresh(
          arrivalSeconds: 120, receivedAtMs: 0, pathEndKey: endKey);
      g.onRefresh(
          arrivalSeconds: 30, receivedAtMs: 15000, pathEndKey: endKey);
      expect(g.positionRemaining(15000), 30);
    });

    test('값이 그대로면 recptnDt 가 갱신돼도 기준쌍을 건드리지 않는다', () {
      final g = TrainForwardGuard();
      g.onRefresh(
          arrivalSeconds: 120, receivedAtMs: 0, pathEndKey: endKey);
      g.onRefresh(
          arrivalSeconds: 120,
          receivedAtMs: 15000,
          pathEndKey: endKey);
      expect(g.posBaseReceivedAtMs, 0, reason: 'stale 반복은 기준 시각을 밀지 않는다');
      expect(g.positionRemaining(15000), 105);
    });
  });

  group('[원칙 1] 경로상 단조 전진 backstop', () {
    test('현재역이 뒤로 흔들려도 최전진 지점을 유지한다', () {
      final g = TrainForwardGuard()
        ..onRefresh(
            arrivalSeconds: 60, receivedAtMs: 0, pathEndKey: endKey);
      final advanced = g.guardedTargetLen(targetLen: 150, pathTotalLen: totalLen);
      expect(advanced, 150);

      // 원칙 3 클램프가 현재역 후퇴로 target 을 뒤로 보내는 상황
      expect(g.guardedTargetLen(targetLen: 100, pathTotalLen: totalLen), 150);
      expect(g.guardedTargetLen(targetLen: 0, pathTotalLen: totalLen), 150);

      // 다시 앞서면 전진 재개
      expect(g.guardedTargetLen(targetLen: 170, pathTotalLen: totalLen), 170);
    });

    test('경로 앞이 늘어나도(expandPathBackward) 끝 기준 거리는 연속이다', () {
      // 설계 전제: 시작점은 흔들려도 끝점(목표역)은 고정.
      final g = TrainForwardGuard()
        ..onRefresh(
            arrivalSeconds: 60, receivedAtMs: 0, pathEndKey: endKey);
      g.guardedTargetLen(targetLen: 150, pathTotalLen: 200); // 끝까지 50px

      // path 앞에 한 역(100px) prepend → 총 300px, 같은 지점은 250px 위치
      expect(g.guardedTargetLen(targetLen: 250, pathTotalLen: 300), 250);
      // 확장 경로에서 뒤로 가려 해도 끝 기준 50px 지점에 고정
      expect(g.guardedTargetLen(targetLen: 200, pathTotalLen: 300), 250);
    });

    test('끝점(목표역)이 바뀌면 전진 기억을 리셋한다', () {
      // 같은 노선·방향에서 출발역만 바꾸면 scopeKey 는 같고 끝점만 바뀐다.
      final g = TrainForwardGuard()
        ..onRefresh(
            arrivalSeconds: 60, receivedAtMs: 0, pathEndKey: endKey);
      g.guardedTargetLen(targetLen: 190, pathTotalLen: totalLen);

      g.onRefresh(
          arrivalSeconds: 120,
          receivedAtMs: 15000,
          pathEndKey: '900,100'); // 다른 목표역
      expect(g.minDistToEnd, isNull);
      expect(g.positionRemaining(15000), 120, reason: '새 경로의 기준쌍을 채택');
      expect(g.guardedTargetLen(targetLen: 10, pathTotalLen: totalLen), 10);
    });

    test('NaN 이 흘러들어도 가드가 꺼지지 않는다', () {
      final g = TrainForwardGuard()
        ..onRefresh(
            arrivalSeconds: 60, receivedAtMs: 0, pathEndKey: endKey);
      g.guardedTargetLen(targetLen: 150, pathTotalLen: totalLen);

      expect(g.guardedTargetLen(targetLen: double.nan, pathTotalLen: totalLen), 150);
      expect(g.minDistToEnd, 50, reason: '기억이 NaN 으로 오염되면 안 된다');
      expect(g.guardedTargetLen(targetLen: 100, pathTotalLen: totalLen), 150);
    });
  });

  group('[원칙 1] 단일 점 path 동기화', () {
    test('실제 도착(<=0)이면 최전진으로 맞춰 이후 후퇴를 막는다', () {
      final g = TrainForwardGuard()
        ..onRefresh(arrivalSeconds: 120, receivedAtMs: 0, pathEndKey: endKey);
      g.guardedTargetLen(targetLen: 50, pathTotalLen: totalLen);

      g.onSinglePointPath(pathEndKey: endKey, nowMs: 20000, arrivalSeconds: 0);
      expect(g.minDistToEnd, 0);

      // 다음 refresh 에서 jitter 로 다시 뒤쪽 경로가 와도 끝점에 고정
      g.onRefresh(arrivalSeconds: 90, receivedAtMs: 25000, pathEndKey: endKey);
      expect(posOf(g, 25000), totalLen);
    });

    test("도착 전('진입' 오보고)에는 고정하지 않는다 — 영구 정착 방지", () {
      // arvlMsg2='진입' 한 프레임으로 minDistToEnd=0 을 박으면, 끝점이 같아
      // pathEndKey 리셋도 안 타므로 그 열차는 목표역에 영구 고정된다.
      final g = TrainForwardGuard()
        ..onRefresh(arrivalSeconds: 120, receivedAtMs: 0, pathEndKey: endKey);
      final before = posOf(g, 30000); // 90초 남음

      g.onSinglePointPath(pathEndKey: endKey, nowMs: 30000, arrivalSeconds: 30);
      expect(g.minDistToEnd, isNot(0), reason: '양수면 최전진을 박지 않는다');

      // 정상 다구간 경로로 복귀하면 원래대로 이어서 전진해야 한다.
      g.onRefresh(arrivalSeconds: 90, receivedAtMs: 30000, pathEndKey: endKey);
      expect(posOf(g, 30000), before);
      expect(posOf(g, 60000), greaterThan(before), reason: '전진 재개');
    });
  });

  group('[원칙 1-a] 표시용 기준쌍 stale 필터', () {
    test('원본이 같으면 recptnDt 만의 갱신을 무시해 카운트다운이 이어진다', () {
      // 2026-08-04 사당→방배 실측: barvlDt=150 고정, recptnDt 만 ~16초씩 전진.
      final d = TrainDisplayBase()
        ..onRefresh(arrivalSeconds: 150, receivedAtMs: 0);
      expect(d.displayRemaining(15000), 135);

      d.onRefresh(arrivalSeconds: 150, receivedAtMs: 16000); // 반복 보고
      expect(d.displayRemaining(30000), 120, reason: '원복(톱니파) 금지');

      d.onRefresh(arrivalSeconds: 150, receivedAtMs: 32000);
      expect(d.displayRemaining(45000), 105);
    });

    test('원본이 바뀌면 새 쌍을 채택한다 — 늘어난 값도 그대로', () {
      final d = TrainDisplayBase()
        ..onRefresh(arrivalSeconds: 150, receivedAtMs: 0);
      expect(d.displayRemaining(60000), 90);

      // 실제 지연으로 남은시간이 늘어난 경우: 깎지 않고 그대로 표시한다.
      d.onRefresh(arrivalSeconds: 200, receivedAtMs: 60000);
      expect(d.displayRemaining(60000), 200);
    });

    test('같은 값으로 되돌아오면 그 시점 쌍을 새로 채택한다', () {
      final d = TrainDisplayBase()
        ..onRefresh(arrivalSeconds: 150, receivedAtMs: 0)
        ..onRefresh(arrivalSeconds: 140, receivedAtMs: 10000)
        ..onRefresh(arrivalSeconds: 150, receivedAtMs: 20000);
      expect(d.displayRemaining(20000), 150,
          reason: '직전 값과 다르므로 stale 이 아니다');
    });
  });

  group('[원칙 1-a] 위치는 표시 기준쌍을 상속한다 (도착 시각 동기화)', () {
    test('stall 이 이어져도 위치 남은시간 == 표시 남은시간', () {
      final d = TrainDisplayBase();
      final g = TrainForwardGuard();

      // t=0: 최초 보고. 이후 stall 로 같은 150 이 recptnDt 만 바꿔 반복.
      for (final recv in [0, 16000, 32000, 48000]) {
        d.onRefresh(arrivalSeconds: 150, receivedAtMs: recv);
        g.onRefreshFrom(d, pathEndKey: endKey);
      }
      for (final now in [16000, 32000, 48000, 60000]) {
        expect(g.positionRemaining(now), d.displayRemaining(now),
            reason: '두 도메인이 같은 시각에 0 이 되어야 한다');
      }
      // 150초 뒤 양쪽 모두 0 — 말풍선 "곧 도착"과 아이콘 도착이 같은 시점.
      expect(d.displayRemaining(150000), 0);
      expect(g.positionRemaining(150000), 0);
    });

    test('stall 중 pathEndKey 리셋이 일어나도 되감기지 않는다', () {
      final d = TrainDisplayBase();
      final g = TrainForwardGuard();
      d.onRefresh(arrivalSeconds: 150, receivedAtMs: 0);
      g.onRefreshFrom(d, pathEndKey: endKey);

      // 60초 뒤 stall 반복 + 경로 끝점 변경(리셋). 원본 recptnDt(60000)를 물면
      // 위치가 150 으로 되감겨 표시(90)보다 뒤처진다.
      d.onRefresh(arrivalSeconds: 150, receivedAtMs: 60000);
      g.onRefreshFrom(d, pathEndKey: '999,999');
      expect(g.positionRemaining(60000), d.displayRemaining(60000));
      expect(g.positionRemaining(60000), 90);
    });
  });

  group('미래 recptnDt 방어 (경과시간 0 하한)', () {
    test('recptnDt 가 미래여도 남은시간이 부풀지 않는다', () {
      expect(
        remainingFromReceivedAt(baseArrival: 0, receivedAtMs: 147000, nowMs: 0),
        0,
      );
    });
  });
}
