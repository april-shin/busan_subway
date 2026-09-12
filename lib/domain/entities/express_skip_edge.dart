import 'package:freezed_annotation/freezed_annotation.dart';

part 'express_skip_edge.freezed.dart';
part 'express_skip_edge.g.dart';

/// 급행이 하루 중 이 시간대에만 운행함을 나타내는 창.
///
/// 같은 노선에 성격이 다른 급행 계통이 섞여 있고 그중 하나가 몇 편성만 운행할
/// 때, 그 계통의 skip edge 를 상시 운행처럼 두면 없는 열차를 안내하게 된다.
/// 실제 사례는 1호선 경부선 **B급행**(지상 서울역 착발·경부1선)으로, 평일 상행
/// 2회·하행 1회뿐인데 A급행보다 빨라 Dijkstra 가 시각과 무관하게 그쪽을 골랐다.
///
/// [startMinute]/[endMinute] 는 자정 기준 분이며, **그 계통 열차가 노선 위에
/// 있는 시간대**를 뜻한다(역 단위가 아니다 — 창의 시작은 첫 편성의 시발 시각,
/// 끝은 마지막 편성의 종착 시각). 그래서 창 안이라도 특정 역에서는 이미 지나간
/// 열차일 수 있다. 구간 단위 정밀도가 필요해지면 그때 세분할 것.
///
/// [isDown] 은 이 창이 적용되는 진행 방향이다(true = 하행 = 역 ID 증가 방향,
/// `line_direction.dart` 의 `isDownBetween` 기준). 출퇴근 편성은 방향이 갈리므로
/// (B급행은 아침 상행·저녁 하행) 방향을 나누지 않으면 아침에 저녁 열차를
/// 안내하게 된다.
@freezed
abstract class ExpressServiceWindow with _$ExpressServiceWindow {
  const factory ExpressServiceWindow({
    required bool isDown,
    required int startMinute,
    required int endMinute,
  }) = _ExpressServiceWindow;

  factory ExpressServiceWindow.fromJson(Map<String, dynamic> json) =>
      _$ExpressServiceWindowFromJson(json);
}

/// 급행 정차역 간 직통 edge.
///
/// 같은 노선 위에서 급행이 [fromStationId]에서 [toStationId]까지
/// 중간 역들(`skippedStationIds`)을 무정차로 통과하며 [seconds]만큼 걸린다.
///
/// 그래프 빌드 단계에서 `{lineId}E` 가상 노선의 노드와 edge로 변환된다.
@freezed
abstract class ExpressSkipEdge with _$ExpressSkipEdge {
  const factory ExpressSkipEdge({
    required String lineId,
    required String fromStationId,
    required String toStationId,
    required int seconds,
    @Default(<String>[]) List<String> skippedStationIds,

    /// 운행 시간대. **비어 있으면 상시 운행**(대부분의 급행).
    ///
    /// 비어 있지 않으면 [runsAt] 이 통과하는 시각·방향에서만 그래프에 실린다.
    @Default(<ExpressServiceWindow>[])
    List<ExpressServiceWindow> serviceWindows,
  }) = _ExpressSkipEdge;

  factory ExpressSkipEdge.fromJson(Map<String, dynamic> json) =>
      _$ExpressSkipEdgeFromJson(json);
}

/// 운행 시간대 판정. freezed 3 의 생성 클래스는 `implements` 라 본체에 둔
/// 메서드를 물려받지 못하므로 확장으로 뺀다.
extension ExpressSkipEdgeService on ExpressSkipEdge {
  /// [at] 시각에 [isDown] 방향으로 이 급행을 탈 수 있는지.
  ///
  /// - [serviceWindows] 가 비어 있으면 항상 true (상시 운행 급행).
  /// - [at] 이 null 이면 항상 true — 시각을 모르는 호출(대부분의 그래프 단위
  ///   테스트, 시간 개념이 없는 화면)에서 게이트를 적용하지 않겠다는 뜻이다.
  /// - 창이 있는 edge 는 **평일 전용**으로 본다. 창을 쓰는 유일한 계통(1호선
  ///   B급행)이 평일만 운행하고, 토·일 판정은 `line_schedule.dart`·
  ///   `departure_query_time.dart` 와 같은 규칙(공휴일 미고려)이다. 평일 외
  ///   운행 계통이 생기면 창에 요일 구분을 넣을 것.
  bool runsAt(DateTime? at, {required bool isDown}) {
    if (serviceWindows.isEmpty || at == null) return true;
    if (at.weekday == DateTime.saturday || at.weekday == DateTime.sunday) {
      return false;
    }
    final minute = at.hour * 60 + at.minute;
    for (final w in serviceWindows) {
      if (w.isDown != isDown) continue;
      if (minute >= w.startMinute && minute <= w.endMinute) return true;
    }
    return false;
  }
}
