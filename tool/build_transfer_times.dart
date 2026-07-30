// ignore_for_file: avoid_print
// assets/json/transfer_times.json 생성 도구 — 환승소요시간의 유일 생성 소스.
//
// `tool/generate_station_data.dart` 는 더 이상 transfer_times.json 을 만들지
// 않는다(드리프트 방지). 이 도구가 단일 소스다.
//
// 데이터 출처:
//   1) 서울교통공사 공식 "환승역거리 소요시간 정보"
//      (tool/data/seoul_metro_transfer_times_20251231.csv, 공공누리 1유형)
//      → 서울교통공사 관할(1~8호선) 환승쌍의 실측 환승거리(m).
//   2) 공식이 커버하지 않는 비(非)서교공 환승(9호선·신분당·경의중앙·수인분당·
//      공항철도·경춘·인천1/2·GTX-A·신림 등)은 아래 _nonOfficialCurated 수기 추정값.
//
// 값 산정 — "수직이동 보정" 모델:
//   공식 `환승소요시간` 컬럼(= 거리 / 1.2m/s, 수평 도보만)은 계단·에스컬레이터·
//   혼잡·방향탐색을 누락해 비현실적으로 짧다(예: 6초). 그래서 공식 `환승거리(m)`만
//   취해 재계산한다:
//       sec = max(60, round(거리 / 0.75) + 45)   // 유효보행 0.75m/s + 오버헤드 45s + floor 60s
//       그다음 10초 단위 반올림.
//   ⚠ 한계: 수평거리만 있어 극단적 수직환승(깊은 에스컬레이터)은 다소 낮게 나올 수 있다.
//   파라미터(_vEff/_overhead/_floor)는 조정 가능.
//
// 필요 키 집합은 stations.json 의 각 환승역 `transferLines` 로 정의한다
// (tool/audit_transfer_stations.py 감사3 과 동일 기준 → 감사 통과 보장).
//
// 실행: dart run tool/build_transfer_times.dart
//
// 4원칙 무관 — 실시간 열차 애니메이션과 무관한 정적 데이터 생성기다.

import 'dart:convert';
import 'dart:io';

// --- 수직이동 보정 모델 파라미터 ---
const double _vEff = 0.75; // 유효 보행속도 (m/s)
const int _overhead = 45; // 고정 오버헤드 (초)
const int _floor = 60; // 최소 환승시간 (초)

int _modelB(int distanceM) {
  final raw = (distanceM / _vEff).round() + _overhead;
  final floored = raw < _floor ? _floor : raw;
  return (floored / 10).round() * 10; // 10초 단위 반올림
}

// 공식 CSV `환승노선` → 우리 lineId 매핑.
const Map<String, String> _lineMap = {
  '1호선': '1', '2호선': '2', '3호선': '3', '4호선': '4', '5호선': '5',
  '6호선': '6', '7호선': '7', '8호선': '8', '9호선': '9',
  '신분당선': 'SB', '경의중앙선': '경의중앙', '경춘선': '경춘', '경강선': '경강',
  '공항철도': '공항철도', '수인분당선': '수인분당', '신림선': '신림',
  '우이신설선': '우이신설', '김포골드라인': '김포골드', '서해선': '서해',
  'GTX-A': 'GTX-A',
};

// 레거시/모호 표기(국철·경원선)는 역별로 해석. '역명|공식표기' → lineId.
const Map<String, String> _legacyByStation = {
  '수서|국철': '수인분당', // 수서역 코레일 = 수인분당선
  '석계|경원선': '1', // 석계 1↔6
};

// 공식이 같은 물리 환승역을 다른 이름으로 싣는 경우 정규화.
const Map<String, String> _nameNorm = {
  '이수': '총신대입구(이수)',
  '총신대입구': '총신대입구(이수)',
};

