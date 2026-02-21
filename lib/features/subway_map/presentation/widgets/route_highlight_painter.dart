import 'package:flutter/material.dart';

import '../../../../core/constants/line_colors.dart';
import '../../../../domain/entities/connection.dart';
import '../../../../domain/entities/station.dart';

/// 경로 하이라이트 오버레이.
///
/// 경로가 활성화되면 반투명 흰색 오버레이 위에 경로 구간만 강조 표시한다.
/// [CustomPaint]으로 렌더링되어 터치 이벤트를 소비하지 않는다.
class RouteHighlightPainter extends CustomPainter {
  final List<Station> stations;
  final List<Connection> connections;
  final Set<String> routeStationIds;
  final Map<String, Station> _stationMap;

  RouteHighlightPainter({
    required this.stations,
    required this.connections,
    required this.routeStationIds,
  }) : _stationMap = {for (final s in stations) s.id: s};

  @override
  void paint(Canvas canvas, Size size) {
    if (routeStationIds.isEmpty) return;

    // 반투명 흰색 오버레이
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()..color = Colors.white.withValues(alpha: 0.6),
    );

    final linePaint = Paint()
      ..strokeWidth = 5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    // 경로 구간 강조 표시
    for (final connection in connections) {
      if (connection.isTransfer) continue;

      final from = _stationMap[connection.fromStationId];
      final to = _stationMap[connection.toStationId];
      if (from == null || to == null) continue;

      final isOnRoute = routeStationIds.contains(from.id) &&
          routeStationIds.contains(to.id);
      if (!isOnRoute) continue;

      linePaint.color = lineColors[connection.lineId] ?? Colors.grey;
      canvas.drawLine(
        Offset(from.svgX, from.svgY),
        Offset(to.svgX, to.svgY),
        linePaint,
      );
    }

    // 경로 위 역 마커 다시 그리기
    final fillPaint = Paint()..style = PaintingStyle.fill;
    final strokePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    for (final stationId in routeStationIds) {
      final station = _stationMap[stationId];
      if (station == null) continue;

      final color = lineColors[station.lineId] ?? Colors.grey;
      final radius = station.isTransfer ? 5.0 : 3.5;
      final center = Offset(station.svgX, station.svgY);

      if (station.isTransfer) {
        fillPaint.color = Colors.white;
        canvas.drawCircle(center, radius, fillPaint);
        strokePaint.color = color;
        canvas.drawCircle(center, radius, strokePaint);
      } else {
        fillPaint.color = color;
        canvas.drawCircle(center, radius, fillPaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant RouteHighlightPainter oldDelegate) {
    return routeStationIds != oldDelegate.routeStationIds ||
        stations != oldDelegate.stations ||
        connections != oldDelegate.connections;
  }
}
