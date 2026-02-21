import 'package:freezed_annotation/freezed_annotation.dart';

part 'line.freezed.dart';
part 'line.g.dart';

@freezed
class Line with _$Line {
  const factory Line({
    required String id,
    required String name,
    required int colorValue,
    required List<String> stationIds,
  }) = _Line;

  factory Line.fromJson(Map<String, dynamic> json) => _$LineFromJson(json);
}
