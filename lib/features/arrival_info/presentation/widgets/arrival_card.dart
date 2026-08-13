import 'package:flutter/material.dart';

import '../../../../core/utils/live_arrival_seconds.dart';
import '../../../../domain/entities/arrival_info.dart';

class ArrivalCard extends StatelessWidget {
  final ArrivalInfo arrival;

  const ArrivalCard({super.key, required this.arrival});

  @override
  Widget build(BuildContext context) {
    final isExpress = arrival.trainType == '급행';

    // receivedAt 기준 경과 시간을 빼서 실시간 카운트다운.
    // liveSeconds == null 은 "알 수 없음"이며 0초와 구분해 표시한다.
    final liveSeconds = liveArrivalSeconds(arrival);

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

/// 이 값 이하의 잔여초는 숫자 대신 "곧 도착"으로 표기한다.
///
/// 지도 말풍선의 `formatArrivalBubbleText`(tool/build_map_html.dart)와 같은 값을
/// 유지해야 두 화면의 표기가 어긋나지 않는다. 한쪽만 바꾸지 말 것.
const int _imminentTextThresholdSeconds = 30;

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
      // 추정값은 "곧 도착"으로 단정하지 않는다 — 약 표기로 불확실성을 유지.
      mainText = '약 ${minutes > 0 ? '$minutes분' : '$remainingSeconds초'}';
    } else if (seconds <= _imminentTextThresholdSeconds) {
      // 지도 말풍선(formatArrivalBubbleText)과 같은 임계로 맞춘다.
      mainText = '곧 도착';
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
