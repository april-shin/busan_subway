import 'package:flutter_test/flutter_test.dart';
import 'package:busan_subway/core/constants/dwell_time.dart';

void main() {
  test('dwellTimeSeconds는 30초', () {
    expect(dwellTimeSeconds, 30);
  });

  test('dwellTimeSeconds는 양수', () {
    expect(dwellTimeSeconds, greaterThan(0));
  });
}
