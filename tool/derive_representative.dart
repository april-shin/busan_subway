// 역별 시간표(`t`)에서 노선 대표값(`f`/`l`)을 도출하고, `p` 첫 band 의 시작을
// 도출된 첫차에 맞춘다. `t` 수집 도구들이 공유한다.
//
// 왜 필요한가
// ----------
// `tool/extract_schedules.dart` 는 노선마다 **앵커역 한 곳**의 API 행에서 대표값을
// 뽑는데, 그 도구의 `lineConfigs` 에서 `apiLineName` 이 빈 노선은 API 로 대표값을
// 만들 수 없어 `_getEstimatedSchedule` 의 **하드코딩 추정치**가 들어간다. 그 값이
// 실측 `t` 와 어긋나 "노선 첫차·막차"라는 이름과 맞지 않는 상태가 오래 있었다:
//   경의중앙 평일 05:10~23:40 (실측 05:00~00:39)
//   김포골드 평일 막차 23:30 (실측 24:58) · 주말 첫차 06:00 (실측 05:26)
//   우이신설 평일 막차 00:40 (실측 00:58)
//   인천1     평일 첫차 05:00 (실측 05:30) · 막차 00:30 (실측 00:59)
//
// 도출 규칙
// --------
// - `f` = 방향별 **정상 시간대(240~1439분) 최소**. 심야 인코딩 값을 섞으면 첫차가
//   자정 직후로 잡힌다.
// - `l` = 방향별 **운영일 기준 최대**. 벽시계로 적으면 `DaySchedule.lastTrainMinutes`
//   의 "첫차 이하면 +1440" 규칙이 운영일 분으로 되돌린다.
// - 한 방향이라도 근거가 없으면 그 방향은 **기존 값을 유지**한다(없는 값을 짓지 않음).
// - **입력은 완행(`t`)뿐이다.** 급행(`tE`)은 보지 않는다 — 현재 대상 노선에 급행이
//   없어 무해하지만, 급행 보유 노선을 넣으면 급행 첫차·막차가 반영되지 않는다.
//
// `p` 첫 band 정렬
// ---------------
// `f` 만 당기고 band 를 두면 그 사이를 덮는 band 가 없어 배차간격 경로가 한때
// null("운행 종료")을 돌려줬다. 지금은 `find_next_departure.dart` 가 다음 band
// 시작으로 보정하지만(2026-09-12), 데이터에 `f` 와 `p` 가 어긋난 상태 자체를
// 남기지 않는다. band 의 **시작만** 옮기고 간격·끝은 건드리지 않는다.
//
// ⛔ **꼬리 갭(마지막 band 끝 ~ `l`)은 의도적으로 남긴다.** 끝을 `l` 까지 늘리면
// 배차간격이 실재하지 않는 심야 출발을 지어낸다. 머리 갭은 "이미 있는 첫차를 못
// 찾는" 문제라 메우고, 꼬리 갭은 "없는 열차를 만드는" 문제라 두는 것이다.
//
// 자정 넘김 인코딩
// --------------
// `t` 는 자정 이후 출발을 1440+ 로 담는 노선(getTrainSch·인천1 CSV 계열, 김포골드
// 24:58 → 1498)과 0~1439 로 담는 노선(경의중앙 엑셀, 00:39 → 39)이 섞여 있다.
// [lateNightCutoff](앱 `departure_candidates.dart` 의 `lateNightCutoffMinutes` 와
// 같은 값)로 둘을 가른다.

/// 자정 넘김 인코딩 경계.
const lateNightCutoff = 240;

/// 벽시계 분 → **운영일** 분(자정 넘김은 1440+).
int operatingMinutes(int m) =>
    m >= 1440 ? m : (m < lateNightCutoff ? m + 1440 : m);

/// 분 → 벽시계 "HH:MM"(자정 넘김은 24시간으로 접는다).
String wallClock(int m) {
  final w = m % 1440;
  return '${(w ~/ 60).toString().padLeft(2, '0')}:'
      '${(w % 60).toString().padLeft(2, '0')}';
}

/// "HH:MM" → 자정 기준 분.
int parseMinutes(String hhmm) {
  final parts = hhmm.split(':');
  return int.parse(parts[0]) * 60 + int.parse(parts[1]);
}

/// band 끝을 운영일 분으로. **`TimePeriod.endMinutes` 를 그대로 미러한다** —
/// `"00:00"` 은 하루의 끝(1440)이고, 그 외에는 끝이 시작보다 **작을 때만**(엄격)
/// 자정을 넘긴 것으로 본다(우이신설 주말 `['05:30','00:00']` → 1440).
///
/// ⚠ `DaySchedule.lastTrainMinutes` 의 `<=` 규칙과 다르다. 그쪽은 길이 0
/// (`start == end`) 구간을 하루짜리로 읽지만, `endMinutes` 는 보정하지 않는다.
/// 이 가드의 목적이 "소비자가 읽는 band 끝"과의 비교이므로 소비자 쪽을 따른다.
///
/// ⚠ 이 함수 없이 `"HH:MM"` 문자열끼리 비교하면 `"05:31" >= "00:00"` 이 참이 되어
/// 자정 넘김 band 를 "이미 지난 band" 로 오판한다.
int bandEndMinutes(String start, String end) {
  final e = parseMinutes(end);
  if (e == 0) return 1440;
  return e < parseMinutes(start) ? e + 1440 : e;
}

