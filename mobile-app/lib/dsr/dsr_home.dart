import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../core/api.dart';
import '../core/format.dart';
import '../core/offline.dart';
import '../core/realtime.dart';
import '../core/tracker.dart';
import '../sr/sr_pages.dart' show signOut, icLogout;
import '../ui/account.dart';
import '../ui/common.dart';
import '../ui/dkit.dart';
import '../ui/hkit.dart';
import '../ui/pwa_kit.dart';
import '../ui/tracker_banner.dart';
import '../ui/update.dart';
import 'attendance_page.dart';
import 'delivery_page.dart';
import 'expense_page.dart';
import 'settlement_page.dart';
import 'van_stock_page.dart';

Map<String, dynamic> _m(Object? v) => Map<String, dynamic>.from((v ?? {}) as Map);

const _icToday = '<path d="M4 11l8-6 8 6v8a1 1 0 0 1-1 1H5a1 1 0 0 1-1-1z"/>';
const _icShops = '<path d="M20 10c0 6-8 12-8 12s-8-6-8-12a8 8 0 0 1 16 0Z"/><circle cx="12" cy="10" r="3"/>';
const _icVan = '<path d="M10 17h4V5H2v12h3"/><path d="M20 17h2v-3.34a4 4 0 0 0-1.17-2.83L19 9h-5"/><circle cx="7.5" cy="17.5" r="2.5"/><circle cx="17.5" cy="17.5" r="2.5"/>';
const _icMe = '<circle cx="12" cy="8" r="4"/><path d="M4 20a8 8 0 0 1 16 0"/>';

void openSettlement(BuildContext context) =>
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => const DPage(kicker: 'ট্রিপ শেষে', title: 'হিসাব মিলাও', child: SettlementPage())));

void openExpenses(BuildContext context) =>
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => const DPage(kicker: 'ট্রিপের খরচ', title: 'আজকের খরচ', child: ExpensePage())));

/// DSR app (design DM1–DM8): আজ · দোকান · ভ্যান · আমি.
class DsrHome extends StatefulWidget {
  const DsrHome({super.key});
  @override
  State<DsrHome> createState() => _DsrHomeState();
}

class _DsrHomeState extends State<DsrHome> {
  int _tab = 0;
  final _visited = <int>{0};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      UpdateChecker.check(context);
      if (!Tracker.instance.running) Tracker.instance.start('dsr');
    });
  }

  void _go(int i) => setState(() {
        _tab = i;
        _visited.add(i);
      });

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.of(context).padding.top;
    Widget lazy(int i, Widget Function() b) => _visited.contains(i) ? b() : const SizedBox.shrink();
    return PopScope(
      canPop: _tab == 0,
      onPopInvokedWithResult: (did, _) {
        if (!did) _go(0);
      },
      child: SkyStatusBar(
        child: Scaffold(
          backgroundColor: HC.outer,
          body: Frame(
            color: HC.outer,
            child: ColoredBox(
              color: HC.bg,
              child: Stack(children: [
                IndexedStack(index: _tab, children: [
                  _TodayPage(onShops: () => _go(1)),
                  lazy(1, () => DeliveryPage(active: _tab == 1)),
                  lazy(2, () => const VanStockPage()),
                  lazy(3, () => const _MePage()),
                ]),
                Positioned(top: top + 6, left: 0, right: 0, child: const Center(child: SyncChip())),
              ]),
            ),
          ),
          bottomNavigationBar: Frame(
            shrink: true,
            color: HC.outer,
            child: HTabBar(index: _tab, onTap: _go, items: const [
              HNavItem('আজ', _icToday),
              HNavItem('দোকান', _icShops),
              HNavItem('ভ্যান', _icVan),
              HNavItem('আমি', _icMe),
            ]),
          ),
        ),
      ),
    );
  }
}

