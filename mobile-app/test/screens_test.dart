import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:happy_bangladesh/auth/login_page.dart';
import 'package:happy_bangladesh/core/format.dart';
import 'package:happy_bangladesh/core/offline.dart';
import 'package:happy_bangladesh/core/tracker.dart';
import 'package:happy_bangladesh/dsr/attendance_page.dart';
import 'package:happy_bangladesh/dsr/dsr_home.dart';
import 'package:happy_bangladesh/retailer/retailer_home.dart';
import 'package:happy_bangladesh/sr/sr_home.dart';
import 'package:happy_bangladesh/ui/pwa_kit.dart';
import 'package:http/http.dart' as http;

import 'fakes.dart';

/// Every screen is built with realistic server data and used the way a field user would.
/// A crash or a layout overflow in any build shows up as a test exception.
void fakeTest(String name, Future<void> Function(WidgetTester t) body) {
  testWidgets(name, (t) async {
    kMapTiles = false; // no network in tests
    await setupEnv();
    await OfflineQueue.instance.clearAll();
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

Finder _text(String text, bool contains) => contains ? find.textContaining(text) : find.text(text);

/// Taps a text, scrolling the page down first when it is further away (lists build lazily).
/// [last] taps the last match (e.g. the bottom-nav label, or a card below a search dropdown).
Future<void> tapText(WidgetTester t, String text, {int index = 0, bool last = false, bool contains = false}) async {
  final f = _text(text, contains);
  for (var i = 0; i < 40 && f.evaluate().length <= index; i++) {
    await t.drag(find.byType(Scrollable).first, const Offset(0, -300), warnIfMissed: false);
    await t.pump(const Duration(milliseconds: 50));
  }
  if (f.evaluate().length <= index) _dump();
  expect(f.evaluate().length > index, isTrue, reason: 'text "$text" not found on screen (even after scrolling)');
  final target = last ? f.last : f.at(index);
  await t.ensureVisible(target);
  await t.pump(const Duration(milliseconds: 200));
  await t.tap(target, warnIfMissed: false);
  await settle(t);
}

/// Taps a button found by its accessibility label (round icon buttons).
Future<void> tapLabel(WidgetTester t, String label) async {
  final f = find.byWidgetPredicate((w) => w is Semantics && w.properties.label == label);
  if (f.evaluate().isEmpty) _dump();
  expect(f, findsWidgets, reason: 'button "$label" not found');
  await t.ensureVisible(f.first);
  await t.pump(const Duration(milliseconds: 200));
  await t.tap(f.first, warnIfMissed: false);
  await settle(t);
}

void _dump() => debugPrint('VISIBLE: ${find.byType(Text).evaluate().map((e) => (e.widget as Text).data ?? (e.widget as Text).textSpan?.toPlainText()).take(80).join(' | ')}');

/// Scrolls the visible page until [text] is built.
Future<void> see(WidgetTester t, String text, {bool contains = false}) async {
  final f = _text(text, contains);
  for (var i = 0; i < 40 && f.evaluate().isEmpty; i++) {
    await t.drag(find.byType(Scrollable).first, const Offset(0, -300), warnIfMissed: false);
    await t.pump(const Duration(milliseconds: 50));
  }
  if (f.evaluate().isEmpty) _dump();
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

bool called(String prefix) => calls.any((c) => c.startsWith(prefix));

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
    fakeTest('SR1 dashboard → SR2 map → search → SR3 catalogue → SR3b sheet → cart → SR4 success', (t) async {
      await pumpApp(t, const SrHome());
      await settle(t);
      await see(t, 'আজকের অর্ডার');
      await tapText(t, 'নতুন অর্ডার'); // dashboard CTA opens the অর্ডার tab
      await see(t, 'কাছের দোকান');
      expect(find.text('রাজকুমার স্টোর'), findsWidgets); // within 50 m of the phone
      expect(find.text('দোকান 3'), findsNothing); // too far — only found by search

      await t.enterText(find.byType(TextField).first, 'দোকান 7');
      await settle(t);
      expect(find.text('দোকান 7'), findsWidgets);
      expect(find.text('দোকান 3'), findsNothing);
      await tapText(t, 'অর্ডার'); // the row's order button (the tab label is last)
      await see(t, 'সব পণ্য');
      await see(t, 'Salman khan');
      await tapText(t, 'Salman khan');
      await see(t, 'অর্ডারে যোগ করুন', contains: true); // SR3b: 1 unit by default
      await see(t, 'আমার ওভার / কমিশন');
      await tapText(t, 'অর্ডারে যোগ করুন', contains: true);
      await see(t, '১টি পণ্য', contains: true); // floating cart bar
      await tapText(t, 'অর্ডার পাঠান');
      await see(t, 'অর্ডার দেখে নিন');
      await tapText(t, 'অর্ডার কনফার্ম করুন');
      expect(called('POST /sr/orders {"retailer_id":107'), isTrue);
      await see(t, 'অর্ডার পাঠানো হয়েছে');
      await see(t, 'মোট · ডেলিভারিতে নগদ');
      await t.pump(const Duration(seconds: 6)); // the warning toast
      await tapText(t, 'অন্য দোকানে যান');
    });

    fakeTest('category rail filters the catalogue, list view, stock warning', (t) async {
      await pumpApp(t, const SrHome());
      await settle(t);
      await tab(t, 'অর্ডার');
      await t.enterText(find.byType(TextField).first, 'দোকান 7');
      await settle(t);
      await tapText(t, 'অর্ডার');
      await see(t, 'বাংলা পণ্য');
      await tapLabel(t, 'লিস্ট ভিউ');
      await see(t, 'বাংলা পণ্য');
      await tapText(t, 'বাংলা পণ্য');
      await see(t, 'স্টকের চেয়ে বেশি', contains: true); // 1 unit of 12 > 3 in stock
      await back(t);
    });

    fakeTest('editing an existing order sends PUT', (t) async {
      await pumpApp(t, const SrHome());
      await settle(t);
      await tab(t, 'অর্ডার');
      await tapText(t, 'এডিট');
      await see(t, 'অর্ডার সম্পাদনা');
      await tapText(t, 'আপডেট');
      await tapText(t, 'অর্ডার আপডেট করুন');
      expect(called('PUT /sr/orders/15'), isTrue);
    });

    fakeTest('offline: a new order is queued and the success page says so', (t) async {
      overrides['POST /sr/orders'] = const NetFail();
      await pumpApp(t, const SrHome());
      await settle(t);
      await tab(t, 'অর্ডার');
      await t.enterText(find.byType(TextField).first, 'দোকান 7');
      await settle(t);
      await tapText(t, 'অর্ডার');
      await tapText(t, 'Salman khan');
      await tapText(t, 'অর্ডারে যোগ করুন', contains: true);
      await tapText(t, 'অর্ডার পাঠান');
      await tapText(t, 'অর্ডার কনফার্ম করুন');
      await see(t, 'অর্ডার ফোনে সংরক্ষিত');
      expect(OfflineQueue.instance.ops.where((o) => o.path == '/sr/orders'), hasLength(1));
      await tapText(t, 'অন্য দোকানে যান');
    });

    fakeTest('complete the day from the আজ sheet', (t) async {
      await pumpApp(t, const SrHome());
      await settle(t);
      await tab(t, 'অর্ডার');
      await tapText(t, 'আজ ·', contains: true);
      await see(t, 'আজকের অর্ডার');
      await tapText(t, 'আজকের অর্ডার সম্পন্ন করুন');
      await tapText(t, 'সম্পন্ন করুন', last: true);
      expect(called('POST /sr/orders/complete'), isTrue);
    });

    fakeTest('SR5 history → SR6 memo (my copy) → SR6b shop copy, SR7 profile', (t) async {
      await pumpApp(t, const SrHome());
      await settle(t);
      await tab(t, 'হিস্ট্রি');
      await see(t, 'অর্ডার হিস্ট্রি');
      await see(t, 'মোট অর্ডার');
      await see(t, 'বাতিল'); // the cancelled memo is listed with its state
      await tapText(t, 'রাজকুমার স্টোর');
      await see(t, 'আমার হিসাব · শুধু আপনি দেখবেন');
      await see(t, 'মোট অর্ডার');
      await tapText(t, 'দোকানের কপি');
      await see(t, 'ক্যাশ মেমো');
      await see(t, 'টাকা মাত্র', contains: true);
      await see(t, 'দোকানে পাঠান');
      await back(t);
      await tab(t, 'আমি');
      await see(t, 'অর্ডার সারাংশ');
      await see(t, 'লগআউট');
    });

    fakeTest('new shop form', (t) async {
      await pumpApp(t, const SrHome());
      await settle(t);
      await tab(t, 'অর্ডার');
      await tapLabel(t, 'নতুন দোকান যোগ করুন');
      await see(t, 'নতুন দোকান');
      await t.enterText(find.byType(TextField).at(0), 'নতুন দোকান');
      await t.enterText(find.byType(TextField).at(1), 'ঠিকানা');
      await settle(t);
      await tapText(t, 'সংরক্ষণ করুন');
      expect(called('POST /sr/retailers'), isTrue);
    });
  });

  group('DSR', () {
    fakeTest('DM1 আজ: trip progress, next shop', (t) async {
      await pumpApp(t, const DsrHome());
      await settle(t);
      await see(t, 'আজকের ডেলিভারি · ট্রিপ TRP-২৬১১২৫-০০০১');
      await see(t, 'পরের দোকান');
      await see(t, 'মিষ্টি ভ্যারাইটিজ স্টোর');
      await see(t, 'টাকা নিতে হবে');
    });

    fakeTest('DMD: সব দিলাম → payment sheet → DM4 delivered → DM7 invoice', (t) async {
      await pumpApp(t, const DsrHome());
      await settle(t);
      await tapText(t, 'ডেলিভারি শুরু');
      await see(t, 'Transcom', contains: true);
      await tapText(t, '✓ সব দিলাম');
      await tapText(t, 'ডেলিভারি শেষ · পরের ধাপ');
      await see(t, 'টাকা গ্রহণ');
      await see(t, 'নতুন বাকি');
      await tapText(t, 'নিশ্চিত করুন');
      expect(called('POST /dsr/stops/188'), isTrue);
      await see(t, 'ডেলিভারি হয়েছে');
      await see(t, 'ভুল হয়েছে? Undo করুন');
      await tapText(t, 'ইনভয়েস');
      await see(t, 'কী অর্ডার · কী নিয়েছে · কত টাকা');
      await back(t);
      await tapText(t, 'পরের দোকান');
    });

    fakeTest('DM2 দোকান list, cancel an order with a reason', (t) async {
      await pumpApp(t, const DsrHome());
      await settle(t);
      await tab(t, 'দোকান');
      await see(t, 'রুটের দোকান');
      await see(t, '✓ দেওয়া');
      await tapText(t, 'দিন');
      await tapText(t, 'এই অর্ডার বাতিল');
      await see(t, 'পুরো অর্ডার বাতিল করবেন?');
      await tapText(t, 'হ্যাঁ, বাতিল');
      await see(t, 'বাতিল ফিরিয়ে আনুন');
    });

    fakeTest('offline: a delivery is queued', (t) async {
      overrides['POST /dsr/stops/188'] = const NetFail();
      await pumpApp(t, const DsrHome());
      await settle(t);
      await tapText(t, 'ডেলিভারি শুরু');
      await tapText(t, 'ডেলিভারি শেষ · পরের ধাপ');
      await tapText(t, 'নিশ্চিত করুন');
      await see(t, 'ফোনে সংরক্ষিত');
      expect(OfflineQueue.instance.ops.where((o) => o.path == '/dsr/stops/188'), hasLength(1));
      await tapText(t, 'পরের দোকান');
    });

    fakeTest('ready sale and the stop\'s damage page open', (t) async {
      await pumpApp(t, const DsrHome());
      await settle(t);
      await tab(t, 'দোকান');
      await tapLabel(t, 'রেডি সেল');
      await see(t, 'রেডি সেল');
      await back(t);
      await tapText(t, 'দিন');
      await tapText(t, '+ ড্যামেজ সংগ্রহ');
      expect(find.text('ড্যামেজ'), findsWidgets);
    });

    fakeTest('DM5 ভ্যান, DM6 আমি (wage, calendar), expenses (add), settlement', (t) async {
      await pumpApp(t, const DsrHome());
      await settle(t);
      await tab(t, 'ভ্যান');
      await see(t, 'ভ্যানের মাল');
      await see(t, 'হিসাব মিলছে', contains: true);
      await tab(t, 'আমি');
      await see(t, 'হাজিরা · নভেম্বর');
      await see(t, 'মাস শেষে পাবো');
      await see(t, '৳৮,৩৫০');
      await tapText(t, 'আজকের খরচ');
      await see(t, 'ডিজেল');
      await tapText(t, '+ খরচ যোগ');
      await t.enterText(find.byType(TextField).at(0), 'খাবার');
      await t.enterText(find.byType(TextField).at(1), '120');
      await tapText(t, 'খরচ সংরক্ষণ করুন');
      expect(called('POST /dsr/expenses'), isTrue);
      await t.pump(const Duration(seconds: 6)); // let the toast leave
      await back(t);
      await tapText(t, 'হিসাব মিলাও (সেটেলমেন্ট)');
      await see(t, 'হিসাবের বিবরণ');
      await see(t, 'নগদ টাকা গণনা');
      await t.enterText(find.byType(TextField).at(0), '6');
      await settle(t);
      await tapText(t, 'সেটেলমেন্ট জমা দিন');
      await tapText(t, 'জমা দিন', last: true);
      expect(called('POST /dsr/settlement'), isTrue);
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
      await see(t, 'আজ কোনো ডেলিভারি নেই');
      await see(t, 'আজ এখনো হাজিরা হয়নি');
      await tab(t, 'দোকান');
      await see(t, 'কোনো ডিসপ্যাচ করা ট্রিপ নেই', contains: true);
    });
  });

  group('Retailer', () {
    fakeTest('today → invoice, history, notifications, sign out row', (t) async {
      await pumpApp(t, const RetailerHome());
      await settle(t);
      await see(t, 'রহিম স্টোর');
      await see(t, 'আজকের মাল');
      await tapText(t, 'Transcom-এর মাল');
      await see(t, 'প্রিন্ট', contains: true);
      await back(t);
      await tab(t, 'হিস্ট্রি');
      await tapText(t, 'নভেম্বর', last: true); // an older day opens its invoice
      await see(t, 'ইনভয়েস', contains: true);
      await back(t);
      await tab(t, 'আজ');
      await tapLabel(t, 'নোটিফিকেশন');
      await see(t, 'নোটিফিকেশন');
      await back(t);
      await see(t, 'সাইন আউট');
    });

    fakeTest('empty day', (t) async {
      overrides['GET /retailer/today'] = {'ok': true, 'date': '2026-11-25', 'shop': {'name': 'দোকান', 'address': '', 'phone': '1'},
        'day': {'orders': [], 'cards': [], 'total': 0, 'counts': {}}, 'unread': 0};
      await pumpApp(t, const RetailerHome());
      await settle(t);
      await see(t, 'আজ কোনো মাল নেই');
    });
  });

  group('Format', () {
    test('Bangla amount in words for the cash memo', () {
      expect(takaWords(3654), 'তিন হাজার ছয়শত চুয়ান্ন টাকা মাত্র');
      expect(takaWords(0), 'শূন্য টাকা মাত্র');
      expect(takaWords(125000), 'এক লক্ষ পঁচিশ হাজার টাকা মাত্র');
      expect(takaWords(10000000), 'এক কোটি টাকা মাত্র');
      expect(takaWords(99.6), 'একশত টাকা মাত্র');
    });
  });
}