/// 한 요일 객체(`wd`/`we`)의 `f`/`l` 을 `t` 에서 도출하고 `p[0]` 시작을 맞춘다.
///
/// 실패 메시지 목록을 반환한다(빈 리스트면 성공). 호출 도구가 자기 실패 채널에
/// 합쳐 보고하도록 **예외를 던지지 않는다** — 병합 결과를 쓰기 전에 죽으면 그때까지의
/// 수집이 통째로 버려진다.
///
/// [dayObj] 의 `f`/`l`/`p` 를 제자리에서 수정한다.
List<String> deriveRepresentativeValues({
  required String lineId,
  required String day,
  required Map<String, dynamic> dayObj,
  void Function(String) log = print,
}) {
  final failures = <String>[];
  final table = (dayObj['t'] as Map?)?.cast<String, dynamic>();
  if (table == null || table.isEmpty) return failures;

  final oldF =
      ((dayObj['f'] as List?)?.cast<String>() ?? const ['', '']).toList();
  final oldL =
      ((dayObj['l'] as List?)?.cast<String>() ?? const ['', '']).toList();
  if (oldF.length < 2 || oldL.length < 2) {
    failures.add('$lineId.$day: f/l 이 길이 2 배열이 아닙니다 (f=$oldF, l=$oldL)');
    return failures;
  }
  final newF = [...oldF];
  final newL = [...oldL];

  for (var idx = 0; idx < 2; idx++) {
    final values = <int>[];
    for (final dirs in table.values) {
      final list = (dirs as List)[idx];
      if (list == null) continue;
      values.addAll((list as List).cast<int>());
    }
    final sameDay =
        values.where((m) => m >= lateNightCutoff && m < 1440).toList();
    if (values.isEmpty || sameDay.isEmpty) {
      if (oldF[idx].isEmpty || oldL[idx].isEmpty) {
        failures
            .add('$lineId.$day idx$idx: 출발이 없고 기존 f/l 도 없어 대표값을 정할 수 없습니다');
        continue;
      }
      log('   ⚠ $lineId.$day idx$idx: 출발이 없어 f/l 을 도출하지 못해 기존 값을 유지합니다.');
      continue;
    }
    newF[idx] = wallClock(sameDay.reduce((a, b) => a < b ? a : b));
    newL[idx] =
        wallClock(values.map(operatingMinutes).reduce((a, b) => a > b ? a : b));
  }

  if (!_listEq(newF, oldF) || !_listEq(newL, oldL)) {
    log('   $lineId.$day f $oldF → $newF');
    log('   $lineId.$day l $oldL → $newL');
  }
  dayObj['f'] = newF;
  dayObj['l'] = newL;

  // `p` 는 방향 공용이므로 두 방향 f 중 **이른 쪽**에 맞춘다(늦은 방향은
  // `currentMinutes < firstTrainMinutes` 게이트가 먼저 막아 준다).
  final bands = dayObj['p'];
  // 도출도 실패하고 기존 값도 비어 있으면 `newF` 에 `''` 가 남는다(위에서 failure
  // 로 보고된 상태). 그대로 `parseMinutes` 에 넣으면 FormatException 이 나서
  // "예외를 던지지 않는다"는 이 모듈의 계약이 깨진다 — 아는 값만으로 정렬한다.
  final knownF = newF.where((v) => v.isNotEmpty).map(parseMinutes);
  if (bands is List && bands.isNotEmpty && knownF.isNotEmpty) {
    final earliest = knownF.reduce((a, b) => a < b ? a : b);
    final first = (bands.first as List).cast<dynamic>();
    final start = first[0] as String;
    final end = first[1] as String;
    if (parseMinutes(start) != earliest) {
      // `!=` 로 양방향 정렬한다 — 다음 시행분에서 첫차가 늦어졌는데 한쪽만 당기면
      // `p[0].start` 가 옛 값에 남아 "도출 첫차에 맞춘다"가 깨진다.
      if (earliest >= bandEndMinutes(start, end)) {
        log('   ⚠ $lineId.$day: 도출 첫차 ${wallClock(earliest)} 가 첫 band 끝 $end '
            '이후라 p[0] 을 그대로 둡니다.');
      } else {
        log('   $lineId.$day p[0] 시작 $start → ${wallClock(earliest)} (도출 첫차에 맞춤)');
        first[0] = wallClock(earliest);
      }
    }
  }

  return failures;
}

bool _listEq(List<String> a, List<String> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
