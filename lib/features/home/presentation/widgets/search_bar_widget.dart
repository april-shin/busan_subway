import 'package:flutter/material.dart';

import '../../../../core/constants/line_colors.dart';
import '../../../../domain/entities/station.dart';

class RouteSearchBar extends StatelessWidget {
  final Station? departure;
  final Station? arrival;
  final VoidCallback? onDepartureTap;
  final VoidCallback? onArrivalTap;
  final VoidCallback? onSwap;
  final VoidCallback? onSearchRoute;

  const RouteSearchBar({
    super.key,
    this.departure,
    this.arrival,
    this.onDepartureTap,
    this.onArrivalTap,
    this.onSwap,
    this.onSearchRoute,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 4,
            offset: const Offset(0, 2),
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
                ),
                const SizedBox(height: 4),
                _StationField(
                  label: '도착',
                  station: arrival,
                  icon: Icons.place,
                  iconColor: Colors.red,
                  onTap: onArrivalTap,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: const Icon(Icons.swap_vert),
                onPressed: onSwap,
                tooltip: '출발/도착 바꾸기',
              ),
              if (onSearchRoute != null)
                IconButton(
                  icon: const Icon(Icons.search),
                  onPressed: onSearchRoute,
                  tooltip: '경로 검색',
                  color: Theme.of(context).colorScheme.primary,
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

  const _StationField({
    required this.label,
    this.station,
    required this.icon,
    required this.iconColor,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color =
        station != null ? lineColors[station!.lineId] ?? Colors.grey : null;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Icon(icon, size: 16, color: iconColor),
            const SizedBox(width: 8),
            if (station != null) ...[
              if (color != null)
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                  ),
                ),
              const SizedBox(width: 4),
              Text(
                station!.name,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ] else
              Text(
                '$label역을 선택하세요',
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.grey[500],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
