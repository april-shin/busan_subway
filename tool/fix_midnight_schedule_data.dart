// ignore_for_file: avoid_print
import 'dart:convert';
import 'dart:io';

/// `assets/json/line_schedules.json`의 자정 넘김 데이터 이상 2건을 인플레이스로
/// 보정하는 idempotent 마이그레이션 스크립트.
///
/// API 호출이 필요 없다 (`.env`에 KOREA_API_KEY/SEOUL_GENERAL_API_KEY가 없어
/// `extract_schedules.dart`/`build_metro_timetable.dart` 재실행이 불가능한 상황을
/// 우회하기 위해 작성됨). 역별 정확 시간표(`t`/`tE`)는 절대 건드리지 않는다 —
/// `t`/`tE`는 오히려 1호선 f/l 재도출의 authoritative 소스로 "읽기만" 한다.
///
/// ## 버그 A — 첫차가 자정 근처인 데이터 이상
/// - **1호선**: `t`/`tE`(역별 정확 시간표) 보유 → f/l을 t/tE에서 재도출한다.
///   f[dir] = 방향별 t∪tE 전체에서 04:00(240분)~23:59(1439분) 사이 최솟값,
///   l[dir] = 방향별 t∪tE 전체 최댓값(1440분 이상이면 -1440). periods(p/pD)는
///   1호선 전체가 이 오염의 영향으로 구조 자체가 깨져 있어(예: 마지막 뿐 아니라
///   첫 period도 "00:00" 시작) 재구성 범위 밖 — f/l만 정정한다.
/// - **서해선**: t/tE가 없어 authoritative 소스가 없다. wd 상행(idx0) f/l이
///   garbage(첫차/막차 간격이 5분 미만)이고 하행(idx1)은 정상이므로,
///   상행 f[0]/l[0]을 하행 f[1]/l[1] 값으로 미러링한다 — **근사치**이며 실제
///   상행 시각과 다를 수 있음을 명시한다.
/// - **GTX-A**: 첫차 00:06/00:15는 이상하지만 막차(23:39/23:50)가 정상이라
///   lastTrainMinutes가 정상 계산되므로 "종일 null" 버그가 아니다. 데이터
///   fabrication을 피하기 위해 이번 마이그레이션 범위에서 제외한다(관찰만 기록).
///
/// ## 버그 B — 마지막 period end가 "00:00"으로 잘림
/// `extract_schedules.dart`의 `_analyzeStationTimes` 마지막 period 생성부
/// (`end: endMin >= 1440 ? '00:00' : ...`)가 자정을 넘긴 종료 시각을 전부
/// "00:00"으로 잘라버리는 버그의 산출물. firstTrain/lastTrain은 이미 올바르게
/// "00:4x" 형태로 저장돼 있으므로, 마지막 period의 end를 lastTrain(l[dir])으로
/// 확장하면 `TimePeriod.endMinutes`가 정확한 값을 반환한다.
///
/// 규칙(1호선 제외 — periods 자체가 전역 오염돼 있어 위 버그 A 처리로 대체):
/// 각 노선의 wd/we, p(방향0)/pD(방향1) 각각에 대해 마지막 period의 end가
/// "00:00"이고, 해당 방향 막차 l[dir]가 "00:00"이 아니며 파싱분이 해당 방향
/// 첫차 f[dir] 분 이하(=자정을 넘겨 다음날로 넘어간 것)이면, 마지막 period의
/// end를 l[dir]로 확장한다. l[dir]=="00:00"(정확히 자정 종료)이거나
/// l[dir]가 자정을 넘기지 않은 경우(예: 서해 wd p — 상행 f/l이 garbage여서
/// 온전한 비교가 불가능한 케이스)는 건드리지 않는다.
///
/// 사용법: dart run tool/fix_midnight_schedule_data.dart
void main() {
  const path = 'assets/json/line_schedules.json';
  final file = File(path);
  final data = jsonDecode(file.readAsStringSync()) as List<dynamic>;

  final bugAFixes = <String>[];
  final bugBFixes = <String>[];

  for (final lineRaw in data) {
    final line = lineRaw as Map<String, dynamic>;
    final lineId = line['id'] as String;

    // --- 버그 A ---
    if (lineId == '1') {
      for (final periodKey in ['wd', 'we']) {
        final obj = line[periodKey] as Map<String, dynamic>?;
        if (obj == null) continue;
        final derived = _deriveFirstLastFromTimetable(obj);
        if (derived == null) continue;
        final (newF, newL) = derived;
        final oldF = (obj['f'] as List).cast<String>();
        final oldL = (obj['l'] as List).cast<String>();
        if (!_listEquals(oldF, newF) || !_listEquals(oldL, newL)) {
          obj['f'] = newF;
          obj['l'] = newL;
          bugAFixes.add(
            '1호선 $periodKey: f $oldF -> $newF, l $oldL -> $newL (t/tE에서 재도출)',
          );
        }
      }
    } else if (lineId == '서해') {
      final obj = line['wd'] as Map<String, dynamic>?;
      if (obj != null) {
        final f = (obj['f'] as List).cast<String>();
        final l = (obj['l'] as List).cast<String>();
        if (f.length > 1 && l.length > 1 && (f[0] != f[1] || l[0] != l[1])) {
          final oldF0 = f[0];
          final oldL0 = l[0];
          f[0] = f[1];
          l[0] = l[1];
          bugAFixes.add(
            '서해선 wd 상행: f[0] $oldF0 -> ${f[0]}, l[0] $oldL0 -> ${l[0]} '
            '(하행 값 미러링, 근사치 — authoritative 소스 없음)',
          );
        }
      }
    }

    // --- 버그 B (1호선은 periods 전역 오염으로 제외 — 버그 A로 f/l만 정정) ---
    if (lineId == '1') continue;
    for (final periodKey in ['wd', 'we']) {
      final obj = line[periodKey] as Map<String, dynamic>?;
      if (obj == null) continue;
      final f = (obj['f'] as List?)?.cast<String>();
      final l = (obj['l'] as List?)?.cast<String>();
      if (f == null || l == null) continue;

      for (final entry in <(String, int)>[('p', 0), ('pD', 1)]) {
        final (key, dirIdx) = entry;
        final periods = obj[key] as List?;
        if (periods == null || periods.isEmpty) continue;
        if (dirIdx >= f.length || dirIdx >= l.length) continue;

        // 확장 대상 period를 고른다. 보통은 배열의 마지막 period이지만,
        // 일부 노선(2,3,4,5,6,7,8,9,SB,인천2 등)은 extract_schedules.dart의
        // 시간 버킷팅이 자정(hour=24 버킷)에서 한 번 더 쪼개져
        // [...,'XX:00~00:00'(진짜 시작시각), '00:00~00:00'(더미 연속 period)]
        // 형태로 끝난다. 더미 period는 start도 "00:00"이라 TimePeriod.endMinutes의
        // wraparound(`end < start`) 조건이 걸리지 않아, end를 l[dir]로 확장해도
        // findNextDeparture의 전날 자정넘김 조회(boosted lookup, +1440)가 매칭되지
        // 않는다 — 반드시 그 앞의 "진짜 시작시각을 가진" period를 확장해야 한다.
        // 더미 period 자체는 배열 순서상 이미 앞선 period가 모든 실제 조회를
        // 가로채므로 건드리지 않아도 무해하다.
        // 주의(idempotency): "이전 period의 end가 00:00인지"를 조건에 넣으면
        // 첫 실행에서 이전 period를 이미 고쳐버린 뒤 재실행 시 그 조건이
        // 더 이상 참이 아니게 되어 더미 쪽으로 타겟이 옮겨가 버린다(발산).
        // 그래서 "이전 period가 진짜 시작시각을 가졌는가(start!='00:00')"만
        // 보고 타겟을 고정한다 — 이후 end=='00:00' 가드가 이미 고친 경우를
        // 걸러내 자연히 idempotent해진다.
        var targetIdx = periods.length - 1;
        final lastEntry = periods[targetIdx] as List;
        if (lastEntry[0] == '00:00' && periods.length >= 2) {
          final prevEntry = periods[targetIdx - 1] as List;
          if (prevEntry[0] != '00:00') {
            targetIdx -= 1;
          }
        }

        final target = periods[targetIdx] as List;
        final end = target[1] as String;
        if (end != '00:00') continue;

        final lStr = l[dirIdx];
        if (lStr == '00:00') continue; // 정확히 자정 종료 — 그대로 둔다

        final fMin = _parseMinutes(f[dirIdx]);
        final lMin = _parseMinutes(lStr);
        if (lMin <= fMin) {
          final start = target[0] as String;
          target[1] = lStr;
          bugBFixes.add(
            '$lineId $periodKey.$key period[$targetIdx] ($start~00:00 -> $start~$lStr)',
          );
        }
      }
    }
  }

  const encoder = JsonEncoder.withIndent('  ');
  file.writeAsStringSync(encoder.convert(data));

  print('=== 버그 A (첫차 자정 이상) 보정: ${bugAFixes.length}건 ===');
  for (final f in bugAFixes) {
    print('  - $f');
  }
  print('');
  print('=== 버그 B (마지막 period end 00:00 절단) 보정: ${bugBFixes.length}건 ===');
  for (final f in bugBFixes) {
    print('  - $f');
  }
}

