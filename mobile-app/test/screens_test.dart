import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:happy_bangladesh/auth/login_page.dart';
import 'package:happy_bangladesh/core/tracker.dart';
import 'package:happy_bangladesh/dsr/attendance_page.dart';
import 'package:happy_bangladesh/dsr/dsr_home.dart';
import 'package:happy_bangladesh/retailer/retailer_home.dart';
import 'package:happy_bangladesh/sr/sr_home.dart';
import 'package:http/http.dart' as http;

import 'fakes.dart';

/// Every screen is built with realistic server data and used the way a field user would.
/// A crash in any build (like a missing localization) shows up as a test exception.
void fakeTest(String name, Future<void> Function(WidgetTester t) body) {
  testWidgets(name, (t) async {
    await setupEnv();
    await http.runWithClient(() async {
      try {
        await body(t);
        expect(t.takeException(), isNull, reason: 'a widget threw while building / handling taps');
      } finally {
        Tracker.instance.stop(); // the SR / DSR screens start GPS tracking (timers); stop it like logout does
      }
    }, fakeServer);
  });
}

/// Taps a text, scrolling the page down first when it is further away (lists build lazily).
Future<void> tapText(WidgetTester t, String text, {int index = 0}) async {
  final f = find.text(text);
  for (var i = 0; i < 40 && f.evaluate().length <= index; i++) {
    await t.drag(find.byType(Scrollable).first, const Offset(0, -300), warnIfMissed: false);
    await t.pump(const Duration(milliseconds: 50));
  }
  expect(f.evaluate().length > index, isTrue, reason: 'text "$text" not found on screen (even after scrolling)');
  await t.ensureVisible(f.at(index));
  await t.pump(const Duration(milliseconds: 200));
  await t.tap(f.at(index));
  await settle(t);
}

/// App-bar back button.
Future<void> back(WidgetTester t) async {
  await t.tap(find.byType(BackButton).first);
  await settle(t);
}

/// Bottom-navigation tab.
Future<void> tab(WidgetTester t, String label) async {
  await t.tap(find.descendant(of: find.byType(NavigationBar), matching: find.text(label)), warnIfMissed: false);
  await settle(t);
}

