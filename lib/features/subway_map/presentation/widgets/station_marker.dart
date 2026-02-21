import 'package:flutter/material.dart';

import '../../../../core/constants/line_colors.dart';
import '../../../../domain/entities/station.dart';

class StationMarker extends StatelessWidget {
  final Station station;
  final bool isSelected;
  final bool isDeparture;
  final bool isArrival;
  final bool isOnRoute;
  final VoidCallback? onTap;

  const StationMarker({
    super.key,
    required this.station,
    this.isSelected = false,
    this.isDeparture = false,
    this.isArrival = false,
    this.isOnRoute = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = lineColors[station.lineId] ?? Colors.grey;
    final markerSize = station.isTransfer ? 14.0 : 10.0;

    return Semantics(
      label: '${station.name}역${station.isTransfer ? ' 환승역' : ''}',
      button: true,
      child: GestureDetector(
        onTap: onTap,
        child: SizedBox(
        width: markerSize + 4,
        height: markerSize + 4,
        child: CustomPaint(
          painter: _StationMarkerPainter(
            color: color,
            isTransfer: station.isTransfer,
            isSelected: isSelected,
            isDeparture: isDeparture,
            isArrival: isArrival,
            isOnRoute: isOnRoute,
            markerSize: markerSize,
          ),
        ),
      ),
      ),
    );
  }
}

class _StationMarkerPainter extends CustomPainter {
  final Color color;
  final bool isTransfer;
  final bool isSelected;
  final bool isDeparture;
  final bool isArrival;
  final bool isOnRoute;
  final double markerSize;

  _StationMarkerPainter({
    required this.color,
    required this.isTransfer,
    required this.isSelected,
    required this.isDeparture,
    required this.isArrival,
    required this.isOnRoute,
    required this.markerSize,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = markerSize / 2;

    if (isDeparture) {
      _drawHighlightCircle(canvas, center, radius + 4, Colors.blue);
    } else if (isArrival) {
      _drawHighlightCircle(canvas, center, radius + 4, Colors.red);
    } else if (isSelected) {
      _drawHighlightCircle(canvas, center, radius + 3, Colors.orange);
    } else if (isOnRoute) {
      _drawHighlightCircle(canvas, center, radius + 2, color.withValues(alpha: 0.3));
    }

    if (isTransfer) {
      canvas.drawCircle(
        center,
        radius,
        Paint()
          ..color = Colors.white
          ..style = PaintingStyle.fill,
      );
      canvas.drawCircle(
        center,
        radius,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
    } else {
      canvas.drawCircle(
        center,
        radius,
        Paint()
          ..color = color
          ..style = PaintingStyle.fill,
      );
    }
  }

  void _drawHighlightCircle(
    Canvas canvas,
    Offset center,
    double radius,
    Color highlightColor,
  ) {
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = highlightColor
        ..style = PaintingStyle.fill,
    );
  }

  @override
  bool shouldRepaint(covariant _StationMarkerPainter oldDelegate) {
    return color != oldDelegate.color ||
        isTransfer != oldDelegate.isTransfer ||
        isSelected != oldDelegate.isSelected ||
        isDeparture != oldDelegate.isDeparture ||
        isArrival != oldDelegate.isArrival ||
        isOnRoute != oldDelegate.isOnRoute;
  }
}
