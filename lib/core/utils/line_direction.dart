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

  if (baseId == '2') {
    return _isLine2DownBetween(fromNum, toNum);
  }

  if (baseId == '4') {
    return _isLine4Down(fromNum, toNum);
  }

  if (baseId == '9') {
    // 9호선은 서울 API 라벨이 일반 규칙과 반대:
    //   하행 = 김포공항/개화 方面 (ID 감소)
    //   상행 = 중앙보훈병원 方面 (ID 증가)
    // `realtimeStationArrival` 의 updnLine 과 일치시키기 위해 규칙을 뒤집는다.
    return toNum < fromNum;
  }

  if (baseId == '공항철도') {
    // 공항철도도 서울 API 라벨이 일반 규칙과 반대:
    //   하행 = 서울역 方面 (A01, ID 감소)
    //   상행 = 인천공항2터미널 方面 (A14, ID 증가)
    return toNum < fromNum;
  }

  // 일반 노선: ID 증가 = 하행
  return toNum > fromNum;
}

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
/// - 신정지선(234-247-248-249): 본선 공식(작은 step)만으로 실제 관례와 일치하므로
///   별도 분기 불필요.
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
