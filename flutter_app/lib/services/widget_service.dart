import 'package:home_widget/home_widget.dart';
import 'news_service.dart';

/// Pushes the latest headline into the Android home screen widget.
class WidgetService {
  static const _appGroupId = 'com.arabnews.arab_news_reels';
  static const _providerName =
      'com.arabnews.arab_news_reels.NewsWidgetProvider';

  static Future<void> init() async {
    await HomeWidget.setAppGroupId(_appGroupId);
  }

  /// Fetches the latest article and writes it to the widget shared prefs,
  /// then triggers a native widget redraw.
  static Future<void> update() async {
    try {
      final response = await NewsService().fetchNews(forceRefresh: true, limit: 1);
      if (response.articles.isEmpty) return;

      final article = response.articles.first;
      final timeAgo = article.isArabic ? article.timeAgoAr : article.timeAgo;

      await Future.wait([
        HomeWidget.saveWidgetData<String>('widget_headline', article.title),
        HomeWidget.saveWidgetData<String>('widget_source', article.source),
        HomeWidget.saveWidgetData<String>('widget_time', timeAgo),
      ]);

      await HomeWidget.updateWidget(
        androidName: _providerName,
      );
    } catch (_) {
      // Widget update is best-effort; never crash the app
    }
  }
}