/// DM1 — today: who I am, progress and cash, the next shop, the rest of the route.
class _TodayPage extends StatefulWidget {
  const _TodayPage({required this.onShops});
  final VoidCallback onShops;
  @override
  State<_TodayPage> createState() => _TodayPageState();
}

class _TodayPageState extends State<_TodayPage> {
  final _body = GlobalKey<AsyncBodyState>();
  double? _lat, _lng;
  StreamSubscription? _sync, _live;

  @override
  void initState() {
    super.initState();
    _sync = OfflineQueue.instance.onSynced.listen((_) => _body.currentState?.reload());
    _live = Realtime.instance.events.listen((_) => _body.currentState?.reload());
    Tracker.currentOnce().then((p) {
      if (p != null && mounted) {
        setState(() {
          _lat = p.latitude;
          _lng = p.longitude;
        });
      }
    });
  }

  @override
  void dispose() {
    _sync?.cancel();
    _live?.cancel();
    super.dispose();
  }

  double _dist(Map s) {
    if (_lat == null || num0(s['lat']) == 0) return 9e12;
    const k = 0.017453292519943295;
    final lat = num0(s['lat']), lng = num0(s['lng']);
    final a = 0.5 - cos((lat - _lat!) * k) / 2 + cos(_lat! * k) * cos(lat * k) * (1 - cos((lng - _lng!) * k)) / 2;
    return 12742000 * asin(sqrt(a));
  }

  Future<Loaded> _load() async {
    final a = await loadCached('dsr_dashboard_open', () => ApiClient.get('/dsr/dashboard'));
    final b = await loadCached('dsr_delivery_open', () => ApiClient.get('/dsr/delivery'));
    return Loaded({'dash': a.data, 'del': b.data}, stale: a.stale || b.stale);
  }

