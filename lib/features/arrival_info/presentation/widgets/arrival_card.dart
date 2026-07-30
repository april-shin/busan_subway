import 'dart:math';

import 'package:flutter/material.dart';

import '../../../../core/constants/api_constants.dart';
import '../../../../domain/entities/arrival_info.dart';

/// 표시할 잔여초. null 이면 **알 수 없음**(0초와 구분).
///
/// [ArrivalInfo.arrivalSeconds] 의 세 상태를 표시 규칙으로 옮긴다:
/// - 양수 → `receivedAt` 기준 경과분을 차감한 잔여초. 차감 결과가 0 이하이면 예정
///   시각이 이미 지난 것이므로 "0초"가 아니라 알 수 없음이다.
/// - 0("그 역에 있음" 상태) → 데이터 경과가 [ApiConstants.arrivalStateGrace] 이내일
///   때만 0초. 그 이상 낡았으면 이미 떠난 열차이므로 알 수 없음.
/// - null → 알 수 없음.
///
/// 예전에는 `max(0, seconds - elapsed)` 로 모든 만료·무효 값을 0초로 뭉개, 갱신이
/// 수 분 지연되는 노선(GTX-A·서해선)에서 전 열차가 "0초"로 보였다.
int? _liveSeconds(ArrivalInfo arrival) {
  final seconds = arrival.arrivalSeconds;
  if (seconds == null) return null;

  // 시계 오차·미래 recptnDt 로 음수 경과가 나오면 카운트다운이 부풀지 않도록 0 하한.
  final elapsed =
      max(0, DateTime.now().difference(arrival.receivedAt).inSeconds);

  if (seconds > 0) {
    final remaining = seconds - elapsed;
    return remaining > 0 ? remaining : null;
  }

  // seconds == 0: 잔여초가 아닌 "역에 있음" 상태 → 신선할 때만 유효.
  return elapsed <= ApiConstants.arrivalStateGrace.inSeconds ? 0 : null;
}

class ArrivalCard extends StatelessWidget {
  final ArrivalInfo arrival;

  const ArrivalCard({super.key, required this.arrival});

  @override
  Widget build(BuildContext context) {
    final isExpress = arrival.trainType == '급행';

    // receivedAt 기준 경과 시간을 빼서 실시간 카운트다운.
    // liveSeconds == null 은 "알 수 없음"이며 0초와 구분해 표시한다.
    final liveSeconds = _liveSeconds(arrival);

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
              )
            else
              const _UnknownBadge(),
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

/// 잔여시간을 알 수 없을 때의 배지.
///
/// "0초"(=지금 역에 있음)와 명확히 구분하기 위한 별도 표시. 배지를 아예 그리지
/// 않으면 로딩 실패와 구별되지 않으므로, 무채색으로 상태를 명시한다. 이 카드의
/// 방면·도착 메시지(`arvlMsg2`, 예: "서울역 출발")는 그대로 보이므로 사용자는
/// 열차의 위치는 알 수 있고 "몇 분 뒤"만 판단 보류된다.
class _UnknownBadge extends StatelessWidget {
  const _UnknownBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        '정보 없음',
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
          color: Colors.grey[600],
        ),
      ),
    );
  }
}
