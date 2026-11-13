import 'package:flutter_test/flutter_test.dart';
import 'package:busan_subway/data/local/local_data_source.dart';
import 'package:busan_subway/domain/entities/transfer_guide.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('LocalDataSource.loadTransferGuides', () {
    late LocalDataSource dataSource;

    setUp(() {
      dataSource = LocalDataSource();
    });

    test('번들 JSON에서 환승 가이드를 로드한다 (빈 맵 허용)', () async {
      final guides = await dataSource.loadTransferGuides();

      expect(guides, isA<Map<String, TransferGuide>>());
    });

    test('재호출 시 캐시된 동일 인스턴스를 반환한다', () async {
      final first = await dataSource.loadTransferGuides();
      final second = await dataSource.loadTransferGuides();

      expect(identical(first, second), isTrue);
    });

    test('clearCache 후 재로딩하면 새 인스턴스를 반환한다', () async {
      final first = await dataSource.loadTransferGuides();
      dataSource.clearCache();
      final second = await dataSource.loadTransferGuides();

      expect(identical(first, second), isFalse);
      expect(second, isA<Map<String, TransferGuide>>());
    });
  });
}
