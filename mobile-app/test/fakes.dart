import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:happy_bangladesh/core/api.dart';
import 'package:happy_bangladesh/core/session.dart';
import 'package:happy_bangladesh/core/store.dart';
import 'package:happy_bangladesh/ui/common.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Requests the screens made, so tests can check what was sent.
final List<String> calls = [];
final Map<String, Object> overrides = {}; // "METHOD /path" -> json body or ApiFail

class ApiFail {
  ApiFail(this.status, this.message);
  final int status;
  final String message;
}

// ---------------------------------------------------------------- data (same shapes as /api/v1, see docs/api)

Map<String, dynamic> _product(int id, String name, {int stock = 800}) => {
      'id': '$id', 'name': name, 'unit_type': 'Dozen', 'qty_per_unit': 12, 'unit_price': 6360, 'pc_price': 530,
      'available_pcs': stock, 'image': null, 'tint': '#fefce8', 'code': 'SK',
    };

Map<String, dynamic> _order(int id, {String status = 'pending', bool editable = true}) => {
      'id': id, 'code': 'ORD-261125-0000$id', 'date': '2026-11-25', 'time': '07:30 PM', 'sr_id': 4, 'sr': 'Salman khan',
      'company_id': 4, 'company': 'Transcom', 'retailer_id': 261, 'retailer': 'রাজকুমার স্টোর', 'retailer_address': 'বাজার',
      'retailer_phone': '01712345678', 'trip': null, 'trip_date': null, 'dsr': null, 'base_total': 3180, 'sr_total': 3150, 'oc': -30,
      'delivered_total': 0, 'paid': 0, 'due': 0, 'damage': 0, 'notes': null, 'cancel_reason': null, 'status': 'Pending',
      'status_key': status, 'editable': editable,
      'items': [
        {'product_id': 1, 'name': 'Salman khan', 'unit_type': 'Dozen', 'qty_per_unit': 12, 'pcs': 6, 'qty': '0 Dozen 6 pcs', 'delivered_pcs': 0,
          'base_rate_pc': 530, 'sr_rate_pc': 525, 'total': 3150, 'oc': -30, 'image': null, 'code': 'SK', 'tint': '#fefce8'}
      ],
    };

Map<String, dynamic> _stats() => {
      'orders': 6, 'retailers': 6, 'value': 44010, 'oc': 20, 'over_oc': 60, 'comm_oc': -40, 'delivered': 18575, 'delivery_oc': 25,
      'pending': 3, 'assigned': 0, 'done': 3, 'delivery_rate': 100,
    };

Map<String, dynamic> _stop(String id, String name, {String status = 'Pending'}) => {
      'id': id, 'retailer_name': name, 'phone': '+880 1712-345678', 'address': 'বাজার রোড', 'lat': 24.28, 'lng': 88.75,
      'sr_names': ['Rabiya islam'],
      'companies': [
        {
          'id': '5', 'order_code': 'ORD-261122-00005', 'name': 'Transcom', 'company_id': 4, 'sr': 'Rabiya islam', 'ready_sale': false,
          'status_key': 'assigned', 'cancelled': false, 'cancel_reason': null,
          'items': [
            {'product_id': '1', 'name': 'Salman khan', 'unit_type': 'Dozen', 'qty_per_unit': 12, 'ordered_qty': 13, 'qty': 13, 'base_rate': 530, 'sr_rate': 529.9, 'stock': 21}
          ],
        }
      ],
      'damages': [
        {'order_id': 5, 'product_id': 1, 'name': 'Salman khan', 'pcs': 1, 'amount': 530}
      ],
      'old_due_collected': 0, 'existing_due': 1200, 'paid_amount': 0, 'due_amount': 0, 'cancel_reason': '', 'status': status, 'editable': true,
    };

Map<String, dynamic> _trip({bool editable = true}) => {
      'id': 1, 'code': 'TRP-261125-0001', 'date': '2026-11-25', 'partner_id': 2, 'status_key': 'dispatched', 'editable': editable,
      'settlement_status': null, 'review_note': null, 'dispatched_at': '2026-11-25 14:58:49', 'sr_ids': [4],
    };

Map<String, dynamic> _van() => {
      'id': 1, 'name': 'Salman khan', 'company': 'Transcom', 'company_id': 4, 'unit_type': 'Dozen', 'qty_per_unit': 12, 'base_rate': 530,
      'ordered_pcs': 48, 'dispatched_pcs': 60, 'delivered_pcs': 39, 'ready_sold_pcs': 4, 'available_pcs': 21, 'delivery_oc': 25,
      'image': null, 'code': 'SK', 'tint': '#fefce8',
    };

