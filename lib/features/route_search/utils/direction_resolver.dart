import '../../../domain/entities/route_result.dart';

/// RouteSegment의 역 ID 순서로 하행/외선 여부를 결정한다.
///
/// - 일반 노선: 숫자 ID가 증가하면 하행(index 1), 감소하면 상행(index 0)
/// - 2호선 순환: 첫 두 역 ID 비교 + 순환 경계(201↔243) 처리
bool isDownDirection(RouteSegment segment) {
  if (segment.stations.length < 2) return false;

  final firstNum = _parseNumericId(segment.stations.first.id);
  final lastNum = _parseNumericId(segment.stations.last.id);
  if (firstNum == null || lastNum == null) return false;

  if (segment.lineId == '2') {
    return _isLine2Down(segment, firstNum);
  }

  // 일반 노선: ID 증가 = 하행
  return lastNum > firstNum;
}

/// 2호선 순환 방향 결정
///
/// 내선(상행): ID 증가 방향 (201→202→...→243→201)
/// 외선(하행): ID 감소 방향 (243→242→...→201→243)
/// 순환 경계(201↔243)에서 |step| > 21이면 반전
bool _isLine2Down(RouteSegment segment, int firstNum) {
  final secondNum = _parseNumericId(segment.stations[1].id);
  if (secondNum == null) return false;

  final step = secondNum - firstNum;
  // step > 0이고 작은 폭: 내선(상행), step < 0이고 작은 폭: 외선(하행)
  // 순환 경계를 넘으면 반전 (|step| > 21이면 반대 방향)
  if (step.abs() > 21) {
    // 순환 경계: step > 21이면 외선, step < -21이면 내선
    return step > 0;
  }
  return step < 0;
}

/// ArrivalInfo.direction 문자열이 하행/외선인지 판별한다.
bool isDownDirectionString(String direction) {
  return direction == '하행' || direction == '외선';
}

/// 역 ID에서 숫자 부분을 추출한다.
/// 예: "201" → 201, "D01" → 1, "K32" → 32
int? _parseNumericId(String id) {
  final match = RegExp(r'(\d+)$').firstMatch(id);
  if (match == null) return null;
  return int.tryParse(match.group(1)!);
}
