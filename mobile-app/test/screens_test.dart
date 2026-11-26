import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:happy_bangladesh/auth/login_page.dart';
import 'package:happy_bangladesh/core/tracker.dart';
import 'package:happy_bangladesh/dsr/attendance_page.dart';
import 'package:happy_bangladesh/dsr/dsr_home.dart';
import 'package:happy_bangladesh/retailer/retailer_home.dart';
import 'package:happy_bangladesh/sr/sr_home.dart';
import 'package:happy_bangladesh/ui/pwa_kit.dart';
import 'package:http/http.dart' as http;

import 'fakes.dart';

/// Every screen is built with realistic server data and used the way a field user would.
/// A crash in any build (like a missing localization) shows up as a test exception.
void fakeTest(String name, Future<void> Function(WidgetTester t) body) {
  testWidgets(name, (t) async {
    kMapTiles = false; // no network in tests
    await setupEnv();
    await http.runWithClient(() async {
      try {
        await body(t);
        final ex = t.takeException();
        if (ex != null) debugPrint(ex is FlutterError ? ex.diagnostics.map((d) => d.toStringDeep()).join(' | ') : '$ex');
        expect(ex, isNull, reason: 'a widget threw while building / handling taps');
      } finally {
        Tracker.instance.stop(); // the SR / DSR screens start GPS tracking (timers); stop it like logout does
      }
    }, fakeServer);
  });
}

/// Taps a text, scrolling the page down first when it is further away (lists build lazily).
/// [last] taps the last match (e.g. the bottom-nav label, or a card below a search dropdown).
Future<void> tapText(WidgetTester t, String text, {int index = 0, bool last = false}) async {
  final f = find.text(text);
  for (var i = 0; i < 40 && f.evaluate().length <= index; i++) {
    await t.drag(find.byType(Scrollable).first, const Offset(0, -300), warnIfMissed: false);
    await t.pump(const Duration(milliseconds: 50));
  }
  expect(f.evaluate().length > index, isTrue, reason: 'text "$text" not found on screen (even after scrolling)');
  final target = last ? f.last : f.at(index);
  await t.ensureVisible(target);
  await t.pump(const Duration(milliseconds: 200));
  await t.tap(target);
  await settle(t);
}

/// Scrolls the visible page until [text] is built.
Future<void> see(WidgetTester t, String text) async {
  final f = find.text(text);
  for (var i = 0; i < 40 && f.evaluate().isEmpty; i++) {
    await t.drag(find.byType(Scrollable).first, const Offset(0, -300), warnIfMissed: false);
    await t.pump(const Duration(milliseconds: 50));
  }
  if (f.evaluate().isEmpty) {
    debugPrint('VISIBLE: ${find.byType(Text).evaluate().map((e) => (e.widget as Text).data ?? (e.widget as Text).textSpan?.toPlainText()).take(60).join(' | ')}');
  }
  expect(f, findsWidgets, reason: 'text "$text" not found on screen (even after scrolling)');
}

/// Pops the top route (the pages have their own round back button, not a Material BackButton).
Future<void> back(WidgetTester t) async {
  t.state<NavigatorState>(find.byType(Navigator).first).pop();
  await settle(t);
}

/// Bottom-navigation tab — the nav bar is the last widget with that label.
Future<void> tab(WidgetTester t, String label) async {
  await t.tap(find.text(label).last, warnIfMissed: false);
  await settle(t);
}

