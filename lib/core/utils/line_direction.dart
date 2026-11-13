// 노선별 두 역 ID 사이의 진행 방향(하행 여부)을 판정하는 유틸.
//
// 세그먼트(`RouteSegment`) 기반 판정은 `features/route_search/utils/direction_resolver.dart`
// 에서, 엣지(역 ID 쌍) 기반 판정은 본 파일에서 제공한다.
// core 레이어가 features에 의존하지 않도록 분리되어 있다.

import '../../domain/entities/connection.dart';

/// 두 역 ID와 노선 ID로 `fromId → toId` 진행 방향이 하행인지 판정한다.
///
/// 부산 도시철도는 전 노선이 지선·순환 없는 단순 선형이고, 역 ID(부산교통공사
/// 역번호)가 `lines.json` 의 stationIds 순서대로 증가한다. 그래서 **역 ID 증가 =
/// 하행**(시간표 방향 인덱스 1) 하나의 규칙으로 판정한다:
///   1호선 다대포해수욕장(95) → 노포(134), 2호선 장산(201) → 양산(243),
///   3호선 수영(301) → 대저(317), 4호선 미남(401) → 안평(414),
///   동해선 부전(801) → 태화강(823), 부산김해 사상(901) → 가야대(921).
///
/// ⚠ 이 극성은 **앱 내부 규약**이다. 부산교통공사 공식 상/하행 표기와 같다는 보장은
/// 없다. 역별 시간표나 실시간 API 를 붙일 때 그쪽 라벨을 이 규약에 맞춰 변환할 것
/// (`line_schedules.json` 의 `t[0]=상행`, `t[1]=하행` 도 이 규약을 따른다).
///
/// 가상 급행 노선 ID(`{base}E`)는 base 노선과 동일한 방향 규칙을 적용한다
/// (현재 부산 데이터에는 급행이 없다).
///
/// 숫자 ID 추출 실패 시 false 반환 (안전한 기본값).
bool isDownBetween(String fromId, String toId, String lineId) {
  final fromNum = _parseNumericId(fromId);
  final toNum = _parseNumericId(toId);
  if (fromNum == null || toNum == null) return false;
  return toNum > fromNum;
}

/// [isDownBetween] 가 이 역 ID 로 방향을 **판정할 수 있는지**.
///
/// `isDownBetween` 은 숫자 ID 추출에 실패하면 안전한 기본값 `false`(= 상행)를
/// 반환한다. 그 값은 "상행이다"가 아니라 "모른다"에 가까우므로, 호출부가 두 경우를
/// 구분해야 할 때(예: 모를 때는 조회를 아예 건너뛰어야 할 때) 이 술어로 먼저
/// 거른다. 판정 규칙(`_parseNumericId`)을 호출부가 복제하지 않도록 여기서 공개한다.
bool canResolveDirection(String stationId) =>
    _parseNumericId(stationId) != null;

/// 역 ID에서 숫자 부분을 추출한다. 예: "201" → 201, "95" → 95.
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
/// 분기가 있는 데이터에서 같은 방향 조건을 만족하는 후보가 둘 이상이면
/// `connections` 순회 순서에 의존하지 않도록 숫자 ID 차이가 가장 작은 역을
/// 선택해 결정성을 확보한다(부산 데이터는 선형이라 후보는 최대 1개).
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

  // 숫자 ID 차이가 가장 작은 후보 선택. 숫자 추출 실패 후보는 후순위로 밀린다.
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
