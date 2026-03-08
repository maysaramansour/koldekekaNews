import 'dart:convert';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';

const _taskName      = 'news_background_sync';
const _taskUnique    = 'kol_dekeka_news_sync';
const _prefSeenIds   = 'bg_sync_seen_ids';
const _apiBase       = 'https://us-central1-kol-dekeka.cloudfunctions.net/api';

// ── Background dispatcher ─────────────────────────────────────────────────────
// Must be a top-level function annotated vm:entry-point
@pragma('vm:entry-point')
void backgroundDispatcher() {
  Workmanager().executeTask((taskName, inputData) async {
    if (taskName != _taskName) return true;
    try {
      await _runSync();
    } catch (_) {}
    return true;
  });
}

Future<void> _runSync() async {
  // Firebase must be initialized in the background isolate
  await Firebase.initializeApp();

  // Fetch latest news (page 1, limit 10 — just headlines)
  final uri = Uri.parse('$_apiBase/api/news?source=all&page=1&limit=10&since=0');
  final resp = await http.get(uri,
      headers: {'Accept': 'application/json'})
      .timeout(const Duration(seconds: 20));
  if (resp.statusCode != 200) return;

  final data = json.decode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
  final rawArticles = (data['articles'] as List<dynamic>? ?? [])
      .whereType<Map<String, dynamic>>()
      .toList();
  if (rawArticles.isEmpty) return;

  // Compare with previously seen IDs
  final prefs = await SharedPreferences.getInstance();
  final seenSet = Set<String>.from(prefs.getStringList(_prefSeenIds) ?? []);
  final newOnes = rawArticles.where((a) => !seenSet.contains(a['id']?.toString() ?? '')).toList();
  if (newOnes.isEmpty) return;

  // Save updated seen IDs (keep last 50 to bound size)
  final allIds = rawArticles.map((a) => a['id']?.toString() ?? '').toList();
  await prefs.setStringList(_prefSeenIds, allIds.take(50).toList());

  // Show a local notification summarising new articles
  final count = newOnes.length;
  final topTitle = newOnes.first['title']?.toString() ?? '';
  final body = count == 1 ? topTitle : '$topTitle (+${count - 1} more)';

  final plugin = FlutterLocalNotificationsPlugin();
  const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
  await plugin.initialize(const InitializationSettings(android: androidSettings));

  const channel = AndroidNotificationChannel(
    'news_updates', 'أخبار جديدة',
    description: 'إشعارات أخبار كل ساعة',
    importance: Importance.high,
  );
  await plugin
      .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(channel);

  await plugin.show(
    0,
    'كل دقيقة — أخبار جديدة',
    body,
    NotificationDetails(
      android: AndroidNotificationDetails(
        channel.id, channel.name,
        channelDescription: channel.description,
        importance: Importance.high,
        priority: Priority.high,
        icon: '@mipmap/ic_launcher',
      ),
    ),
    payload: json.encode({
      'link': newOnes.first['link']?.toString() ?? '',
      'title': topTitle,
      'source': newOnes.first['source']?.toString() ?? '',
      'articleId': newOnes.first['id']?.toString() ?? '',
    }),
  );
}

// ── Public API ────────────────────────────────────────────────────────────────

class BackgroundSync {
  BackgroundSync._();

  /// Call once from main() after Firebase is initialized.
  static Future<void> init() async {
    await Workmanager().initialize(backgroundDispatcher, isInDebugMode: false);
  }

  /// Register (or replace) the periodic sync task.
  /// Runs every 15 minutes when network is available.
  static Future<void> register() async {
    await Workmanager().registerPeriodicTask(
      _taskUnique,
      _taskName,
      frequency: const Duration(minutes: 15),
      existingWorkPolicy: ExistingWorkPolicy.keep,
      constraints: Constraints(networkType: NetworkType.connected),
      backoffPolicy: BackoffPolicy.linear,
      backoffPolicyDelay: const Duration(minutes: 5),
    );
  }

  /// Seed the "seen" IDs from a fresh fetch so we don't notify about old news.
  static Future<void> markAllSeen(List<String> ids) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_prefSeenIds, ids.take(50).toList());
  }
}
