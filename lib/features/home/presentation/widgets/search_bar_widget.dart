import 'package:flutter/material.dart';

import '../../../../core/constants/line_colors.dart';
import '../../../../core/theme/tokens/app_dimensions.dart';
import '../../../../core/theme/tokens/app_radii.dart';
import '../../../../domain/entities/station.dart';

/// 경유역 필드/마커에 쓰는 색. 지도 마커(`window.setMarker('waypoint-N', …)`)의
/// `#FF9800` 과 같은 색이어야 검색바와 지도가 같은 정차역을 가리키는 것으로 읽힌다.
const Color waypointColor = Color(0xFFFF9800);

/// 입력창 내부 액션(+ / X) 아이콘 색.
///
/// 두 액션 모두 같은 회색 톤을 쓴다 — 역 이름보다는 약하되 또렷하게 눌러 보이는
/// 정도(grey 700). 색으로 서로를 구분하지 않고 모양(+/×)과 위치로만 구분한다.
const Color _fieldActionColor = Color(0xFF616161);

/// 지도 위에 떠 있는(floating) 경로 검색 카드.
///
/// 지도를 전체 배경으로 두고 그 위에 겹쳐 배치되는 것을 전제로 한다.
/// 둥근 모서리 + 그림자 + 좌우 여백으로 카드가 지도 위에 떠 있는 느낌을 준다.
///
/// 필드는 위에서부터 출발 → 경유역들(방문 순서) → 도착 순으로 쌓인다.
///
/// 출발을 제외한 각 필드는 취소(X) 좌측에 경유지 추가(+) 를 갖는다. + 는 화면을
/// 이동시키지 않고 **빈 경유지 칸만 만든다**. 역 선택은 그 칸을 눌렀을 때 일어난다
/// ([onWaypointTap]). 삽입 위치는 누른 정차역 바로 다음이다:
///   - 경유지 필드의 + → 그 경유지 **아래**(index i+1). 뒤 경유지들은 한 칸 밀린다.
///   - 도착 필드의 + → 도착역 **위**(index waypoints.length). 도착역 뒤에는 정차할
///     곳이 없으므로 이 필드만 위로 삽입된다.
/// 출발 필드에 + 가 없는 이유: 출발 다음 자리는 첫 경유지 필드의 + 가 담당한다.
/// 경유지 상한 도달 시 호출부가 `onAddSlotAt: null` 로 모든 + 를 숨긴다.
///
/// [waypoints] 의 `null` 원소는 아직 역을 고르지 않은 빈 칸이며, 안내 문구와 함께
/// 그려진다. 빈 칸도 X 로 지울 수 있어야 실수로 만든 칸을 되돌릴 수 있다.
class RouteSearchBar extends StatelessWidget {
  final Station? departure;
  final Station? arrival;

  /// 경유지 칸(방문 순서). 출발/도착 필드 사이에 순서대로 렌더된다.
  /// `null` 원소는 아직 역을 고르지 않은 빈 칸이다.
  final List<Station?> waypoints;

  final VoidCallback? onDepartureTap;
  final VoidCallback? onArrivalTap;
  final VoidCallback? onSwap;
  final VoidCallback? onSearchRoute;

  /// 출발역만 취소(X). 출발역이 선택돼 있을 때만 각 입력창 내부 우측에
  /// 노출되며, null 이면 취소 버튼을 그리지 않는다.
  final VoidCallback? onClearDeparture;

  /// 도착역만 취소(X). 도착역이 선택돼 있을 때만 노출된다.
  final VoidCallback? onClearArrival;

  /// [waypoints] 의 index 번째 경유지 칸을 탭했을 때 — 역 선택 화면으로 간다.
  /// 빈 칸이면 "고르기", 이미 채워진 칸이면 "바꾸기"로, 동작은 같다.
  final void Function(int index)? onWaypointTap;

  /// [waypoints] 의 index 번째 경유지 칸만 제거(X). 빈 칸도 제거 가능해야 한다.
  final void Function(int index)? onWaypointClear;

