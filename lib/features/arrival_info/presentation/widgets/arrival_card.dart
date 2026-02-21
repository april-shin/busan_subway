import 'package:flutter/material.dart';

import '../../../../domain/entities/arrival_info.dart';

class ArrivalCard extends StatelessWidget {
  final ArrivalInfo arrival;

  const ArrivalCard({super.key, required this.arrival});

  @override
  Widget build(BuildContext context) {
    final isExpress = arrival.trainType == '급행';

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
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (isExpress) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 1,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.red,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text(
                            '급행',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    arrival.arrivalMessage,
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.grey[600],
                    ),
                  ),
                ],
              ),
            ),
            if (arrival.arrivalSeconds != null)
              _CountdownBadge(seconds: arrival.arrivalSeconds!),
          ],
        ),
      ),
    );
  }
}

class _CountdownBadge extends StatelessWidget {
  final int seconds;

  const _CountdownBadge({required this.seconds});

  @override
  Widget build(BuildContext context) {
    final minutes = seconds ~/ 60;
    final remainingSeconds = seconds % 60;
    final isImminent = seconds <= 60;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: isImminent ? Colors.red[50] : Colors.blue[50],
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            minutes > 0 ? '$minutes분' : '$remainingSeconds초',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: isImminent ? Colors.red : Colors.blue,
            ),
          ),
          if (minutes > 0)
            Text(
              '$remainingSeconds초',
              style: TextStyle(
                fontSize: 11,
                color: isImminent ? Colors.red[300] : Colors.blue[300],
              ),
            ),
        ],
      ),
    );
  }
}
