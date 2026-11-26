import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/api.dart';
import '../core/format.dart';
import '../core/push.dart';
import '../core/realtime.dart';
import '../core/session.dart';
import '../core/offline.dart';
import '../ui/common.dart';
import '../ui/printer_page.dart';
import '../ui/pwa_kit.dart';
import '../ui/update.dart';
import 'invoice_page.dart';
import 'notifications_page.dart';
import 'rkit.dart';

Map<String, dynamic> _m(Object? v) => Map<String, dynamic>.from((v ?? {}) as Map);

/// Retailer panel — same screens as /retailer in the PWA: আজ, হিস্ট্রি (floating pill nav), notifications via the bell.
class RetailerHome extends StatefulWidget {
  const RetailerHome({super.key});
  @override
  State<RetailerHome> createState() => _RetailerHomeState();
}

class _RetailerHomeState extends State<RetailerHome> {
  int _tab = 0;
  int _unread = 0;
  Timer? _poll;
  StreamSubscription? _live;
  bool _first = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => UpdateChecker.check(context));
    _check();
    // The live connection / push show notifications at once; this keeps the badge right and covers the case
    // when neither is available (checked every minute while the app is open).
    _poll = Timer.periodic(const Duration(seconds: 60), (_) => _check());
    _live = Realtime.instance.events.listen((_) => _check());
  }

  @override
  void dispose() {
    _live?.cancel();
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _check() async {
    try {
      final r = await ApiClient.get('/retailer/notifications');
      final unread = int0(r['unread']);
      if (!_first && unread > _unread && !Realtime.instance.connected) {
        final first = (r['events'] as List).map(_m).firstWhere((e) => e['unread'] == true, orElse: () => {});
        Notifier.show('Happy Bangladesh', (first['title'] ?? 'নতুন খবর আছে').toString());
      }
      _first = false;
      if (mounted) setState(() => _unread = unread);
    } catch (_) {}
  }

  Future<void> _openNotifications() async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const NotificationsPage()));
    _check();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: RC.outer,
      body: Frame(
        child: Container(
          color: RC.bg,
          child: Stack(children: [
            IndexedStack(index: _tab, children: [
              _TodayPage(unread: _unread, onBell: _openNotifications),
              _HistoryPage(onToday: () => setState(() => _tab = 0)),
            ]),
            RPillNav(index: _tab, onTap: (i) => setState(() => _tab = i)),
          ]),
        ),
      ),
    );
  }
}

class _TodayPage extends StatelessWidget {
  const _TodayPage({required this.unread, required this.onBell});
  final int unread;
  final VoidCallback onBell;

