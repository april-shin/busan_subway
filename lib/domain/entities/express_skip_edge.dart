import 'package:freezed_annotation/freezed_annotation.dart';

part 'express_skip_edge.freezed.dart';
part 'express_skip_edge.g.dart';

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
  }) = _ExpressSkipEdge;

  factory ExpressSkipEdge.fromJson(Map<String, dynamic> json) =>
      _$ExpressSkipEdgeFromJson(json);
}
