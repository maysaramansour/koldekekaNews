import 'dart:async';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:google_fonts/google_fonts.dart';
import 'screens/home_screen.dart';
import 'services/widget_service.dart';
import 'widgets/perf_overlay.dart';

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

  // Lock orientation then show UI immediately
  unawaited(SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]));

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
    await _localNotif.initialize(initSettings);

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

    // Show local notification when app is in the foreground
    FirebaseMessaging.onMessage.listen((RemoteMessage msg) {
      final n = msg.notification;
      if (n == null) return;
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
      );
    });
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
      home: const PerfOverlay(child: HomeScreen()),
    );
  }
}
