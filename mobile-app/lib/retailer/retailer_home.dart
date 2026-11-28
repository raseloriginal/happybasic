import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/api.dart';
import '../core/format.dart';
import '../core/offline.dart';
import '../core/push.dart';
import '../core/realtime.dart';
import '../core/session.dart';
import '../ui/common.dart';
import '../ui/hkit.dart';
import '../ui/motion.dart';
import '../ui/printer_page.dart';
import '../ui/pwa_kit.dart';
import '../ui/update.dart';
import 'invoice_page.dart';
import 'notifications_page.dart';

Map<String, dynamic> _m(Object? v) => Map<String, dynamic>.from((v ?? {}) as Map);

const _icHome = '<path d="M4 11l8-6 8 6v8a1 1 0 0 1-1 1H5a1 1 0 0 1-1-1z"/>';
const _icList = '<path d="M8 6h12M8 12h12M8 18h12"/><circle cx="4" cy="6" r="1"/><circle cx="4" cy="12" r="1"/><circle cx="4" cy="18" r="1"/>';
const _icBell = '<path d="M6 16V11a6 6 0 0 1 12 0v5l1.5 2h-15z"/><path d="M10 20a2 2 0 0 0 4 0"/>';
const icTruck = '<path d="M3 6h11v10H3zM14 10h4l3 3v3h-7"/><circle cx="7" cy="18" r="2"/><circle cx="17" cy="18" r="2"/>';

/// Retailer app (design R1–R8): আজ · হিস্ট্রি tabs, notifications behind the bell, invoices on tap.
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
    // Live connection / push show news at once; the poll keeps the badge right when neither is available.
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
    return PopScope(
      canPop: _tab == 0,
      onPopInvokedWithResult: (did, _) {
        if (!did) setState(() => _tab = 0); // Android back: history → today, then leave
      },
      child: SkyStatusBar(
        child: Scaffold(
          backgroundColor: HC.outer,
          body: Frame(
            color: HC.outer,
            child: ColoredBox(
              color: HC.bg,
              child: IndexedStack(index: _tab, children: [
                TabFade(active: _tab == 0, child: _TodayPage(unread: _unread, onBell: _openNotifications)),
                TabFade(active: _tab == 1, child: const _HistoryPage()),
              ]),
            ),
          ),
          bottomNavigationBar: Frame(
            shrink: true,
            color: HC.outer,
            child: HTabBar(
              index: _tab,
              onTap: (i) => setState(() => _tab = i),
              items: const [HNavItem('আজ', _icHome), HNavItem('হিস্ট্রি', _icList)],
            ),
          ),
        ),
      ),
    );
  }
}

/// Main · আজ: greeting, today's bill, the van on the way, counts, today's goods.
class _TodayPage extends StatelessWidget {
  const _TodayPage({required this.unread, required this.onBell});
  final int unread;
  final VoidCallback onBell;

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthState>();
    final shops = auth.profile['shops'];
    final fallbackName = shops is List && shops.isNotEmpty ? '${shops.first['name']}' : '';
    return AsyncBody(
      sky: true,
      load: () => loadCached('ret_today', () => ApiClient.get('/retailer/today')),
      builder: (context, d, reload) {
        final shop = _m(d['shop']);
        final day = _m(d['day']);
        final cards = (day['cards'] as List).map(_m).toList();
        final orders = (day['orders'] as List).map(_m).toList();
        final c = _m(day['counts']);
        final badge = int0(d['unread']) > 0 ? int0(d['unread']) : unread;
        final name = '${shop['name'] ?? fallbackName}';
        final live = cards.where((x) => x['stage'] == 'onway').firstOrNull;
        final srCount = int0(day['sr_count']);
        void openInvoice(Map<String, dynamic> card) => Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => InvoicePage(mode: InvoiceMode.order, date: '${d['date']}', orders: orders, selectedId: int0(card['first']))));

