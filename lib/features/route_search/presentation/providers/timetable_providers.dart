import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../../data/local/timetable_data_source.dart';
import '../../../../domain/entities/line_schedule.dart';

part 'timetable_providers.g.dart';

@Riverpod(keepAlive: true)
TimetableDataSource timetableDataSource(Ref ref) {
  return TimetableDataSource();
}

@Riverpod(keepAlive: true)
Future<Map<String, LineSchedule>> lineSchedules(Ref ref) async {
  return ref.watch(timetableDataSourceProvider).loadSchedules();
}