// 공식 CSV 가 커버하지 않는 비서교공 환승(수기 추정). 공식 CSV 갱신과 무관.
// 키 형식: `역명_id1_id2` (id 오름차순 정렬).
const Map<String, int> _nonOfficialCurated = {
  '검암_공항철도_인천2': 240,
  '계양_공항철도_인천1': 240,
  '고잔_4_수인분당': 120,
  '공덕_경의중앙_공항철도': 180,
  '구리_8_경의중앙': 240,
  '구성_GTX-A_수인분당': 360,
  '김포공항_9_공항철도': 300,
  '노량진_1_9': 240,
  '대곡_3_GTX-A': 300,
  '대곡_3_경의중앙': 300,
  '대곡_GTX-A_경의중앙': 300,
  '대방_1_신림': 480,
  '디지털미디어시티_경의중앙_공항철도': 180,
  '마곡나루_9_공항철도': 240,
  '망우_경의중앙_경춘': 120,
  '미금_SB_수인분당': 180,
  '별내_8_경춘': 180,
  '부평구청_7_인천1': 240,
  '상봉_경의중앙_경춘': 120,
  '샛강_9_신림': 150,
  '서울역_GTX-A_경의중앙': 360,
  '서울역_GTX-A_공항철도': 360,
  '서울역_경의중앙_공항철도': 240,
  '선정릉_9_수인분당': 180,
  '수서_GTX-A_수인분당': 300,
  '수원_1_수인분당': 180,
  '신길온천_4_수인분당': 120,
  '신논현_9_SB': 180,
  '안산_4_수인분당': 120,
  '오이도_4_수인분당': 120,
  '왕십리_경의중앙_수인분당': 180,
  '용산_1_경의중앙': 240,
  '원인재_수인분당_인천1': 180,
  '이매_경춘_수인분당': 240,
  '인천_1_수인분당': 180,
  '정왕_4_수인분당': 120,
  '정자_SB_수인분당': 240,
  '중랑_경의중앙_경춘': 120,
  '중앙_4_수인분당': 120,
  '청량리_경의중앙_경춘': 120,
  '청량리_경의중앙_수인분당': 180,
  '청량리_경춘_수인분당': 180,
  '초지_4_수인분당': 120,
  '평택지제_1_GTX-A': 300,
  '한대앞_4_수인분당': 120,
  '홍대입구_경의중앙_공항철도': 180,
  '회기_1_경의중앙': 180,
  '회기_1_경춘': 180,
  '회기_경의중앙_경춘': 120,
};

const String _csvPath = 'tool/data/seoul_metro_transfer_times_20251231.csv';
const String _stationsPath = 'assets/json/stations.json';
const String _outPath = 'assets/json/transfer_times.json';

/// 무방향 환승쌍 키. 역명 + 정렬된 두 lineId.
String _pairKey(String name, String a, String b) {
  final ids = [a, b]..sort();
  return '${name}_${ids[0]}_${ids[1]}';
}

void main() {
  // 1) stations.json → 필요 키 집합 (audit 감사3 과 동일: 각 환승역의 transferLines 기준)
  final stations = (jsonDecode(File(_stationsPath).readAsStringSync()) as List)
      .cast<Map<String, dynamic>>();
  final required = <String>{};
  for (final s in stations) {
    if (s['isTransfer'] != true) continue;
    final lid = s['lineId'].toString();
    for (final tl in (s['transferLines'] as List? ?? const [])) {
      final other = tl.toString();
      if (other == lid) continue;
      required.add(_pairKey(s['name'] as String, lid, other));
    }
  }

  // 2) 공식 CSV → model B (필요 키 내로 한정)
  final official = <String, int>{};
  final skipped = <String>[];
  final csvLines = File(_csvPath).readAsLinesSync();
  for (final line in csvLines.skip(1)) {
    if (line.trim().isEmpty) continue;
    final c = line.split(',');
    if (c.length < 6) continue;
    final base = c[1].trim();
    final rawName = c[2].trim();
    final transLine = c[3].trim();
    final distance = int.tryParse(c[4].trim());
    if (distance == null) continue;
    final name = _nameNorm[rawName] ?? rawName;
    final partner =
        _lineMap[transLine] ?? _legacyByStation['$rawName|$transLine'];
    if (partner == null) {
      skipped.add('$rawName($base↔$transLine): 노선 매핑 불가');
      continue;
    }
    if (base == partner) continue;
    final key = _pairKey(name, base, partner);
    if (!required.contains(key)) {
      skipped.add('$name($base↔$transLine): transferLines 에 없는 환승');
      continue;
    }
    official[key] = _modelB(distance);
  }

  // 3) 병합: 기본 180 → 비서교공 수기 → 공식(우선)
  final result = <String, int>{};
  for (final k in required) {
    result[k] = 180;
  }
  _nonOfficialCurated.forEach((k, v) {
    if (required.contains(k)) result[k] = v;
  });
  official.forEach((k, v) => result[k] = v);

  // 4) 출력 (키 정렬, 2-space indent, 끝 개행)
  final sortedKeys = result.keys.toList()..sort();
  final ordered = <String, int>{for (final k in sortedKeys) k: result[k]!};
  File(_outPath)
      .writeAsStringSync('${const JsonEncoder.withIndent('  ').convert(ordered)}\n');

  // 5) 리포트
  final curatedUsed =
      required.where((k) => _nonOfficialCurated.containsKey(k)).length;
  final defaulted = required
      .where((k) =>
          !official.containsKey(k) && !_nonOfficialCurated.containsKey(k))
      .length;
  print('transfer_times.json 재생성 완료 ($_outPath)');
  print('  필요 환승쌍(transferLines 기준): ${required.length}');
  print('  공식 model B 적용: ${official.length}');
  print('  비서교공 수기 유지: $curatedUsed');
  print('  180 기본값: $defaulted');
  print('  총 엔트리: ${result.length}');
  if (skipped.isNotEmpty) {
    print('  공식 스킵 ${skipped.length}건 (우리 transferLines/데이터 공백 또는 매핑불가):');
    for (final s in skipped) {
      print('    - $s');
    }
  }
}
