import 'package:flutter_test/flutter_test.dart';
import 'package:seoul_subway/core/utils/estimate_train_position.dart';

void main() {
  group('estimateTrainPosition - 검증 예시 (요구사항 고정)', () {
    // 경로 A-B-C, seg=[60,60], dwell=30, 총 150s
    test('t=120 → A-B 정중앙 (segIdx=0, progress=0.5, 주행)', () {
      final r = estimateTrainPosition(
        remainingSeconds: 120,
        segmentTravelTimes: [60, 60],
        dwellSeconds: 30,
      );
      expect(r.outOfPath, isFalse);
      expect(r.segmentIndex, 0);
      expect(r.progress, closeTo(0.5, 1e-9));
      expect(r.isDwelling, isFalse);
    });

    test('t=80 → B 정차 중 (segIdx=1, isDwelling=true, progress=0.0)', () {
      final r = estimateTrainPosition(
        remainingSeconds: 80,
        segmentTravelTimes: [60, 60],
        dwellSeconds: 30,
      );
      expect(r.outOfPath, isFalse);
      expect(r.segmentIndex, 1);
      expect(r.isDwelling, isTrue);
      expect(r.progress, 0.0);
    });
  });

  group('estimateTrainPosition - 경계 조건', () {
    test('t=0 → 이미 도착 (segIdx=n-1, progress=1.0)', () {
      final r = estimateTrainPosition(
        remainingSeconds: 0,
        segmentTravelTimes: [60, 60],
        dwellSeconds: 30,
      );
      expect(r.outOfPath, isFalse);
      expect(r.segmentIndex, 1);
      expect(r.progress, 1.0);
      expect(r.isDwelling, isFalse);
    });

    test('t<0(음수) → 도착 상태로 고정', () {
      final r = estimateTrainPosition(
        remainingSeconds: -5,
        segmentTravelTimes: [60, 60],
        dwellSeconds: 30,
      );
      expect(r.outOfPath, isFalse);
      expect(r.segmentIndex, 1);
      expect(r.progress, 1.0);
    });

    test('t=60 → B-C 세그먼트 시작(segIdx=1, progress=0.0) — 주행 우선', () {
      final r = estimateTrainPosition(
        remainingSeconds: 60,
        segmentTravelTimes: [60, 60],
        dwellSeconds: 30,
      );
      expect(r.outOfPath, isFalse);
      expect(r.segmentIndex, 1);
      expect(r.progress, 0.0);
      expect(r.isDwelling, isFalse);
    });

    test('t=90 → B 정차 방금 시작 (isDwelling=true)', () {
      final r = estimateTrainPosition(
        remainingSeconds: 90,
        segmentTravelTimes: [60, 60],
        dwellSeconds: 30,
      );
      expect(r.segmentIndex, 1);
      expect(r.isDwelling, isTrue);
      expect(r.progress, 0.0);
    });

    test('t=150 → A-B 세그먼트 시작 (segIdx=0, progress=0.0)', () {
      final r = estimateTrainPosition(
        remainingSeconds: 150,
        segmentTravelTimes: [60, 60],
        dwellSeconds: 30,
      );
      expect(r.outOfPath, isFalse);
      expect(r.segmentIndex, 0);
      expect(r.progress, 0.0);
      expect(r.isDwelling, isFalse);
    });

    test('t=151 → outOfPath=true, remainingAfterPath=1', () {
      final r = estimateTrainPosition(
        remainingSeconds: 151,
        segmentTravelTimes: [60, 60],
        dwellSeconds: 30,
      );
      expect(r.outOfPath, isTrue);
      expect(r.remainingAfterPath, 1);
    });
  });

  group('estimateTrainPosition - 단일 세그먼트', () {
    test('seg=[60], dwell=30, t=30 → (segIdx=0, progress=0.5)', () {
      final r = estimateTrainPosition(
        remainingSeconds: 30,
        segmentTravelTimes: [60],
        dwellSeconds: 30,
      );
      expect(r.outOfPath, isFalse);
      expect(r.segmentIndex, 0);
      expect(r.progress, closeTo(0.5, 1e-9));
      expect(r.isDwelling, isFalse);
    });

    test('seg=[60], dwell=30, t=60 → (segIdx=0, progress=0.0)', () {
      final r = estimateTrainPosition(
        remainingSeconds: 60,
        segmentTravelTimes: [60],
        dwellSeconds: 30,
      );
      expect(r.segmentIndex, 0);
      expect(r.progress, 0.0);
    });

    test('seg=[60], dwell=30, t=61 → outOfPath=true (단일 세그먼트는 dwell 없음)',
        () {
      final r = estimateTrainPosition(
        remainingSeconds: 61,
        segmentTravelTimes: [60],
        dwellSeconds: 30,
      );
      expect(r.outOfPath, isTrue);
      expect(r.remainingAfterPath, 1);
    });
  });

  group('estimateTrainPosition - 방어적 케이스', () {
    test('빈 segmentTravelTimes → ArgumentError', () {
      expect(
        () => estimateTrainPosition(
          remainingSeconds: 10,
          segmentTravelTimes: [],
          dwellSeconds: 30,
        ),
        throwsArgumentError,
      );
    });

    test('세 세그먼트 중간 정차 검증 (seg=[60,60,60], dwell=30)', () {
      // 총시간 = 60*3 + 30*2 = 240s
      // t=240 → 세그0 시작
      final r1 = estimateTrainPosition(
        remainingSeconds: 240,
        segmentTravelTimes: [60, 60, 60],
        dwellSeconds: 30,
      );
      expect(r1.segmentIndex, 0);
      expect(r1.progress, 0.0);

      // t=150 → 세그1 정중앙: back 60(세그2) + 30(정차) + 60(세그1 끝)=150
      // -> tRem 150 > 60, tRem=90; dwell 90>30, tRem=60; 세그1 60<=60 → segIdx=1 progress=0
      final r2 = estimateTrainPosition(
        remainingSeconds: 150,
        segmentTravelTimes: [60, 60, 60],
        dwellSeconds: 30,
      );
      expect(r2.segmentIndex, 1);
      expect(r2.progress, 0.0);
    });
  });

  // ⛔ 4원칙 회귀 방지 — 변경 금지 (CLAUDE.md 최상위 정책)
  //
  // 원칙 2 (매 frame 역산) 의 기본 계약이 깨지면 이 그룹이 실패한다.
  // 본 테스트는 dwell=0 전제(JS 애니메이션 시간축)에서 역산 결과를 고정한다.
  // 실패 시 먼저 "원칙 위반이 아닌지" 확인하고, CLAUDE.md 4원칙 섹션 검토.
  group('[원칙 2 회귀 방지] dwell=0 역산 시나리오 고정', () {
    test('A-B-C, s=[60,60], dwell=0, t=120 → A 위치 (segIdx=0, progress=0)', () {
      final r = estimateTrainPosition(
        remainingSeconds: 120,
        segmentTravelTimes: [60, 60],
        dwellSeconds: 0,
      );
      expect(r.outOfPath, isFalse);
      expect(r.segmentIndex, 0);
      expect(r.progress, closeTo(0.0, 1e-9));
      expect(r.isDwelling, isFalse);
    });

    test('A-B-C, s=[60,60], dwell=0, t=80 → A-B 의 2/3 지점 (B 쪽)', () {
      // 80 > 60(seg1) → t=20. seg0: 20 ≤ 60 → progress=(60-20)/60 = 2/3.
      final r = estimateTrainPosition(
        remainingSeconds: 80,
        segmentTravelTimes: [60, 60],
        dwellSeconds: 0,
      );
      expect(r.outOfPath, isFalse);
      expect(r.segmentIndex, 0);
      expect(r.progress, closeTo(2.0 / 3.0, 1e-9));
      expect(r.isDwelling, isFalse);
    });

    test('고속-사평-신논현 실측, s=[135,130], dwell=0, t=131 → 사평 직전', () {
      // 131 > 130(seg1, 사평→신논현) → t=1. seg0(고속→사평): 1 ≤ 135.
      // progress=(135-1)/135 ≈ 0.993 (사평 직전).
      final r = estimateTrainPosition(
        remainingSeconds: 131,
        segmentTravelTimes: [135, 130],
        dwellSeconds: 0,
      );
      expect(r.outOfPath, isFalse);
      expect(r.segmentIndex, 0);
      expect(r.progress, closeTo(134.0 / 135.0, 1e-9));
      expect(r.isDwelling, isFalse);
    });

    test('s=[135,130], dwell=0, t=265 (총합과 동일) → A 위치', () {
      final r = estimateTrainPosition(
        remainingSeconds: 265,
        segmentTravelTimes: [135, 130],
        dwellSeconds: 0,
      );
      expect(r.outOfPath, isFalse);
      expect(r.segmentIndex, 0);
      expect(r.progress, closeTo(0.0, 1e-9));
    });

    test('s=[135,130], dwell=0, t=266 (총합 초과) → outOfPath', () {
      // 총 주행시간(265) 보다 남은시간이 크면 outOfPath 반환.
      // (JS 측에서는 원칙 3 에 따라 path[curIdx] 에 클램프)
      final r = estimateTrainPosition(
        remainingSeconds: 266,
        segmentTravelTimes: [135, 130],
        dwellSeconds: 0,
      );
      expect(r.outOfPath, isTrue);
    });

    test('현재역 다음 세그먼트 이후 매칭 시 3-way 클램프 전제', () {
      // path=[고속, 사평, 신논현], s=[135, 130], t=60 (사평-신논현 진행 중)
      // 역산: t=60 ≤ 130 → segIdx=1, progress=(130-60)/130 ≈ 0.538
      // JS 측 3-way 클램프: curIdx=0 이면 segmentIndex(1) ≥ nextIdx(1) →
      // path[nextIdx=사평]에 고정 (원칙 3). 여기서는 역산 기대값만 검증.
      final r = estimateTrainPosition(
        remainingSeconds: 60,
        segmentTravelTimes: [135, 130],
        dwellSeconds: 0,
      );
      expect(r.outOfPath, isFalse);
      expect(r.segmentIndex, 1);
      expect(r.progress, closeTo(70.0 / 130.0, 1e-9));
    });
  });
}
