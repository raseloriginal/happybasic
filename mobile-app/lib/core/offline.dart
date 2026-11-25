import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

import 'api.dart';
import 'store.dart';

/// One write waiting for the network.
class QueuedOp {
  QueuedOp({required this.id, required this.method, required this.path, required this.body, required this.label, required this.at, this.error});
  final String id;
  final String method;
  final String path;
  final Object? body;
  final String label;
  final int at;
  String? error; // set when the server refused it (needs the user's attention)

  Map<String, dynamic> toJson() => {'id': id, 'method': method, 'path': path, 'body': body, 'label': label, 'at': at, 'error': error};
  factory QueuedOp.fromJson(Map<String, dynamic> j) => QueuedOp(
        id: j['id'], method: j['method'], path: j['path'], body: j['body'], label: j['label'] ?? '', at: j['at'] ?? 0, error: j['error']);
}

/// Offline write queue. Every op carries an X-Op-Id, so a retry after a lost response never applies twice.
/// Order is kept: later ops (e.g. "complete the day") only run after the earlier ones succeeded.
class OfflineQueue extends ChangeNotifier {
  OfflineQueue._();
  static final OfflineQueue instance = OfflineQueue._();
  static const _key = 'offline_queue';

  final List<QueuedOp> _ops = [];
  bool _flushing = false;
  Timer? _timer;
  StreamSubscription? _conn;
  final StreamController<void> _synced = StreamController<void>.broadcast();

  /// Fires after at least one queued write reached the server.
  Stream<void> get onSynced => _synced.stream;

  List<QueuedOp> get ops => List.unmodifiable(_ops);
  int get pending => _ops.where((o) => o.error == null).length;
  int get failed => _ops.where((o) => o.error != null).length;
  bool get flushing => _flushing;

  Future<void> init() async {
    final raw = await LocalStore.readJson(_key);
    if (raw is List) {
      _ops
        ..clear()
        ..addAll(raw.whereType<Map>().map((m) => QueuedOp.fromJson(Map<String, dynamic>.from(m))));
    }
    _conn = Connectivity().onConnectivityChanged.listen((r) {
      if (!r.contains(ConnectivityResult.none)) flush();
    });
    _timer = Timer.periodic(const Duration(seconds: 45), (_) => flush());
    flush();
  }

  Future<void> _save() => LocalStore.writeJson(_key, _ops.map((o) => o.toJson()).toList());

  Future<void> enqueue(QueuedOp op) async {
    _ops.add(op);
    await _save();
    notifyListeners();
  }

  Future<void> discard(String id) async {
    _ops.removeWhere((o) => o.id == id);
    await _save();
    notifyListeners();
  }

  /// Sends everything that is waiting. Safe to call at any time (re-entrant calls are ignored).
  Future<void> flush() async {
    if (_flushing || ApiClient.token == null) return;
    if (_ops.every((o) => o.error != null)) return;
    _flushing = true;
    notifyListeners();
    var any = false;
    try {
      for (final op in List<QueuedOp>.from(_ops)) {
        if (op.error != null) continue;
        try {
          await ApiClient.send(op.method, op.path, body: op.body, opId: op.id);
          _ops.removeWhere((o) => o.id == op.id);
          any = true;
          await _save();
        } on ApiException catch (e) {
          if (e.network || e.status == 401 || e.status == 426) break; // try again later
          op.error = e.message; // refused for good: keep it visible, carry on with the rest
          await _save();
        }
      }
    } finally {
      _flushing = false;
      notifyListeners();
      if (any) _synced.add(null);
    }
  }

  Future<void> clearAll() async {
    _ops.clear();
    await LocalStore.deleteJson(_key);
    notifyListeners();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _conn?.cancel();
    super.dispose();
  }

  /// Sends a write now; if the phone is offline (or the server is down) parks it in the queue.
  static Future<WriteResult> write(String method, String path,
      {Object? body, required String label, bool queueable = true}) async {
    final opId = ApiClient.newOpId();
    try {
      final data = await ApiClient.send(method, path, body: body, opId: opId);
      return WriteResult(data: data);
    } on ApiException catch (e) {
      if (queueable && e.network) {
        await instance.enqueue(QueuedOp(
            id: opId, method: method, path: path, body: body, label: label, at: DateTime.now().millisecondsSinceEpoch ~/ 1000));
        return WriteResult(queued: true);
      }
      rethrow;
    }
  }
}
