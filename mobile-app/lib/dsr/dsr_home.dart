import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/api.dart';
import '../core/format.dart';
import '../core/offline.dart';
import '../core/session.dart';
import '../core/tracker.dart';
import '../ui/account.dart';
import '../ui/common.dart';
import '../ui/dkit.dart';
import '../ui/pwa_kit.dart';
import '../ui/tracker_banner.dart';
import '../ui/update.dart';
import 'attendance_page.dart';
import 'delivery_page.dart';
import 'expense_page.dart';
import 'settlement_page.dart';
import 'van_stock_page.dart';

Map<String, dynamic> _m(Object? v) => Map<String, dynamic>.from((v ?? {}) as Map);

/// DSR panel shell — same 5 tabs as the PWA bottom nav, top bar on every tab except the full-screen delivery map.
class DsrHome extends StatefulWidget {
  const DsrHome({super.key});
  @override
  State<DsrHome> createState() => _DsrHomeState();
}

class _DsrHomeState extends State<DsrHome> {
  int _tab = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      UpdateChecker.check(context);
      if (!Tracker.instance.running) Tracker.instance.start('dsr');
    });
  }

  Future<void> _logout() async {
    final q = OfflineQueue.instance.ops.length;
    if (await confirm(context, 'সাইন আউট করবেন?', body: q > 0 ? 'এখনো ${bn(q)}টি কাজ সিঙ্ক হয়নি। সাইন আউট করলে সেগুলো মুছে যাবে।' : null, danger: true, yes: 'সাইন আউট')) {
      if (mounted) await context.read<AuthState>().logout();
    }
  }

  @override
  Widget build(BuildContext context) {
    const titles = ['ড্যাশবোর্ড', 'ডেলিভারি', 'ভ্যান স্টক', 'সেটেলমেন্ট', 'খরচ'];
    return Scaffold(
      backgroundColor: DC.outer,
      body: Frame(
        color: DC.outer,
        child: ColoredBox(
          color: DC.bg,
          child: Column(children: [
            if (_tab != 1)
              DTopBar(title: titles[_tab], actions: [
                const Padding(padding: EdgeInsets.only(left: 8), child: SyncChip()),
                DIconBtn(icon: Ic.user, tooltip: 'আমি', onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const _DsrAccountPage()))),
                DIconBtn(icon: Ic.logout, tooltip: 'সাইন আউট', onTap: _logout),
              ]),
            Expanded(
              child: IndexedStack(index: _tab, children: [
                _DsrDashboard(onGo: (i) => setState(() => _tab = i)),
                const DeliveryPage(),
                const VanStockPage(),
                const SettlementPage(),
                const ExpensePage(),
              ]),
            ),
            DBottomNav(index: _tab, onTap: (i) => setState(() => _tab = i)),
          ]),
        ),
      ),
    );
  }
}

class _DsrAccountPage extends StatelessWidget {
  const _DsrAccountPage();
  @override
  Widget build(BuildContext context) {
    final p = context.watch<AuthState>().profile;
    final photo = ApiClient.asset(p['photo']);
    return DPage(
      title: 'আমি',
      child: ListView(padding: const EdgeInsets.all(14), children: [
        DCard(
          child: Row(children: [
            ClipOval(child: SizedBox(width: 60, height: 60, child: NetImage(photo, fallback: Container(color: DC.subtle, child: const Icon(Icons.person, size: 30, color: DC.muted))))),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${p['name']}', style: ts(18, w: FontWeight.w700)),
                Text('${p['code'] ?? ''} · ${p['phone']}', style: ts(13, color: DC.muted)),
                Text('${p['partner'] ?? ''}', style: ts(12.5, color: DC.muted)),
              ]),
            ),
          ]),
        ),
        const SizedBox(height: 12),
        const AccountCard(),
      ]),
    );
  }
}

class _DsrDashboard extends StatefulWidget {
  const _DsrDashboard({required this.onGo});
  final ValueChanged<int> onGo;
  @override
  State<_DsrDashboard> createState() => _DsrDashboardState();
}

class _DsrDashboardState extends State<_DsrDashboard> {
  String? _date;

  static const _icons = {
    'att': '<rect x="3" y="3" width="7" height="7" rx="1"/><rect x="14" y="3" width="7" height="7" rx="1"/><rect x="3" y="14" width="7" height="7" rx="1"/><path d="M14 14h3v3h-3zM20 14v.01M14 20v.01M20 20h-3v-3"/>',
  };

