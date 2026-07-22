import 'dart:math';

import 'package:flutter/material.dart';

import '../../../../domain/entities/arrival_info.dart';

class ArrivalCard extends StatelessWidget {
  final ArrivalInfo arrival;

  const ArrivalCard({super.key, required this.arrival});

  @override
  Widget build(BuildContext context) {
    final isExpress = arrival.trainType == '급행';

    // receivedAt 기준 경과 시간을 빼서 실시간 카운트다운
    final int? liveSeconds;
    if (arrival.arrivalSeconds != null) {
      final elapsed =
          DateTime.now().difference(arrival.receivedAt).inSeconds;
      liveSeconds = max(0, arrival.arrivalSeconds! - elapsed);
    } else {
      liveSeconds = null;
    }

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        arrival.trainLineNm,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      if (isExpress) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.red,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            '급행',
                            // bodySmall(12px) — route_result_screen 급행 배지와 통일
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    arrival.arrivalMessage,
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: Colors.grey[600],
                    ),
                  ),
                ],
              ),
            ),
            if (liveSeconds != null)
              _CountdownBadge(
                seconds: liveSeconds,
                isEstimated: arrival.isEstimated,
              ),
          ],
        ),
      ),
    );
  }
}

class _CountdownBadge extends StatelessWidget {
  final int seconds;
  final bool isEstimated;

  const _CountdownBadge({
    required this.seconds,
    this.isEstimated = false,
  });

  @override
  Widget build(BuildContext context) {
    final minutes = seconds ~/ 60;
    final remainingSeconds = seconds % 60;
    final isImminent = !isEstimated && seconds <= 60;

    final Color backgroundColor;
    final Color textColor;
    final Color subTextColor;

    if (isEstimated) {
      backgroundColor = Colors.orange[50]!;
      textColor = Colors.orange[800]!;
      subTextColor = Colors.orange[400]!;
    } else if (isImminent) {
      backgroundColor = Colors.red[50]!;
      textColor = Colors.red;
      subTextColor = Colors.red[300]!;
    } else {
      backgroundColor = Colors.blue[50]!;
      textColor = Colors.blue;
      subTextColor = Colors.blue[300]!;
    }

    final String mainText;
    if (isEstimated) {
      mainText = '약 ${minutes > 0 ? '$minutes분' : '$remainingSeconds초'}';
    } else {
      mainText = minutes > 0 ? '$minutes분' : '$remainingSeconds초';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            mainText,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              color: textColor,
            ),
          ),
          if (!isEstimated && minutes > 0)
            Text(
              '$remainingSeconds초',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: subTextColor,
              ),
            ),
        ],
      ),
    );
  }
}
