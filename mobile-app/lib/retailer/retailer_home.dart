import 'dart:async';

import 'package:flutter/material.dart';

import '../core/api.dart';
import '../core/format.dart';
import '../core/push.dart';
import '../core/realtime.dart';
import '../ui/account.dart';
import '../ui/common.dart';
import '../ui/update.dart';
import 'invoice_page.dart';

Map<String, dynamic> _m(Object? v) => Map<String, dynamic>.from((v ?? {}) as Map);

class RetailerHome extends StatefulWidget {
  const RetailerHome({super.key});
  @override
  State<RetailerHome> createState() => _RetailerHomeState();
}

class _RetailerHomeState extends State<RetailerHome> {
  int _tab = 0;
  int _unread = 0;
  Timer? _poll;
  bool _first = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => UpdateChecker.check(context));
    _check();
    // Realtime-ish: the shop's goods/delivery events are checked every minute while the app is open
    // (push notifications cover the closed-app case).
    _poll = Timer.periodic(const Duration(seconds: 60), (_) => _check());
    _live = Realtime.instance.events.listen((_) => _check());
  }

  StreamSubscription? _live;

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
      // The live connection / push already showed it; only fall back to a local notification when neither is up.
      if (!_first && unread > _unread && !Realtime.instance.connected) {
        final first = (r['events'] as List).map(_m).firstWhere((e) => e['unread'] == true, orElse: () => {});
        Notifier.show('হ্যাপি বাংলাদেশ', (first['title'] ?? 'নতুন খবর আছে').toString());
      }
      _first = false;
      if (mounted) setState(() => _unread = unread);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    const titles = ['আজ', 'হিস্ট্রি', 'নোটিফিকেশন', 'আমি'];
    return Scaffold(
      appBar: AppBar(title: Text(titles[_tab])),
      body: IndexedStack(index: _tab, children: [
        const _TodayPage(),
        const _HistoryPage(),
        _NotificationsPage(onSeen: () => setState(() => _unread = 0), active: _tab == 2),
        const _MePage(),
      ]),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: [
          const NavigationDestination(icon: Icon(Icons.local_shipping_outlined), selectedIcon: Icon(Icons.local_shipping), label: 'আজ'),
          const NavigationDestination(icon: Icon(Icons.history), label: 'হিস্ট্রি'),
          NavigationDestination(
            icon: Badge(isLabelVisible: _unread > 0, label: Text(bn(_unread)), child: const Icon(Icons.notifications_outlined)),
            selectedIcon: const Icon(Icons.notifications), label: 'নোটিফিকেশন'),
          const NavigationDestination(icon: Icon(Icons.person_outline), selectedIcon: Icon(Icons.person), label: 'আমি'),
        ],
      ),
    );
  }
}

class _TodayPage extends StatelessWidget {
  const _TodayPage();
  @override
  Widget build(BuildContext context) {
    return AsyncBody(
      load: () => loadCached('ret_today', () => ApiClient.get('/retailer/today')),
      builder: (context, d, reload) {
        final shop = _m(d['shop']);
        final day = _m(d['day']);
        final cards = (day['cards'] as List).map(_m).toList();
        final orders = (day['orders'] as List).map(_m).toList();
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${shop['name']}', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
          Text(dateBn(d['date']?.toString()), style: const TextStyle(color: kMuted)),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(children: [
                const Expanded(child: Text('আজকের মোট বিল', style: TextStyle(fontWeight: FontWeight.w700))),
                Text(money(day['total']), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: kBlue)),
              ]),
            ),
          ),
          if (cards.isEmpty)
            const Padding(padding: EdgeInsets.all(40), child: Center(child: Text('আজ কোনো মাল আসার কথা নেই।', style: TextStyle(color: kMuted)))),
          for (final c in cards)
            Card(
              margin: const EdgeInsets.only(top: 10),
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => InvoicePage(date: d['date'].toString(), orders: orders, selectedId: int0(c['first'])))),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Expanded(child: Text('${c['title']}', style: const TextStyle(fontWeight: FontWeight.w800))),
                      Pill('${c['chip']}', color: switch (c['stage']) { 'arrived' => kOk, 'onway' => kBlue, _ => kWarn }),
                    ]),
                    if (c['dm'] != null) Padding(padding: const EdgeInsets.only(top: 4), child: Text('ডেলিভারি ম্যান: ${c['dm']}', style: const TextStyle(color: kMuted, fontSize: 13))),
                    const Divider(height: 20),
                    for (final r in (c['rows'] as List).map(_m))
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Row(children: [
                          Expanded(child: Text('SR ${r['sr']} · ${r['company']}', style: const TextStyle(fontSize: 13.5))),
                          Text(money(r['bill']), style: const TextStyle(fontWeight: FontWeight.w700)),
                        ]),
                      ),
                    const Divider(height: 20),
                    Row(children: [
                      const Expanded(child: Text('মোট', style: TextStyle(fontWeight: FontWeight.w800))),
                      Text(money(c['total']), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                      const SizedBox(width: 6),
                      const Icon(Icons.receipt_long, size: 18, color: kBlue),
                    ]),
                  ]),
                ),
              ),
            ),
        ]);
      },
    );
  }
}