  @override
  Widget build(BuildContext context) {
    return AsyncBody(
      key: ValueKey(_date),
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 20),
      load: () => loadCached('dsr_dashboard_${_date ?? 'open'}', () => ApiClient.get('/dsr/dashboard', query: {'date': _date})),
      builder: (context, d, reload) {
        final trip = d['trip'] == null ? null : _m(d['trip']);
        final s = _m(d['stats']);
        final att = d['attendance'] == null ? null : _m(d['attendance']);
        final sum = d['settlement'] == null ? <String, dynamic>{} : _m(d['settlement']);
        final date = d['date'].toString();
        final today = d['today']?.toString() ?? todayYmd();
        final stops = int0(s['stops']), cancelled = int0(s['cancelled']), delivered = int0(s['delivered']);
        final total = (stops - cancelled) < 1 ? 1 : stops - cancelled;
        final pct = stops > 0 ? (delivered / total * 100).round().clamp(0, 100) : 0;
        final scanned = att != null && att['checked_in_at'] != null;
        final attLabel = scanned ? 'হাজিরা — ${date == today ? 'আজ ' : ''}${timeBn(att['checked_in_at']?.toString())}-এ সম্পন্ন' : 'হাজিরা — QR স্ক্যান করুন';
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          DDateNav(date: date, onChange: (v) => setState(() => _date = v == today ? null : v)),
          const SizedBox(height: 14),
          const TrackerBanner(role: 'dsr'),
          if (trip == null)
            DCard(padding: const EdgeInsets.fromLTRB(18, 22, 18, 22), child: Center(child: Text('কোনো ডিসপ্যাচ করা ট্রিপ নেই', style: ts(15, w: FontWeight.w600))))
          else ...[
            if (trip['editable'] != true)
              const Padding(padding: EdgeInsets.only(bottom: 12), child: DBanner('সেটেলমেন্ট জমা দেওয়া হয়েছে — পার্টনারের যাচাইয়ের অপেক্ষায়।'))
            else if (trip['settlement_status'] == 'returned')
              Padding(padding: const EdgeInsets.only(bottom: 12), child: DBanner('সেটেলমেন্ট ফেরত পাঠানো হয়েছে${trip['review_note'] != null && '${trip['review_note']}'.isNotEmpty ? ': ${trip['review_note']}' : ''}। সংশোধন করে পুনরায় জমা দিন।', returned: true)),
            DCard(
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('মোট দোকান', style: ts(11.5, w: FontWeight.w600, color: DC.muted)),
                      const SizedBox(height: 4),
                      Text(bn(stops), style: ts(32, w: FontWeight.w700, ls: -0.8, h: 1.1, tabular: true)),
                      const SizedBox(height: 4),
                      Text('${bn(delivered)} / ${bn(total)}টি ডেলিভারি হয়েছে', style: ts(13.5, w: FontWeight.w600, color: DC.ink2, tabular: true)),
                    ]),
                  ),
                  Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                    DBadge('${bn(pct)}% সম্পন্ন', tone: pct >= 100 ? DTone.success : DTone.info),
                    const SizedBox(height: 4),
                    Text(dateBn('${trip['date']}'), style: ts(12, color: DC.muted, tabular: true)),
                  ]),
                ]),
                const SizedBox(height: 14),
                DProgress(pct.toDouble(), complete: pct >= 100),
                const SizedBox(height: 7),
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  Flexible(child: Text.rich(TextSpan(style: ts(12, color: DC.muted), children: [const TextSpan(text: 'ডেলিভারি: '), TextSpan(text: bn(delivered), style: ts(12, w: FontWeight.w700, color: DC.muted)), TextSpan(text: ' (বাকি ${bn(int0(s['due']))})')]))),
                  const SizedBox(width: 8),
                  Flexible(child: Text.rich(TextSpan(style: ts(12, color: DC.muted), children: [const TextSpan(text: 'অপেক্ষায়: '), TextSpan(text: bn(int0(s['pending'])), style: ts(12, w: FontWeight.w700, color: DC.muted)), const TextSpan(text: ' · বাতিল: '), TextSpan(text: bn(cancelled), style: ts(12, w: FontWeight.w700, color: DC.muted))]), textAlign: TextAlign.right)),
                ]),
              ]),
            ),
            const SizedBox(height: 14),
            IntrinsicHeight(child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Expanded(child: _Mini('চলমান ট্রিপ', bn('${trip['code']}'), 'ভ্যানে বাকি ${bn(int0(s['available_pcs']))} / ${bn(int0(s['dispatched_pcs']))} পিস')),
              const SizedBox(width: 10),
              Expanded(child: _Mini('জমা দেওয়ার ক্যাশ', bnMoney(sum['net_pay'] ?? 0), 'খরচ ${bnMoney(sum['daily_expenses'] ?? 0)} · বাকি ${bnMoney(sum['retailer_due'] ?? 0)}')),
            ])),
          ],
          const SizedBox(height: 14),
          _Quick(_icons['att']!, attLabel, () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AttendancePage())).then((_) => reload())),
          _Quick(DBottomNav.items[1].icon, 'ডেলিভারি ম্যাপ ও দোকান', () => widget.onGo(1)),
          _Quick(DBottomNav.items[2].icon, 'ভ্যান স্টক সারাংশ', () => widget.onGo(2)),
          _Quick(DBottomNav.items[3].icon, 'ট্রিপ সেটেলমেন্ট ও নোট গণনা', () => widget.onGo(3)),
          _Quick(DBottomNav.items[4].icon, 'ট্রিপ খরচ', () => widget.onGo(4)),
        ]);
      },
    );
  }
}

class _Mini extends StatelessWidget {
  const _Mini(this.label, this.value, this.sub);
  final String label, value, sub;
  @override
  Widget build(BuildContext context) => DCard(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: ts(12, color: DC.muted)),
          const SizedBox(height: 3),
          Text(value, style: ts(17.5, w: FontWeight.w700, h: 1.2, tabular: true)),
          const SizedBox(height: 3),
          Text(sub, style: ts(12, color: DC.muted, tabular: true)),
        ]),
      );
}

class _Quick extends StatelessWidget {
  const _Quick(this.icon, this.label, this.onTap);
  final String icon, label;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: DCard(
          padding: const EdgeInsets.all(14), onTap: onTap,
          child: Row(children: [
            Container(
              width: 38, height: 38,
              decoration: BoxDecoration(color: DC.subtle, borderRadius: BorderRadius.circular(9), border: Border.all(color: DC.border)),
              child: Center(child: Svg(icon, size: 18, color: DC.ink, stroke: 1.9)),
            ),
            const SizedBox(width: 12),
            Expanded(child: Text(label, style: ts(13.5, w: FontWeight.w600))),
            Text('→', style: ts(16, color: DC.muted)),
          ]),
        ),
      );
}