bool _listEquals(List<String> a, List<String> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// t/tE 전체에서 방향별 f(첫차: 04:00~23:59 사이 최솟값)/l(막차: 전체 최댓값)을
/// 도출한다. t/tE 둘 다 없으면 null.
(List<String>, List<String>)? _deriveFirstLastFromTimetable(
  Map<String, dynamic> obj,
) {
  final t = obj['t'] as Map<String, dynamic>? ?? const {};
  final tE = obj['tE'] as Map<String, dynamic>? ?? const {};

  final dir0 = <int>[];
  final dir1 = <int>[];
  for (final src in [t, tE]) {
    for (final dirs in src.values) {
      final list = dirs as List;
      if (list.isNotEmpty && list[0] != null) {
        dir0.addAll((list[0] as List).cast<int>());
      }
      if (list.length > 1 && list[1] != null) {
        dir1.addAll((list[1] as List).cast<int>());
      }
    }
  }

  if (dir0.isEmpty || dir1.isEmpty) return null;

  String? firstOf(List<int> vals) {
    final filtered = vals.where((v) => v >= 240 && v <= 1439).toList();
    if (filtered.isEmpty) return null;
    filtered.sort();
    return _minutesToTimeStr(filtered.first);
  }

  String lastOf(List<int> vals) {
    final maxV = vals.reduce((a, b) => a > b ? a : b);
    return _minutesToTimeStr(maxV >= 1440 ? maxV - 1440 : maxV);
  }

  final f0 = firstOf(dir0);
  final f1 = firstOf(dir1);
  if (f0 == null || f1 == null) return null;
  final l0 = lastOf(dir0);
  final l1 = lastOf(dir1);

  return ([f0, f1], [l0, l1]);
}

int _parseMinutes(String time) {
  final parts = time.split(':');
  return int.parse(parts[0]) * 60 + int.parse(parts[1]);
}

String _minutesToTimeStr(int minutes) {
  final h = (minutes ~/ 60) % 24;
  final m = minutes % 60;
  return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
}
