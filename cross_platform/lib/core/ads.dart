import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

/// AdMob banner ads on Android with Google's consent form (UMP).
/// Mac and Windows builds never load the SDK.
class Ads extends ChangeNotifier {
  Ads._();
  static final shared = Ads._();

  /// Google's sample banner unit; debug builds use it.
  static const testBannerUnit = 'ca-app-pub-3940256099942544/6300978111';

  /// AdMob Android app "Kumanda" (ca-app-pub-3117486801133085~3472120260),
  /// banner unit "Kumanda Banner Android". An empty
  /// --dart-define=KUMANDA_BANNER_UNIT= turns ads off.
  static const _releaseBannerUnit = String.fromEnvironment(
    'KUMANDA_BANNER_UNIT',
    defaultValue: 'ca-app-pub-3117486801133085/2287031101',
  );

  /// Play internal/closed test builds show test ads when built with
  /// --dart-define=KUMANDA_TEST_ADS=true.
  static const _forceTestAds = bool.fromEnvironment('KUMANDA_TEST_ADS');

  static bool get supported => !kIsWeb && Platform.isAndroid;

  static String? get bannerUnit {
    if (!supported) return null;
    if (kDebugMode || _forceTestAds) return testBannerUnit;
    return _releaseBannerUnit.startsWith('ca-app-pub-')
        ? _releaseBannerUnit
        : null;
  }

  bool ready = false;
  bool privacyOptionsRequired = false;
  bool _started = false;

  void start() {
    if (bannerUnit == null || _started) return;
    _started = true;
    ConsentInformation.instance.requestConsentInfoUpdate(
      ConsentRequestParameters(),
      () async {
        await ConsentForm.loadAndShowConsentFormIfRequired((_) {});
        privacyOptionsRequired =
            await ConsentInformation.instance
                .getPrivacyOptionsRequirementStatus() ==
            PrivacyOptionsRequirementStatus.required;
        notifyListeners();
        await _startSdkIfAllowed();
      },
      (_) => unawaited(_startSdkIfAllowed()),
    );
    // Consent from an earlier launch lets ads start without waiting.
    unawaited(_startSdkIfAllowed());
  }

  Future<void> _startSdkIfAllowed() async {
    if (ready || !await ConsentInformation.instance.canRequestAds()) return;
    await MobileAds.instance.initialize();
    ready = true;
    notifyListeners();
  }

  void showPrivacyOptions() {
    ConsentForm.showPrivacyOptionsForm((_) async {
      privacyOptionsRequired =
          await ConsentInformation.instance
              .getPrivacyOptionsRequirementStatus() ==
          PrivacyOptionsRequirementStatus.required;
      notifyListeners();
    });
  }
}