void main() {
  group('Login', () {
    fakeTest('renders both fields and shows a server error', (t) async {
      await pumpApp(t, const LoginPage());
      await settle(t);
      expect(find.byType(TextField), findsNWidgets(2));
      expect(find.text('লগইন'), findsWidgets);
      await t.enterText(find.byType(TextField).first, '01711889012');
      await t.enterText(find.byType(TextField).last, 'wrong');
      overrides['POST /auth/login'] = ApiFail(422, 'ফোন নম্বর বা পাসওয়ার্ড ভুল।');
      await t.tap(find.widgetWithText(FilledButton, 'লগইন'));
      await settle(t);
      expect(find.text('ফোন নম্বর বা পাসওয়ার্ড ভুল।'), findsOneWidget);
    });

    fakeTest('empty fields show a hint, no request is sent', (t) async {
      await pumpApp(t, const LoginPage());
      await settle(t);
      await t.tap(find.widgetWithText(FilledButton, 'লগইন'));
      await settle(t);
      expect(find.text('ফোন নম্বর ও পাসওয়ার্ড দিন।'), findsOneWidget);
      expect(calls.where((c) => c.startsWith('POST /auth/login')), isEmpty);
    });
  });

  group('SR', () {
    fakeTest('order page: shops, today orders, search, open the editor, save an order', (t) async {
      await pumpApp(t, const SrHome());
      await settle(t);
      expect(find.text('আজকের অর্ডার'), findsOneWidget);
      expect(find.text('রাজকুমার স্টোর'), findsOneWidget);
      expect(find.widgetWithText(ListTile, 'দোকান 3'), findsOneWidget);

      await t.enterText(find.byType(TextField).first, 'দোকান 7');
      await settle(t);
      expect(find.widgetWithText(ListTile, 'দোকান 7'), findsOneWidget);
      expect(find.widgetWithText(ListTile, 'দোকান 3'), findsNothing);

      await t.tap(find.widgetWithText(ListTile, 'দোকান 7'));
      await settle(t);
      expect(find.text('Salman khan'), findsWidgets);
      // quantity (dozen + pcs) fields: first product
      final fields = find.byType(TextField);
      await t.enterText(fields.at(1), '1'); // dozen
      await t.enterText(fields.at(2), '3'); // pcs
      await settle(t);
      expect(find.textContaining('১৫ পিস'), findsOneWidget); // 12 + 3
      await tapText(t, 'সংরক্ষণ');
      expect(calls.any((c) => c.startsWith('POST /sr/orders {"retailer_id":107')), isTrue);
    });

    fakeTest('editing an existing order and the empty-order guard', (t) async {
      await pumpApp(t, const SrHome());
      await settle(t);
      await tapText(t, 'রাজকুমার স্টোর');
      expect(find.text('আপডেট'), findsOneWidget);
      await tapText(t, 'আপডেট');
      expect(calls.any((c) => c.startsWith('PUT /sr/orders/15')), isTrue);
    });

    fakeTest('complete the day', (t) async {
      await pumpApp(t, const SrHome());
      await settle(t);
      await tapText(t, 'আজকের অর্ডার সম্পন্ন করুন');
      await tapText(t, 'সম্পন্ন করুন');
      expect(calls.any((c) => c.startsWith('POST /sr/orders/complete')), isTrue);
    });

    fakeTest('dashboard, history and profile tabs', (t) async {
      await pumpApp(t, const SrHome());
      await settle(t);
      await tab(t, 'ড্যাশবোর্ড');
      expect(find.text('Salman khan'), findsWidgets);
      await tab(t, 'ইতিহাস');
      expect(find.textContaining('অর্ডার'), findsWidgets);
      await tapText(t, 'রাজকুমার স্টোর'); // expand
      await tab(t, 'আমি');
      expect(find.text('অ্যাকাউন্ট'), findsOneWidget);
    });

    fakeTest('new shop form', (t) async {
      await pumpApp(t, const SrHome());
      await settle(t);
      await tapText(t, 'নতুন দোকান');
      expect(find.byType(TextField), findsWidgets);
      await t.enterText(find.byType(TextField).at(0), 'নতুন দোকান');
      await t.enterText(find.byType(TextField).at(2), 'ঠিকানা');
      await settle(t);
      await tapText(t, 'দোকান যোগ করুন');
      expect(calls.any((c) => c.startsWith('POST /sr/retailers')), isTrue);
    });
  });

  group('DSR', () {
    fakeTest('home dashboard', (t) async {
      await pumpApp(t, const DsrHome());
      await settle(t);
      expect(find.textContaining('স্বাগতম'), findsOneWidget);
      expect(find.text('TRP-261125-0001'), findsOneWidget);
    });

    fakeTest('delivery list → open a stop → save', (t) async {
      await pumpApp(t, const DsrHome());
      await settle(t);
      await tab(t, 'ডেলিভারি');
      expect(find.text('মিষ্টি ভ্যারাইটিজ স্টোর'), findsOneWidget);
      await tapText(t, 'মিষ্টি ভ্যারাইটিজ স্টোর');
      expect(find.textContaining('Transcom'), findsWidgets);
      await tapText(t, 'সংরক্ষণ'); // footer button
      await tapText(t, 'সংরক্ষণ', index: 1); // confirm dialog
      expect(calls.any((c) => c.startsWith('POST /dsr/stops/188')), isTrue);
    });

    fakeTest('cancel an order inside a stop', (t) async {
      await pumpApp(t, const DsrHome());
      await settle(t);
      await tab(t, 'ডেলিভারি');
      await tapText(t, 'মিষ্টি ভ্যারাইটিজ স্টোর');
      await tapText(t, 'এই অর্ডার বাতিল');
      expect(find.text('বাতিলের কারণ'), findsOneWidget);
      await tapText(t, 'নিশ্চিত');
      expect(find.text('বাতিল'), findsWidgets);
    });

    fakeTest('ready sale and damage pages open', (t) async {
      await pumpApp(t, const DsrHome());
      await settle(t);
      await tab(t, 'ডেলিভারি');
      await tapText(t, 'রেডি সেল');
      expect(find.text('ভ্যানের মাল'), findsOneWidget);
      await back(t);
      await settle(t);
      await tapText(t, 'ড্যামেজ');
      expect(find.text('কোন দোকানের ড্যামেজ?'), findsOneWidget);
    });

    fakeTest('van stock, expenses (add), settlement', (t) async {
      await pumpApp(t, const DsrHome());
      await settle(t);
      await tab(t, 'ভ্যান');
      expect(find.textContaining('ভ্যানে এখন'), findsOneWidget);
      await tab(t, 'খরচ');
      expect(find.text('ডিজেল'), findsOneWidget);
      await tapText(t, 'খরচ যোগ করুন');
      await t.enterText(find.byType(TextField).at(0), 'খাবার');
      await t.enterText(find.byType(TextField).at(1), '120');
      await tapText(t, 'যোগ করুন');
      expect(calls.any((c) => c.startsWith('POST /dsr/expenses')), isTrue);
      await tab(t, 'সেটেলমেন্ট');
      expect(find.text('জমা দেওয়ার টাকা'), findsWidgets);
      expect(find.text('ক্যাশ গোনা'), findsOneWidget);
      await t.enterText(find.byType(TextField).at(0), '6');
      await settle(t);
      await tapText(t, 'সেটেলমেন্ট জমা দিন');
      await tapText(t, 'জমা দিন');
      expect(calls.any((c) => c.startsWith('POST /dsr/settlement')), isTrue);
    });

    fakeTest('attendance page', (t) async {
      await pumpApp(t, const AttendancePage());
      await settle(t);
      expect(find.text('আজকের হাজিরা বাকি'), findsOneWidget);
      expect(find.text('QR স্ক্যান করুন'), findsOneWidget);
    });

    fakeTest('delivery page with no trip', (t) async {
      overrides['GET /dsr/delivery'] = {'ok': true, 'trip': null, 'selectedDate': '2026-11-25', 'orders': [], 'vanStock': [], 'damageProducts': [], 'cancelReasons': [], 'server_time': 1};
      overrides['GET /dsr/dashboard'] = {'ok': true, 'date': '2026-11-25', 'today': '2026-11-25', 'dsr': {'name': 'safar', 'partner': 'P', 'photo': null}, 'trip': null, 'attendance': null,
        'stats': {'stops': 0, 'delivered': 0, 'due': 0, 'pending': 0, 'cancelled': 0, 'dispatched_pcs': 0, 'available_pcs': 0}, 'settlement': null};
      await pumpApp(t, const DsrHome());
      await settle(t);
      expect(find.textContaining('কোনো ট্রিপ নেই'), findsOneWidget);
      await tab(t, 'ডেলিভারি');
      expect(find.textContaining('কোনো ট্রিপ নেই'), findsOneWidget);
    });
  });

  group('Retailer', () {
    fakeTest('today → invoice, history, notifications, account', (t) async {
      await pumpApp(t, const RetailerHome());
      await settle(t);
      expect(find.text('রহিম স্টোর'), findsWidgets);
      await tapText(t, 'Transcom-এর মাল');
      expect(find.textContaining('মেমো'), findsWidgets);
      expect(find.text('প্রিন্ট করুন'), findsOneWidget);
      await back(t);
      await settle(t);
      await tab(t, 'হিস্ট্রি');
      await tapText(t, 'নভেম্বর', index: 1);
      expect(find.textContaining('ইনভয়েস'), findsWidgets);
      await back(t);
      await settle(t);
      await tab(t, 'নোটিফিকেশন');
      expect(find.textContaining('মাল দিয়ে গেছে'), findsOneWidget);
      await tab(t, 'আমি');
      expect(find.text('লগআউট'), findsOneWidget);
    });

    fakeTest('empty day', (t) async {
      overrides['GET /retailer/today'] = {'ok': true, 'date': '2026-11-25', 'shop': {'name': 'দোকান', 'address': '', 'phone': '1'},
        'day': {'orders': [], 'cards': [], 'total': 0, 'counts': {}}, 'unread': 0};
      await pumpApp(t, const RetailerHome());
      await settle(t);
      expect(find.textContaining('কোনো মাল আসার কথা নেই'), findsOneWidget);
    });
  });
}
