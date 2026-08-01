import '../../domain/entities/arrival_info.dart';
import '../../domain/entities/connection.dart';
import '../../domain/entities/station.dart';
import '../constants/subway_id_mapping.dart';
import 'estimate_arrival_seconds.dart';
import 'path_on_line.dart';

/// 위치 API 로 만든 도착정보의 기본 유효 범위(초).
///
/// 위치 API 는 노선의 **전 열차**를 돌려주므로 대상 역과 아무 관계 없는 열차까지
/// 섞여 있다. 도착정보 API 가 방향별로 2대 안팎만 주는 것과 비슷한 밀도를
/// 유지하도록 시간으로 자른다. 10분이면 배차가 드문 시간대에도 다음 열차가
/// 들어오고, 지도에 몇 정거장 밖 열차가 줄줄이 붙는 것을 막는다.
const int fallbackMaxSecondsAway = 600;

/// 방향별로 남길 열차 수. 도착정보 API 의 응답 밀도(방향당 2대)를 따른다.
const int fallbackMaxTrainsPerDirection = 2;

/// 방향 문자열이 하행(외선)인지.
///
/// `features/route_search/utils/direction_resolver.dart` 의 `isDownDirectionString`
/// 과 같은 규칙이다. core 레이어가 features 를 import 할 수 없어 여기 둔다
/// (한쪽을 바꾸면 다른 쪽도 함께 바꿔야 한다).
bool _isDownDirection(String direction) =>
    direction == '하행' || direction == '외선';

/// 노선별 실시간 열차 위치를 **도착정보 형태로** 환산한다.
///
/// 도착정보 API 가 특정 (역, 노선) 을 제공하지 않을 때의 폴백이다. 예) 5호선
/// 천호는 등록명 `천호(풍납토성)` 로 조회하면 8호선만 응답하고, 전체역 일괄
/// 조회에도 5호선 엔트리 자체가 없다(2026-07-31 실측). 위치 API 는 노선 단위라
/// 그 공백을 우회할 수 있다.
///
/// [rawPositions] 는 `TrainPositionDto.toArrivalInfo` 로 변환된 값 —
/// `currentStationName`·`positionStatus`·`arrivalCode`·`direction` 은 채워져
/// 있고 `arrivalSeconds` 는 null 이다. 이 함수가 하는 일은 둘이다:
///
///  1. **잔여초 추정** — 도착정보 API 의 `barvlDt` 에 해당하는 값이 없으므로
///     현재역 → 대상역 구간 소요시간으로 추정한다. 도착정보 API 의 추정 경로와
///     같은 [estimateArrivalSeconds] 를 쓴다(추정 규칙을 한 곳에 유지).
///     기준 시각은 `recptnDt` 그대로 두고 경과분을 차감하지 않는다 —
///     4원칙 1 에 따라 실시간 역산은 JS 가 `receivedAtEpochMs` 로 수행한다.
///  2. **범위 제한** — 추정 실패(경로 없음)·[maxSecondsAway] 초과 열차를 버리고,
///     방향별로 가까운 [maxPerDirection] 대만 남긴다.
///
/// 추정값이므로 `isEstimated: true` 로 표시한다. 대상역에 정차 중인 열차는
/// 추정값 0 ("그 역에 있음" 상태)으로 남으며, 이는 잔여초 0 과 구분되는 값이라
/// 그대로 통과시킨다(표시 단계가 `arrivalStateGrace` 로 신선도를 판단).
List<ArrivalInfo> fallbackArrivalsFromPositions({
  required List<ArrivalInfo> rawPositions,
  required String targetStationName,
  required List<Station> stations,
  required List<Connection> connections,
  int maxSecondsAway = fallbackMaxSecondsAway,
  int maxPerDirection = fallbackMaxTrainsPerDirection,
}) {
  final estimated = <ArrivalInfo>[];

  for (final position in rawPositions) {
    // trainNo 는 카운트다운 매칭 키(4원칙 1)이자 지도 열차 식별자다. 없으면
    // 화면에서 열차를 추적할 수 없으므로 버린다.
    if (position.trainNo.isEmpty) continue;
    if (position.currentStationName.isEmpty) continue;

    final lineId = subwayIdToLineId[position.subwayId];
    if (lineId == null) continue;

    // **진행 방향 정합성** — 열차가 자기 방향으로 대상역에 닿는지 확인한다.
    // 이 검사가 없으면 대상역에서 **멀어지는** 열차가 접근 열차로 잡힌다:
    // 예) 마천 지선 둔촌동의 하행("마천행") 열차는 천호에서 멀어지는데, 방향
    // 제약 없는 경로 탐색은 둔촌동 → 강동 → 천호(되짚는 경로)를 찾아내 260초
    // 뒤 도착하는 유령 열차를 만든다. 도착정보 API 는 접근 열차만 주므로 이런
    // 문제가 없고, 노선 전체를 받는 위치 API 에서만 필요한 방어다.
    if (position.currentStationName != targetStationName) {
      final directional = findPathOnLine(
        fromStationName: position.currentStationName,
        toStationName: targetStationName,
        lineId: lineId,
        stations: stations,
        connections: connections,
        isDown: _isDownDirection(position.direction),
      );
      if (directional == null) continue;
    }

    final seconds = estimateArrivalSeconds(
      currentStationName: position.currentStationName,
      targetStationName: targetStationName,
      lineId: lineId,
      positionStatus: position.positionStatus,
      arrivalCode: position.arrivalCode,
      stations: stations,
      connections: connections,
    );
    // 경로가 없다 = 그 열차는 대상역을 향하지 않는다(반대 방향·다른 지선).
    if (seconds == null) continue;
    if (seconds > maxSecondsAway) continue;

    estimated.add(position.copyWith(
      arrivalSeconds: seconds,
      isEstimated: true,
    ));
  }

  // 방향별로 가까운 열차만. 같은 잔여초면 trainNo 로 안정 정렬해 refresh 마다
  // 순서가 흔들리지 않게 한다(흔들리면 지도 열차가 깜빡인다).
  final byDirection = <String, List<ArrivalInfo>>{};
  for (final a in estimated) {
    byDirection.putIfAbsent(a.direction, () => []).add(a);
  }

  final result = <ArrivalInfo>[];
  for (final trains in byDirection.values) {
    trains.sort((a, b) {
      final byTime = (a.arrivalSeconds ?? 0).compareTo(b.arrivalSeconds ?? 0);
      return byTime != 0 ? byTime : a.trainNo.compareTo(b.trainNo);
    });
    result.addAll(trains.take(maxPerDirection));
  }
  return result;
}