  /// index 위치에 **빈 경유지 칸**을 추가(+). index 는 [waypoints] 의 삽입
  /// 지점이며 `0..waypoints.length` 범위다 — 경유지 필드는 `i+1`, 도착 필드는
  /// `waypoints.length` 를 넘긴다(위 클래스 문서의 삽입 규칙 참조).
  ///
  /// null 이면 모든 필드의 + 를 그리지 않는다 — 호출부가 경유지 상한 도달 시
  /// null 을 넘겨 추가 UI 를 숨긴다.
  final void Function(int index)? onAddSlotAt;

  /// 입력칸들 아래(카드 전체 폭)에 붙는 영역 — 즐겨찾기 태그 줄 자리.
  ///
  /// 호출부가 자체 Consumer 위젯을 넘겨, 그 상태 변화가 검색바나 지도를
  /// 다시 그리지 않게 한다. 보여 줄 것이 없으면 그 위젯이 스스로 자리를 비운다.
  final Widget? footer;

  const RouteSearchBar({
    super.key,
    this.departure,
    this.arrival,
    this.waypoints = const [],
    this.onDepartureTap,
    this.onArrivalTap,
    this.onSwap,
    this.onSearchRoute,
    this.onClearDeparture,
    this.onClearArrival,
    this.onWaypointTap,
    this.onWaypointClear,
    this.onAddSlotAt,
    this.footer,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      // 지도 위에 떠 있도록 좌우/상단 여백.
      margin: const EdgeInsets.fromLTRB(
        AppSpacing.space12,
        AppSpacing.space12,
        AppSpacing.space12,
        0,
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.space12,
        vertical: AppSpacing.space8,
      ),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: AppBorderRadius.lg,
        // 하단으로 뻗는 부드러운 그림자 + 살짝 넓게 퍼지는 앰비언트 그림자
        // 이중 레이어로 카드가 지도 위에 확실히 떠 있는 느낌을 강화.
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.18),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: _withFooter(
        Row(
          children: [
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _StationField(
                    label: '출발',
                    station: departure,
                    icon: Icons.trip_origin,
                    iconColor: Colors.blue,
                    onTap: onDepartureTap,
                    onClear: onClearDeparture,
                  ),
                  // 경유역: 출발 다음, 도착 앞에 방문 순서대로.
                  // 각 경유 필드의 + 는 자기 **다음** 자리(i+1)에 새 칸을 끼워 넣는다.
                  for (var i = 0; i < waypoints.length; i++) ...[
                    const SizedBox(height: AppSpacing.space4),
                    _StationField(
                      label: '경유',
                      station: waypoints[i],
                      icon: Icons.adjust,
                      iconColor: waypointColor,
                      onTap: onWaypointTap == null
                          ? null
                          : () => onWaypointTap!(i),
                      onClear: onWaypointClear == null
                          ? null
                          : () => onWaypointClear!(i),
                      // 빈 칸(station == null)도 X 로 지울 수 있어야 실수로 만든
                      // 칸을 되돌릴 수 있다. 출발/도착과 다른 점.
                      clearableWhenEmpty: true,
                      onAddStop: onAddSlotAt == null
                          ? null
                          : () => onAddSlotAt!(i + 1),
                    ),
                  ],
                  const SizedBox(height: AppSpacing.space4),
                  // 도착 필드의 + 는 맨 뒤 경유역으로 추가(= 도착 바로 위).
                  // 도착역 뒤에는 정차할 곳이 없어 이 필드만 위로 삽입한다.
                  _StationField(
                    label: '도착',
                    station: arrival,
                    icon: Icons.place,
                    iconColor: Colors.red,
                    onTap: onArrivalTap,
                    onClear: onClearArrival,
                    onAddStop: onAddSlotAt == null
                        ? null
                        : () => onAddSlotAt!(waypoints.length),
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.space8),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.swap_vert),
                  onPressed: onSwap,
                  tooltip: '출발/도착 바꾸기',
                  visualDensity: VisualDensity.compact,
                ),
                if (onSearchRoute != null)
                  IconButton(
                    icon: const Icon(Icons.search),
                    onPressed: onSearchRoute,
                    tooltip: '경로 검색',
                    color: Theme.of(context).colorScheme.primary,
                    visualDensity: VisualDensity.compact,
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// 입력칸 줄 아래에 [footer] 를 붙인다. 없으면 입력칸 줄 그대로.
  Widget _withFooter(Widget fields) => footer == null
      ? fields
      : Column(
          mainAxisSize: MainAxisSize.min,
          // 태그 줄(내용 폭만큼인 가로 스크롤)이 카드 가운데가 아니라 입력칸과
          // 같은 왼쪽에서 시작하게 한다.
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [fields, footer!],
        );
}

/// 입력창 내부 우측 액션 아이콘(+ / X).
///
/// 부모 입력창의 `GestureDetector` 보다 안쪽에서 탭을 소비해야 하므로
/// `HitTestBehavior.opaque` 를 쓴다. 아이콘 자체는 작지만 좌우 패딩으로
/// 인접 액션과 구분되는 탭 영역을 확보한다.
class _FieldAction extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  const _FieldAction({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Tooltip(
        message: tooltip,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.space4),
          child: Icon(icon, size: AppIconSize.sm, color: _fieldActionColor),
        ),
      ),
    );
  }
}

