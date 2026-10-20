// 노선별 두 역 ID 사이의 진행 방향(하행/외선 여부)을 판정하는 유틸.
//
// 세그먼트(`RouteSegment`) 기반 판정은 `features/route_search/utils/direction_resolver.dart`
// 에서, 엣지(역 ID 쌍) 기반 판정은 본 파일에서 제공한다.
// core 레이어가 features에 의존하지 않도록 분리되어 있다.

import '../../domain/entities/connection.dart';

/// 두 역 ID와 노선 ID로 `fromId → toId` 진행 방향이 하행(외선)인지 판정한다.
///
/// 노선별 분기:
/// - 일반 노선: ID 증가 = 하행
/// - 번호 순서가 물리 순서와 어긋나는 역: [_stationRanks] 로 rank 보정
/// - 2호선 순환: 인접 역 ID 쌍 기준 + 순환 경계(201↔243) 반전
/// - 4호선: 진접선(449-452) 특수 처리
/// - 9호선/공항철도: 서울 API 라벨 기준 규칙 반전
///
/// 가상 급행 노선 ID(`{base}E`, 예: `9E`)는 base 노선과 동일한 방향 규칙을 적용한다.
/// 이 정규화가 누락되면 9호선 갈아타기 경로(`9E → 9M → 9`)에서 첫 세그먼트가
/// 일반 규칙으로 평가되어 방향이 반대로 잡히는 회귀가 발생한다.
///
/// 숫자 ID 추출 실패 시 false 반환 (안전한 기본값).
bool isDownBetween(String fromId, String toId, String lineId) {
  final fromNum = _parseNumericId(fromId);
  final toNum = _parseNumericId(toId);
  if (fromNum == null || toNum == null) return false;

  // 가상 급행 노선 정규화: `9E` → `9`, `1E` → `1`, `경춘E` → `경춘` 등.
  // 모드 전환 가상 노선(`{base}M`)은 환승 edge라 isDownBetween로 들어올 일이 없지만
  // 들어와도 base로 정규화되면 일반 분기를 탄다.
  final baseId = lineId.endsWith('E')
      ? lineId.substring(0, lineId.length - 1)
      : lineId;

  // 2호선(순환)·4호선(진접선)은 번호 자체를 특수 규칙으로 해석하므로 rank 보정
  // 대상이 아니다. [_stationRanks] 에도 항목이 없다.
  if (baseId == '2') {
    return _isLine2DownBetween(fromNum, toNum);
  }

  if (baseId == '4') {
    return _isLine4Down(fromNum, toNum);
  }

  // 6호선 응암 순환 폐합 edge(구산 606 ↔ 응암 601): 2호선 순환 경계(201↔243)와
  // 같은 사정으로, ID 비교만으로는 방향이 뒤집힌다. 하행(신내 방면) 열차는
  // 응암→역촌→…→구산→응암 순환을 마저 돌아 새절로 향하므로 구산→응암이
  // 하행 연속이다. 반전하지 않으면 방향별 인접 리스트(`path_on_line.dart`)에서
  // 하행 체인이 구산에서 끊겨 순환 구간 ↔ 본선 간 방향 경로가 전부 소실된다
  // (실시간 열차 아이콘·위치 폴백 도착정보 누락). 회귀 가드:
  // `test/data/eungam_loop_order_test.dart`.
  // ⚠ 이 특례는 **인접 edge 쌍 전제**다. 비인접 쌍(예: 605→601)은 일반 규칙을
  // 타므로, 순환 구간을 가로지르는 비인접 비교를 새로 도입하면 오판할 수 있다.
  if (baseId == '6') {
    if (fromNum == 606 && toNum == 601) return true; // 구산→응암 = 하행
    if (fromNum == 601 && toNum == 606) return false; // 응암→구산 = 상행
  }

  // 번호 순서가 물리 순서와 어긋나는 역은 rank 로 환산한다([_stationRanks]).
  final ranks = _stationRanks[baseId];
  final from = ranks?[fromId] ?? fromNum.toDouble();
  final to = ranks?[toId] ?? toNum.toDouble();

  if (baseId == '9' || baseId == '공항철도') {
    // 이 두 노선은 서울 API 라벨이 일반 규칙과 반대다:
    //   9호선   하행 = 김포공항/개화 方面 (ID 감소) / 상행 = 중앙보훈병원 方面
    //   공항철도 하행 = 서울역 方面 (A01, ID 감소) / 상행 = 인천공항2터미널 方面
    // `realtimeStationArrival` 의 updnLine 과 일치시키기 위해 규칙을 뒤집는다.
    return to < from;
  }

  // 일반 노선: ID(rank) 증가 = 하행
  return to > from;
}