  @override
  Widget build(BuildContext context) {
    final shopName = (context.watch<AuthState>().profile['shops'] is List && (context.watch<AuthState>().profile['shops'] as List).isNotEmpty)
        ? '${(context.watch<AuthState>().profile['shops'] as List).first['name']}'
        : '';
    return AsyncBody(
      padding: EdgeInsets.zero,
      load: () => loadCached('ret_today', () => ApiClient.get('/retailer/today')),
      builder: (context, d, reload) {
        final shop = _m(d['shop']);
        final day = _m(d['day']);
        final cards = (day['cards'] as List).map(_m).toList();
        final orders = (day['orders'] as List).map(_m).toList();
        final c = _m(day['counts']);
        final badge = int0(d['unread']) > 0 ? int0(d['unread']) : unread;
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          RHero(
            child: Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('আসসালামু আলাইকুম', style: ts(15, color: const Color(0xD9FFFFFF), h: 1.45)),
                  Text('${shop['name'] ?? shopName}', style: ts(26, w: FontWeight.w700, color: Colors.white, h: 1.25)),
                ]),
              ),
              const SizedBox(width: 12),
              _Bell(count: badge, onTap: onBell),
            ]),
          ),
          NegativeTop(
            overlap: 44,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                RCard(
                  margin: const EdgeInsets.only(bottom: 24),
                  padding: const EdgeInsets.all(16),
                  shadow: const [BoxShadow(color: Color(0x0A0F172A), blurRadius: 4, offset: Offset(0, 2)), BoxShadow(color: Color(0x241E40AF), blurRadius: 36, offset: Offset(0, 16))],
                  child: Column(children: [
                    Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                      Text('আজকের মোট বিল', style: ts(14, color: RC.ink2, h: 1.5)),
                      Text(money(day['total']), style: ts(30, w: FontWeight.w700, ls: -0.5, tabular: true, h: 1.2)),
                    ]),
                    const SizedBox(height: 16),
                    Row(children: [
                      _Stat(bn(c['arrived'] ?? 0), 'এসেছে', RC.okSoft, RC.ok),
                      const SizedBox(width: 10),
                      _Stat(bn(c['onway'] ?? 0), 'পথে', RC.blueSoft, RC.blueInk),
                      const SizedBox(width: 10),
                      _Stat(bn(c['later'] ?? 0), 'পরে আসবে', RC.muteSoft, RC.ink2),
                    ]),
                  ]),
                ),
                const RSecTitle('আজকের মাল'),
                if (cards.isEmpty) const REmpty('আজ কোনো মাল নেই', body: 'SR অর্ডার নিলে বা ডেলিভারি হলে এখানে দেখা যাবে।'),
                for (final card in cards) _DCard(card: card, onTap: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => InvoicePage(mode: InvoiceMode.order, date: d['date'].toString(), orders: orders, selectedId: int0(card['first']))))),
                Center(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(0, 22, 0, 6),
                    child: TextButton(
                      onPressed: () => _logout(context),
                      style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8), foregroundColor: RC.muted),
                      child: Text('সাইন আউট', style: ts(14, w: FontWeight.w600, color: RC.muted).copyWith(decoration: TextDecoration.underline)),
                    ),
                  ),
                ),
                Center(
                  child: TextButton(
                    onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const PrinterPage())),
                    child: Text('ব্লুটুথ প্রিন্টার সেটিংস', style: ts(13, color: RC.muted)),
                  ),
                ),
                const SizedBox(height: 110),
              ]),
            ),
          ),
        ]);
      },
    );
  }

  Future<void> _logout(BuildContext context) async {
    final q = OfflineQueue.instance.ops.length;
    if (await confirm(context, 'সাইন আউট করবেন?', body: q > 0 ? 'এখনো $qটি কাজ সিঙ্ক হয়নি।' : null, danger: true, yes: 'সাইন আউট')) {
      if (context.mounted) await context.read<AuthState>().logout();
    }
  }
}

class _Bell extends StatelessWidget {
  const _Bell({required this.count, required this.onTap});
  final int count;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: SizedBox(
          width: 60, height: 62,
          child: Stack(clipBehavior: Clip.none, children: [
            Positioned(
              left: 0, top: 6,
              child: Container(
                width: 56, height: 56,
                decoration: BoxDecoration(color: const Color(0x2EFFFFFF), borderRadius: BorderRadius.circular(18), border: Border.all(color: const Color(0x38FFFFFF))),
                child: const Center(child: Svg(Ic.bell, size: 26, color: Colors.white)),
              ),
            ),
            if (count > 0)
              Positioned(
                right: -2, top: 0,
                child: Container(
                  constraints: const BoxConstraints(minWidth: 24), height: 24, padding: const EdgeInsets.symmetric(horizontal: 5),
                  decoration: BoxDecoration(color: const Color(0xFFEF4444), borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFF3B6FE0), width: 2)),
                  child: Center(child: Text(count > 9 ? '৯+' : bn(count), style: ts(12, w: FontWeight.w700, color: Colors.white, h: 1))),
                ),
              ),
          ]),
        ),
      );
}

class _Stat extends StatelessWidget {
  const _Stat(this.value, this.label, this.bg, this.fg);
  final String value, label;
  final Color bg, fg;
  @override
  Widget build(BuildContext context) => Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 2),
          decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(16)),
          child: Column(children: [
            Text(value, style: ts(22, w: FontWeight.w700, color: fg, h: 1.2)),
            const SizedBox(height: 2),
            Text(label, style: ts(13, w: FontWeight.w600, color: fg, h: 1.4)),
          ]),
        ),
      );
}

