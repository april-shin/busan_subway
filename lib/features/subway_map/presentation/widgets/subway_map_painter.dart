import 'package:flutter/material.dart';

import '../../../../core/constants/line_colors.dart';
import '../../../../domain/entities/station.dart';
import '../../../../domain/entities/connection.dart';

class SubwayMapPainter extends CustomPainter {
  final List<Station> stations;
  final List<Connection> connections;
  final Set<String> routeStationIds;
  final String? routeLineId;

  SubwayMapPainter({
    required this.stations,
    required this.connections,
    this.routeStationIds = const {},
    this.routeLineId,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final stationMap = {for (final s in stations) s.id: s};

    for (final connection in connections) {
      if (connection.isTransfer) continue;

      final from = stationMap[connection.fromStationId];
      final to = stationMap[connection.toStationId];
      if (from == null || to == null) continue;

      final color = lineColors[connection.lineId] ?? Colors.grey;
      final isOnRoute = routeStationIds.contains(from.id) &&
          routeStationIds.contains(to.id);

      final paint = Paint()
        ..color = isOnRoute ? color : color.withValues(alpha: 0.4)
        ..strokeWidth = isOnRoute ? 4 : 2
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round;

      canvas.drawLine(
        Offset(from.svgX, from.svgY),
        Offset(to.svgX, to.svgY),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant SubwayMapPainter oldDelegate) {
    return stations != oldDelegate.stations ||
        connections != oldDelegate.connections ||
        routeStationIds != oldDelegate.routeStationIds;
  }
}