  @override
  Widget build(BuildContext context) {
    return AsyncBody(
      key: _body,
      sky: true,
      load: _load,
      builder: (context, all, reload) {
        final d = _m(all['dash']);
        final del = _m(all['del']);
        final me = _m(d['dsr']);
        final trip = d['trip'] == null ? null : _m(d['trip']);
        final sum = d['settlement'] == null ? <String, dynamic>{} : _m(d['settlement']);
        final att = d['attendance'] == null ? null : _m(d['attendance']);
        final stops = ((del['orders'] as List?) ?? const []).map(_m).toList();
        final numbered = {for (var i = 0; i < stops.length; i++) '${stops[i]['id']}': i + 1};
        final pending = stops.where((s) => s['status'] == 'Pending').toList()..sort((a, b) => _dist(a).compareTo(_dist(b)));
        final done = stops.length - pending.length;
        final cash = stops.fold<double>(0, (a, s) => a + stopCash(s));
        final next = pending.isEmpty ? null : pending.first;
        final rest = pending.skip(1).toList();
        final editable = trip != null && trip['editable'] == true;
        final scanned = att != null && att['checked_in_at'] != null;
        Future<void> open(Map<String, dynamic> s) async {
          final v = await openStop(context, s, del);
          if (v == true) reload();
        }

        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          SkyBox(
            height: 210,
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                LetterAvatar('${me['name'] ?? 'D'}', size: 48, radius: 16, image: me['photo'] == null ? null : NetImage(ApiClient.asset(me['photo']))),
                const SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('ডেলিভারি · ${me['partner'] ?? ''}', maxLines: 1, overflow: TextOverflow.ellipsis, style: hs(12.5, color: HC.onSky)),
                  Text('${me['name'] ?? ''}', maxLines: 1, overflow: TextOverflow.ellipsis, style: hs(20, w: w8, color: Colors.white)),
                ])),
              ]),
              const SizedBox(height: 18),
              HCard(
                lift: true, radius: 24,
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Text(trip == null ? 'আজ কোনো ট্রিপ নেই' : 'আজকের ডেলিভারি · ট্রিপ ${bn('${trip['code']}')}', style: hs(12.5, color: HC.muted)),
                  const SizedBox(height: 6),
                  Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                    Text(bn(done), style: hs(34, w: w8, num: true, h: 1)),
                    Padding(padding: const EdgeInsets.only(bottom: 4, left: 4), child: Text('/ ${bn(stops.length)} দোকান', style: hs(14, w: w6, color: HC.muted, num: true))),
                    const Spacer(),
                    Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                      Text('হাতে নগদ', style: hs(12, color: HC.muted)),
                      Text(tk(cash), style: hs(20, w: w8, color: HC.blue, num: true, h: 1.2)),
                    ]),
                  ]),
                  const SizedBox(height: 12),
                  DProgress(stops.isEmpty ? 0 : done / stops.length * 100, complete: stops.isNotEmpty && done == stops.length),
                ]),
              ),
            ]),
          ),
          const SizedBox(height: 4),
          const TrackerBanner(role: 'dsr'),
          if (trip != null && trip['editable'] != true)
            const Padding(padding: EdgeInsets.only(top: 10), child: DBanner('সেটেলমেন্ট জমা দেওয়া হয়েছে — পার্টনারের যাচাইয়ের অপেক্ষায়।'))
          else if (trip != null && trip['settlement_status'] == 'returned')
            Padding(padding: const EdgeInsets.only(top: 10), child: DBanner('সেটেলমেন্ট ফেরত পাঠানো হয়েছে${'${trip['review_note'] ?? ''}'.isNotEmpty ? ': ${trip['review_note']}' : ''}। সংশোধন করে পুনরায় জমা দিন।', returned: true)),
          if (!scanned) ...[
            gap12,
            HCard(
              radius: 20, onTap: () => Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => const AttendancePage(scan: true))).then((v) => v == true ? reload() : null),
              child: Row(children: [
                const NumDot('QR', bg: HC.soft, fg: HC.blue, size: 40),
                const SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('আজ এখনো হাজিরা হয়নি', style: hs(14.5, w: w7)),
                  Text('গুদামের QR স্ক্যান করুন', style: hs(12, color: HC.muted)),
                ])),
                const Svg('<path d="m9 18 6-6-6-6"/>', size: 18, color: HC.muted, stroke: 2.2),
              ]),
            ),
          ],
          gap16,
          if (next != null)
            _NextCard(stop: next, number: numbered['${next['id']}'] ?? 1, editable: editable, onOpen: () => open(next))
          else if (trip != null && stops.isNotEmpty)
            HCard(
              lift: true, radius: 24,
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Text('সব দোকান শেষ', style: hs(18, w: w8)),
                Text('${bn(stops.length)}টি দোকান · নগদ ${tk(cash)} · জমা দিতে হবে ${tk(sum['net_pay'] ?? 0)}', style: hs(12.5, color: HC.muted, num: true)),
                gap12,
                HBtn(editable ? 'হিসাব মিলাও (সেটেলমেন্ট)' : 'সেটেলমেন্ট দেখুন', onTap: () => openSettlement(context)),
              ]),
            )
          else
            const HEmpty('আজ কোনো ডেলিভারি নেই', body: 'পার্টনার ট্রিপ দিলে এখানে দোকানগুলো আসবে।'),
          if (rest.isNotEmpty) ...[
            gap16,
            HSec('এরপর', trailing: 'মোট বিল ${tk(rest.fold<double>(0, (a, s) => a + stopBill(s)))}'),
            gap8,
            HList(children: [
              for (final s in rest.take(6))
                InkWell(
                  onTap: () => open(s),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 11),
                    child: Row(children: [
                      NumDot(bn(numbered['${s['id']}'] ?? 0), bg: HC.chip, fg: HC.ink2, size: 34),
                      const SizedBox(width: 12),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('${s['retailer_name']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: hs(14.5, w: w6)),
                        Text([if ('${s['address'] ?? ''}'.isNotEmpty) '${s['address']}', if (stopMemo(s).isNotEmpty) 'মেমো ${bn(stopMemo(s))}'].join(' · '), maxLines: 1, overflow: TextOverflow.ellipsis, style: hs(12, color: HC.muted, num: true)),
                      ])),
                      Text(tk(stopBill(s)), style: hs(14, w: w7, num: true)),
                    ]),
                  ),
                ),
            ]),
            if (rest.length > 6) ...[gap8, HBtn('সব দোকান দেখুন', kind: HBtnKind.line, height: 46, onTap: widget.onShops)],
          ],
        ]);
      },
    );
  }
}

