import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'api.dart';

final FlutterLocalNotificationsPlugin localNotifications = FlutterLocalNotificationsPlugin();

const AndroidNotificationChannel hbChannel = AndroidNotificationChannel(
  'hb_default',
  'হ্যাপি বাংলাদেশ',
  description: 'অর্ডার, ডেলিভারি ও সেটেলমেন্টের খবর',
  importance: Importance.high,
);

/// Shows a notification once, even if it arrives by Firebase push AND by the live connection
/// (the server gives both the same `nid`).
class Notifier {
  static final List<String> _seen = [];

  static Future<void> show(String title, String body, {String? nid}) async {
    if (nid != null) {
      if (_seen.contains(nid)) return;
      _seen.add(nid);
      if (_seen.length > 60) _seen.removeAt(0);
    }
    try {
      await localNotifications.show(
        id: (nid ?? DateTime.now().microsecondsSinceEpoch.toString()).hashCode & 0x7fffffff,
        title: title,
        body: body,
        notificationDetails: NotificationDetails(
          android: AndroidNotificationDetails(hbChannel.id, hbChannel.name,
              channelDescription: hbChannel.description, importance: Importance.high, priority: Priority.high),
        ),
      );
    } catch (e) {
      if (kDebugMode) debugPrint('notification failed: $e');
    }
  }
}

/// Firebase push (works when the app is closed). Needs android/app/google-services.json; without it the app
/// still gets live notifications while open through [Realtime].
class PushService {
  PushService._();
  static final PushService instance = PushService._();

  String? token;
  bool _firebaseReady = false;
  StreamSubscription? _refreshSub;
  StreamSubscription? _msgSub;

  static Future<void> initLocal() async {
    await localNotifications.initialize(
      settings: const InitializationSettings(android: AndroidInitializationSettings('@mipmap/ic_launcher')),
    );
    final android = localNotifications.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    await android?.createNotificationChannel(hbChannel);
  }

  /// Local notifications need the permission on Android 13+, with or without Firebase.
  Future<void> start() async {
    try {
      final android = localNotifications.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      await android?.requestNotificationsPermission();
    } catch (_) {}
    try {
      if (!_firebaseReady) {
        await Firebase.initializeApp();
        _firebaseReady = true;
      }
      final fm = FirebaseMessaging.instance;
      token = await fm.getToken();
      await _register();
      _refreshSub ??= fm.onTokenRefresh.listen((t) {
        token = t;
        _register();
      });
      _msgSub ??= FirebaseMessaging.onMessage.listen((m) {
        final n = m.notification;
        if (n != null) Notifier.show(n.title ?? '', n.body ?? '', nid: m.data['nid']?.toString());
      });
    } catch (e) {
      // No google-services.json (push not set up yet) or no Google services on this phone.
      if (kDebugMode) debugPrint('push disabled: $e');
    }
  }

  Future<void> _register() async {
    final t = token;
    if (t == null || ApiClient.token == null) return;
    try {
      await ApiClient.send('POST', '/device', body: {'fcm_token': t, 'platform': 'android', 'app_version': ApiClient.versionName});
    } catch (_) {/* retried on next start / token refresh */}
  }

  Future<void> stop() async {
    token = null;
    await _refreshSub?.cancel();
    await _msgSub?.cancel();
    _refreshSub = null;
    _msgSub = null;
    if (_firebaseReady) {
      try {
        await FirebaseMessaging.instance.deleteToken();
      } catch (_) {}
    }
  }
}