void main() {
  group('Login', () {
    fakeTest('renders both fields and shows a server error', (t) async {
      await pumpApp(t, const LoginPage());
      await settle(t);
      expect(find.byType(TextField), findsNWidgets(2));
      expect(find.text('সাইন ইন করুন'), findsWidgets);
      await t.enterText(find.byType(TextField).first, '01711889012');
      await t.enterText(find.byType(TextField).last, 'wrong');
      overrides['POST /auth/login'] = ApiFail(422, 'ফোন নম্বর বা পাসওয়ার্ড ভুল।');
      await tapText(t, 'সাইন ইন করুন', last: true);
      expect(find.text('ফোন নম্বর বা পাসওয়ার্ড ভুল।'), findsOneWidget);
    });

    fakeTest('empty fields show a hint, no request is sent', (t) async {
      await pumpApp(t, const LoginPage());
      await settle(t);
      await tapText(t, 'সাইন ইন করুন', last: true);
      expect(find.text('মোবাইল নম্বর ও পাসওয়ার্ড লিখুন।'), findsOneWidget);
      expect(calls.where((c) => c.startsWith('POST /auth/login')), isEmpty);
    });
  });

  group('SR', () {
    fakeTest('order map: shops, search, pick products, confirm and save an order', (t) async {
      await pumpApp(t, const SrHome());
      await settle(t);
      await tab(t, 'অর্ডার');
      expect(find.text('কাছের দোকান'), findsOneWidget);
      expect(find.text('রাজকুমার স্টোর'), findsWidgets); // within 50 m of the phone
      expect(find.text('দোকান 3'), findsNothing); // too far — only found by search

      await t.enterText(find.byType(TextField).first, 'দোকান 7');
      await settle(t);
      expect(find.text('দোকান 7'), findsWidgets);
      expect(find.text('দোকান 3'), findsNothing);
      expect(find.text('সকল এলাকা'), findsOneWidget);

      await t.tap(find.text('দোকান 7').last); // the card (the search dropdown is above it)
      await settle(t);
      expect(find.text('Salman khan'), findsWidgets);
      await tapText(t, 'Salman khan'); // product sheet: 1 dozen + 0 pcs by default
      final fields = find.byType(TextField);
      await t.enterText(fields.at(fields.evaluate().length - 4 + 1), '3'); // loose pcs field
      await settle(t);
      await tapText(t, 'অর্ডারে যোগ করুন');
      expect(find.text('অর্ডার পাঠান'), findsOneWidget);
      await tapText(t, 'অর্ডার পাঠান');
      expect(find.text('অর্ডার সারাংশ'), findsOneWidget);
      await tapText(t, 'অর্ডার কনফার্ম');
      expect(calls.any((c) => c.startsWith('POST /sr/orders {"retailer_id":107')), isTrue);
      expect(find.text('অর্ডার পাঠানো হয়েছে'), findsOneWidget);
      await t.pump(const Duration(seconds: 1));
      await tapText(t, 'অন্য দোকানে যান');
    });

    fakeTest('editing an existing order', (t) async {
      await pumpApp(t, const SrHome());
      await settle(t);
      await tab(t, 'অর্ডার');
      await t.tap(find.text('রাজকুমার স্টোর').last);
      await settle(t);
      expect(find.text('অর্ডার আপডেট'), findsOneWidget);
      await tapText(t, 'অর্ডার আপডেট');
      await tapText(t, 'অর্ডার কনফার্ম');
      expect(calls.any((c) => c.startsWith('PUT /sr/orders/15')), isTrue);
    });

    fakeTest('complete the day from the আজ sheet', (t) async {
      await pumpApp(t, const SrHome());
      await settle(t);
      await tab(t, 'অর্ডার');
      await t.tap(find.text('আজ').first);
      await settle(t);
      expect(find.text('আজকের অর্ডারসমূহ'), findsOneWidget);
      await tapText(t, 'আজকের অর্ডার সম্পন্ন করুন');
      await tapText(t, 'সম্পন্ন করুন');
      expect(calls.any((c) => c.startsWith('POST /sr/orders/complete')), isTrue);
    });

    fakeTest('dashboard, history (memo detail) and profile tabs', (t) async {
      await pumpApp(t, const SrHome());
      await settle(t);
      expect(find.textContaining('Salman khan'), findsWidgets);
      expect(find.text('নতুন অর্ডার'), findsOneWidget);
      expect(find.text('আজকের বিক্রি'), findsOneWidget);
      await tab(t, 'হিস্ট্রি');
      expect(find.text('অর্ডার হিস্ট্রি'), findsOneWidget);
      await tapText(t, 'রাজকুমার স্টোর');
      expect(find.text('আমার কপি'), findsOneWidget);
      await tapText(t, 'দোকানের কপি', index: 0);
      expect(find.text('আসল মেমো'), findsOneWidget);
      await back(t);
      await tab(t, 'আমি');
      expect(find.text('অর্ডার সারাংশ'), findsOneWidget);
      expect(find.text('সাইন আউট'), findsWidgets);
    });

    fakeTest('new shop form', (t) async {
      await pumpApp(t, const SrHome());
      await settle(t);
      await tab(t, 'অর্ডার');
      await tapText(t, 'নতুন দোকান');
      expect(find.text('নতুন দোকান যোগ করুন'), findsOneWidget);
      await t.enterText(find.byType(TextField).at(0), 'নতুন দোকান');
      await t.enterText(find.byType(TextField).at(1), 'ঠিকানা');
      await settle(t);
      await tapText(t, 'সংরক্ষণ করুন');
      expect(calls.any((c) => c.startsWith('POST /sr/retailers')), isTrue);
    });
  });

  group('DSR', () {
    fakeTest('home dashboard', (t) async {
      await pumpApp(t, const DsrHome());
      await settle(t);
      expect(find.text('মোট দোকান'), findsOneWidget);
      expect(find.text('TRP-২৬১১২৫-০০০১'), findsOneWidget);
      expect(find.text('ট্রিপ সেটেলমেন্ট ও নোট গণনা'), findsOneWidget);
    });

    fakeTest('delivery map → open a stop → save', (t) async {
      await pumpApp(t, const DsrHome());
      await settle(t);
      await tab(t, 'ডেলিভারি');
      expect(find.text('কাছাকাছি অর্ডার'), findsOneWidget);
      await tapText(t, 'মিষ্টি ভ্যারাইটিজ স্টোর', last: true);
      expect(find.textContaining('Transcom'), findsWidgets);
      await tapText(t, 'সংরক্ষণ'); // footer button
      await tapText(t, 'সংরক্ষণ', index: 1); // confirm dialog
      expect(calls.any((c) => c.startsWith('POST /dsr/stops/188')), isTrue);
    });

    fakeTest('cancel an order inside a stop', (t) async {
      await pumpApp(t, const DsrHome());
      await settle(t);
      await tab(t, 'ডেলিভারি');
      await tapText(t, 'মিষ্টি ভ্যারাইটিজ স্টোর', last: true);
      await tapText(t, 'এই অর্ডার বাতিল');
      expect(find.text('বাতিলের কারণ'), findsOneWidget);
      await tapText(t, 'নিশ্চিত');
      expect(find.text('বাতিল'), findsWidgets);
    });

    fakeTest('ready sale page and the stop\'s damage page open', (t) async {
      await pumpApp(t, const DsrHome());
      await settle(t);
      await tab(t, 'ডেলিভারি');
      await tapText(t, 'রেডি সেল');
      expect(find.text('ভ্যানের মাল'), findsOneWidget);
      await back(t);
      await tapText(t, 'মিষ্টি ভ্যারাইটিজ স্টোর', last: true);
      await tapText(t, '+ ড্যামেজ সংগ্রহ');
      expect(find.text('ড্যামেজ'), findsWidgets);
    });

    fakeTest('van stock, expenses (add), settlement', (t) async {
      await pumpApp(t, const DsrHome());
      await settle(t);
      await tab(t, 'ভ্যান স্টক');
      expect(find.text('ভ্যানে বাকি'), findsOneWidget);
      expect(find.text('লোডকৃত'), findsWidgets);
      await tab(t, 'খরচ');
      expect(find.text('ডিজেল'), findsOneWidget);
      await tapText(t, '+ খরচ যোগ');
      await t.enterText(find.byType(TextField).at(0), 'খাবার');
      await t.enterText(find.byType(TextField).at(1), '120');
      await tapText(t, 'খরচ সংরক্ষণ করুন');
      expect(calls.any((c) => c.startsWith('POST /dsr/expenses')), isTrue);
      await t.pump(const Duration(seconds: 6)); // let the toast leave the bottom nav
      await settle(t);
      await tab(t, 'সেটেলমেন্ট');
      await see(t, 'হিসাবের বিবরণ');
      await see(t, 'নগদ টাকা গণনা');
      await t.enterText(find.byType(TextField).at(0), '6');
      await settle(t);
      await tapText(t, 'সেটেলমেন্ট জমা দিন');
      await tapText(t, 'জমা দিন');
      expect(calls.any((c) => c.startsWith('POST /dsr/settlement')), isTrue);
    });

    fakeTest('attendance page', (t) async {
      await pumpApp(t, const AttendancePage());
      await settle(t);
      expect(find.text('আজ এখনো হাজিরা হয়নি'), findsOneWidget);
      expect(find.text('QR স্ক্যান করুন'), findsOneWidget);
    });

    fakeTest('no trip', (t) async {
      overrides['GET /dsr/delivery'] = {'ok': true, 'trip': null, 'selectedDate': '2026-11-25', 'orders': [], 'vanStock': [], 'damageProducts': [], 'cancelReasons': [], 'server_time': 1};
      overrides['GET /dsr/dashboard'] = {'ok': true, 'date': '2026-11-25', 'today': '2026-11-25', 'dsr': {'name': 'safar', 'partner': 'P', 'photo': null}, 'trip': null, 'attendance': null,
        'stats': {'stops': 0, 'delivered': 0, 'due': 0, 'pending': 0, 'cancelled': 0, 'dispatched_pcs': 0, 'available_pcs': 0}, 'settlement': null};
      await pumpApp(t, const DsrHome());
      await settle(t);
      expect(find.textContaining('কোনো ডিসপ্যাচ করা ট্রিপ নেই'), findsOneWidget);
      await tab(t, 'ডেলিভারি');
      expect(find.textContaining('কোনো ডিসপ্যাচ করা ট্রিপ নেই'), findsWidgets);
    });
  });

  group('Retailer', () {
    fakeTest('today → invoice, history, notifications, sign out row', (t) async {
      await pumpApp(t, const RetailerHome());
      await settle(t);
      expect(find.text('রহিম স্টোর'), findsWidgets);
      expect(find.text('আজকের মাল'), findsOneWidget);
      await tapText(t, 'Transcom-এর মাল');
      expect(find.text('INVOICE'), findsOneWidget);
      await see(t, 'প্রিন্ট করুন');
      await back(t);
      await tab(t, 'হিস্ট্রি');
      await tapText(t, 'নভেম্বর', last: true); // an older day opens its delivery invoice
      expect(find.text('ডেলিভারি ইনভয়েস'), findsWidgets);
      await back(t);
      await tab(t, 'আজ');
      await t.drag(find.byType(Scrollable).first, const Offset(0, 1500), warnIfMissed: false); // back to the top
      await t.pump(const Duration(milliseconds: 300));
      await t.tap(find.byWidgetPredicate((w) => w is Svg && w.path == Ic.bell));
      await settle(t);
      expect(find.text('নোটিফিকেশন'), findsOneWidget);
      expect(find.textContaining('মাল দিয়ে গেছে'), findsOneWidget);
      await back(t);
      await see(t, 'সাইন আউট');
    });

    fakeTest('empty day', (t) async {
      overrides['GET /retailer/today'] = {'ok': true, 'date': '2026-11-25', 'shop': {'name': 'দোকান', 'address': '', 'phone': '1'},
        'day': {'orders': [], 'cards': [], 'total': 0, 'counts': {}}, 'unread': 0};
      await pumpApp(t, const RetailerHome());
      await settle(t);
      expect(find.text('আজ কোনো মাল নেই'), findsOneWidget);
    });
  });
}
