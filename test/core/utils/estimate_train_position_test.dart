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
}