/// "역 번호 순서 = 물리 순서" 규칙에서 벗어나는 역의 정렬 rank. `{노선: {역ID: rank}}`.
///
/// 대부분의 노선은 역 번호가 물리 순서대로 붙어 있어 번호 비교만으로 방향이
/// 나온다. 그러나 (a) 번호가 소진된 구간에 역이 뒤늦게 추가되거나(1호선 금정),
/// (b) 지선·연장 구간이 본선 번호 체계 밖의 ID 를 쓰거나(1호선 광명, 수인분당
/// 원인재), (c) 연장 구간 번호가 물리 순서와 반대로 매겨진 경우(8호선 별내선,
/// 경의중앙 임진강 지선, 서해 김포공항)에는 번호 비교가 방향을 뒤집는다.
///
/// rank 값은 **`connections.json` 의 실제 인접 체인상 위치**에서 유도한다.
/// "번호가 이 값이어야 옳다"가 아니라 "이 노선 데이터에서 이 역이 놓인 자리"를
/// 뜻하므로, 결선 데이터를 고치면 rank 도 함께 갱신해야 한다.
///
/// 회귀 가드: `test/core/utils/line_rank_consistency_test.dart` 가 전 노선의
/// 인접 체인을 순회하며 방향 판정이 단조인지 검사한다. 새 역·연장 구간을
/// 추가했을 때 이 표가 필요한지 여부를 그 테스트가 알려준다.
///
/// **키는 역 ID 문자열이다.** `_parseNumericId` 결과(예: `'1A1'` → 1)로 키잉하면
/// 다른 역과 충돌할 여지가 있고 의미도 드러나지 않는다.
///
/// 2호선(순환)·4호선(진접선)은 번호를 특수 규칙으로 해석하므로 여기 넣지 않는다.
const _stationRanks = <String, Map<String, double>>{
  '1': {
    // 경원선 북단은 소요산(101) 위쪽인데 번호가 163~165 로 크다.
    // 물리 순서: 연천(165) - 전곡(164) - 청산(163) - 소요산(101) - 동두천(102).
    '165': 100.7, // 연천 (최북단 종착)
    '164': 100.8, // 전곡
    '163': 100.9, // 청산
    // 가산디지털단지 — 구로(142)와 독산(166) 사이. 142~165 가 경인선·경원선
    // 북단에 빈틈없이 소진돼 정수 번호가 없어 "142.5" 를 뜻하는 1425 를 부여했다.
    // 공식 역번호는 P142(구로 141 과 독산 P143 사이)이고, 서울 열린데이터광장
    // `subwayStationMaster` 에 `LINE_NUM=경부선` 레코드가 있다.
    '1425': 142.5,
    // 금정 — 명학(171)과 군포(172) 사이. ID `1715` 자체가 "171.5" 를 뜻한다.
    '1715': 171.5,
    // 광명 — 금천구청(167)에서 분기하는 단일역 dead-end 지선. 물리적으로
    // 금천구청보다 남쪽(위도 37.4176 < 37.4568)이라 하행 방향에 놓인다.
    // 근거: 서교공 SearchSTNTimeTableByIDService(STATION_CD 1750) INOUT_TAG=1(상행)
    // 이 광명→영등포 출발 20편, INOUT_TAG=2(하행)는 영등포→광명 당역종착 20편.
    // getTrainSch 캐시(`data/timetables/1_광명_{상행,하행}.json`)도 동일하다.
    //
    // ⚠ 경부선 구로 이남 순서 교정으로 금천구청 ID 가 166 → 167 로 바뀌면서
    //   이 rank 도 166.5 → 167.5 로 옮겼다. 금천구청의 남쪽 이웃은 이제 석수(168)다.
    '1A1': 167.5,
  },
  '3': {
    // 원흥 — 2014년 원당(308)과 삼송(309) 사이에 개통해 번호만 344 로 뒤에 붙었다.
    // 물리 순서: 원당(308) - 원흥(344) - 삼송(309) - 지축(310).
    // 근거: getTrainSch 의 공식 역 순번 stnNo — 원당 316, 원흥 317, 삼송 318,
    // 지축 319 (`data/timetables/3_*.json`).
    '344': 308.5,
  },
  '8': {
    // 별내선(819~824)은 암사(801) **북쪽** 연장인데 번호가 크고, 게다가 물리
    // 순서와 반대로 매겨져 있다. 남행 물리 순서:
    // 별내(819) - 다산 - 동구릉 - 구리 - 장자호수공원 - 암사역사공원(824) - 암사(801).
    '819': 800.1, // 별내 (최북단 종착)
    '820': 800.2, // 다산
    '821': 800.3, // 동구릉
    '822': 800.4, // 구리
    '823': 800.5, // 장자호수공원
    '824': 800.6, // 암사역사공원
  },
  '경의중앙': {
    // 임진강 지선은 문산(K01) 북쪽인데 번호가 K55/K56 으로 크다.
    // 물리 순서: 임진강(K55) - 운천(K56) - 문산(K01) - 파주(K02).
    'K55': 0.8, // 임진강 (최북단 종착)
    'K56': 0.9, // 운천
    // 서울역 지선은 가좌(K20)에서 분기하는 dead-end 인데, 서울역(K54)은 노선 끝번이고
    // 신촌(K57)은 뒤늦게 추가돼 번호가 물리 순서와 맞지 않는다(둘 다 K20 보다 한참 크고,
    // K57→K54 는 번호상 감소다). 가좌에서 서울역 쪽으로 가는 방향을 ID 증가(= 하행,
    // 시각표 인덱스 1)로 통일한다 — `tool/build_center_line_timetable.py` 의 "경의선
    // 상행(→서울역) = idx 1" 규약과 같다.
    // 물리 순서: 가좌(K20) - 신촌(K57) - 서울역(K54, 종착).
    // 이 지선은 가좌에서 홍대입구(K21) 쪽 본선과 같은 쪽(하행)으로 갈라진다.
    'K57': 20.5, // 신촌(경의중앙선)
    'K54': 20.6, // 서울역 (지선 종착)
  },
  '에버라인': {
    // 기흥 — 에버라인의 실제 기점(수인분당 환승)인데 기존 E01~E14 번호를 재배정하지
    // 않으려고 E15 를 덧붙였다. 물리 순서: 기흥(E15) - 강남대(E01) - 지석(E02) - …
    'E15': 0.5,
  },
  '의정부': {
    // 회룡 — 범골(U13)과 발곡(U14) 사이(1호선 환승)인데 번호는 U15 로 덧붙었다.
    // 물리 순서: … - 범골(U13) - 회룡(U15) - 발곡(U14, 종착).
    'U15': 13.5,
  },
  '서해': {
    // 서해선 북단(일산~능곡)과 대곡소사선 중간 신설역은 기존 H01~H12 번호가
    // 소진된 뒤 추가돼 H13~H20 이 물리 순서와 무관하게 붙었다.
    // 남행(하행) 물리 순서:
    // 일산(H13) - 풍산(H14) - 백마(H15) - 대곡(H16) - 능곡(H17) - 김포공항(H12)
    // - 원종(H01) - 부천종합운동장(H18) - 소사(H19) - 소새울(H02) - … -
    // 선부(H09) - 초지(H20) - 시우(H10) - 원시(H11).
    'H13': 0.05, // 일산 (최북단 종착)
    'H14': 0.1, // 풍산
    'H15': 0.2, // 백마
    'H16': 0.3, // 대곡
    'H17': 0.4, // 능곡
    // 김포공항(H12)은 원종(H01) **북쪽**인데 번호가 크다.
    'H12': 0.5,
    'H18': 1.3, // 부천종합운동장 (원종 H01 과 소새울 H02 사이)
    'H19': 1.6, // 소사
    'H20': 9.5, // 초지 (선부 H09 와 시우 H10 사이)
  },
  '수인분당': {
    // 원인재만 구 수인선 코드(K266)를 유지해 파싱값이 266 으로 튄다.
    // 물리 순서: 남동인더스파크(B60) - 원인재 - 연수(B61).
    // ※ 이 주석이 한때 B60 을 인천논현으로 적었던 것은 stations.json 의
    //   B58/B60 오배정 때문이다(수정 후 B58=인천논현·B60=남동인더스파크).
    //   rank 값 60.5 는 "B60 과 B61 사이"라는 뜻이라 그 수정과 무관하게 옳다.
    'K266': 60.5,
    // 인천 방면 종단(인하대~인천)은 송도(B62) 너머인데 번호가 B54~B57 로 작다.
    // 물리 순서: 연수(B61) - 송도(B62) - 인하대(B54) - 숭의 - 신포 - 인천(B57).
    'B54': 62.5, // 인하대
    'B55': 62.6, // 숭의
    'B56': 62.7, // 신포
    'B57': 62.8, // 인천 (종착)
  },
};

