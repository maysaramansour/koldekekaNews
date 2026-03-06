import 'dart:io';
import 'package:flutter/material.dart' show Color;
import 'package:google_mobile_ads/google_mobile_ads.dart';

/// Centralised AdMob service.
///
/// ── HOW TO REPLACE TEST IDs WITH REAL IDs ───────────────────────────────
/// 1. Go to https://admob.google.com → Apps → Add app → get App ID
/// 2. In AndroidManifest.xml replace com.google.android.gms.ads.APPLICATION_ID
/// 3. Replace the ad unit IDs below with your real ones from AdMob dashboard
/// ────────────────────────────────────────────────────────────────────────

class AdService {
  AdService._();

  // ── Ad unit IDs (PRODUCTION) ─────────────────────────────────────────────
  // App: كل دقيقة  |  ca-app-pub-5971282809592096~7841959124
  //
  // TODO: create Interstitial + Native units in AdMob and replace the
  //       placeholder below with their real IDs.
  static String get _bannerId => Platform.isAndroid
      ? 'ca-app-pub-5971282809592096/8942958239'   // ✅ real banner
      : 'ca-app-pub-3940256099942544/2934735716';  // iOS — replace when available

  static String get _interstitialId => Platform.isAndroid
      ? 'ca-app-pub-5971282809592096/7650387432'   // ✅ real interstitial
      : 'ca-app-pub-3940256099942544/4411468910';  // iOS — replace when available

  static String get _nativeId => Platform.isAndroid
      ? 'ca-app-pub-5971282809592096/2185978190'   // ✅ real native unit
      : 'ca-app-pub-3940256099942544/3986624511';  // iOS — replace when available

  // ── Initialise SDK ───────────────────────────────────────────────────────
  static Future<void> init() async {
    await MobileAds.instance.initialize();
  }

  // ── Banner ───────────────────────────────────────────────────────────────
  static BannerAd createBanner({required void Function(Ad) onLoaded}) {
    return BannerAd(
      adUnitId: _bannerId,
      size: AdSize.banner,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: onLoaded,
        onAdFailedToLoad: (ad, error) {
          ad.dispose();
        },
      ),
    )..load();
  }

  // ── Interstitial ─────────────────────────────────────────────────────────
  static void loadInterstitial({
    required void Function(InterstitialAd ad) onLoaded,
  }) {
    InterstitialAd.load(
      adUnitId: _interstitialId,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: onLoaded,
        onAdFailedToLoad: (_) {},
      ),
    );
  }

  // ── Native ───────────────────────────────────────────────────────────────
  static NativeAd createNative({required void Function(Ad) onLoaded}) {
    return NativeAd(
      adUnitId: _nativeId,
      request: const AdRequest(),
      listener: NativeAdListener(
        onAdLoaded: onLoaded,
        onAdFailedToLoad: (ad, _) => ad.dispose(),
      ),
      nativeTemplateStyle: NativeTemplateStyle(
        templateType: TemplateType.small,
        mainBackgroundColor: const Color(0xFF1A1A1A),
        cornerRadius: 12,
        callToActionTextStyle: NativeTemplateTextStyle(
          textColor: const Color(0xFFFFFFFF),
          backgroundColor: const Color(0xFFCC0000),
          style: NativeTemplateFontStyle.bold,
          size: 13,
        ),
        primaryTextStyle: NativeTemplateTextStyle(
          textColor: const Color(0xFFFFFFFF),
          style: NativeTemplateFontStyle.bold,
          size: 14,
        ),
        secondaryTextStyle: NativeTemplateTextStyle(
          textColor: const Color(0xFFAAAAAA),
          style: NativeTemplateFontStyle.normal,
          size: 12,
        ),
      ),
    )..load();
  }

  /// Insert native ad positions into an article list.
  /// Returns a new list where every [interval]-th item is [_adSentinel].
  static const String adSentinel = '__AD__';
  static const int nativeAdInterval = 8; // show ad every 8 articles

  static List<dynamic> injectAdSlots(List<dynamic> items) {
    final result = <dynamic>[];
    for (int i = 0; i < items.length; i++) {
      result.add(items[i]);
      if ((i + 1) % nativeAdInterval == 0 && i < items.length - 1) {
        result.add(adSentinel);
      }
    }
    return result;
  }
}
