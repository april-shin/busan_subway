import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import 'app.dart';
import 'core/constants/app_info.dart';
import 'core/utils/foldable_layout.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // edge-to-edge 명시 opt-in. **필수** — 생략하면 하단 시스템 nav bar 영역이
  // 불투명 검정으로 렌더된다.
  //
  // Flutter 3.44 의 `PlatformPlugin` 은 systemUiMode 가 EDGE_TO_EDGE 가
  // 아니면 `WindowCompat.setDecorFitsSystemWindows(window, true)` 를 호출해
  // edge-to-edge 를 끈다. 그러면 Flutter 표면이 nav bar 위쪽으로 인셋되어
  // `MediaQuery.padding.bottom` 이 0 이 되고, app.dart 의 SafeArea/ColoredBox
  // 는 칠할 띠가 없어진다. 동시에 같은 버전에서 `setNavigationBarColor` 가
  // `SDK_INT < 35` 로 가드되어 Android 15+ 에서는 호출되지 않으므로,
  // nav bar 는 시스템 기본값(검정)으로 남는다.
  //
  // 3.41.x 에서는 PlatformPlugin 이 setDecorFitsSystemWindows 를 건드리지
  // 않아 Android 15+ 의 강제 edge-to-edge 를 그냥 받아썼기 때문에 이 호출이
  // 없어도 동작했다. 3.44 부터는 opt-in 이 필요하다.
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

  await dotenv.load(fileName: '.env');
  await AppInfo.init();
  await FoldableLayout.init();
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