/// 성수지선 역 번호 (성수 211 ↔ 용답 244 ↔ 신답 245 ↔ 용두 246 ↔ 신설동 250).
/// 본선 순환과 상/하행 극성이 반대라 전용 분기가 필요하다. 분기 소속 판별에는
/// 211(성수)을 넣지 않는다 — 211은 본선 순환(210↔211, 211↔212)에도 쓰이므로,
/// 넣으면 본선 간선까지 지선 규칙으로 오염된다. 지선 전용 ID(244/245/246/250)
/// 중 한쪽이라도 걸리는 간선은 항상 211↔지선 또는 지선 내부이므로 안전하다.
const _line2SeongsuBranchIds = {244, 245, 246, 250};

/// 2호선 순환 방향 결정 (두 역 ID 기반).
///
/// - 본선 순환(201~243): 내선(상행)=ID 증가(201→202→...→243→201),
///   외선(하행)=ID 감소. 순환 경계(201↔243)에서 |step| > 21이면 반전.
/// - 성수지선(211-244-245-246-250): 실제 관례가 본선과 **반대 극성** —
///   ID 증가(신설동 방향)=하행/외선. 4호선 진접선(`_isLine4Down`)처럼 전용 분기로 처리.
/// - 신정지선(234-247-248-249-251): 본선 공식(작은 step)만으로 실제 관례와
///   일치하므로 별도 분기 불필요. 까치산(251, 2026-08 신설)도 249 다음의
///   증가 ID 라 같은 공식을 그대로 탄다(249→251 step +2).
bool _isLine2DownBetween(int fromNum, int toNum) {
  // 성수지선: ID 증가 = 하행(신설동 방향). 본선 극성과 반대.
  if (_line2SeongsuBranchIds.contains(fromNum) ||
      _line2SeongsuBranchIds.contains(toNum)) {
    return toNum > fromNum;
  }

  final step = toNum - fromNum;
  // step > 0이고 작은 폭: 내선(상행), step < 0이고 작은 폭: 외선(하행)
  // 순환 경계를 넘으면 반전 (|step| > 21이면 반대 방향)
  if (step.abs() > 21) {
    // 순환 경계: step > 21이면 외선, step < -21이면 내선
    return step > 0;
  }
  return step < 0;
}