Map<String, dynamic> _retailerOrder() => {
      'id': 5, 'code': 'HB-০০০৫', 'company': 'Transcom', 'sr': 'Rabiya islam', 'dm': 'safar', 'trip_id': 1, 'stage': 'arrived', 'status': 'বাকি',
      'tone': 'warn', 'time': '2:58', 'delivered_at': '2026-11-25 14:58:00', 'date': '2026-11-25', 'bill': 3210,
      'shop': {'name': 'রহিম স্টোর', 'address': 'বাজার', 'phone': '+880 1712-345678'},
      'partner': {'name': 'Sabbir Alam', 'address': 'ঢাকা', 'phone': '+880 1700-000000'},
      'items': [
        {'name': 'Salman khan', 'mrp': 600, 'pcs': 6, 'rate': 529.92, 'amount': 3179.5, 'gain': 420.5, 'short': 0},
        {'name': 'Other product', 'mrp': null, 'pcs': 2, 'rate': 100, 'amount': 200, 'gain': null, 'short': 1},
      ],
      'subtotal': 3379.5, 'damage': 0, 'total': 3379.5, 'paid': 100, 'due': 3279.5, 'mrp_total': null, 'profit': null, 'profit_per_100': null,
      'words': 'তিন হাজার তিনশত উনআশি',
    };

Map<String, dynamic> _settlement({bool pending = false}) => {
      'trip': {'id': 1, 'code': 'TRP-261125-0001', 'date': '2026-11-25', 'dsr': 'safar', 'status_key': 'dispatched', 'status': 'Dispatched', 'settlement_status': null, 'review_note': null, 'submitted_at': null, 'approved_at': null},
      'counts': {'orders': 6, 'pending': pending ? 2 : 0, 'cancelled': 1, 'stops_total': 4, 'stops_done': 4, 'due_shops': 2},
      'summary': {
        'order_amount': 25463.92, 'total_load': 31800, 'return_amount': 11130, 'total_sales_base': 18550, 'total_sales_sr': 18575, 'ready_sale': 2120,
        'prior_due_collected': 0, 'system_cash': 6355, 'damaged_amount': 2120, 'daily_expenses': 345, 'expense_categories': ['Helper'],
        'delivery_oc': 25, 'retailer_due': 12220, 'paid': 6355, 'net_pay': 6010,
      },
      'cash': null,
      'damage_review': {'dsr_amount': 2120, 'partner_amount': null, 'partner_note': null, 'items': []},
      'return_items': [
        {'image': null, 'code': 'SK', 'tint': '#fefce8', 'product_id': 1, 'name': 'Salman khan', 'company': 'Transcom', 'unit_type': 'Dozen', 'qty_per_unit': 12,
          'base_rate': 530, 'dispatched_pcs': 60, 'delivered_pcs': 39, 'expected_return_pcs': 21, 'counted_return_pcs': 21, 'reason': 'বাতিল'}
      ],
      'expenses': [],
      'notes': [for (final v in [1000, 500, 200, 100, 50, 20, 10, 5, 2, 1]) {'value': v, 'qty': 0}],
      'sr_oc_rows': [],
      'due_details': [
        {'order_id': 'ORD-261122-00010', 'retailer': 'বসির স্টোর', 'phone': '8477036336', 'area': '', 'order_total': 3210, 'paid': 0, 'due': 3210}
      ],
    };

