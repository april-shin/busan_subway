import 'package:flutter/foundation.dart'
    show kDebugMode, kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

/// 화면 하단에 노출되는 AdMob 적응형(앵커드) 배너 광고 위젯.
/// 홈/경로 결과/도착 정보 화면 하단에 공용으로 사용된다.
///
/// - kDebugMode: Google 공식 테스트 단위 ID 사용
/// - release  : 발급 후 [_kAndroidReleaseUnitId]/[_kIosReleaseUnitId]에 채워 넣을 것.
///   release 단위 ID가 비어 있으면 광고 로드를 시도하지 않고 [SizedBox.shrink]를 반환한다.
class HomeBannerAd extends StatefulWidget {
  const HomeBannerAd({super.key});

  // Google 공식 테스트 단위 ID — 디버그 빌드 전용.
  static const String _kAndroidTestUnitId =
      'ca-app-pub-3940256099942544/6300978111';
  static const String _kIosTestUnitId =
      'ca-app-pub-3940256099942544/2934735716';

  static const String _kAndroidReleaseUnitId =
      'ca-app-pub-3206652264632834/5042177959';
  static const String _kIosReleaseUnitId =
      'ca-app-pub-3206652264632834/1169097697';

  @override
  State<HomeBannerAd> createState() => _HomeBannerAdState();
}

class _HomeBannerAdState extends State<HomeBannerAd> {
  BannerAd? _bannerAd;
  bool _isLoaded = false;
  bool _failed = false;
  bool _loadAttempted = false;

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
    if (!_loadAttempted) {
      _loadAttempted = true;
      _loadAd();
    }
  }

  Future<void> _loadAd() async {
    final adUnitId = _resolveAdUnitId();
    if (adUnitId == null) {
      // release 미설정 또는 미지원 플랫폼: 광고 미노출.
      return;
    }

    final width = MediaQuery.of(context).size.width.truncate();
    final size = await AdSize.getAnchoredAdaptiveBannerAdSize(
      Orientation.portrait,
      width,
    );
    if (size == null) {
      // 적응형 사이즈 계산 실패: 광고 미노출.
      return;
    }
    if (!mounted) return;

    final ad = BannerAd(
      adUnitId: adUnitId,
      size: size,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (loadedAd) {
          // dispose된 위젯이면 BannerAd도 즉시 해제하여 누수를 방지한다.
          if (!mounted) {
            loadedAd.dispose();
            return;
          }
          setState(() {
            _isLoaded = true;
            _failed = false;
          });
        },
        onAdFailedToLoad: (failedAd, error) {
          failedAd.dispose();
          if (!mounted) return;
          setState(() {
            _bannerAd = null;
            _isLoaded = false;
            _failed = true;
          });
        },
      ),
    );

    _bannerAd = ad;
    await ad.load();
    // load() 도중 dispose 되었다면 ad를 직접 해제하여 누수 방지.
    if (!mounted) {
      ad.dispose();
      _bannerAd = null;
    }
  }

  @override
  void dispose() {
    _bannerAd?.dispose();
    _bannerAd = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ad = _bannerAd;
    if (!_isLoaded || _failed || ad == null) {
      return const SizedBox.shrink();
    }
    return Container(
      color: Theme.of(context).colorScheme.surface,
      width: ad.size.width.toDouble(),
      height: ad.size.height.toDouble(),
      child: AdWidget(ad: ad),
    );
  }
}
