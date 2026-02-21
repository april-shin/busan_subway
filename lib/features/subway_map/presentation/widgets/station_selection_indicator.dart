import 'package:flutter/material.dart';

import '../../../../domain/entities/station.dart';

/// 출발/도착역 선택 표시 위젯.
///
/// 출발역은 파란색, 도착역은 빨간색 원형 링으로 표시한다.
/// SVG 지도 위에 [Positioned]로 배치되어 svgX/svgY 좌표를 그대로 사용한다.
class StationSelectionIndicator extends StatelessWidget {
  static const indicatorSize = 24.0;
  static const indicatorOffset = indicatorSize / 2;

  final Station station;
  final bool isDeparture;

  const StationSelectionIndicator({
    super.key,
    required this.station,
    required this.isDeparture,
  });

  @override
  Widget build(BuildContext context) {
    final color = isDeparture ? Colors.blue : Colors.red;
    final label = isDeparture ? '출발역: ${station.name}' : '도착역: ${station.name}';

    return Semantics(
      label: label,
      child: SizedBox(
        width: indicatorSize,
        height: indicatorSize,
        child: CustomPaint(
          painter: _SelectionRingPainter(color: color),
        ),
      ),
    );
  }
}

class _SelectionRingPainter extends CustomPainter {
  final Color color;

  _SelectionRingPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final outerRadius = size.width / 2;
    final innerRadius = outerRadius - 3;

    // 외곽 반투명 원
    canvas.drawCircle(
      center,
      outerRadius,
      Paint()
        ..color = color.withValues(alpha: 0.2)
        ..style = PaintingStyle.fill,
    );

    // 링
    canvas.drawCircle(
      center,
      innerRadius,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5,
    );
  }

  @override
  bool shouldRepaint(covariant _SelectionRingPainter oldDelegate) {
    return color != oldDelegate.color;
  }
}
