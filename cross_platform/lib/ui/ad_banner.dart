import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:material_ui/material_ui.dart';

import '../core/ads.dart';

/// Anchored adaptive banner at the bottom of a tab; takes no space until an ad loads.
class AdBanner extends StatefulWidget {
  const AdBanner({super.key});
  @override
  State<AdBanner> createState() => _AdBannerState();
}

class _AdBannerState extends State<AdBanner> {
  BannerAd? _ad;
  bool _loaded = false, _loading = false, _failed = false;
  int? _width;

  @override
  void initState() {
    super.initState();
    Ads.shared.addListener(_onAds);
  }

  void _onAds() {
    if (mounted) setState(() {});
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _load();
  }

  Future<void> _load() async {
    final unit = Ads.bannerUnit;
    if (unit == null || !Ads.shared.ready || _loading) return;
    final width = MediaQuery.sizeOf(context).width.truncate();
    // One request per width; a failed (no-fill) request is not retried on rebuild.
    if (width == _width && (_ad != null || _failed)) return;
    _width = width;
    _failed = false;
    _loading = true;
    final size = await AdSize.getLargeAnchoredAdaptiveBannerAdSize(width);
    _loading = false;
    if (size == null || !mounted) return;
    await _ad?.dispose();
    _loaded = false;
    _ad = BannerAd(
      adUnitId: unit,
      size: size,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (_) {
          if (mounted) setState(() => _loaded = true);
        },
        onAdFailedToLoad: (ad, _) {
          ad.dispose();
          _failed = true;
          if (mounted) setState(() => _ad = null);
        },
      ),
    )..load();
  }

  @override
  void dispose() {
    Ads.shared.removeListener(_onAds);
    _ad?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (Ads.shared.ready && _ad == null) _load();
    final ad = _ad;
    if (ad == null || !_loaded) return const SizedBox.shrink();
    return Semantics(
      label: 'Reklam',
      child: SizedBox(
        width: ad.size.width.toDouble(),
        height: ad.size.height.toDouble(),
        child: AdWidget(ad: ad),
      ),
    );
  }
}
