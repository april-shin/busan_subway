import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:busan_subway/core/network/network_info.dart';

class MockConnectivity extends Mock implements Connectivity {}

void main() {
  late MockConnectivity mockConnectivity;
  late NetworkInfo networkInfo;

  setUp(() {
    mockConnectivity = MockConnectivity();
    networkInfo = NetworkInfo(connectivity: mockConnectivity);
  });

  group('NetworkInfo', () {
    test('isConnected returns true when wifi connected', () async {
      when(() => mockConnectivity.checkConnectivity())
          .thenAnswer((_) async => [ConnectivityResult.wifi]);

      final result = await networkInfo.isConnected;
      expect(result, true);
    });

    test('isConnected returns true when mobile connected', () async {
      when(() => mockConnectivity.checkConnectivity())
          .thenAnswer((_) async => [ConnectivityResult.mobile]);

      final result = await networkInfo.isConnected;
      expect(result, true);
    });

    test('isConnected returns false when no connection', () async {
      when(() => mockConnectivity.checkConnectivity())
          .thenAnswer((_) async => [ConnectivityResult.none]);

      final result = await networkInfo.isConnected;
      expect(result, false);
    });

    test('isConnected returns true when multiple connections', () async {
      when(() => mockConnectivity.checkConnectivity())
          .thenAnswer((_) async => [
                ConnectivityResult.wifi,
                ConnectivityResult.mobile,
              ]);

      final result = await networkInfo.isConnected;
      expect(result, true);
    });
  });
}
