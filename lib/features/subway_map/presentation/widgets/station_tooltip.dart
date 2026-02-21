import 'package:flutter/material.dart';

import '../../../../core/constants/line_colors.dart';
import '../../../../domain/entities/station.dart';

class StationTooltip extends StatelessWidget {
  final Station station;
  final VoidCallback? onSetDeparture;
  final VoidCallback? onSetArrival;
  final VoidCallback? onViewArrivalInfo;
  final VoidCallback? onDismiss;

  const StationTooltip({
    super.key,
    required this.station,
    this.onSetDeparture,
    this.onSetArrival,
    this.onViewArrivalInfo,
    this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final color = lineColors[station.lineId] ?? Colors.grey;
    final lineName = lineNames[station.lineId] ?? station.lineId;

    return Card(
      elevation: 8,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    lineName,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  station.name,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(width: 4),
                GestureDetector(
                  onTap: onDismiss,
                  child:
                      const Icon(Icons.close, size: 18, color: Colors.grey),
                ),
              ],
            ),
            if (station.isTransfer && station.transferLines.length > 1) ...[
              const SizedBox(height: 4),
              Wrap(
                spacing: 4,
                children: station.transferLines
                    .where((l) => l != station.lineId)
                    .map((l) => Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 1),
                          decoration: BoxDecoration(
                            color: lineColors[l] ?? Colors.grey,
                            borderRadius: BorderRadius.circular(3),
                          ),
                          child: Text(
                            lineNames[l] ?? l,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 9,
                            ),
                          ),
                        ))
                    .toList(),
              ),
            ],
            const SizedBox(height: 8),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _ActionButton(
                  icon: Icons.trip_origin,
                  label: '출발',
                  color: Colors.blue,
                  onTap: onSetDeparture,
                ),
                const SizedBox(width: 8),
                _ActionButton(
                  icon: Icons.place,
                  label: '도착',
                  color: Colors.red,
                  onTap: onSetArrival,
                ),
                const SizedBox(width: 8),
                _ActionButton(
                  icon: Icons.access_time,
                  label: '도착정보',
                  color: Colors.green,
                  onTap: onViewArrivalInfo,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback? onTap;

  const _ActionButton({
    required this.icon,
    required this.label,
    required this.color,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(fontSize: 10, color: color),
          ),
        ],
      ),
    );
  }
}