class _NextCard extends StatelessWidget {
  const _NextCard({required this.stop, required this.number, required this.editable, required this.onOpen});
  final Map<String, dynamic> stop;
  final int number;
  final bool editable;
  final VoidCallback onOpen;
  @override
  Widget build(BuildContext context) {
    final memo = stopMemo(stop);
    return HCard(
      lift: true, radius: 26, padding: const EdgeInsets.all(18),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          const HChip('পরের দোকান', dot: true, size: 11.5),
          const SizedBox(width: 10),
          Expanded(child: Text(memo.isEmpty ? '' : 'মেমো ${bn(memo)}', textAlign: TextAlign.right, maxLines: 1, overflow: TextOverflow.ellipsis, style: hs(12, color: HC.muted, num: true))),
        ]),
        const SizedBox(height: 14),
        Row(children: [
          LetterAvatar('${stop['retailer_name']}', size: 52, radius: 16, bg: HC.soft, fg: HC.blue, fontSize: 21),
          const SizedBox(width: 14),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${stop['retailer_name']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: hs(19, w: w8)),
            Text([if ('${stop['address'] ?? ''}'.isNotEmpty) '${stop['address']}', '${bn(stopItems(stop))}টি পণ্য'].join(' · '), maxLines: 1, overflow: TextOverflow.ellipsis, style: hs(12.5, color: HC.muted)),
          ])),
          NumDot(bn(number), bg: HC.ink, fg: Colors.white, size: 30),
        ]),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(color: HC.bg, borderRadius: BorderRadius.circular(16)),
          child: Row(children: [
            Expanded(child: Text('টাকা নিতে হবে', style: hs(13.5, w: w6, color: HC.ink2))),
            Text(tk(stopBill(stop)), style: hs(22, w: w8, num: true)),
          ]),
        ),
        const SizedBox(height: 14),
        HBtn(editable ? 'ডেলিভারি শুরু' : 'দেখুন', trailingIcon: '<path d="M5 12h14M13 6l6 6-6 6"/>', onTap: onOpen),
      ]),
    );
  }
}

/// DM6 — আমি: profile, today's QR check-in, cash to hand over, attendance calendar, wage, settings.
class _MePage extends StatefulWidget {
  const _MePage();
  @override
  State<_MePage> createState() => _MePageState();
}

class _MePageState extends State<_MePage> {
  Future<Loaded> _load() async {
    final a = await loadCached('dsr_dashboard_open', () => ApiClient.get('/dsr/dashboard'));
    final b = await loadCached('dsr_attendance_today', () => ApiClient.get('/dsr/attendance'));
    return Loaded({'dash': a.data, 'att': b.data}, stale: a.stale || b.stale);
  }