class _StationField extends StatelessWidget {
  final String label;
  final Station? station;
  final IconData icon;
  final Color iconColor;
  final VoidCallback? onTap;

  /// 이 입력창의 역만 취소(X). 역이 선택돼 있고 콜백이 주어질 때만
  /// 입력창 내부 우측에 X 버튼을 그린다([clearableWhenEmpty] 로 완화 가능).
  final VoidCallback? onClear;

  /// 역이 선택되지 않아도 X 를 노출할지. 경유지 칸 전용.
  ///
  /// 출발/도착은 항상 존재하는 칸이라 비었을 때 지울 대상이 없지만, 경유지는
  /// + 로 만든 빈 칸 자체를 되돌릴 수 있어야 한다.
  final bool clearableWhenEmpty;

  /// 이 입력창 옆에 경유칸을 추가(+). X 버튼 좌측에 그린다.
  /// null 이면 + 를 그리지 않는다(출발 필드, 또는 경유역 상한 도달).
  ///
  /// 삽입 위치(위/아래)는 호출부가 정한다 — [RouteSearchBar] 문서 참조.
  ///
  /// 역 선택 여부와 무관하게 노출한다 — "여기 한 곳 더 들른다"는 조작은 이 칸이
  /// 비어 있어도 의미가 있다(도착역 미정 상태에서 경유지 추가).
  final VoidCallback? onAddStop;

  const _StationField({
    required this.label,
    this.station,
    required this.icon,
    required this.iconColor,
    this.onTap,
    this.onClear,
    this.clearableWhenEmpty = false,
    this.onAddStop,
  });

  @override
  Widget build(BuildContext context) {
    final color =
        station != null ? lineColors[station!.lineId] ?? Colors.grey : null;
    final showClear =
        onClear != null && (station != null || clearableWhenEmpty);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.space8,
          vertical: AppSpacing.space6,
        ),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
        child: Row(
          children: [
            Icon(icon, size: AppIconSize.sm, color: iconColor),
            const SizedBox(width: AppSpacing.space8),
            // 라벨/역 이름이 남은 폭을 차지해 취소(X)를 우측 끝으로 민다.
            Expanded(
              child: station != null
                  ? Row(
                      children: [
                        if (color != null)
                          Container(
                            width: 6,
                            height: 6,
                            decoration: BoxDecoration(
                              color: color,
                              shape: BoxShape.circle,
                            ),
                          ),
                        const SizedBox(width: AppSpacing.space4),
                        Flexible(
                          child: Text(
                            station!.name,
                            style: Theme.of(context).textTheme.labelLarge,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    )
                  : Text(
                      '$label역을 선택하세요',
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                            color: Colors.grey[500],
                          ),
                    ),
            ),
            // 입력창 내부 우측 액션들(+, X). 부모 GestureDetector 보다 안쪽이라
            // 탭 시 역 선택 화면으로 이동하지 않고 각자의 동작만 수행한다.
            //
            // 경유지 추가(+) 가 취소(X) 왼쪽에 온다.
            if (onAddStop != null)
              _FieldAction(
                icon: Icons.add,
                tooltip: '경유지 추가',
                onTap: onAddStop!,
              ),
            if (showClear)
              _FieldAction(
                icon: Icons.close,
                tooltip: '$label역 취소',
                onTap: onClear!,
              ),
          ],
        ),
      ),
    );
  }
}
