import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:busan_subway/domain/usecases/find_next_departure.dart';

import '../helpers/compact_schedule_parser.dart';

/// 부산 `assets/json/line_schedules.json` 정합성.
///
/// 부산 데이터는 노선 대표값(`f`/`l`/`p`)만 있는 **추정 배차간격** 시간표다(역별
/// 시간표 `t` 없음). 그래서 "역별 시간표 왕복" 대신 노선 집합·형식·배차 band 의
/// 연속성과, 배차간격 폴백으로 실제 다음 열차가 구해지는지를 잠근다.
void main() {
  late List<Map<String, dynamic>> raw;
  late Set<String> lineIds;

  setUpAll(() {
    raw = (jsonDecode(File('assets/json/line_schedules.json').readAsStringSync())
            as List)
        .cast<Map<String, dynamic>>();
    lineIds = {
      for (final l in (jsonDecode(File('assets/json/lines.json').readAsStringSync())
              as List)
          .cast<Map<String, dynamic>>())
        l['id'] as String,
    };
  });

  int toMin(String hhmm) {
    final p = hhmm.split(':');
    return int.parse(p[0]) * 60 + int.parse(p[1]);
  }

  test('lines.json 의 모든 노선이 시간표를 갖고, 모르는 노선은 없다', () {
    expect(raw.map((e) => e['id']).toSet(), lineIds);
    expect(raw.length, lineIds.length, reason: '노선 중복 없음');
  });

  test('역별 시간표(t/tE)는 아직 없다 — 추정 배차간격만 (데이터 전제 고정)', () {
    for (final e in raw) {
      for (final k in ['wd', 'we']) {
        final day = e[k] as Map<String, dynamic>;
        expect(day.containsKey('t'), isFalse, reason: '${e['id']} $k');
        expect(day.containsKey('tE'), isFalse, reason: '${e['id']} $k');
      }
    }
  });

  test('첫차·막차 형식이 HH:mm 이고 첫차가 이른 새벽 시간대다', () {
    final re = RegExp(r'^\d{2}:\d{2}$');
    for (final e in raw) {
      for (final k in ['wd', 'we']) {
        final day = e[k] as Map<String, dynamic>;
        for (final key in ['f', 'l']) {
          final v = (day[key] as List).cast<String>();
          expect(v, hasLength(2), reason: '${e['id']} $k $key = [상행, 하행]');
          for (final t in v) {
            expect(re.hasMatch(t), isTrue, reason: '${e['id']} $k $key $t');
          }
        }
        for (final t in (day['f'] as List).cast<String>()) {
          expect(toMin(t), inInclusiveRange(4 * 60, 7 * 60),
              reason: '${e['id']} $k 첫차 $t');
        }
      }
    }
  });

  test('배차 band 는 연속·증가하고 배차간격이 양수·합리적(<=60분)이다', () {
    for (final e in raw) {
      for (final k in ['wd', 'we']) {
        final bands = ((e[k] as Map<String, dynamic>)['p'] as List).cast<List>();
        expect(bands, isNotEmpty, reason: '${e['id']} $k');
        var prevEnd = toMin(bands.first[0] as String);
        for (final b in bands) {
          final s = toMin(b[0] as String);
          final en = toMin(b[1] as String);
          final headway = b[2] as int;
          expect(s, prevEnd, reason: '${e['id']} $k band 끊김/겹침 $b');
          expect(en, greaterThan(s), reason: '${e['id']} $k $b');
          expect(headway, inInclusiveRange(1, 60), reason: '${e['id']} $k $b');
          prevEnd = en;
        }
      }
    }
  });

  test('배차간격 폴백으로 전 노선·양방향에서 다음 열차가 구해진다', () {
    final monday9 = DateTime(2026, 11, 16, 9, 0);
    for (final e in raw) {
      final schedule = parseCompactSchedule(e);
      for (final isDown in [false, true]) {
        final next = findNextDeparture(
          schedule: schedule,
          now: monday9,
          isDown: isDown,
        );
        expect(next, isNotNull, reason: '${e['id']} ${isDown ? "하행" : "상행"}');
        final waitMin = next!.difference(monday9).inMinutes;
        expect(waitMin, inInclusiveRange(0, 60),
            reason: '${e['id']} ${isDown ? "하행" : "상행"} 대기 $waitMin분');
      }
    }
  });
}
