import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';

import 'api.dart';
import 'store.dart';

/// GPS trail of the signed-in SR or DSR. Runs as an Android foreground service (a notification stays visible)
/// so the partner's live map keeps updating with the screen off. Points are buffered on the phone and sent in
/// batches; nothing is lost when the network drops.
class Tracker extends ChangeNotifier {
  Tracker._();
  static final Tracker instance = Tracker._();
  static const _bufferKey = 'track_buffer';
  static const _battery = MethodChannel('hb/battery');

  StreamSubscription<Position>? _sub;
  Timer? _flushTimer;
  final List<Map<String, dynamic>> _buffer = [];
  bool _sending = false;
  String _path = '/dsr/track';

  bool running = false;
  String? problem; // shown to the user: permission / GPS off
  Position? last;

  Future<bool> ensurePermission() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      problem = 'ফোনের লোকেশন (GPS) চালু করুন।';
      notifyListeners();
      return false;
    }
    var p = await Geolocator.checkPermission();
    if (p == LocationPermission.denied) p = await Geolocator.requestPermission();
    if (p == LocationPermission.denied || p == LocationPermission.deniedForever) {
      problem = 'লোকেশনের অনুমতি দিন (সেটিংস → অ্যাপ → অনুমতি → লোকেশন)।';
      notifyListeners();
      return false;
    }
    problem = null;
    return true;
  }

  /// [role] is 'sr' or 'dsr': it decides which endpoint receives the points.
  Future<void> start(String role) async {
    _path = role == 'sr' ? '/sr/track' : '/dsr/track';
    if (running) return;
    final saved = await LocalStore.readJson(_bufferKey);
    if (saved is List && _buffer.isEmpty) _buffer.addAll(saved.whereType<Map>().map((m) => Map<String, dynamic>.from(m)));

    if (!await ensurePermission()) return;
    running = true;
    notifyListeners();

    final settings = AndroidSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 20,
      intervalDuration: const Duration(seconds: 20),
      foregroundNotificationConfig: const ForegroundNotificationConfig(
        notificationTitle: 'হ্যাপি বাংলাদেশ',
        notificationText: 'লোকেশন ট্র্যাকিং চালু আছে',
        enableWakeLock: true,
        setOngoing: true,
      ),
    );
    _sub = Geolocator.getPositionStream(locationSettings: settings).listen(_onPosition, onError: (_) {
      problem = 'লোকেশন পাওয়া যাচ্ছে না।';
      notifyListeners();
    });
    _flushTimer = Timer.periodic(const Duration(seconds: 30), (_) => flush());
  }

  Future<int?> _batteryLevel() async {
    try {
      final v = await _battery.invokeMethod<int>('level');
      return v != null && v >= 0 ? v : null;
    } catch (_) {
      return null;
    }
  }

  Future<void> _onPosition(Position p) async {
    last = p;
    if (p.isMocked) return; // fake-GPS apps are ignored
    final bat = await _batteryLevel();
    _buffer.add({
      't': p.timestamp.millisecondsSinceEpoch ~/ 1000,
      'lat': double.parse(p.latitude.toStringAsFixed(7)),
      'lng': double.parse(p.longitude.toStringAsFixed(7)),
      'acc': p.accuracy.round(),
      if (bat != null) 'bat': bat,
    });
    if (_buffer.length > 600) _buffer.removeRange(0, _buffer.length - 600);
    LocalStore.writeJson(_bufferKey, _buffer);
    if (_buffer.length >= 6) flush();
    notifyListeners();
  }

  Future<void> flush() async {
    if (_sending || _buffer.isEmpty || ApiClient.token == null) return;
    _sending = true;
    try {
      final batch = _buffer.take(300).toList();
      await ApiClient.send('POST', _path, body: {'points': batch});
      _buffer.removeRange(0, batch.length);
      await LocalStore.writeJson(_bufferKey, _buffer);
    } on ApiException catch (e) {
      if (!e.network && e.status != 401) {
        _buffer.clear(); // the server refuses these points: do not retry forever
        await LocalStore.writeJson(_bufferKey, _buffer);
      }
    } finally {
      _sending = false;
    }
  }

  Future<void> stop() async {
    await _sub?.cancel();
    _sub = null;
    _flushTimer?.cancel();
    _flushTimer = null;
    running = false;
    _buffer.clear();
    await LocalStore.deleteJson(_bufferKey);
    notifyListeners();
  }

  /// One-off position for forms (new shop, attendance, ready sale).
  static Future<Position?> currentOnce() async {
    if (!await instance.ensurePermission()) return null;
    try {
      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, timeLimit: Duration(seconds: 15)),
      );
    } catch (_) {
      return Geolocator.getLastKnownPosition();
    }
  }
}
