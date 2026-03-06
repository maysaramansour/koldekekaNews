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
    return VideoResponse.fromJson(data);
  }

  Future<List<Map<String, dynamic>>> fetchChannels() async {
    final uri = Uri.parse('$serverBase/api/video-channels');
    final resp = await http.get(uri).timeout(const Duration(seconds: 10));
    if (resp.statusCode != 200) return [];
    final data = await compute(_parseChannelsBytes, resp.bodyBytes);
    return data.cast<Map<String, dynamic>>();
  }
}