        return SkyBox(
          height: 245,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            SkyHead(
              leading: LetterAvatar(name, size: 44, radius: 14, fontSize: 18),
              kicker: 'আসসালামু আলাইকুম',
              title: name,
              trailing: GlassBtn(icon: _icBell, label: 'নোটিফিকেশন', onTap: onBell, badge: badge > 0 ? (badge > 9 ? '৯+' : bn(badge)) : null),
            ),
            gap12,
            Text('আজকের মোট বিল', style: hs(12, color: HC.onSky)),
            Text(tk(day['total']), style: hs(40, w: w8, color: Colors.white, h: 1.15, ls: -.5, num: true)),
            Text('${bn(cards.length)}টি ডেলিভারি${srCount > 0 ? ' · ${bn(srCount)} জন SR-এর অর্ডার' : ''}', style: hs(12, color: HC.onSky)),
            gap12,
            if (live != null) ...[
              _LiveCard(card: live, onTap: () => openInvoice(live)),
              gap12,
            ],
            Row(children: [
              _Count(bn(c['arrived'] ?? 0), 'এসেছে', HC.soft, HC.blue),
              const SizedBox(width: 8),
              _Count(bn(c['onway'] ?? 0), 'পথে', HC.ink, Colors.white),
              const SizedBox(width: 8),
              _Count(bn(c['later'] ?? 0), 'পরে আসবে', Colors.white, HC.muted, border: true),
            ]),
            gap16,
            HSec('আজকের মাল', trailing: '${bn(cards.length)}টি'),
            gap12,
            if (cards.isEmpty) const HEmpty('আজ কোনো মাল নেই', body: 'SR অর্ডার নিলে বা ডেলিভারি হলে এখানে দেখা যাবে।'),
            for (final card in cards) ...[_GoodsCard(card: card, onTap: () => openInvoice(card)), gap12],
            const SizedBox(height: 6),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              TextButton(onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const PrinterPage())),
                  child: Text('ব্লুটুথ প্রিন্টার', style: hs(13, w: w6, color: HC.muted))),
              Text('·', style: hs(13, color: HC.faint)),
              TextButton(onPressed: () => _logout(context), child: Text('সাইন আউট', style: hs(13, w: w6, color: HC.muted))),
            ]),
          ]),
        );
      },
    );
  }

  Future<void> _logout(BuildContext context) async {
    final q = OfflineQueue.instance.ops.length;
    if (await confirm(context, 'সাইন আউট করবেন?', body: q > 0 ? 'এখনো ${bn(q)}টি কাজ সিঙ্ক হয়নি।' : null, danger: true, yes: 'সাইন আউট')) {
      if (context.mounted) await context.read<AuthState>().logout();
    }
  }
}

class _Count extends StatelessWidget {
  const _Count(this.n, this.label, this.bg, this.fg, {this.border = false});
  final String n, label;
  final Color bg, fg;
  final bool border;
  @override
  Widget build(BuildContext context) => Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
          decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(14), border: border ? Border.all(color: HC.line) : null),
          child: Column(children: [
            Text(n, style: hs(18, w: w7, color: fg, num: true, h: 1.25)),
            Text(label, style: hs(11, color: fg)),
          ]),
        ),
      );
}

/// The van that is on its way: pulsing truck, DM · companies, cash to keep ready.
class _LiveCard extends StatefulWidget {
  const _LiveCard({required this.card, required this.onTap});
  final Map<String, dynamic> card;
  final VoidCallback onTap;
  @override
  State<_LiveCard> createState() => _LiveCardState();
}

class _LiveCardState extends State<_LiveCard> with SingleTickerProviderStateMixin {
  late final AnimationController _a = AnimationController(vsync: this, duration: const Duration(milliseconds: 1600))..repeat();

