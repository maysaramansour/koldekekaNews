import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/video.dart';

// Top-level helpers for compute() — run JSON decode in a background isolate
Map<String, dynamic> _parseVideoBytes(Uint8List bytes) =>
    json.decode(utf8.decode(bytes)) as Map<String, dynamic>;

List<dynamic> _parseChannelsBytes(Uint8List bytes) =>
    json.decode(utf8.decode(bytes)) as List<dynamic>;

class VideoService {
  static String? _overrideBase;
  static void setServerBase(String base) => _overrideBase = base;

  static String get _defaultBase {
    // Production: Firebase Cloud Functions (accessible from any device/network)
    return 'https://us-central1-kol-dekeka.cloudfunctions.net/api';
  }

  static String get serverBase => _overrideBase ?? _defaultBase;

  // ── In-memory cache ────────────────────────────────────────────────────────
  static List<Video>? _cachedVideos;
  static List<Map<String, dynamic>>? _cachedChannels;
  static String _cachedChannel = 'all';

  static List<Video>? get cachedVideos => _cachedVideos;
  static List<Map<String, dynamic>>? get cachedChannels => _cachedChannels;
  static String get cachedChannel => _cachedChannel;

  static void clearCache() {
    _cachedVideos = null;
    _cachedChannels = null;
    _cachedChannel = 'all';
  }

  Future<VideoResponse> fetchVideos({
    String channel = 'all',
    int page = 1,
    int limit = 10,
  }) async {
    final uri = Uri.parse(
      '$serverBase/api/videos?channel=${Uri.encodeComponent(channel)}&page=$page&limit=$limit',
    );
    // Network request on the calling isolate; JSON decode offloaded via compute()
    final resp = await http.get(uri).timeout(const Duration(seconds: 15));
    if (resp.statusCode != 200) throw Exception('Server error ${resp.statusCode}');
    final data = await compute(_parseVideoBytes, resp.bodyBytes);
    final result = VideoResponse.fromJson(data);
    // Cache page-1 results for stale-while-revalidate
    if (page == 1) {
      _cachedVideos = result.videos;
      _cachedChannel = channel;
    }
    return result;
  }

  Future<List<Map<String, dynamic>>> fetchChannels() async {
    final uri = Uri.parse('$serverBase/api/video-channels');
    final resp = await http.get(uri).timeout(const Duration(seconds: 10));
    if (resp.statusCode != 200) return _cachedChannels ?? [];
    final data = await compute(_parseChannelsBytes, resp.bodyBytes);
    _cachedChannels = data.cast<Map<String, dynamic>>();
    return _cachedChannels!;
  }
}
