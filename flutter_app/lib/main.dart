import 'dart:async';
import 'dart:convert';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:google_fonts/google_fonts.dart';
import 'models/article.dart';
import 'screens/article_screen.dart';
import 'screens/home_screen.dart';
import 'services/ad_service.dart';
import 'services/background_sync.dart';
import 'services/widget_service.dart';
import 'widgets/perf_overlay.dart';

// Global navigator key so notification handlers can push routes
final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();

// Stores notification data from terminated-state tap — consumed once the
// navigator is mounted (avoids null-state race condition).
Map<String, dynamic>? _pendingNotificationData;

void _navigateToArticle(Map<String, dynamic> data) {
  final link = data['link']?.toString() ?? '';
  if (link.isEmpty) return;
  final article = Article(
    id: data['articleId']?.toString() ?? '',
    title: data['title']?.toString() ?? data['source']?.toString() ?? '',
    link: link,
    description: '',
    pubDate: DateTime.now(),
    source: data['source']?.toString() ?? '',
    color: '#2c3e50',
    lang: 'ar',
    image: null,
    aiImage: false,
    domain: '',
    isNew: false,
  );
  _navigatorKey.currentState?.push(
    MaterialPageRoute(builder: (_) => ArticleScreen(article: article)),
  );
}

// ── Notification channel (Android) ───────────────────────────────────────────
const AndroidNotificationChannel _channel = AndroidNotificationChannel(
  'news_updates',
  'أخبار جديدة',
  description: 'إشعارات أخبار كل ساعة',
  importance: Importance.high,
);

final FlutterLocalNotificationsPlugin _localNotif =
    FlutterLocalNotificationsPlugin();

// Handle FCM messages when app is in background/terminated
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Firebase must init before runApp (other services use it)
  await Firebase.initializeApp();
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

  // Handle notification tap when app is in background (resumed state)
  FirebaseMessaging.onMessageOpenedApp.listen((msg) => _navigateToArticle(msg.data));

  // ── Terminated-state notification tap ─────────────────────────────────────
  // Must be retrieved BEFORE runApp so we have it ready before the navigator
  // is built. We store it and navigate once the navigator is confirmed ready.
  final initialMsg = await FirebaseMessaging.instance.getInitialMessage();
  if (initialMsg != null && initialMsg.data['link']?.toString().isNotEmpty == true) {
    _pendingNotificationData = initialMsg.data;
  }

  // Initialise AdMob SDK
  await AdService.init();

  // Background sync init (WorkManager)
  await BackgroundSync.init();

  // Lock orientation then show UI immediately
  unawaited(SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]));

  // Cap image cache to 40 MB / 80 images
  PaintingBinding.instance.imageCache.maximumSize = 80;
  PaintingBinding.instance.imageCache.maximumSizeBytes = 40 * 1024 * 1024;

  runApp(const ArabNewsApp());

  // Defer heavy init to after first frame so UI appears instantly
  WidgetsBinding.instance.addPostFrameCallback((_) async {
    await _localNotif
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(_channel);

    const initSettings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(
        requestAlertPermission: true,
        requestBadgePermission: true,
        requestSoundPermission: true,
      ),
      macOS: DarwinInitializationSettings(),
    );
    await _localNotif.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (NotificationResponse response) {
        final payload = response.payload;
        if (payload != null && payload.isNotEmpty) {
          try {
            final data = jsonDecode(payload) as Map<String, dynamic>;
            _navigateToArticle(data);
          } catch (_) {}
        }
      },
    );

    unawaited(_localNotif
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission());

    await WidgetService.init();
    unawaited(WidgetService.update());

    // ── FCM setup ────────────────────────────────────────────────────────────
    final messaging = FirebaseMessaging.instance;

    // Request permission (iOS / Android 13+)
    await messaging.requestPermission(alert: true, badge: true, sound: true);

    // Subscribe to the topic the server publishes to
    await messaging.subscribeToTopic('news_updates');

    // Register background periodic sync task
    unawaited(BackgroundSync.register());

    // Show local notification when app is in the foreground
    FirebaseMessaging.onMessage.listen((RemoteMessage msg) {
      final n = msg.notification;
      if (n == null) return;
      final payload = jsonEncode({
        'articleId': msg.data['articleId'] ?? '',
        'source': msg.data['source'] ?? n.title ?? '',
        'link': msg.data['link'] ?? '',
        'title': n.body ?? '',
      });
      _localNotif.show(
        msg.hashCode,
        n.title ?? 'كل دقيقة',
        n.body,
        NotificationDetails(
          android: AndroidNotificationDetails(
            _channel.id,
            _channel.name,
            channelDescription: _channel.description,
            importance: Importance.high,
            priority: Priority.high,
            icon: '@mipmap/ic_launcher',
          ),
          iOS: const DarwinNotificationDetails(),
        ),
        payload: payload,
      );
    });

    // Navigate for terminated-state tap — delayed to let the navigator settle
    if (_pendingNotificationData != null) {
      await Future.delayed(const Duration(milliseconds: 800));
      _navigateToArticle(_pendingNotificationData!);
      _pendingNotificationData = null;
    }
  });
}

class ArabNewsApp extends StatelessWidget {
  const ArabNewsApp({super.key});

  // Built once — avoids recreating GoogleFonts text theme on every rebuild
  static final ThemeData _theme = _buildTheme();

  static ThemeData _buildTheme() {
    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: Colors.black,
      colorScheme: const ColorScheme.dark(
        primary: Color(0xFF2471a3),
        secondary: Color(0xFFa93226),
        surface: Color(0xFF0d0d1a),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Color(0xFF0d0d1a),
        foregroundColor: Colors.white,
        elevation: 0,
        systemOverlayStyle: SystemUiOverlayStyle(
          statusBarBrightness: Brightness.dark,
          statusBarIconBrightness: Brightness.light,
        ),
      ),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: CupertinoPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        },
      ),
    );
    return base.copyWith(
      textTheme: GoogleFonts.cairoTextTheme(base.textTheme).apply(
        bodyColor: Colors.white,
        displayColor: Colors.white,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'كل دقيقة',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.dark,
      theme: _theme,
      darkTheme: _theme,
      navigatorKey: _navigatorKey,
      home: const PerfOverlay(child: HomeScreen()),
    );
  }
}
