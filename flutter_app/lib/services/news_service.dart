import 'dart:convert';
import 'dart:io' show HttpException;
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/article.dart';

// Top-level helpers — required by compute() which uses Isolate.spawn
Map<String, dynamic> _parseNewsBytes(Uint8List bytes) =>
    json.decode(utf8.decode(bytes)) as Map<String, dynamic>;

List<dynamic> _parseSourcesBytes(Uint8List bytes) =>
    json.decode(utf8.decode(bytes)) as List<dynamic>;

class NewsService {
  // ── Server base URL ──────────────────────────────────────────────────────────
  // Production: Firebase Cloud Functions (accessible from any device/network)
  static String get _defaultBase {
    return 'https://us-central1-kol-dekeka.cloudfunctions.net/api';
  }

  static String? _overrideBase;

  /// Change the server URL at runtime (from Settings screen).
  static void setServerBase(String base) => _overrideBase = base;

  /// The currently active server base URL.
  static String get serverBase => _overrideBase ?? _defaultBase;

  // ── Singleton ────────────────────────────────────────────────────────────────
  static final NewsService _instance = NewsService._();
  factory NewsService() => _instance;
  NewsService._();

  // ── In-memory cache ──────────────────────────────────────────────────────────
  List<Article> _cachedArticles = [];
  int? _lastFetchedAt;
  String _activeSource = 'all';

  List<Article> get cachedArticles => _cachedArticles;
  String get activeSource => _activeSource;

  // ── Fetch news with pagination ───────────────────────────────────────────────
  Future<NewsResponse> fetchNews({
    String source = 'all',
    bool forceRefresh = false,
    int page = 1,
    int limit = 30,
  }) async {
    final since =
        (!forceRefresh && _lastFetchedAt != null && page == 1) ? _lastFetchedAt : 0;
    final uri = Uri.parse(
        '${NewsService.serverBase}/api/news?since=$since&source=${Uri.encodeQueryComponent(source)}&page=$page&limit=$limit');

    final response = await http
        .get(uri, headers: {'Accept': 'application/json'})
        .timeout(const Duration(seconds: 15));

    if (response.statusCode != 200) {
      throw HttpException(
          'Server returned ${response.statusCode}', uri: uri);
    }

    // Decode JSON in a background isolate so the UI thread stays unblocked
    final data = await compute(_parseNewsBytes, response.bodyBytes);
    final newsResponse = NewsResponse.fromJson(data);

    // Merge new articles into cache (deduplicated)
    if (source == 'all' || source == _activeSource) {
      _activeSource = source;
      final existingIds = _cachedArticles.map((a) => a.id).toSet();
      final newOnes = newsResponse.articles
          .where((a) => !existingIds.contains(a.id))
          .toList();
      _cachedArticles = [...newOnes, ..._cachedArticles];
      _cachedArticles.sort((a, b) => b.pubDate.compareTo(a.pubDate));
      // Cap cache to prevent unbounded growth
      if (_cachedArticles.length > 120) {
        _cachedArticles = _cachedArticles.sublist(0, 120);
      }
      _lastFetchedAt = newsResponse.lastUpdated;
    }

    return newsResponse;
  }

  // ── Fetch sources list ───────────────────────────────────────────────────────
  Future<List<NewsSource>> fetchSources() async {
    final uri = Uri.parse('${NewsService.serverBase}/api/sources');
    final response = await http
        .get(uri, headers: {'Accept': 'application/json'})
        .timeout(const Duration(seconds: 10));

    if (response.statusCode != 200) {
      throw HttpException('Server returned ${response.statusCode}', uri: uri);
    }

    final data = await compute(_parseSourcesBytes, response.bodyBytes);
    return data
        .whereType<Map<String, dynamic>>()
        .map(NewsSource.fromJson)
        .toList();
  }

  // ── Fetch article body (scraped) ─────────────────────────────────────────────
  Future<Map<String, dynamic>> fetchArticle(String url) async {
    final uri = Uri.parse(
        '${NewsService.serverBase}/api/article?url=${Uri.encodeQueryComponent(url)}');
    final response = await http
        .get(uri, headers: {'Accept': 'application/json'})
        .timeout(const Duration(seconds: 20));

    if (response.statusCode != 200) {
      throw HttpException('Server returned ${response.statusCode}', uri: uri);
    }

    return json.decode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
  }

  // ── Server status ────────────────────────────────────────────────────────────
  Future<Map<String, dynamic>> fetchStatus() async {
    final uri = Uri.parse('${NewsService.serverBase}/api/status');
    final response = await http
        .get(uri, headers: {'Accept': 'application/json'})
        .timeout(const Duration(seconds: 5));

    if (response.statusCode != 200) {
      throw HttpException('Server returned ${response.statusCode}', uri: uri);
    }

    return json.decode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
  }

  void clearCache() {
    _cachedArticles = [];
    _lastFetchedAt = null;
  }
}