class _DCard extends StatelessWidget {
  const _DCard({required this.card, required this.onTap});
  final Map<String, dynamic> card;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final stage = '${card['stage']}';
    final (chipBg, chipFg, stripe) = switch (stage) {
      'arrived' => (RC.okSoft, RC.ok, RC.okStripe),
      'onway' => (RC.blueSoft, RC.blueInk, RC.blue),
      _ => (RC.muteSoft, RC.ink2, RC.muteSoft),
    };
    final rows = (card['rows'] as List).map(_m).toList();
    return RCard(
      margin: const EdgeInsets.only(bottom: 14),
      onTap: onTap,
      child: Stack(children: [
        Positioned(left: 0, top: 18, bottom: 18, width: 4, child: DecoratedBox(decoration: BoxDecoration(color: stripe, borderRadius: const BorderRadius.horizontal(right: Radius.circular(4))))),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${card['title']}', style: ts(16.5, w: FontWeight.w700, h: 1.3)),
                  Text(card['dm'] != null ? 'ডেলিভারি ম্যান ${card['dm']}' : 'ডেলিভারি ম্যান ঠিক হয়নি', style: ts(13.5, color: RC.ink2, h: 1.45)),
                ]),
              ),
              const SizedBox(width: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 6),
                decoration: BoxDecoration(color: chipBg, borderRadius: BorderRadius.circular(99)),
                child: Text('${card['chip']}', style: ts(13, w: FontWeight.w600, color: chipFg, h: 1.3)),
              ),
            ]),
            const SizedBox(height: 12),
            for (final r in rows)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(child: Text('${r['sr'] == 'রেডি সেল' ? 'রেডি সেল' : 'SR ${r['sr']}'} · ${r['company']}', style: ts(14.5, color: RC.ink2, h: 1.4))),
                  const SizedBox(width: 12),
                  Text(money(r['bill']), style: ts(14.5, color: RC.ink2, h: 1.4)),
                ]),
              ),
            Container(
              margin: const EdgeInsets.only(top: 12),
              padding: const EdgeInsets.only(top: 14),
              decoration: const BoxDecoration(border: Border(top: BorderSide(color: RC.border))),
              child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Text(money(card['total']), style: ts(22, w: FontWeight.w700, tabular: true, h: 1.3)),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(color: RC.blueSoft, borderRadius: BorderRadius.circular(99)),
                  child: Text('ইনভয়েস দেখুন ›', style: ts(13.5, w: FontWeight.w700, color: RC.blueInk, h: 1.3)),
                ),
              ]),
            ),
          ]),
        ),
      ]),
    );
  }
}

class _HistoryPage extends StatelessWidget {
  const _HistoryPage({required this.onToday});
  final VoidCallback onToday;

  static const _palette = [
    (Color(0xFFE4ECFF), Color(0xFF1D4FD0)),
    (Color(0xFFFFEEDD), Color(0xFFB45309)),
    (Color(0xFFE1F3E6), Color(0xFF15803D)),
    (Color(0xFFEFE5FF), Color(0xFF7C3FD6)),
    (Color(0xFFFDE4EA), Color(0xFFBE185D)),
    (Color(0xFFDFF3F6), Color(0xFF0F766E)),
  ];

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      const RPlainHead(title: 'হিস্ট্রি'),
      Expanded(
        child: AsyncBody(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 0),
          load: () => loadCached('ret_history', () => ApiClient.get('/retailer/history')),
          builder: (context, d, reload) {
            final rows = (d['rows'] as List).map(_m).toList();
            return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              if (rows.isEmpty) const REmpty('এখনো কোনো হিস্ট্রি নেই', body: 'অর্ডার ও ডেলিভারি হলে দিন অনুযায়ী এখানে জমা হবে।'),
              for (var i = 0; i < rows.length; i++)
                RCard(
                  margin: const EdgeInsets.only(bottom: 14),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  onTap: () async {
                    final r = rows[i];
                    if (r['today'] == true) {
                      onToday();
                      return;
                    }
                    final res = await busy(context, () => ApiClient.get('/retailer/day', query: {'date': r['date']}));
                    if (res != null && context.mounted) {
                      final orders = (res['orders'] as List).map(_m).toList();
                      Navigator.of(context).push(MaterialPageRoute(
                          builder: (_) => InvoicePage(mode: InvoiceMode.delivery, date: r['date'].toString(), orders: orders, selectedId: orders.isEmpty ? 0 : int0(orders.first['id']))));
                    }
                  },
                  child: Row(children: [
                    Container(
                      width: 66, height: 66,
                      decoration: BoxDecoration(color: _palette[i % 6].$1, borderRadius: BorderRadius.circular(18)),
                      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                        Text('${rows[i]['day']}', style: ts(22, w: FontWeight.w700, color: _palette[i % 6].$2, h: 1.1)),
                        Text('${rows[i]['month']}', style: ts(13, w: FontWeight.w600, color: _palette[i % 6].$2, h: 1.3)),
                      ]),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(money(rows[i]['total']), style: ts(20, w: FontWeight.w700, h: 1.3)),
                        Text('${rows[i]['sub']}', style: ts(13.5, color: RC.ink2, h: 1.4)),
                      ]),
                    ),
                    const Svg(Ic.chevRight, size: 20, color: RC.ink2, stroke: 2.4),
                  ]),
                ),
              const SizedBox(height: 110),
            ]);
          },
        ),
      ),
    ]);
  }
}