  @override
  Widget build(BuildContext context) {
    return AsyncBody(
      sky: true,
      load: _load,
      builder: (context, all, reload) {
        final d = _m(all['dash']);
        final att = _m(all['att']);
        final me = _m(d['dsr']);
        final sum = d['settlement'] == null ? <String, dynamic>{} : _m(d['settlement']);
        final today = att['today'] == null ? null : _m(att['today']);
        final days = ((att['days'] as List?) ?? const []).map(_m).toList();
        final wage = att['wage'] == null ? null : _m(att['wage']);
        final came = days.where((x) => x['status'] == 'present' || x['status'] == 'half').length;
        final month = DateTime.tryParse('${att['selectedDate'] ?? todayYmd()}') ?? DateTime.now();
        const months = ['জানুয়ারি', 'ফেব্রুয়ারি', 'মার্চ', 'এপ্রিল', 'মে', 'জুন', 'জুলাই', 'আগস্ট', 'সেপ্টেম্বর', 'অক্টোবর', 'নভেম্বর', 'ডিসেম্বর'];
        final late = today != null && int0(today['late_min']) > 0;
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          SkyBox(
            height: 150,
            child: Row(children: [
              LetterAvatar('${me['name'] ?? 'D'}', size: 56, radius: 18, image: me['photo'] == null ? null : NetImage(ApiClient.asset(me['photo']))),
              const SizedBox(width: 14),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${me['name'] ?? ''}', maxLines: 1, overflow: TextOverflow.ellipsis, style: hs(20, w: w8, color: Colors.white)),
                Text('ডেলিভারি ম্যান · ${me['partner'] ?? ''}', maxLines: 1, overflow: TextOverflow.ellipsis, style: hs(12.5, color: HC.onSky)),
              ])),
              GlassBtn(icon: icLogout, label: 'সাইন আউট', onTap: () => signOut(context)),
            ]),
          ),
          HCard(
            lift: true, radius: 22,
            onTap: today == null ? () => Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => const AttendancePage(scan: true))).then((v) => v == true ? reload() : null) : null,
            child: Row(children: [
              NumDot(today == null ? 'QR' : '✓', bg: today == null ? HC.soft : HC.blue, fg: today == null ? HC.blue : Colors.white, size: 44),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(today == null ? 'আজ হাজিরা দিন' : 'হাজিরা · ${timeBn(today['checked_in_at']?.toString())}', style: hs(15, w: w7, num: true)),
                Text(today == null ? 'গুদামের QR কোডে ক্যামেরা ধরুন' : (late ? '${bn(today['late_min'])} মিনিট দেরি' : 'সময়মতো এসেছেন'), style: hs(12, color: late ? HC.red : HC.muted, num: true)),
              ])),
              if (today == null) HBtn('স্ক্যান', expand: false, height: 40, radius: 12, fontSize: 13, onTap: () => Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => const AttendancePage(scan: true))).then((v) => v == true ? reload() : null)),
            ]),
          ),
          gap12,
          GestureDetector(
            onTap: () => openSettlement(context),
            child: Container(
              padding: const EdgeInsets.fromLTRB(18, 16, 16, 16),
              decoration: BoxDecoration(color: HC.ink, borderRadius: BorderRadius.circular(22)),
              child: Row(children: [
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('আজ হাতে নগদ · পার্টনারকে জমা দিন', style: hs(12.5, color: HC.onDark)),
                  Text(tk(sum['net_pay'] ?? 0), style: hs(26, w: w8, color: Colors.white, num: true, h: 1.2)),
                ])),
                const Svg('<path d="m9 18 6-6-6-6"/>', size: 20, color: Colors.white, stroke: 2.2),
              ]),
            ),
          ),
          gap16,
          HCard(radius: 22, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Expanded(child: Text('হাজিরা · ${months[month.month - 1]}', style: hs(15, w: w7))),
              Text('${bn(came)} দিন এসেছি', style: hs(12.5, w: w6, color: HC.blue, num: true)),
            ]),
            gap12,
            _Calendar(month: month, days: days),
          ])),
          if (wage != null) ...[
            gap12,
            HCard(radius: 22, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              HKv('পাওনা (${bn(numTrim(wage['worked']))} দিন × ${tk(wage['daily_wage'])})', tk(wage['wage'])),
              if (num0(wage['over']) > 0) ...[const SizedBox(height: 8), HKv('ওভার (টাকা বেশি)', '+${tk(wage['over'])}', valueColor: HC.blue)],
              if (num0(wage['advance']) > 0) ...[const SizedBox(height: 8), HKv('অ্যাডভান্স নিয়েছি', '−${tk(wage['advance'])}', valueColor: HC.red)],
              if (num0(wage['short']) > 0) ...[const SizedBox(height: 8), HKv('শর্ট (টাকা কম)', '−${tk(wage['short'])}', valueColor: HC.red)],
              if (num0(wage['paid']) > 0) ...[const SizedBox(height: 8), HKv('বেতন পেয়েছি', '−${tk(wage['paid'])}', valueColor: HC.red)],
              const SizedBox(height: 10),
              const HDashed(),
              const SizedBox(height: 10),
              HKv('মাস শেষে পাবো', tk(wage['net']), big: true),
            ])),
          ],
          gap16,
          HList(children: [
            _menu(context, '<rect x="2" y="5" width="20" height="14" rx="2"/><path d="M2 10h20"/>', 'হিসাব মিলাও (সেটেলমেন্ট)', () => openSettlement(context)),
            _menu(context, '<path d="M4 2v20l2-1 2 1 2-1 2 1 2-1 2 1 2-1 2 1V2l-2 1-2-1-2 1-2-1-2 1-2-1-2 1Z"/><path d="M8 7h8M8 11h8"/>', 'আজকের খরচ', () => openExpenses(context)),
            _menu(context, '<circle cx="12" cy="12" r="9"/><path d="M12 8v4l3 2"/>', 'হাজিরার বিস্তারিত', () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AttendancePage()))),
          ]),
          gap12,
          const AccountCard(),
        ]);
      },
    );
  }

  Widget _menu(BuildContext context, String icon, String label, VoidCallback onTap) => InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 13),
          child: Row(children: [
            Container(width: 38, height: 38, decoration: BoxDecoration(color: HC.bg, borderRadius: BorderRadius.circular(12)), child: Center(child: Svg(icon, size: 18, color: HC.ink))),
            const SizedBox(width: 12),
            Expanded(child: Text(label, style: hs(14.5, w: w6))),
            const Svg('<path d="m9 18 6-6-6-6"/>', size: 18, color: HC.muted, stroke: 2.2),
          ]),
        ),
      );
}

