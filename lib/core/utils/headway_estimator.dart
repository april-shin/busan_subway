import '../../domain/entities/line_schedule.dart';

/// 배차간격 추출 시 사용할 평일 평시 시간대 (분 단위)
const int _peakWindowStart = 10 * 60; // 10:00
const int _peakWindowEnd = 16 * 60; // 16:00

/// 배차 데이터가 없을 때 사용할 기본값 (3분).
const int _defaultHeadwaySeconds = 180;

/// [LineSchedule]에서 평일 평시(10:00~16:00) 평균 배차간격을 초 단위로 추출한다.
///
/// 알고리즘:
/// 1. 평일 스케줄(`weekday`)의 `periods`에서 평시 시간대와 겹치는 항목만 선택
/// 2. 각 항목의 `headwayMinutes` 평균(가중치 없는 산술평균) → 초 변환
/// 3. 평시 항목이 없으면 평일 전체 `periods` 평균으로 폴백
/// 4. 평일 `periods`도 비어있으면 [_defaultHeadwaySeconds] (3분) 반환
int estimateHeadwaySeconds(LineSchedule schedule) {
  final weekday = schedule.weekday;

  // 1) 평시 시간대와 겹치는 periods 평균
  final peakHeadways = <int>[];
  for (final p in weekday.periods) {
    if (_overlapsPeakWindow(p)) {
      peakHeadways.add(p.headwayMinutes);
    }
  }
  if (peakHeadways.isNotEmpty) {
    final avgMin = peakHeadways.reduce((a, b) => a + b) / peakHeadways.length;
    return (avgMin * 60).round();
  }

  // 2) 평시 항목 없음 → 전체 평일 periods 평균
  if (weekday.periods.isNotEmpty) {
    final all = weekday.periods.map((p) => p.headwayMinutes).toList();
    final avgMin = all.reduce((a, b) => a + b) / all.length;
    return (avgMin * 60).round();
  }

  // 3) 폴백
  return _defaultHeadwaySeconds;
}

/// 여러 노선의 배차간격 맵을 일괄 생성한다.
///
/// 키: lineId (실제 노선과 가상 노선 둘 다 동일 lineId 사용 — `9` 노선의
/// 배차간격은 `9` 키로만 저장된다. 그래프 빌드 시 `9E`/`9M` edge에서도
/// 베이스 lineId(`9`)로 조회한다.)
Map<String, int> buildHeadwayMap(Map<String, LineSchedule> schedules) {
  return {
    for (final entry in schedules.entries)
      entry.key: estimateHeadwaySeconds(entry.value),
  };
}

bool _overlapsPeakWindow(TimePeriod p) {
  final start = p.startMinutes;
  final end = p.endMinutes;
  // 빈 구간 또는 비정상 구간은 무시
  if (end <= start) return false;
  return start < _peakWindowEnd && end > _peakWindowStart;
}