Map<String, dynamic> defaultRoutes(String key) {
  switch (key) {
    case 'POST /auth/login':
      return {'ok': true, 'token': 'a' * 64, 'role': 'sr', 'profile': {'user_id': 4, 'name': 'Salman khan', 'phone': '01711889012', 'role': 'sr', 'sr_id': 1, 'code': 'SR-0001', 'area': 'Bagha', 'company': 'ACI', 'partner': 'Partner', 'photo': null, 'daily_target': 50000}};
    case 'GET /auth/me':
      return {'ok': true, 'role': 'sr', 'profile': {'name': 'Salman khan', 'phone': '01711889012', 'role': 'sr'}};
    case 'GET /app/version':
      return {'ok': true, 'update': false};
    // ---- SR
    case 'GET /sr/bootstrap':
      return {
        'ok': true, 'server_time': 1795587450,
        'products': [_product(1, 'Salman khan'), _product(2, 'বাংলা পণ্য', stock: 3)],
        'retailers': [
          for (var i = 0; i < 30; i++)
            {'id': '${100 + i}', 'name': 'দোকান $i', 'phone': i.isEven ? '' : '01712-3456$i', 'address': 'ঠিকানা $i', 'lat': 24.28 + i / 1000, 'lng': 88.75, 'sr_id': 4, 'due': i == 3 ? 500 : 0}
        ],
        'day': {'date': '2026-11-25', 'completed': false, 'locked': false, 'orders': [_order(15)], 'totals': {'orders': 1, 'value': 3150, 'oc': -30}},
        'day_completed': false,
      };
    case 'GET /sr/dashboard':
      return {
        'ok': true, 'date': '2026-11-25',
        'profile': {'name': 'Salman khan', 'initials': 'SK', 'code': 'SR-0001', 'phone': '+880 1711-889012', 'email': null, 'area': 'Bagha', 'company': 'ACI', 'partner': 'P',
          'joining_date': '20 Nov 2026', 'daily_target': 50000, 'monthly_target': 1000000, 'oc_balance': 25, 'retailers_added': 2, 'status': 'Active'},
        'today': _stats(), 'month': _stats(), 'day_completed': false,
      };
    case 'GET /sr/history':
      return {'ok': true, 'date': '2026-11-23', 'today': '2026-11-25', 'orders': [_order(15), {..._order(16, status: 'cancelled', editable: false), 'cancel_reason': 'বন্ধ', 'dsr': 'safar'}]};
    case 'GET /sr/profile':
      return {
        'ok': true, 'date': '2026-11-23', 'today': '2026-11-25',
        'day_summary': {'date': '2026-11-23', 'stats': _stats(), 'products': [
          {'id': 1, 'name': 'Salman khan', 'unit_type': 'Dozen', 'qty_per_unit': 12, 'ordered_pcs': 12, 'dispatched_pcs': 0, 'delivered_pcs': 0, 'returned_pcs': 0, 'image': null, 'code': 'SK', 'tint': '#fefce8'}
        ]},
        'profile': {'name': 'Salman khan', 'initials': 'SK', 'code': 'SR-0001', 'phone': '+880 1711-889012', 'area': 'Bagha', 'company': 'ACI', 'partner': 'P', 'photo': null, 'daily_target': 0, 'monthly_target': 0, 'oc_balance': 25},
        'month': _stats(), 'month_label': 'November 2026',
      };
    case 'POST /sr/orders':
      return {'ok': true, 'message': 'অর্ডার সংরক্ষিত হয়েছে।', 'order': _order(17), 'warnings': ['স্টক কম'], 'day': {'date': '2026-11-25', 'completed': false, 'locked': false, 'orders': [], 'totals': {'orders': 0, 'value': 0, 'oc': 0}}};
    case 'POST /sr/orders/complete':
      return {'ok': true, 'message': 'সম্পন্ন'};
    case 'POST /sr/retailers':
      return {'ok': true, 'message': 'দোকান যোগ হয়েছে।', 'retailer': {'id': '999', 'name': 'নতুন'}};
    case 'POST /sr/track':
    case 'POST /dsr/track':
      return {'ok': true, 'saved': 1, 'tracking': true};
    // ---- DSR
    case 'GET /dsr/dashboard':
      return {
        'ok': true, 'date': '2026-11-25', 'today': '2026-11-25', 'dsr': {'name': 'safar', 'partner': 'Sabbir', 'photo': null}, 'trip': _trip(),
        'attendance': {'checked_in_at': '2026-11-25 10:03:21', 'late_min': 12},
        'stats': {'stops': 4, 'delivered': 2, 'due': 1, 'pending': 1, 'cancelled': 1, 'dispatched_pcs': 60, 'available_pcs': 21},
        'settlement': _settlement()['summary'],
      };
    case 'GET /dsr/delivery':
      return {
        'ok': true, 'trip': _trip(), 'selectedDate': '2026-11-25',
        'orders': [_stop('188', 'মিষ্টি ভ্যারাইটিজ স্টোর'), _stop('189', 'রহিম স্টোর', status: 'Delivered'), _stop('190', 'করিম', status: 'Due'), _stop('191', 'বাতিল দোকান', status: 'Cancelled')],
        'vanStock': [_van()],
        'damageProducts': [{'id': '1', 'name': 'Salman khan', 'company': 'Transcom', 'company_id': 4, 'unit_type': 'Dozen', 'qty_per_unit': 12, 'rate': 530, 'image': null}],
        'cancelReasons': ['Shop Closed', 'Owner / Decision Maker Not Available', 'Insufficient Cash / Credit Issue'], 'server_time': 1795587450,
      };
    case 'GET /dsr/van-stock':
      return {'ok': true, 'trip': _trip(), 'selectedDate': '2026-11-25', 'products': [_van()]};
    case 'GET /dsr/expenses':
      return {
        'ok': true, 'trip': _trip(), 'selectedDate': '2026-11-25',
        'expenses': [{'id': 7, 'title': 'ডিজেল', 'category': 'Fuel', 'amount': '345.00', 'note': null, 'time': '02:00 PM', 'date': '2026-11-25'}],
        'categories': ['Fuel', 'Helper', 'Food', 'Toll & Parking', 'Van Repair', 'Mobile / Communication', 'Other'],
      };
    case 'POST /dsr/expenses':
      return {'ok': true, 'message': 'খরচ যোগ হয়েছে', 'expenses': []};
    case 'GET /dsr/settlement':
      return {'ok': true, 'trip': _trip(), 'selectedDate': '2026-11-25', 'settlement': _settlement()};
    case 'POST /dsr/settlement':
      return {'ok': true, 'message': 'জমা হয়েছে'};
    case 'GET /dsr/attendance':
      return {
        'ok': true, 'selectedDate': '2026-11-25', 'is_today': true, 'today': null,
        'days': [
          {'date': '2026-11-24', 'day': 24, 'weekday': 2, 'status': 'present', 'value': 1, 'manual': false, 'time': '2026-11-24 14:03:21', 'late_min': 303, 'distance': 0},
          {'date': '2026-11-25', 'day': 25, 'weekday': 3, 'status': 'absent', 'value': 0, 'manual': true, 'time': null, 'late_min': 0, 'distance': null},
        ],
      };
    case 'GET /dsr/retailers':
      return {'ok': true, 'retailers': [for (var i = 0; i < 20; i++) {'id': '${300 + i}', 'name': 'দোকান $i', 'phone': '', 'address': 'ঠিকানা $i', 'lat': 24.2, 'lng': 88.7, 'due': 0}]};
    case 'POST /dsr/ready-sales':
      return {'ok': true, 'message': 'রেডি সেল হয়েছে', 'receipt': {'retailer': 'দোকান 1', 'total': 1590, 'codes': ['X'], 'items': [{'name': 'Salman khan', 'pcs': 3, 'rate': 530, 'total': 1590}]}};
    case 'POST /dsr/damages':
      return {'ok': true, 'message': 'ড্যামেজ সাবমিট হয়েছে', 'damageResult': {'count': 1, 'total': 530, 'retailer': 'x'}};
    // ---- retailer
    case 'GET /retailer/today':
      return {
        'ok': true, 'date': '2026-11-25', 'shop': {'name': 'রহিম স্টোর', 'address': 'বাজার', 'phone': '8476002609'},
        'day': {
          'orders': [_retailerOrder()],
          'cards': [
            {'title': 'Transcom-এর মাল', 'dm': 'safar', 'stage': 'arrived', 'chip': '✓ ২:৫৮-তে এসেছে', 'rows': [{'sr': 'Rabiya', 'company': 'Transcom', 'bill': 3210, 'id': 5}], 'total': 3210, 'first': 5},
            {'title': 'ACI-এর মাল', 'dm': null, 'stage': 'later', 'chip': 'পরে আসবে', 'rows': [], 'total': 0, 'first': 5},
          ],
          'total': 3210, 'counts': {'arrived': 1, 'onway': 0, 'later': 1},
        },
        'unread': 2,
      };
    case 'GET /retailer/day':
      return {'ok': true, 'date': '2026-11-22', 'date_label': '২২ নভেম্বর ২০২৬', 'orders': [_retailerOrder()], 'cards': [], 'total': 3210, 'counts': {}};
    case 'GET /retailer/history':
      return {'ok': true, 'rows': [{'date': '2026-11-25', 'day': '২৫', 'month': 'নভেম্বর', 'total': 3210, 'sub': 'আজ · ১টি ডেলিভারি', 'today': true}, {'date': '2026-11-22', 'day': '২২', 'month': 'নভেম্বর', 'total': 100, 'sub': '১টি ডেলিভারি', 'today': false}]};
    case 'GET /retailer/notifications':
      return {
        'ok': true, 'unread': 1,
        'events': [
          {'kind': 'arrived', 'at': '2026-11-25 14:00:00', 'title': 'safar মাল দিয়ে গেছে · ৳৩,২১০', 'group': 'আজ', 'when': 'এইমাত্র', 'unread': true},
          {'kind': 'onway', 'at': '2026-11-25 11:00:00', 'title': 'safar আসছে', 'group': 'আজ', 'when': '১১:০০', 'unread': false},
          {'kind': 'order', 'at': '2026-11-24 11:00:00', 'title': 'SR Rabiya · Transcom', 'sub': 'অর্ডার নিয়েছে · ৳৩,১৫০', 'group': 'গতকাল', 'when': 'সকাল ১১:০০', 'unread': false},
        ],
      };
    case 'POST /retailer/notifications/seen':
    case 'POST /device':
    case 'POST /auth/logout':
      return {'ok': true};
  }
  throw StateError('Test has no fake for $key');
}

