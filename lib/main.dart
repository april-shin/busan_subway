import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import 'app.dart';
import 'core/constants/app_info.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: '.env');
  await AppInfo.init();
  await MobileAds.instance.initialize();
  runApp(
    ProviderScope(
      // riverpod 3 는 실패한 프로바이더를 지수 백오프로 자동 재시도한다(v2 미존재
      // 동작). 도착정보 프로바이더는 오프라인/캐시미스 시 throw 하는데, 자동 재시도가
      // 붙으면 일일 호출 한도(1000건, api_constants.dart)를 소진할 수 있다.
      // v2 동작(재시도 없음)을 유지하기 위해 전역 재시도를 비활성화한다.
      retry: (retryCount, error) => null,
      child: const SeoulSubwayApp(),
    ),
  );
}
