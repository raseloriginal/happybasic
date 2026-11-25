import 'package:flutter/foundation.dart';

import 'api.dart';
import 'offline.dart';
import 'push.dart';
import 'realtime.dart';
import 'store.dart';
import 'tracker.dart';

/// Who is signed in. The role ('sr' | 'dsr' | 'retailer') decides which panel the app shows.
class AuthState extends ChangeNotifier {
  String? role;
  Map<String, dynamic> profile = {};
  bool ready = false;
  String? updateMessage; // set when the server demands a newer build

  bool get signedIn => ApiClient.token != null && role != null;

  Future<void> init() async {
    ApiClient.onUnauthorized = () => signOutLocal();
    ApiClient.onUpdateRequired = (m) {
      updateMessage = m;
      notifyListeners();
    };
    role = LocalStore.getString('role');
    final cached = LocalStore.getString('profile');
    if (cached != null) {
      profile = Map<String, dynamic>.from(await LocalStore.readJson('profile') ?? {});
    }
    ready = true;
    notifyListeners();
    if (signedIn) {
      _afterSignIn();
      refreshProfile();
    }
  }

  Future<void> login(String phone, String password) async {
    final res = await ApiClient.send('POST', '/auth/login', body: {'phone': phone, 'password': password});
    await LocalStore.clearCache();
    await ApiClient.setToken(res['token'] as String);
    role = res['role'] as String;
    profile = Map<String, dynamic>.from(res['profile'] as Map);
    await LocalStore.setString('role', role);
    await LocalStore.setString('profile', 'cached');
    await LocalStore.writeJson('profile', profile);
    notifyListeners();
    _afterSignIn();
  }

  void _afterSignIn() {
    PushService.instance.start();
    if (role == 'dsr' || role == 'sr') Tracker.instance.start(role!);
    Realtime.instance.start();
    OfflineQueue.instance.flush();
  }

  Future<void> refreshProfile() async {
    try {
      final res = await ApiClient.get('/auth/me');
      profile = Map<String, dynamic>.from(res['profile'] as Map);
      role = res['role'] as String;
      await LocalStore.setString('role', role);
      await LocalStore.writeJson('profile', profile);
      notifyListeners();
    } catch (_) {/* offline: keep the cached profile */}
  }

  Future<void> logout() async {
    try {
      await ApiClient.send('POST', '/auth/logout', body: {'fcm_token': PushService.instance.token});
    } catch (_) {/* token is dropped locally anyway */}
    await signOutLocal();
  }

  Future<void> signOutLocal() async {
    Realtime.instance.stop();
    Tracker.instance.stop();
    await PushService.instance.stop();
    await ApiClient.setToken(null);
    await LocalStore.setString('role', null);
    await LocalStore.setString('profile', null);
    await OfflineQueue.instance.clearAll();
    await LocalStore.clearCache();
    role = null;
    profile = {};
    notifyListeners();
  }

  String get name => (profile['name'] ?? '').toString();
}
