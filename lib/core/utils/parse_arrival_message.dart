/// arvlMsg2에서 시간 정보를 파싱한다.
///
/// "3분 30초" → 210, "2분" → 120, "1분 후" → 60, "2분 30초 후" → 150
/// 시간 정보가 없으면 null을 반환한다.
int? parseTimeFromMessage(String message) {
  if (message.isEmpty) return null;

  final match = RegExp(r'(\d+)분\s*(?:(\d+)초)?').firstMatch(message);
  if (match == null) return null;

  final minutes = int.parse(match.group(1)!);
  final seconds = match.group(2) != null ? int.parse(match.group(2)!) : 0;
  return minutes * 60 + seconds;
}

/// arvlMsg2에서 역 수 정보를 파싱한다.
///
/// "전역 출발" → (count: 1, status: "출발")
/// "3번째 전역 도착" → (count: 3, status: "도착")
/// "[4]번째 전역 (판교)" → (count: 4, status: "")
/// "전역" → (count: 1, status: "")
/// 역 수 정보가 없으면 null을 반환한다.
({int count, String status})? parseStationCount(String message) {
  if (message.isEmpty) return null;

  // API 형식 두 가지:
  // 1) "3번째 전역 도착", "전역 출발"
  // 2) "[4]번째 전역 (판교)", "[2]번째 전역"
  final match = RegExp(
    r'^(?:\[?(\d+)\]?번째 )?전역(?:\s*\(.+\))?(?:\s+(출발|도착|진입))?$',
  ).firstMatch(message);
  if (match == null) return null;

  final count = match.group(1) != null ? int.parse(match.group(1)!) : 1;
  final status = match.group(2) ?? '';
  return (count: count, status: status);
}
