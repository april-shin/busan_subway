import 'package:flutter_test/flutter_test.dart';
import 'package:seoul_subway/domain/entities/line_schedule.dart';

// TimetableDataSource의 파싱 로직은 rootBundle에 의존하므로
// 파싱 함수를 직접 테스트하기 어렵다.
// 대신 컴팩트 JSON → LineSchedule 변환 로직을 단위 테스트한다.

/// 역별 출발시각 맵을 파싱한다.
/// [key]: 완행 't' 또는 급행 'tE'.
Map<String, List<int>>? parseStationDepartures(
  Map<String, dynamic> day,
  int dirIndex,
  String key,
) {
  final tRaw = day[key] as Map<String, dynamic>?;
  if (tRaw == null || tRaw.isEmpty) return null;

  final result = <String, List<int>>{};
  for (final entry in tRaw.entries) {
    final dirList = entry.value as List;
    if (dirIndex >= dirList.length) continue;
    final minutes = dirList[dirIndex];
    if (minutes == null) continue;
    result[entry.key] = (minutes as List).cast<int>();
  }

  return result.isEmpty ? null : result;
}

/// 컴팩트 JSON의 DaySchedule 파싱 테스트용 헬퍼
DaySchedule parseDayScheduleAt(Map<String, dynamic> day, int dirIndex) {
  final f = day['f'] as List;
  final l = day['l'] as List;
  final periods = (day['p'] as List).map((p) {
    final arr = p as List;
    return TimePeriod(
      start: arr[0] as String,
      end: arr[1] as String,
      headwayMinutes: arr[2] as int,
    );
  }).toList();
  final stationDepartures = parseStationDepartures(day, dirIndex, 't');
  final expressStationDepartures =
      parseStationDepartures(day, dirIndex, 'tE');
  return DaySchedule(
    firstTrain: f[dirIndex] as String,
    lastTrain: l[dirIndex] as String,
    periods: periods,
    stationDepartures: stationDepartures,
    expressStationDepartures: expressStationDepartures,
  );
}

DaySchedule? parseDayScheduleDown(Map<String, dynamic> day) {
  final f = day['f'] as List;
  final l = day['l'] as List;
  if (f.length < 2) return null;

  final hasStationDepartures =
      day.containsKey('t') || day.containsKey('tE');
  final hasDedicatedPeriods = day.containsKey('pD');

  // pD/t/tE가 없고 첫차/막차도 동일하면 null (상행과 동일)
  if (!hasDedicatedPeriods && !hasStationDepartures &&
      f[0] == f[1] && l[0] == l[1]) {
    return null;
  }
  final periodsRaw = day['pD'] as List? ?? day['p'] as List;
  final periods = (periodsRaw).map((p) {
    final arr = p as List;
    return TimePeriod(
      start: arr[0] as String,
      end: arr[1] as String,
      headwayMinutes: arr[2] as int,
    );
  }).toList();
  final stationDepartures = parseStationDepartures(day, 1, 't');
  final expressStationDepartures = parseStationDepartures(day, 1, 'tE');
  return DaySchedule(
    firstTrain: f[1] as String,
    lastTrain: l[1] as String,
    periods: periods,
    stationDepartures: stationDepartures,
    expressStationDepartures: expressStationDepartures,
  );
}

LineSchedule parseCompactSchedule(Map<String, dynamic> json) {
  final lineId = json['id'] as String;
  final wd = json['wd'] as Map<String, dynamic>;
  final we = (json['we'] as Map<String, dynamic>?) ?? wd;
  return LineSchedule(
    lineId: lineId,
    weekday: parseDayScheduleAt(wd, 0),
    weekend: parseDayScheduleAt(we, 0),
    weekdayDown: parseDayScheduleDown(wd),
    weekendDown: parseDayScheduleDown(we),
  );
}

