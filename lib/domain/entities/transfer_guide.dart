import 'package:freezed_annotation/freezed_annotation.dart';

part 'transfer_guide.freezed.dart';
part 'transfer_guide.g.dart';

/// 환승 가이드 정보.
///
/// 환승역에서 하차 시 내려야 할 문 방향, 추천 객차, 문 번호를 제공한다.
/// 모든 필드는 nullable이어서 일부 정보만 아는 경우에도 graceful하게 동작한다.
@freezed
class TransferGuide with _$TransferGuide {
  const factory TransferGuide({
    /// 하차 시 내릴 문 방향 (좌/우).
    DoorSide? doorSide,

    /// 추천 객차 번호 (1-based).
    int? car,

    /// 추천 문 번호 (객차 내 1-based).
    int? door,

    /// 보조 설명 (예: "충무로 방면 가까움").
    String? note,
  }) = _TransferGuide;

  factory TransferGuide.fromJson(Map<String, dynamic> json) =>
      _$TransferGuideFromJson(json);
}

/// 문 방향 (열차 진행 방향 기준).
enum DoorSide {
  /// 왼쪽 문.
  left,

  /// 오른쪽 문.
  right,
}
