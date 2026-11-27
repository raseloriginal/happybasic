import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';

import 'api.dart';
import 'geo_filter.dart';
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
  int _gen = 0; // bumped by stop(): a start() that was still waiting for permission must not come alive afterwards
  String _path = '/dsr/track';

  bool running = false;
  String? problem; // shown to the user: permission / GPS off
  Position? last;

  /// Smoothed position for the maps; [heading] (degrees from north) is set only while moving.
  final ValueNotifier<({double lat, double lng, double accuracy, double? heading})?> fix = ValueNotifier(null);
  GeoFilter _filter = GeoFilter();
  int _liveHolders = 0; // maps on screen
  bool _live = false; // which settings the running stream uses
  Future<void> _switching = Future.value();
  Position? _sent; // last point put in the server buffer

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
    final gen = _gen;
    final saved = await LocalStore.readJson(_bufferKey);
    if (saved is List && _buffer.isEmpty) _buffer.addAll(saved.whereType<Map>().map((m) => Map<String, dynamic>.from(m)));

    if (!await ensurePermission() || gen != _gen || running) return;
    running = true;
    notifyListeners();

    _listen();
    _flushTimer = Timer.periodic(const Duration(seconds: 30), (_) => flush());
  }

  void _listen() {
    _live = _liveHolders > 0;
    final settings = AndroidSettings(
      accuracy: _live ? LocationAccuracy.bestForNavigation : LocationAccuracy.high,
      distanceFilter: _live ? 0 : 20,
      intervalDuration: Duration(seconds: _live ? 1 : 20),
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
  }

  /// A map calls this with true when it comes on screen and false when it leaves: one fix per second while any
  /// map is visible, the battery-friendly rate otherwise. Geolocator shares a single position stream, so the
  /// stream is closed and reopened with the other settings.
  Future<void> setLive(bool on) {
    _liveHolders += on ? 1 : -1;
    if (_liveHolders < 0) _liveHolders = 0;
    return _switching = _switching.then((_) async {
      final sub = _sub;
      if (!running || sub == null || _live == (_liveHolders > 0)) return;
      final gen = _gen;
      _sub = null;
      await sub.cancel();
      if (gen == _gen && running) _listen();
    });
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
    _updateFix(p);
    // The server trail keeps its old density (a point at most every 20 s and 20 m), also at the live rate.
    final prev = _sent;
    if (prev != null &&
        (p.timestamp.difference(prev.timestamp).inSeconds < 20 || GeoFilter.metres(prev.latitude, prev.longitude, p.latitude, p.longitude) < 20)) {
      return;
    }
    _sent = p;
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

  void _updateFix(Position p) {
    final f = _filter.push(lat: p.latitude, lng: p.longitude, accuracy: p.accuracy, speed: p.speed, timeMs: p.timestamp.millisecondsSinceEpoch);
    if (f == null) return;
    fix.value = (lat: f.lat, lng: f.lng, accuracy: f.accuracy, heading: p.speed > 0.8 && p.heading >= 0 ? p.heading : null);
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
    _gen++;
    _flushTimer?.cancel(); // synchronously: nothing may fire after stop() returns
    _flushTimer = null;
    final sub = _sub;
    _sub = null;
    running = false;
    _buffer.clear();
    _sent = null;
    _filter = GeoFilter();
    fix.value = null;
    notifyListeners();
    await sub?.cancel();
    await LocalStore.deleteJson(_bufferKey);
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
