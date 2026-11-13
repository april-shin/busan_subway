import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart'
    show kDebugMode, kIsWeb, debugPrint, defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../../../../core/utils/foldable_layout.dart';

/// 화면 하단에 노출되는 AdMob 적응형(앵커드) 배너 광고 위젯.
/// 홈/경로 결과/도착 정보 화면 하단에 공용으로 사용된다.
///
/// - kDebugMode: Google 공식 테스트 단위 ID 사용
/// - release  : 발급 후 [_kAndroidReleaseUnitId]/[_kIosReleaseUnitId]에 채워 넣을 것.
///   release 단위 ID가 비어 있으면 광고 로드를 시도하지 않고 [SizedBox.shrink]를 반환한다.
///
/// 펼친 iPhone Duo([FoldableLayout.isUnfolded])에서는 오른쪽 페이지 폭으로
/// 요청해 오른쪽에 붙인다. 접기/펼치기로 이 상태가 바뀌면 다시 로드한다.
/// 다른 기기에서는 기존과 동일하다(화면 폭 전체로 1회 로드).
class HomeBannerAd extends StatefulWidget {
  const HomeBannerAd({super.key});

  // Google 공식 테스트 단위 ID — 디버그 빌드 전용.
  static const String _kAndroidTestUnitId =
      'ca-app-pub-3940256099942544/6300978111';
  static const String _kIosTestUnitId =
      'ca-app-pub-3940256099942544/2934735716';

  static const String _kAndroidReleaseUnitId =
      'ca-app-pub-3206652264632834/2124292309';
  static const String _kIosReleaseUnitId =
      'ca-app-pub-3206652264632834/2858789472';

  @override
  State<HomeBannerAd> createState() => _HomeBannerAdState();
}

class _HomeBannerAdState extends State<HomeBannerAd> {
  BannerAd? _bannerAd;
  bool _isLoaded = false;
  bool _loadStarted = false;

  // 마지막 로드를 시작한 시점의 펼침 상태. 바뀌면 폭이 달라지므로 재로드한다.
  bool _loadedUnfolded = false;

  // 재로드로 무효가 된 진행 중 _loadAd 를 버리기 위한 세대 번호.
  int _loadGeneration = 0;

  // 로드 실패 시 지수 백오프 재시도.
  // 새로 만든 광고 단위는 초기 몇 시간 동안 no-fill(code=3)을 반환할 수 있어,
  // 세션당 1회만 로드하면 그 세션 내내 배너가 뜨지 않는다. 제한된 횟수만큼
  // 백오프하며 재시도하되, 상한에 도달하면 조용히 멈춰 요청 낭비를 막는다.
  int _retryCount = 0;
  Timer? _retryTimer;
  static const int _kMaxRetries = 5;
  static const Duration _kBaseRetryDelay = Duration(seconds: 2);
  static const Duration _kMaxRetryDelay = Duration(minutes: 1);

