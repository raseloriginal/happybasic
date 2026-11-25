import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';

import 'config.dart';
import 'store.dart';

class ApiException implements Exception {
  ApiException(this.message, {this.status = 0, this.errors = const {}, this.network = false, this.code});
  final String message;
  final int status;
  final Map<String, dynamic> errors;
  final bool network; // no connection / timeout: the request may not have reached the server
  final String? code;
  @override
  String toString() => message;
}

/// Outcome of a write that may be parked in the offline queue.
class WriteResult {
  WriteResult({this.data = const {}, this.queued = false});
  final Map<String, dynamic> data;
  final bool queued;
}

/// Thin JSON client for /api/v1. Bearer token, app build header, 401 / 426 hooks.
class ApiClient {
  static String _base = AppConfig.defaultBase;
  static String? token;
  static int buildNumber = 1;
  static String versionName = '1.0.0';
  static String _userAgent = 'HappyBangladesh/1.0.0';

  /// Called when the server says the session is over (401 on a non-login call).
  static void Function()? onUnauthorized;
  /// Called when this build is older than the server's minimum.
  static void Function(String message)? onUpdateRequired;

  static String get base => _base;
  static String get origin => Uri.parse(_base).origin;

  static Future<void> init() async {
    final saved = LocalStore.getString('server_base');
    if (saved != null && saved.isNotEmpty) _base = saved;
    token = LocalStore.getString('token');
    try {
      final info = await PackageInfo.fromPlatform();
      buildNumber = int.tryParse(info.buildNumber) ?? 1;
      versionName = info.version;
      final android = await DeviceInfoPlugin().androidInfo;
      _userAgent =
          'HappyBangladesh/$versionName (${android.manufacturer} ${android.model}; Android ${android.version.release})';
    } catch (_) {
      _userAgent = 'HappyBangladesh/$versionName';
    }
  }

  static Future<void> setBase(String url) async {
    var u = url.trim();
    while (u.endsWith('/')) {
      u = u.substring(0, u.length - 1);
    }
    _base = u.isEmpty ? AppConfig.defaultBase : u;
    await LocalStore.setString('server_base', u.isEmpty ? null : u);
  }

  static Future<void> setToken(String? t) async {
    token = t;
    await LocalStore.setString('token', t);
  }

  /// Makes a server path (e.g. "/happybasic/uploads/x.webp") loadable.
  static String? asset(Object? path) {
    final p = path?.toString();
    if (p == null || p.isEmpty) return null;
    if (p.startsWith('http')) return p;
    return '$origin${p.startsWith('/') ? '' : '/'}$p';
  }

  static Uri _uri(String path, [Map<String, dynamic>? query]) {
    final q = query?.map((k, v) => MapEntry(k, '$v'))
      ?..removeWhere((k, v) => v == 'null');
    return Uri.parse('$_base/api/v1$path').replace(queryParameters: (q == null || q.isEmpty) ? null : q);
  }

  static Map<String, String> _headers({String? opId, bool json = true}) => {
        'Accept': 'application/json',
        if (json) 'Content-Type': 'application/json',
        'User-Agent': _userAgent,
        'X-App-Version': '$buildNumber',
        if (token != null) 'Authorization': 'Bearer $token',
        if (opId != null) 'X-Op-Id': opId,
      };

  static Future<Map<String, dynamic>> get(String path, {Map<String, dynamic>? query}) =>
      _run(() => http.get(_uri(path, query), headers: _headers()), path);

  static Future<Map<String, dynamic>> send(String method, String path, {Object? body, String? opId}) {
    final uri = _uri(path);
    final h = _headers(opId: opId);
    final payload = body == null ? null : jsonEncode(body);
    return _run(() {
      switch (method) {
        case 'POST':
          return http.post(uri, headers: h, body: payload ?? '{}');
        case 'PUT':
          return http.put(uri, headers: h, body: payload ?? '{}');
        case 'DELETE':
          return http.delete(uri, headers: h, body: payload);
        default:
          throw ArgumentError(method);
      }
    }, path);
  }

  static Future<Map<String, dynamic>> upload(String path, String field, File file) async {
    return _run(() async {
      final req = http.MultipartRequest('POST', _uri(path))
        ..headers.addAll(_headers(json: false))
        ..files.add(await http.MultipartFile.fromPath(field, file.path));
      return http.Response.fromStream(await req.send());
    }, path, timeout: const Duration(seconds: 60));
  }

  static Future<Map<String, dynamic>> _run(Future<http.Response> Function() call, String path,
      {Duration timeout = const Duration(seconds: 25)}) async {
    http.Response res;
    try {
      res = await call().timeout(timeout);
    } on TimeoutException {
      throw ApiException('সার্ভার সাড়া দিচ্ছে না। ইন্টারনেট দেখে আবার চেষ্টা করুন।', network: true);
    } on SocketException {
      throw ApiException('ইন্টারনেট সংযোগ নেই।', network: true);
    } on http.ClientException {
      throw ApiException('ইন্টারনেট সংযোগ নেই।', network: true);
    } on HandshakeException {
      throw ApiException('নিরাপদ সংযোগ স্থাপন করা যায়নি। ফোনের তারিখ ও সময় ঠিক আছে কিনা দেখুন।', network: true);
    }

    Map<String, dynamic> data = {};
    try {
      final decoded = jsonDecode(utf8.decode(res.bodyBytes));
      if (decoded is Map<String, dynamic>) data = decoded;
    } catch (_) {/* non-JSON (proxy error page, etc.) */}

    if (res.statusCode == 426) {
      final m = (data['message'] ?? 'অ্যাপ আপডেট করুন।').toString();
      onUpdateRequired?.call(m);
      throw ApiException(m, status: 426, code: 'update_required');
    }
    if (res.statusCode == 401) {
      if (path != '/auth/login') onUnauthorized?.call();
      throw ApiException((data['message'] ?? 'সেশন শেষ হয়েছে। আবার লগইন করুন।').toString(), status: 401, code: 'unauthenticated');
    }
    if (res.statusCode >= 500) {
      // Treated like "try later": the offline queue keeps the op.
      throw ApiException('সার্ভারে সমস্যা হয়েছে। একটু পরে আবার চেষ্টা করুন।', status: res.statusCode, network: true);
    }
    if (res.statusCode >= 400 || data['ok'] == false) {
      throw ApiException(
        (data['message'] ?? data['error'] ?? 'কিছু একটা ভুল হয়েছে।').toString(),
        status: res.statusCode,
        errors: data['errors'] is Map ? Map<String, dynamic>.from(data['errors'] as Map) : const {},
      );
    }
    return data;
  }

  /// Unique id for an idempotent write (X-Op-Id): a retry can never apply twice.
  static String newOpId() {
    final r = Random.secure();
    final b = List<int>.generate(12, (_) => r.nextInt(256));
    return 'a${DateTime.now().millisecondsSinceEpoch.toRadixString(36)}${b.map((e) => e.toRadixString(16).padLeft(2, '0')).join()}';
  }
}