/// Month grid (Saturday first) coloured by attendance status.
class _Calendar extends StatelessWidget {
  const _Calendar({required this.month, required this.days});
  final DateTime month;
  final List<Map<String, dynamic>> days;
  @override
  Widget build(BuildContext context) {
    final byDay = {for (final x in days) int0(x['day']): '${x['status']}'};
    final first = DateTime(month.year, month.month, 1);
    final count = DateTime(month.year, month.month + 1, 0).day;
    final lead = (first.weekday + 1) % 7; // Sat = 0
    const heads = ['শনি', 'রবি', 'সোম', 'মঙ্গল', 'বুধ', 'বৃহঃ', 'শুক্র'];
    final cells = <Widget>[
      for (final h in heads) Center(child: Text(h, style: hs(11, w: w6, color: HC.muted))),
      for (var i = 0; i < lead; i++) const SizedBox(),
      for (var day = 1; day <= count; day++)
        Builder(builder: (_) {
          final st = byDay[day] ?? 'future';
          final (bg, fg) = switch (st) {
            'present' => (HC.blue, Colors.white),
            'half' => (HC.lilac, HC.ink),
            'absent' => (HC.redSoft, HC.red),
            'holiday' => (HC.chip, HC.muted),
            'pending' => (HC.soft, HC.blue),
            _ => (Colors.transparent, HC.faint),
          };
          return Container(
            margin: const EdgeInsets.all(2.5),
            decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(10)),
            alignment: Alignment.center,
            child: Text(bn(day), style: hs(12.5, w: w6, color: fg, num: true)),
          );
        }),
    ];
    return GridView.count(
      crossAxisCount: 7, shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), childAspectRatio: 1.05,
      children: cells,
    );
  }
}