void main() {
  group('컴팩트 JSON 파싱', () {
    test('기본 컴팩트 포맷을 올바르게 파싱한다', () {
      final json = {
        'id': '2',
        'wd': {
          'f': ['05:00', '05:02'],
          'l': ['00:00', '23:55'],
          'p': [
            ['05:00', '09:00', 3],
            ['09:00', '00:00', 5],
          ],
        },
        'we': {
          'f': ['05:30', '05:32'],
          'l': ['23:40', '23:35'],
          'p': [
            ['05:30', '23:40', 6],
          ],
        },
      };

      final schedule = parseCompactSchedule(json);

      expect(schedule.lineId, '2');
      // 상행 (index 0)
      expect(schedule.weekday.firstTrain, '05:00');
      expect(schedule.weekday.lastTrain, '00:00');
      expect(schedule.weekday.periods.length, 2);
      expect(schedule.weekday.periods[0].headwayMinutes, 3);
      // 하행 (index 1)
      expect(schedule.weekdayDown, isNotNull);
      expect(schedule.weekdayDown!.firstTrain, '05:02');
      expect(schedule.weekdayDown!.lastTrain, '23:55');
      // 주말 상행
      expect(schedule.weekend.firstTrain, '05:30');
      // 주말 하행
      expect(schedule.weekendDown, isNotNull);
      expect(schedule.weekendDown!.firstTrain, '05:32');
      expect(schedule.weekendDown!.lastTrain, '23:35');
    });

    test('pD(하행 전용 배차간격)가 있으면 하행에 적용된다', () {
      final json = {
        'id': '1',
        'wd': {
          'f': ['05:20', '05:18'],
          'l': ['00:48', '00:42'],
          'p': [
            ['05:00', '09:00', 4],
            ['09:00', '00:00', 5],
          ],
          'pD': [
            ['05:00', '09:00', 5],
            ['09:00', '00:00', 6],
          ],
        },
        'we': {
          'f': ['05:20', '05:18'],
          'l': ['00:00', '23:55'],
          'p': [
            ['05:00', '00:00', 7],
          ],
        },
      };

      final schedule = parseCompactSchedule(json);

      // 상행 배차간격
      expect(schedule.weekday.periods[0].headwayMinutes, 4);
      // 하행 전용 배차간격 (pD)
      expect(schedule.weekdayDown!.periods[0].headwayMinutes, 5);
      expect(schedule.weekdayDown!.periods[1].headwayMinutes, 6);
    });

    test('we 키 없으면 wd로 폴백 (평일=주말 동일)', () {
      final json = {
        'id': '의정부',
        'wd': {
          'f': ['05:16', '05:14'],
          'l': ['00:26', '00:20'],
          'p': [
            ['05:00', '06:00', 10],
            ['06:00', '09:00', 4],
          ],
        },
        // we 없음
      };

      final schedule = parseCompactSchedule(json);
      expect(schedule.lineId, '의정부');
      // 주말 = 평일 폴백
      expect(schedule.weekend.firstTrain, '05:16');
      expect(schedule.weekend.periods.length, 2);
      expect(schedule.weekend.periods[1].headwayMinutes, 4);
    });

    test('상하행 첫차/막차 동일 + pD 없으면 하행 null (폴백)', () {
      final json = {
        'id': '경의중앙',
        'wd': {
          'f': ['05:00', '05:00'],
          'l': ['23:30', '23:30'],
          'p': [
            ['05:00', '23:30', 15],
          ],
        },
        'we': {
          'f': ['05:30', '05:30'],
          'l': ['23:00', '23:00'],
          'p': [
            ['05:30', '23:00', 15],
          ],
        },
      };

      final schedule = parseCompactSchedule(json);
      // 상하행 동일 → null로 폴백
      expect(schedule.weekdayDown, isNull);
      expect(schedule.weekendDown, isNull);
    });

    test('f 배열이 1개뿐이면 하행 데이터 null', () {
      final json = {
        'id': 'test',
        'wd': {
          'f': ['05:00'],
          'l': ['23:00'],
          'p': [
            ['05:00', '23:00', 5],
          ],
        },
        'we': {
          'f': ['05:30'],
          'l': ['23:00'],
          'p': [
            ['05:30', '23:00', 8],
          ],
        },
      };

      final schedule = parseCompactSchedule(json);
      expect(schedule.weekdayDown, isNull);
      expect(schedule.weekendDown, isNull);
    });

    test('t 키가 있으면 역별 시간표를 파싱한다', () {
      final json = {
        'id': '김포골드',
        'wd': {
          'f': ['05:30', '05:26'],
          'l': ['00:00', '23:55'],
          'p': [
            ['05:00', '00:00', 6],
          ],
          't': {
            'P01': [null, [330, 340, 350, 360]],
            'P05': [[335, 345, 355], [328, 338, 348]],
          },
        },
      };

      final schedule = parseCompactSchedule(json);

      // 상행 (dirIndex=0)
      expect(schedule.weekday.stationDepartures, isNotNull);
      // P01 상행은 null → 상행 맵에 포함되지 않음
      expect(schedule.weekday.stationDepartures!.containsKey('P01'), isFalse);
      // P05 상행
      expect(schedule.weekday.stationDepartures!['P05'], [335, 345, 355]);

      // 하행 (dirIndex=1)
      expect(schedule.weekdayDown, isNotNull);
      expect(schedule.weekdayDown!.stationDepartures, isNotNull);
      // P01 하행
      expect(schedule.weekdayDown!.stationDepartures!['P01'], [330, 340, 350, 360]);
      // P05 하행
      expect(schedule.weekdayDown!.stationDepartures!['P05'], [328, 338, 348]);
    });

    test('t 키가 있으면 상하행 동일해도 하행 데이터를 생성한다', () {
      final json = {
        'id': '김포골드',
        'wd': {
          'f': ['05:30', '05:30'],
          'l': ['23:30', '23:30'],
          'p': [
            ['05:00', '23:30', 6],
          ],
          't': {
            'P05': [[335, 345], [328, 338]],
          },
        },
      };

      final schedule = parseCompactSchedule(json);

      // t가 있으므로 첫차/막차 동일해도 하행 생성
      expect(schedule.weekdayDown, isNotNull);
      expect(schedule.weekdayDown!.stationDepartures, isNotNull);
      expect(schedule.weekdayDown!.stationDepartures!['P05'], [328, 338]);
    });

    test('t 키가 없으면 stationDepartures는 null이다', () {
      final json = {
        'id': '2',
        'wd': {
          'f': ['05:00', '05:02'],
          'l': ['00:00', '23:55'],
          'p': [
            ['05:00', '00:00', 5],
          ],
        },
      };

      final schedule = parseCompactSchedule(json);
      expect(schedule.weekday.stationDepartures, isNull);
      expect(schedule.weekdayDown!.stationDepartures, isNull);
    });

    test('t 키가 빈 맵이면 stationDepartures는 null이다', () {
      final json = {
        'id': 'test',
        'wd': {
          'f': ['05:00', '05:02'],
          'l': ['00:00', '23:55'],
          'p': [
            ['05:00', '00:00', 5],
          ],
          't': <String, dynamic>{},
        },
      };

      final schedule = parseCompactSchedule(json);
      expect(schedule.weekday.stationDepartures, isNull);
    });
  });

  group('급행(tE) 파싱', () {
    test('tE 키가 있으면 급행 역별 시간표를 방향별로 파싱한다', () {
      final json = {
        'id': '9',
        'wd': {
          'f': ['05:30', '05:40'],
          'l': ['00:50', '00:51'],
          'p': [
            ['05:30', '00:50', 6],
          ],
          'tE': {
            '902': [
              [330, 340, 352],
              [335, 345, 355],
            ],
            '905': [null, [338, 348, 358]],
          },
        },
      };

      final schedule = parseCompactSchedule(json);

      // 상행 (dirIndex=0)
      expect(schedule.weekday.expressStationDepartures, isNotNull);
      expect(schedule.weekday.expressStationDepartures!['902'], [330, 340, 352]);
      // 905 상행은 null → 상행 급행 맵에 포함되지 않음 (급행 미정차)
      expect(schedule.weekday.expressStationDepartures!.containsKey('905'), isFalse);

      // 하행 (dirIndex=1)
      expect(schedule.weekdayDown, isNotNull);
      expect(schedule.weekdayDown!.expressStationDepartures, isNotNull);
      expect(schedule.weekdayDown!.expressStationDepartures!['902'], [335, 345, 355]);
      expect(schedule.weekdayDown!.expressStationDepartures!['905'], [338, 348, 358]);
    });

    test('t만 있고 tE가 없으면 expressStationDepartures는 null이다', () {
      final json = {
        'id': '2',
        'wd': {
          'f': ['05:00', '05:02'],
          'l': ['00:00', '23:55'],
          'p': [
            ['05:00', '00:00', 5],
          ],
          't': {
            'P05': [[335, 345], [328, 338]],
          },
        },
      };

      final schedule = parseCompactSchedule(json);

      expect(schedule.weekday.stationDepartures, isNotNull);
      expect(schedule.weekday.expressStationDepartures, isNull);
      expect(schedule.weekdayDown!.stationDepartures, isNotNull);
      expect(schedule.weekdayDown!.expressStationDepartures, isNull);
    });

    test('t와 tE가 모두 있으면 각각 독립적으로 파싱되어 서로 섞이지 않는다', () {
      final json = {
        'id': '9',
        'wd': {
          'f': ['05:30', '05:40'],
          'l': ['00:50', '00:51'],
          'p': [
            ['05:30', '00:50', 6],
          ],
          't': {
            '902': [[330, 340, 350], [335, 345, 355]],
          },
          'tE': {
            '902': [[331, 341, 351], [336, 346, 356]],
          },
        },
      };

      final schedule = parseCompactSchedule(json);

      // 완행과 급행이 1분씩만 달라도 각자 독립적으로 유지되어야 함
      expect(schedule.weekday.stationDepartures!['902'], [330, 340, 350]);
      expect(schedule.weekday.expressStationDepartures!['902'], [331, 341, 351]);
      expect(schedule.weekdayDown!.stationDepartures!['902'], [335, 345, 355]);
      expect(schedule.weekdayDown!.expressStationDepartures!['902'], [336, 346, 356]);
    });

    test('tE만 있고 t가 없으면 stationDepartures는 null, expressStationDepartures만 존재한다', () {
      final json = {
        'id': '9',
        'wd': {
          'f': ['05:30', '05:40'],
          'l': ['00:50', '00:51'],
          'p': [
            ['05:30', '00:50', 6],
          ],
          'tE': {
            '902': [[330, 340], [335, 345]],
          },
        },
      };

      final schedule = parseCompactSchedule(json);

      expect(schedule.weekday.stationDepartures, isNull);
      expect(schedule.weekday.expressStationDepartures, isNotNull);
      expect(schedule.weekday.expressStationDepartures!['902'], [330, 340]);
    });

    test('tE가 빈 맵이면 expressStationDepartures는 null이다', () {
      final json = {
        'id': '9',
        'wd': {
          'f': ['05:30', '05:40'],
          'l': ['00:50', '00:51'],
          'p': [
            ['05:30', '00:50', 6],
          ],
          'tE': <String, dynamic>{},
        },
      };

      final schedule = parseCompactSchedule(json);
      expect(schedule.weekday.expressStationDepartures, isNull);
    });

    test('_parseDayScheduleDown: tE만 있고 t가 없어도 상하행 첫차/막차가 같으면 non-null을 반환한다', () {
      final json = {
        'id': '9',
        'wd': {
          // 상하행 첫차/막차 동일 (pD도 없음) → 원래는 null 폴백 대상이지만
          // tE가 있으므로 하행 전용 DaySchedule을 생성해야 한다.
          'f': ['05:30', '05:30'],
          'l': ['23:30', '23:30'],
          'p': [
            ['05:30', '23:30', 6],
          ],
          'tE': {
            '902': [[330, 340], [332, 342]],
          },
        },
      };

      final schedule = parseCompactSchedule(json);

      expect(schedule.weekdayDown, isNotNull);
      expect(schedule.weekdayDown!.expressStationDepartures, isNotNull);
      expect(schedule.weekdayDown!.expressStationDepartures!['902'], [332, 342]);
    });
  });

  group('LineSchedule.getSchedule', () {
    test('평일 상행 스케줄 반환', () {
      final schedule = LineSchedule(
        lineId: '2',
        weekday: const DaySchedule(
          firstTrain: '05:00', lastTrain: '00:00', periods: [],
        ),
        weekend: const DaySchedule(
          firstTrain: '05:30', lastTrain: '23:40', periods: [],
        ),
        weekdayDown: const DaySchedule(
          firstTrain: '05:02', lastTrain: '23:55', periods: [],
        ),
      );

      final monday = DateTime(2026, 2, 23); // 월요일
      final result = schedule.getSchedule(monday);
      expect(result.firstTrain, '05:00');
    });

    test('평일 하행 스케줄 반환', () {
      final schedule = LineSchedule(
        lineId: '2',
        weekday: const DaySchedule(
          firstTrain: '05:00', lastTrain: '00:00', periods: [],
        ),
        weekend: const DaySchedule(
          firstTrain: '05:30', lastTrain: '23:40', periods: [],
        ),
        weekdayDown: const DaySchedule(
          firstTrain: '05:02', lastTrain: '23:55', periods: [],
        ),
      );

      final monday = DateTime(2026, 2, 23);
      final result = schedule.getSchedule(monday, isDown: true);
      expect(result.firstTrain, '05:02');
    });

    test('하행 데이터 없으면 상행으로 폴백', () {
      final schedule = LineSchedule(
        lineId: '2',
        weekday: const DaySchedule(
          firstTrain: '05:00', lastTrain: '00:00', periods: [],
        ),
        weekend: const DaySchedule(
          firstTrain: '05:30', lastTrain: '23:40', periods: [],
        ),
      );

      final monday = DateTime(2026, 2, 23);
      final result = schedule.getSchedule(monday, isDown: true);
      expect(result.firstTrain, '05:00'); // weekday로 폴백
    });

    test('주말 하행 데이터 없으면 주말 상행으로 폴백', () {
      final schedule = LineSchedule(
        lineId: '2',
        weekday: const DaySchedule(
          firstTrain: '05:00', lastTrain: '00:00', periods: [],
        ),
        weekend: const DaySchedule(
          firstTrain: '05:30', lastTrain: '23:40', periods: [],
        ),
        weekdayDown: const DaySchedule(
          firstTrain: '05:02', lastTrain: '23:55', periods: [],
        ),
        // weekendDown 없음
      );

      final saturday = DateTime(2026, 2, 21); // 토요일
      final result = schedule.getSchedule(saturday, isDown: true);
      expect(result.firstTrain, '05:30'); // weekend로 폴백
    });
  });
}