class _HistoryPage extends StatelessWidget {
  const _HistoryPage();
  @override
  Widget build(BuildContext context) {
    return AsyncBody(
      load: () => loadCached('ret_history', () => ApiClient.get('/retailer/history')),
      builder: (context, d, reload) {
        final rows = (d['rows'] as List).map(_m).toList();
        if (rows.isEmpty) return const Padding(padding: EdgeInsets.all(40), child: Center(child: Text('এখনো কোনো ডেলিভারি নেই।', style: TextStyle(color: kMuted))));
        return Column(children: [
          for (final r in rows)
            Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                leading: Container(
                  width: 48, padding: const EdgeInsets.symmetric(vertical: 6),
                  decoration: BoxDecoration(color: r['today'] == true ? kBlue : const Color(0xFFEFF4FF), borderRadius: BorderRadius.circular(10)),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Text('${r['day']}', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17, color: r['today'] == true ? Colors.white : kBlue)),
                    Text('${r['month']}', style: TextStyle(fontSize: 10.5, color: r['today'] == true ? Colors.white : kBlue)),
                  ]),
                ),
                title: Text(money(r['total']), style: const TextStyle(fontWeight: FontWeight.w800)),
                subtitle: Text('${r['sub']}'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () async {
                  final res = await busy(context, () => ApiClient.get('/retailer/day', query: {'date': r['date']}));
                  if (res != null && context.mounted) {
                    final orders = (res['orders'] as List).map(_m).toList();
                    Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => InvoicePage(date: r['date'].toString(), orders: orders, selectedId: orders.isEmpty ? 0 : int0(orders.first['id']))));
                  }
                },
              ),
            ),
        ]);
      },
    );
  }
}

class _NotificationsPage extends StatefulWidget {
  const _NotificationsPage({required this.onSeen, required this.active});
  final VoidCallback onSeen;
  final bool active;
  @override
  State<_NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<_NotificationsPage> {
  final _key = GlobalKey<AsyncBodyState>();

  @override
  void didUpdateWidget(covariant _NotificationsPage old) {
    super.didUpdateWidget(old);
    if (widget.active && !old.active) {
      _key.currentState?.reload();
      ApiClient.send('POST', '/retailer/notifications/seen').then((_) => widget.onSeen()).catchError((_) => <String, dynamic>{});
    }
  }

  @override
  Widget build(BuildContext context) {
    return AsyncBody(
      key: _key,
      load: () => loadCached('ret_notif', () => ApiClient.get('/retailer/notifications')),
      builder: (context, d, reload) {
        final events = (d['events'] as List).map(_m).toList();
        if (events.isEmpty) return const Padding(padding: EdgeInsets.all(40), child: Center(child: Text('কোনো নোটিফিকেশন নেই।', style: TextStyle(color: kMuted))));
        final out = <Widget>[];
        String? group;
        for (final e in events) {
          if (e['group'] != group) {
            group = e['group']?.toString();
            out.add(SectionTitle(group ?? ''));
          }
          out.add(Card(
            margin: const EdgeInsets.only(bottom: 8),
            color: e['unread'] == true ? const Color(0xFFEFF4FF) : null,
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: switch (e['kind']) { 'arrived' => const Color(0xFFDCFCE7), 'onway' => const Color(0xFFEFF4FF), _ => const Color(0xFFFEF3C7) },
                child: Icon(switch (e['kind']) { 'arrived' => Icons.check, 'onway' => Icons.local_shipping, _ => Icons.receipt_long }, size: 20,
                    color: switch (e['kind']) { 'arrived' => kOk, 'onway' => kBlue, _ => kWarn }),
              ),
              title: Text('${e['title']}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5)),
              subtitle: e['sub'] == null ? null : Text('${e['sub']}'),
              trailing: Text('${e['when']}', style: const TextStyle(color: kMuted, fontSize: 12)),
            ),
          ));
        }
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: out);
      },
    );
  }
}

class _MePage extends StatelessWidget {
  const _MePage();
  @override
  Widget build(BuildContext context) {
    return ListView(padding: const EdgeInsets.all(14), children: const [
      AccountCard(canChangePassword: false),
    ]);
  }
}