  @override
  void dispose() {
    _a.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final card = widget.card;
    final companies = (card['rows'] as List).map((r) => '${_m(r)['company']}').toSet().join(' + ');
    return HCard(
      lift: true, radius: 22, onTap: widget.onTap,
      child: Row(children: [
        SizedBox(
          width: 48, height: 48,
          child: Stack(clipBehavior: Clip.none, children: [
            Container(decoration: BoxDecoration(color: HC.soft, borderRadius: BorderRadius.circular(16)), alignment: Alignment.center,
                child: const Svg(icTruck, size: 24, color: HC.blue)),
            AnimatedBuilder(
              animation: _a,
              builder: (_, __) => Positioned(
                left: -4, top: -4, right: -4, bottom: -4,
                child: Transform.scale(
                  scale: 1 + _a.value * .35,
                  child: Opacity(opacity: (1 - _a.value) * .8,
                      child: Container(decoration: BoxDecoration(borderRadius: BorderRadius.circular(19), border: Border.all(color: HC.blue, width: 2)))),
                ),
              ),
            ),
          ]),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('● পথে আছে', style: hs(12, w: w7, color: HC.blue)),
            Text('${card['dm'] ?? 'ডেলিভারি ম্যান'} · $companies', maxLines: 1, overflow: TextOverflow.ellipsis, style: hs(15, w: w7)),
            Text.rich(TextSpan(style: hs(12, color: HC.muted), children: [
              const TextSpan(text: 'নগদ রেডি রাখুন '),
              TextSpan(text: tk(card['total']), style: hs(12, w: w7, num: true)),
            ])),
          ]),
        ),
      ]),
    );
  }
}

/// One delivery's goods: title, DM · partner, amount + stage, progress, SR chips.
class _GoodsCard extends StatelessWidget {
  const _GoodsCard({required this.card, required this.onTap});
  final Map<String, dynamic> card;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final stage = '${card['stage']}';
    final fill = switch (stage) { 'arrived' => 1.0, 'onway' => .62, _ => .18 };
    final srs = card['srs'] is List ? (card['srs'] as List).map((e) => '$e').toList()
        : (card['rows'] as List).map((r) => '${_m(r)['sr'] == 'রেডি সেল' ? 'রেডি সেল' : 'SR ${_m(r)['sr']}'} · ${_m(r)['company']}').toSet().toList();
    final chipColor = switch (stage) { 'arrived' => HC.blue, 'onway' => HC.ink, _ => HC.muted };
    return Opacity(
      opacity: stage == 'arrived' ? .8 : 1,
      child: HCard(
        onTap: onTap,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${card['title']}', style: hs(15, w: w7)),
                Text('${card['dm'] != null ? 'DM ${card['dm']}' : 'ডেলিভারি ম্যান ঠিক হয়নি'}${card['partner'] != null ? ' · ${card['partner']}' : ''}',
                    style: hs(12, color: HC.muted)),
              ]),
            ),
            const SizedBox(width: 8),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text(tk(card['total']), style: hs(16, w: w7, num: true)),
              Text('${card['chip']}', style: hs(12, w: stage == 'later' ? w6 : w7, color: chipColor)),
            ]),
          ]),
          const SizedBox(height: 16),
          LayoutBuilder(builder: (_, box) {
            final w = box.maxWidth;
            return SizedBox(
              height: 6,
              child: Stack(clipBehavior: Clip.none, children: [
                Container(decoration: BoxDecoration(color: HC.bg, borderRadius: BorderRadius.circular(3))),
                Container(width: w * fill, decoration: BoxDecoration(color: stage == 'later' ? HC.faint : HC.blue, borderRadius: BorderRadius.circular(3))),
                if (stage == 'onway')
                  Positioned(left: w * fill - 13, top: -8, child: Container(
                    width: 26, height: 22, decoration: BoxDecoration(color: HC.ink, borderRadius: BorderRadius.circular(7)),
                    alignment: Alignment.center, child: const Svg(icTruck, size: 14, color: Colors.white),
                  )),
              ]),
            );
          }),
          const SizedBox(height: 12),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final s in srs)
              Container(
                padding: const EdgeInsets.fromLTRB(3, 3, 10, 3),
                decoration: BoxDecoration(color: HC.bg, borderRadius: BorderRadius.circular(999)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  LetterAvatar(s.replaceFirst(RegExp(r'^(SR|DM)\s+'), ''), size: 22, bg: HC.ink, fg: Colors.white, fontSize: 11),
                  const SizedBox(width: 6),
                  Text(s, style: hs(11, w: w6)),
                ]),
              ),
          ]),
        ]),
      ),
    );
  }
}