/// 4호선 방향 결정.
///
/// 진접선(449-452) → 상계(402) 경계에서 ID가 불연속.
/// 실제 노선 순서: 진접(449)→오남(450)→별내별가람(451)→불암산(452)→상계(402)→...→오이도(448)
/// 하행 = 남쪽(오이도 방향), 상행 = 북쪽(진접 방향)
bool _isLine4Down(int firstNum, int lastNum) {
  final firstIsExtension = firstNum >= 449;
  final lastIsExtension = lastNum >= 449;

  // 두 역이 모두 본선(402-448)이면 기본 로직 적용
  if (!firstIsExtension && !lastIsExtension) {
    return lastNum > firstNum;
  }

  // 진접선 내부(둘 다 449+): ID 증가 = 하행(남쪽, 오이도 방향)
  if (firstIsExtension && lastIsExtension) {
    return lastNum > firstNum;
  }

  // 진접선 → 본선: 하행 (남쪽으로 이동)
  if (firstIsExtension && !lastIsExtension) return true;

  // 본선 → 진접선: 상행 (북쪽으로 이동)
  return false;
}

/// [isDownBetween] 가 이 역 ID 로 방향을 **판정할 수 있는지**.
///
/// `isDownBetween` 은 숫자 ID 추출에 실패하면 안전한 기본값 `false`(= 상행)를
/// 반환한다. 그 값은 "상행이다"가 아니라 "모른다"에 가까우므로, 호출부가 두 경우를
/// 구분해야 할 때(예: 모를 때는 조회를 아예 건너뛰어야 할 때) 이 술어로 먼저
/// 거른다. 판정 규칙(`_parseNumericId`)을 호출부가 복제하지 않도록 여기서 공개한다.
///
/// 현재 번들 데이터의 모든 역 ID 는 후행 숫자를 가져 항상 true 지만, 데이터가
/// 확장될 때 계약이 조용히 어긋나지 않도록 두는 방어선이다.
bool canResolveDirection(String stationId) =>
    _parseNumericId(stationId) != null;