  /// 현재 플랫폼/빌드 모드에 맞는 광고 단위 ID를 반환한다.
  /// release 모드에서 ID 미설정이면 `null`을 반환하여 로드 자체를 건너뛴다.
  /// web 등 미지원 플랫폼에서도 `null`을 반환한다.
  String? _resolveAdUnitId() {
    // google_mobile_ads는 web을 지원하지 않으므로 즉시 차단.
    if (kIsWeb) return null;
    if (kDebugMode) {
      if (defaultTargetPlatform == TargetPlatform.android) {
        return HomeBannerAd._kAndroidTestUnitId;
      }
      if (defaultTargetPlatform == TargetPlatform.iOS) {
        return HomeBannerAd._kIosTestUnitId;
      }
      return null;
    }
    if (defaultTargetPlatform == TargetPlatform.android) {
      return HomeBannerAd._kAndroidReleaseUnitId.isEmpty
          ? null
          : HomeBannerAd._kAndroidReleaseUnitId;
    }
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      return HomeBannerAd._kIosReleaseUnitId.isEmpty
          ? null
          : HomeBannerAd._kIosReleaseUnitId;
    }
    return null;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // MediaQuery는 initState 시점에는 안전하지 않을 수 있어
    // didChangeDependencies에서 1회만 로드한다.
    // 단, 펼친 Duo 를 접거나 펼치면 배너 폭이 바뀌므로 그때만 다시 로드한다.
    final unfolded = FoldableLayout.isUnfolded(context);
    if (!_loadStarted) {
      _loadStarted = true;
      _loadedUnfolded = unfolded;
      _loadAd();
    } else if (unfolded != _loadedUnfolded) {
      _loadedUnfolded = unfolded;
      _reload();
    }
  }

  void _reload() {
    _loadGeneration++;
    _retryTimer?.cancel();
    _retryTimer = null;
    _retryCount = 0;
    _bannerAd?.dispose();
    _bannerAd = null;
    _isLoaded = false;
    // didChangeDependencies 직후 build 가 이어지므로 setState 불필요.
    _loadAd();
  }

  Future<void> _loadAd() async {
    if (!mounted) return;

    final adUnitId = _resolveAdUnitId();
    if (adUnitId == null) {
      // release 미설정 또는 미지원 플랫폼: 광고 미노출(재시도 안 함).
      return;
    }

    final generation = _loadGeneration;
    final width = _loadedUnfolded
        ? rightPageWidth(MediaQueryData.fromView(View.of(context))).truncate()
        : MediaQuery.of(context).size.width.truncate();
    final size = await AdSize.getAnchoredAdaptiveBannerAdSize(
      Orientation.portrait,
      width,
    );
    if (!mounted || generation != _loadGeneration) return;
    if (size == null) {
      // 적응형 사이즈 계산 실패: 잠시 후 재시도(초기 레이아웃 미확정 등).
      debugPrint('[HomeBannerAd] 적응형 배너 사이즈 계산 실패 (width=$width)');
      _scheduleRetry();
      return;
    }

    final ad = BannerAd(
      adUnitId: adUnitId,
      size: size,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (loadedAd) {
          // dispose된 위젯이면 BannerAd도 즉시 해제하여 누수를 방지한다.
          if (!mounted || generation != _loadGeneration) {
            loadedAd.dispose();
            return;
          }
          _retryCount = 0; // 성공 시 백오프 리셋.
          debugPrint('[HomeBannerAd] 로드 성공');
          setState(() {
            _isLoaded = true;
          });
        },
        onAdFailedToLoad: (failedAd, error) {
          failedAd.dispose();
          if (generation != _loadGeneration) return;
          // release 실기기에서도 원인 파악이 가능하도록 에러 코드를 남긴다.
          // code=3: no-fill(광고 재고 없음/신규 단위), code=1/0: 요청/설정 오류.
          debugPrint(
            '[HomeBannerAd] 로드 실패: code=${error.code} '
            'domain=${error.domain} message=${error.message}',
          );
          if (!mounted) return;
          setState(() {
            _bannerAd = null;
            _isLoaded = false;
          });
          _scheduleRetry();
        },
      ),
    );

    // 재시도 등으로 이전 인스턴스가 남아 있으면 먼저 해제(방어적).
    _bannerAd?.dispose();
    _bannerAd = ad;
    await ad.load();
    // load() 도중 dispose 되었다면 ad를 직접 해제하여 누수 방지.
    // 단, State.dispose()가 같은 인스턴스를 이미 해제했을 수 있으므로
    // 아직 우리가 들고 있는 인스턴스일 때만 해제해 이중 dispose를 막는다.
    if (!mounted && identical(_bannerAd, ad)) {
      ad.dispose();
      _bannerAd = null;
    }
  }

  /// 지수 백오프로 [_loadAd] 재시도를 예약한다.
  /// 지연: 2s, 4s, 8s, 16s, 32s (최대 [_kMaxRetryDelay]). 상한 도달 시 중단.
  void _scheduleRetry() {
    if (!mounted) return;
    if (_retryCount >= _kMaxRetries) {
      debugPrint('[HomeBannerAd] 최대 재시도($_kMaxRetries회) 도달 — 로드 중단');
      return;
    }
    _retryCount++;
    final delayMs = math.min(
      _kBaseRetryDelay.inMilliseconds * (1 << (_retryCount - 1)),
      _kMaxRetryDelay.inMilliseconds,
    );
    final delay = Duration(milliseconds: delayMs);
    debugPrint('[HomeBannerAd] ${delay.inSeconds}s 후 재시도 '
        '($_retryCount/$_kMaxRetries)');
    _retryTimer?.cancel();
    _retryTimer = Timer(delay, _loadAd);
  }

  @override
  void dispose() {
    _retryTimer?.cancel();
    _retryTimer = null;
    _bannerAd?.dispose();
    _bannerAd = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ad = _bannerAd;
    if (!_isLoaded || ad == null) {
      return const SizedBox.shrink();
    }
    final banner = Container(
      color: Theme.of(context).colorScheme.surface,
      width: ad.size.width.toDouble(),
      height: ad.size.height.toDouble(),
      child: AdWidget(ad: ad),
    );
    if (!_loadedUnfolded) return banner;
    // 펼친 Duo: 오른쪽 페이지 하단에 붙인다. heightFactor 로 높이는 배너만큼.
    return Align(
      alignment: Alignment.centerRight,
      heightFactor: 1,
      child: banner,
    );
  }
}