http.Response _json(Object body, [int status = 200]) =>
    http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json; charset=utf-8'});

MockClient fakeServer() => MockClient((req) async {
      final path = req.url.path.replaceFirst(RegExp(r'^.*?/api/v1'), '');
      final key = '${req.method} $path';
      calls.add('$key${req.body.isEmpty ? '' : ' ${req.body}'}');
      final o = overrides[key];
      if (o is ApiFail) return _json({'ok': false, 'message': o.message}, o.status);
      if (o != null) return _json(o);
      if (RegExp(r'^POST /dsr/stops/\d+$').hasMatch(key)) return _json({'ok': true, 'message': 'ডেলিভারি সংরক্ষিত হয়েছে।'});
      if (RegExp(r'^(PUT|DELETE) /sr/orders/\d+$').hasMatch(key)) return _json({'ok': true, 'message': 'ঠিক আছে'});
      return _json(defaultRoutes(key));
    });

// ---------------------------------------------------------------- environment

void mockPlugins() {
  final m = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  void on(String ch, Future<Object?>? Function(MethodCall) f) => m.setMockMethodCallHandler(MethodChannel(ch), f);
  on('flutter.baseflow.com/geolocator', (c) async {
    switch (c.method) {
      case 'isLocationServiceEnabled':
        return true;
      case 'checkPermission':
      case 'requestPermission':
        return 2; // whileInUse
      case 'getCurrentPosition':
      case 'getLastKnownPosition':
        return {'latitude': 24.28, 'longitude': 88.75, 'timestamp': DateTime.now().millisecondsSinceEpoch, 'accuracy': 8.0, 'altitude': 0.0, 'heading': 0.0, 'speed': 0.0, 'speed_accuracy': 0.0, 'altitude_accuracy': 0.0, 'heading_accuracy': 0.0, 'is_mocked': false};
    }
    return null;
  });
  on('flutter.baseflow.com/permissions/methods', (c) async {
    if (c.method == 'checkPermissionStatus' || c.method == 'requestPermissions') {
      return c.method == 'checkPermissionStatus' ? 1 : {for (final p in (c.arguments as List)) p: 1};
    }
    return null;
  });
  on('hb/battery', (c) async => 77);
}

Future<void> setupEnv({String role = 'sr'}) async {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});
  await LocalStore.initForTest();
  mockPlugins();
  calls.clear();
  overrides.clear();
  await ApiClient.setToken('a' * 64);
}

/// Pumps [home] exactly like main.dart builds the app (theme, Bengali locale + localizations, AuthState).
Future<void> pumpApp(WidgetTester tester, Widget home) async {
  final auth = AuthState();
  await tester.pumpWidget(ChangeNotifierProvider<AuthState>.value(
    value: auth,
    child: MaterialApp(
      theme: buildTheme(),
      localizationsDelegates: const [GlobalMaterialLocalizations.delegate, GlobalWidgetsLocalizations.delegate, GlobalCupertinoLocalizations.delegate],
      locale: const Locale('bn', 'BD'),
      supportedLocales: const [Locale('bn', 'BD'), Locale('en')],
      home: home,
    ),
  ));
}

/// Lets network fakes, animations and timers settle.
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 120));
  }
}

T withFakeServer<T>(T Function() body) => http.runWithClient(body, fakeServer);
