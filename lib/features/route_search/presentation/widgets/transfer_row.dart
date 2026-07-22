import 'package:flutter/material.dart';

import '../../../../core/theme/tokens/app_dimensions.dart';
import '../../../../domain/entities/transfer_guide.dart';

/// 점선 세로선 높이.
const double _dashedLineHeight = 36.0;

/// 환승 정보 한 행 UI.
///
/// 1행 레이아웃: `🚶 환승 도보 N분 · 빠른 환승 X-Y · 내리는문 왼쪽`
///
/// 가이드(`guide`) 데이터가 있으면 같은 행에 ` · ` 구분자로 정보를 덧붙인다.
/// 데이터가 전혀 없으면 `🚶 환승 도보 N분`만 표시.
class TransferRow extends StatelessWidget {
  final int transferMinutes;
  final TransferGuide? guide;

  const TransferRow({
    super.key,
    required this.transferMinutes,
    this.guide,
  });

  @override
  Widget build(BuildContext context) {
    final segments = _buildTextSegments(transferMinutes, guide);
    final note = guide?.note;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.space4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const SizedBox(width: 54),
          SizedBox(
            width: 20,
            height: _dashedLineHeight,
            child: CustomPaint(
              painter: DashedLinePainter(color: Colors.orange.shade700),
            ),
          ),
          const SizedBox(width: AppSpacing.space8),
          Icon(Icons.directions_walk, size: 14, color: Colors.orange[700]),
          const SizedBox(width: AppSpacing.space4),
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: segments.join(' · '),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Colors.orange[700],
                          fontWeight: FontWeight.w500,
                        ),
                  ),
                  if (note != null && note.isNotEmpty) ...[
                    TextSpan(
                      text: '  $note',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: Colors.grey[600],
                          ),
                    ),
                  ],
                ],
              ),
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
          ),
        ],
      ),
    );
  }
}

/// 점선 세로선을 그리는 커스텀 페인터.
class DashedLinePainter extends CustomPainter {
  final Color color;

  const DashedLinePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    const dashHeight = 4.0;
    const dashGap = 3.0;
    final centerX = size.width / 2;
    var startY = 0.0;

    while (startY < size.height) {
      canvas.drawLine(
        Offset(centerX, startY),
        Offset(centerX, (startY + dashHeight).clamp(0, size.height)),
        paint,
      );
      startY += dashHeight + dashGap;
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// 텍스트 세그먼트 조립.
///
/// 우선순위 순서로 추가하며, 최종적으로 ` · `로 join.
/// 1. "환승 도보 N분" — 단, N==0 이면 "같은 승강장 환승"
///    (예: 9호선 완행↔급행 모드 전환은 같은 플랫폼이라 도보 0분)
/// 2. "빠른 환승 X-Y" 또는 "X번 칸" 또는 "Y번 문" (객차/문 정보)
/// 3. "내리는문 왼쪽" 또는 "내리는문 오른쪽" (방향 정보)
List<String> _buildTextSegments(int minutes, TransferGuide? guide) {
  final firstLabel =
      minutes == 0 ? '같은 승강장 환승' : '환승 도보 $minutes분';
  final segments = <String>[firstLabel];
  if (guide == null) return segments;

  final carDoor = _carDoorLabel(guide.car, guide.door);
  if (carDoor != null) segments.add(carDoor);

  final sideLabel = _doorSideLabel(guide.doorSide);
  if (sideLabel != null) segments.add(sideLabel);

  return segments;
}

String? _carDoorLabel(int? car, int? door) {
  if (car != null && door != null) return '빠른 환승 $car-$door';
  if (car != null) return '$car번 칸';
  if (door != null) return '$door번 문';
  return null;
}

String? _doorSideLabel(DoorSide? side) {
  switch (side) {
    case DoorSide.left:
      return '내리는문 왼쪽';
    case DoorSide.right:
      return '내리는문 오른쪽';
    case null:
      return null;
  }
}
