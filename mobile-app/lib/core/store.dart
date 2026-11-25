import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Small key/value settings (SharedPreferences) + JSON cache files for big payloads.
class LocalStore {
  static late SharedPreferences prefs;
  static late Directory _dir;
  static Map<String, String>? _mem; // tests: cache in memory (real file IO never completes inside fake-async tests)

  static Future<void> init() async {
    prefs = await SharedPreferences.getInstance();
    _dir = Directory('${(await getApplicationSupportDirectory()).path}/cache');
    if (!await _dir.exists()) await _dir.create(recursive: true);
  }

  /// Tests: keep the cache in memory.
  @visibleForTesting
  static Future<void> initForTest() async {
    prefs = await SharedPreferences.getInstance();
    _mem = {};
  }

  static String? getString(String key) => prefs.getString(key);
  static Future<void> setString(String key, String? value) async {
    if (value == null) {
      await prefs.remove(key);
    } else {
      await prefs.setString(key, value);
    }
  }

  static String _name(String key) => key.replaceAll(RegExp(r'[^A-Za-z0-9_.-]'), '_');
  static File _file(String key) => File('${_dir.path}/${_name(key)}.json');

  static Future<void> writeJson(String key, Object? data) async {
    try {
      if (_mem != null) {
        _mem![_name(key)] = jsonEncode(data);
        return;
      }
      await _file(key).writeAsString(jsonEncode(data), flush: true);
    } catch (_) {/* cache only */}
  }

  static Future<dynamic> readJson(String key) async {
    try {
      if (_mem != null) {
        final s = _mem![_name(key)];
        return s == null ? null : jsonDecode(s);
      }
      final f = _file(key);
      if (!await f.exists()) return null;
      return jsonDecode(await f.readAsString());
    } catch (_) {
      return null;
    }
  }

  static Future<void> deleteJson(String key) async {
    try {
      if (_mem != null) {
        _mem!.remove(_name(key));
        return;
      }
      final f = _file(key);
      if (await f.exists()) await f.delete();
    } catch (_) {}
  }

  /// Wipes everything cached for the signed-in user (on logout).
  static Future<void> clearCache({bool keepQueue = false}) async {
    try {
      if (_mem != null) {
        _mem!.removeWhere((k, _) => !(keepQueue && k.contains('offline_queue')));
        return;
      }
      await for (final e in _dir.list()) {
        if (keepQueue && e.path.contains('offline_queue')) continue;
        if (e is File) await e.delete();
      }
    } catch (_) {}
  }
}
