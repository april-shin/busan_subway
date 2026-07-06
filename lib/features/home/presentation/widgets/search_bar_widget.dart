import 'package:flutter/material.dart';

import '../../../../core/constants/line_colors.dart';
import '../../../../core/theme/tokens/app_dimensions.dart';
import '../../../../core/theme/tokens/app_radii.dart';
import '../../../../domain/entities/station.dart';

/// 지도 위에 떠 있는(floating) 경로 검색 카드.
///
/// 지도를 전체 배경으로 두고 그 위에 겹쳐 배치되는 것을 전제로 한다.
/// 둥근 모서리 + 그림자 + 좌우 여백으로 카드가 지도 위에 떠 있는 느낌을 준다.
class RouteSearchBar extends StatelessWidget {
  final Station? departure;
  final Station? arrival;
  final VoidCallback? onDepartureTap;
  final VoidCallback? onArrivalTap;
  final VoidCallback? onSwap;
  final VoidCallback? onSearchRoute;

  /// 출발역만 취소(X). 출발역이 선택돼 있을 때만 각 입력창 내부 우측에
  /// 노출되며, null 이면 취소 버튼을 그리지 않는다.
  final VoidCallback? onClearDeparture;

  /// 도착역만 취소(X). 도착역이 선택돼 있을 때만 노출된다.
  final VoidCallback? onClearArrival;

  const RouteSearchBar({
    super.key,
    this.departure,
    this.arrival,
    this.onDepartureTap,
    this.onArrivalTap,
    this.onSwap,
    this.onSearchRoute,
    this.onClearDeparture,
    this.onClearArrival,
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
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.15),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
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
                const SizedBox(height: AppSpacing.space4),
                _StationField(
                  label: '도착',
                  station: arrival,
                  icon: Icons.place,
                  iconColor: Colors.red,
                  onTap: onArrivalTap,
                  onClear: onClearArrival,
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
  /// 입력창 내부 우측에 X 버튼을 그린다.
  final VoidCallback? onClear;

  const _StationField({
    required this.label,
    this.station,
    required this.icon,
    required this.iconColor,
    this.onTap,
    this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    final color =
        station != null ? lineColors[station!.lineId] ?? Colors.grey : null;
    final showClear = station != null && onClear != null;

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
            // 입력창 내부 우측 취소(X). 부모 GestureDetector 보다 안쪽이라
            // X 탭 시 역 선택 화면으로 이동하지 않고 이 역만 취소된다.
            if (showClear)
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onClear,
                child: Padding(
                  padding: const EdgeInsets.only(left: AppSpacing.space4),
                  child: Icon(
                    Icons.close,
                    size: AppIconSize.sm,
                    color: Colors.grey[500],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