/// R3 · হিস্ট্রি: 7-day summary, date tiles with bars.
class _HistoryPage extends StatefulWidget {
  const _HistoryPage();
  @override
  State<_HistoryPage> createState() => _HistoryPageState();
}

/// R3 · হিস্ট্রি: ৭ দিন / ৩০ দিন / এই মাস (or a past month), bought + profit, a bar per day, then the days.
class _HistoryPageState extends State<_HistoryPage> {
  static const _ranges = ['7', '30', 'month'];
  int _tab = 0;
  String? _month;
  List<Map<String, dynamic>> _months = const [];

  Future<void> _openDay(BuildContext context, Map<String, dynamic> r) async {
    final res = await busy(context, () => ApiClient.get('/retailer/day', query: {'date': r['date']}));
    if (res == null || !context.mounted) return;
    final orders = (res['orders'] as List).map(_m).toList();
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => InvoicePage(
        mode: r['today'] == true ? InvoiceMode.order : InvoiceMode.delivery,
        date: '${r['date']}', orders: orders, selectedId: orders.isEmpty ? 0 : int0(orders.first['id']))));
  }

  Future<void> _pickMonth() async {
    if (_months.isEmpty) return;
    final v = await showHSheet<String>(context, builder: (c) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('মাস বাছুন', style: hs(18, w: w7)),
          gap12,
          for (final m in _months)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: HCard(
                onTap: () => Navigator.pop(c, '${m['value']}'),
                color: '${m['value']}' == (_month ?? '') ? HC.soft : Colors.white,
                child: Row(children: [
                  Expanded(child: Text('${m['label']}', style: hs(15, w: w7))),
                  if ('${m['value']}' == (_month ?? '')) const Svg('<path d="M5 12l5 5L20 7"/>', size: 18, color: HC.blue, stroke: 2.4),
                ]),
              ),
            ),
        ]));
    if (v != null && mounted) {
      setState(() {
        _tab = 2;
        _month = v;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final range = _ranges[_tab];
    final month = _tab == 2 ? _month : null;
    return AsyncBody(
      key: ValueKey('$range$month'),
      sky: true,
      load: () => loadCached('ret_history_$range${month ?? ''}', () => ApiClient.get('/retailer/history', query: {'range': range, if (month != null) 'month': month})),
      builder: (context, d, reload) {
        final rows = (d['rows'] as List).map(_m).toList();
        _months = ((d['months'] as List?) ?? const []).map(_m).toList();
        final monthLabel = _months.firstWhere((m) => m['value'] == d['month'], orElse: () => _months.isEmpty ? {'label': monthYearBn()} : _months.first)['label'];
        final bars = rows.take(7).toList().reversed.toList();
        final max = bars.fold<double>(1, (a, r) => num0(r['total']) > a ? num0(r['total']) : a);
        final profit = d['profit'];
        return SkyBox(
          height: 250,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Expanded(child: Text('হিস্ট্রি', style: hs(21, w: w7, color: Colors.white))),
              Pressable(
                child: GestureDetector(
                  onTap: _pickMonth,
                  child: Container(
                    height: 40, padding: const EdgeInsets.symmetric(horizontal: 14),
                    decoration: BoxDecoration(color: const Color(0x29FFFFFF), borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0x42FFFFFF))),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      const Svg('<rect x="3" y="5" width="18" height="16" rx="2"/><path d="M3 10h18M8 3v4M16 3v4"/>', size: 16, color: Colors.white, stroke: 1.8),
                      const SizedBox(width: 8),
                      Text('$monthLabel', style: hs(14, w: w7, color: Colors.white)),
                    ]),
                  ),
                ),
              ),
            ]),
            gap12,
            HSeg(items: const ['৭ দিন', '৩০ দিন', 'এই মাস'], index: _tab, onTap: (i) => setState(() {
                  _tab = i;
                  if (i == 2) _month = null;
                })),
            gap12,
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(22),
                  boxShadow: const [BoxShadow(color: Color(0x240A1640), blurRadius: 40, offset: Offset(0, 18))]),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('মোট কেনা', style: hs(12, color: HC.muted)),
                    FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text(tk(d['bought']), style: hs(28, w: w7, num: true, h: 1.1))),
                  ])),
                  if (profit != null)
                    Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                      Text('আপনার লাভ', style: hs(12, color: HC.muted)),
                      Text(sMoney(profit), style: hs(20, w: w7, color: const Color(0xFF12805C), num: true)),
                    ]),
                ]),
                if (bars.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  Row(children: [
                    for (var i = 0; i < bars.length; i++) ...[
                      if (i > 0) const SizedBox(width: 10),
                      Expanded(child: Column(children: [
                        SizedBox(
                          height: 56,
                          child: Align(
                            alignment: Alignment.bottomCenter,
                            child: TweenAnimationBuilder<double>(
                              tween: Tween(begin: 0, end: (num0(bars[i]['total']) / max).clamp(.06, 1).toDouble()),
                              duration: Duration(milliseconds: 600 + i * 60), curve: kEase,
                              builder: (_, v, __) => FractionallySizedBox(
                                heightFactor: v,
                                child: Container(decoration: BoxDecoration(color: i == bars.length - 1 ? HC.blue : HC.onSky, borderRadius: BorderRadius.circular(6))),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text('${bars[i]['day']}', style: hs(11, color: HC.muted)),
                      ])),
                    ],
                  ]),
                ],
              ]),
            ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
                Expanded(child: Text('ডেলিভারি', style: hs(17, w: w7))),
                Text('${bn(int0(d['days']))} দিন · ${bn(int0(d['deliveries']))}টি ডেলিভারি', style: hs(13, color: HC.muted)),
              ]),
            ),
            gap8,
            if (rows.isEmpty)
              const HEmpty('এই সময়ে কোনো কেনা নেই', body: 'অর্ডার ও ডেলিভারি হলে দিন অনুযায়ী এখানে জমা হবে।')
            else
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(22),
                    boxShadow: const [BoxShadow(color: Color(0x140A1640), blurRadius: 30, offset: Offset(0, 10))]),
                child: Column(children: [
                  for (var i = 0; i < rows.length; i++)
                    Pressable(
                      scale: .98,
                      child: InkWell(
                        onTap: () => _openDay(context, rows[i]),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 11),
                          decoration: BoxDecoration(border: i == 0 ? null : const Border(top: BorderSide(color: Color(0xFFEEF0F5)))),
                          child: Row(children: [
                            Container(
                              width: 46, height: 46,
                              decoration: BoxDecoration(color: i == 0 ? HC.sky : HC.soft, borderRadius: BorderRadius.circular(14)),
                              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                                Text('${rows[i]['day']}', style: hs(16, w: w7, color: i == 0 ? Colors.white : HC.blue, h: 1.05)),
                                Text('${rows[i]['month']}', style: hs(10, color: i == 0 ? Colors.white : HC.blue, h: 1.05)),
                              ]),
                            ),
                            const SizedBox(width: 12),
                            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text('${rows[i]['title']}', style: hs(15, w: w7)),
                              Text('${rows[i]['companies']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: hs(12, color: HC.muted)),
                            ])),
                            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                              Text(tk(rows[i]['total']), style: hs(15, w: w7, num: true)),
                              if (rows[i]['profit'] != null)
                                Text('লাভ ${sMoney(rows[i]['profit'])}', style: hs(12, w: w7, color: const Color(0xFF12805C), num: true)),
                            ]),
                          ]),
                        ),
                      ),
                    ),
                ]),
              ),
          ]),
        );
      },
    );
  }
}