/// 역 ID에서 숫자 부분을 추출한다.
/// 예: "201" → 201, "D01" → 1, "K32" → 32
int? _parseNumericId(String id) {
  final match = RegExp(r'(\d+)$').firstMatch(id);
  if (match == null) return null;
  return int.tryParse(match.group(1)!);
}

/// [currentId] 의 직전 역(= [isDown] 반대 방향 인접역) ID를 반환한다.
///
/// 주어진 [connections] 에서 동일 노선이며 환승이 아닌(`isTransfer=false`)
/// 연결만 고려한다. 후보 중 "other → currentId 방향이 [isDown] 과 일치" 하는
/// 경우, 즉 currentId 로 향하는 방향이 isDown 과 같은 인접역을 선택한다.
///
/// 경로 확장(pathToTarget prepend) 시 사용한다.
///
/// 분기 노선(예: 4호선 진접선 ↔ 본선 경계, 2호선 본선 ↔ 성수지선) 에서
/// 같은 방향 조건을 만족하는 후보가 둘 이상일 수 있다. 이 경우 `connections`
/// 순회 순서에 의존해 비결정적으로 한쪽을 선택하면 잘못된 가지로 확장될 수
/// 있으므로, 숫자 ID 차이가 가장 작은(= 물리적으로 가장 인접한) 역을 선택해
/// 결정성을 확보한다.
///
/// 후보가 없으면 null.
String? findPreviousStationId({
  required String currentId,
  required String lineId,
  required bool isDown,
  required List<Connection> connections,
}) {
  final matches = <String>[];
  for (final c in connections) {
    if (c.lineId != lineId) continue;
    if (c.isTransfer) continue;

    String? other;
    if (c.fromStationId == currentId) {
      other = c.toStationId;
    } else if (c.toStationId == currentId) {
      other = c.fromStationId;
    }
    if (other == null) continue;

    // other → currentId 방향이 isDown 과 일치해야 "직전 역" 자격.
    if (isDownBetween(other, currentId, lineId) == isDown) {
      matches.add(other);
    }
  }
  if (matches.isEmpty) return null;
  if (matches.length == 1) return matches.first;

  // 분기: 숫자 ID 차이가 가장 작은 후보 선택 (가장 인접한 물리 역).
  // 숫자 추출 실패 후보는 후순위로 밀린다.
  //
  // 주의: 거리 계산에는 [_stationRanks] rank 보정을 **적용하지 않는다. 의도된
  // 동작이다.** 금천구청(167)의 상행 직전역 후보는 석수(168)와 광명(1A1) 둘인데,
  // 보정 없는 숫자 거리(1 vs 166)가 본선(석수)을 고른다. 상행 열차 절대다수가
  // 본선 경유이므로 본선 우선이 옳은 기본값이다. rank 환산(1 vs 0.5)으로 바꾸면
  // 광명이 이겨 금천구청의 모든 상행 경로 확장이 하루 20편짜리 지선으로
  // 뒤집힌다 — 바꾸지 말 것.
  //
  // ⚠ 구로 이남 순서 교정(2026-08) 전에는 이 예시가 "독산(167)" 이었다. 금천구청
  //   ID 가 166→167 로, 남쪽 이웃이 독산→석수 로 바뀌었을 뿐 결론은 같다.
  final currentNum = _parseNumericId(currentId);
  matches.sort((a, b) {
    final aDist = _idDistance(a, currentNum);
    final bDist = _idDistance(b, currentNum);
    return aDist.compareTo(bDist);
  });
  return matches.first;
}

/// ID 간 숫자 거리. 한쪽이 파싱 실패면 매우 큰 값(= 후순위) 반환.
int _idDistance(String id, int? currentNum) {
  if (currentNum == null) return 1 << 30;
  final n = _parseNumericId(id);
  if (n == null) return 1 << 30;
  return (n - currentNum).abs();
}
