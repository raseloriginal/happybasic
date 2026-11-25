import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'api.dart';
import 'offline.dart';
import 'push.dart';

/// Live connection to the Node realtime service (Server-Sent Events, `/rt/app`).
/// While the app is open the server pushes events the moment they happen:
///   notify  -> a notification (shown at once)
///   refresh -> something changed, screens reload
/// If the service is unreachable the app keeps working: screens still refresh on pull-down, on resume and
/// every minute (see [pollInterval]); it retries the connection with a growing delay.
class Realtime {
  Realtime._();
  static final Realtime instance = Realtime._();

  static const pollInterval = Duration(seconds: 60);

  final StreamController<String> _events = StreamController<String>.broadcast();
  /// Fires with the event name ("refresh", "notify", "resume", "poll").
  Stream<String> get events => _events.stream;

  http.Client? _client;
  bool _running = false;
  bool connected = false;
  int _fails = 0;
  Timer? _retry;
  Timer? _poll;

  void start() {
    if (_running) return;
    _running = true;
    _fails = 0;
    _connect();
    _poll = Timer.periodic(pollInterval, (_) {
      if (!connected) _events.add('poll'); // live link is down: screens refresh on a timer instead
    });
  }

  void stop() {
    _running = false;
    connected = false;
    _retry?.cancel();
    _poll?.cancel();
    _client?.close();
    _client = null;
  }

  /// App came back to the foreground.
  void resumed() {
    if (!_running) return;
    OfflineQueue.instance.flush();
    _events.add('resume');
    if (!connected) {
      _retry?.cancel();
      _fails = 0;
      _connect();
    }
  }

  Future<void> _connect() async {
    if (!_running || ApiClient.token == null) return;
    final client = http.Client();
    _client = client;
    try {
      final req = http.Request('GET', Uri.parse('${ApiClient.base}/rt/app'))
        ..headers.addAll({'Authorization': 'Bearer ${ApiClient.token}', 'Accept': 'text/event-stream', 'Cache-Control': 'no-cache'});
      final res = await client.send(req).timeout(const Duration(seconds: 20));
      if (res.statusCode == 401) {
        // The session is gone: let the normal API path log the user out.
        ApiClient.onUnauthorized?.call();
        return;
      }
      if (res.statusCode != 200) throw StateError('status ${res.statusCode}');

      String event = 'message';
      final data = StringBuffer();
      await for (final line in res.stream.transform(utf8.decoder).transform(const LineSplitter())) {
        if (!_running || !identical(_client, client)) return;
        if (line.startsWith('event:')) {
          event = line.substring(6).trim();
        } else if (line.startsWith('data:')) {
          data.write(line.substring(5).trim());
        } else if (line.isEmpty) {
          if (event == 'ready') {
            connected = true;
            _fails = 0;
          } else {
            _handle(event, data.toString());
          }
          event = 'message';
          data.clear();
        }
      }
    } catch (e) {
      if (kDebugMode) debugPrint('realtime: $e');
    } finally {
      connected = false;
      client.close();
    }
    if (!_running || !identical(_client, client)) return;
    // Backoff: 3s, 6s, 12s ... 5 min. (Server may simply not offer the service.)
    _fails++;
    final secs = (3 * (1 << (_fails > 7 ? 7 : _fails - 1))).clamp(3, 300);
    _retry = Timer(Duration(seconds: secs), _connect);
  }

  void _handle(String event, String raw) {
    Map<String, dynamic> d = {};
    try {
      final j = jsonDecode(raw);
      if (j is Map<String, dynamic>) d = j;
    } catch (_) {}
    if (event == 'notify') {
      Notifier.show('${d['title'] ?? 'হ্যাপি বাংলাদেশ'}', '${d['body'] ?? ''}', nid: d['nid']?.toString());
    }
    _events.add(event == 'notify' ? 'refresh' : event);
  }
}
