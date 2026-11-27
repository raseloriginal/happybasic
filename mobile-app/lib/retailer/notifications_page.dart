import 'dart:async';

import 'package:flutter/material.dart';

import '../core/api.dart';
import '../core/format.dart';
import '../ui/common.dart';
import '../ui/hkit.dart';
import '../ui/pwa_kit.dart';
import 'invoice_page.dart';
import 'retailer_home.dart' show icTruck;

Map<String, dynamic> _m(Object? v) => Map<String, dynamic>.from((v ?? {}) as Map);

/// R4 · নোটিফিকেশন: SR orders / delivery-man news, unread dots, seen 1.5s after opening.
class NotificationsPage extends StatefulWidget {
  const NotificationsPage({super.key});
  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage> {
  Timer? _seen;
  int? _tab;

  @override
  void initState() {
    super.initState();
    _seen = Timer(const Duration(milliseconds: 1500), () => ApiClient.send('POST', '/retailer/notifications/seen').catchError((_) => <String, dynamic>{}));
  }

  @override
  void dispose() {
    _seen?.cancel();
    super.dispose();
  }

  Future<void> _open(Map<String, dynamic> e) async {
    final date = '${e['date'] ?? ''}';
    if (date.isEmpty) return;
    final res = await busy(context, () => ApiClient.get('/retailer/day', query: {'date': date}));
    if (res == null || !mounted) return;
    final orders = (res['orders'] as List).map(_m).toList();
    final sel = e['order_id'] != null ? int0(e['order_id']) : (orders.isEmpty ? 0 : int0(orders.first['id']));
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => InvoicePage(
        mode: e['kind'] == 'arrived' ? InvoiceMode.delivery : InvoiceMode.order, date: date, orders: orders, selectedId: sel)));
  }

  @override
  Widget build(BuildContext context) {
    return SkyStatusBar(
      child: Scaffold(
        backgroundColor: HC.bg,
        body: Frame(
          color: HC.outer,
          child: ColoredBox(
            color: HC.bg,
            child: AsyncBody(
              sky: true,
              load: () => loadCached('ret_notif', () => ApiClient.get('/retailer/notifications')),
              builder: (context, d, reload) {
                final events = (d['events'] as List).map(_m).toList();
                final orders = events.where((e) => e['kind'] == 'order').toList();
                final dms = events.where((e) => e['kind'] != 'order').toList();
                final unread = int0(d['unread']);
                final tab = _tab ?? (orders.isEmpty && dms.isNotEmpty ? 1 : 0);
                final list = tab == 0 ? orders : dms;
                String when(Map<String, dynamic> e) => e['group'] == 'আজ' ? '${e['when']}' : '${e['group']} · ${e['when']}';
                return SkyBox(
                  height: 230,
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    SkyHead(leading: const SkyBack(), kicker: unread > 0 ? '${bn(unread)}টি নতুন' : 'সব দেখা হয়েছে', title: 'নোটিফিকেশন'),
                    gap12,
                    HSeg(
                      items: const ['SR অর্ডার', 'ডেলিভারি ম্যান'], index: tab, onTap: (i) => setState(() => _tab = i),
                      badges: [orders.where((e) => e['unread'] == true).length, dms.where((e) => e['unread'] == true).length],
                    ),
                    gap12,
                    HCard(
                      lift: true, padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                      child: list.isEmpty
                          ? Padding(padding: const EdgeInsets.symmetric(vertical: 18),
                              child: Text(tab == 0 ? 'এখনো কোনো অর্ডার নেই' : 'এখনো কোনো ডেলিভারির খবর নেই', textAlign: TextAlign.center, style: hs(13, color: HC.muted)))
                          : Column(children: [
                              for (var i = 0; i < list.length; i++)
                                Container(
                                  decoration: BoxDecoration(border: i == 0 ? null : const Border(top: BorderSide(color: HC.line))),
                                  child: _Row(e: list[i], when: when(list[i]), onTap: () => _open(list[i])),
                                ),
                            ]),
                    ),
                    gap12,
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(borderRadius: BorderRadius.circular(18), border: Border.all(color: const Color(0xFFC9D4EA), width: 1.5)),
                      child: Row(children: [
                        Text('%', style: hs(16, w: w7, color: HC.blue)),
                        const SizedBox(width: 10),
                        Expanded(child: Text('কোম্পানির অফার শীঘ্রই এখানে আসবে', style: hs(13, color: HC.muted))),
                      ]),
                    ),
                  ]),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.e, required this.when, required this.onTap});
  final Map<String, dynamic> e;
  final String when;
  final VoidCallback onTap;
  static const _tints = [Color(0xFF5B4FE0), Color(0xFF1F4FE0), Color(0xFF1E8FE0), Color(0xFF475273)];

  @override
  Widget build(BuildContext context) {
    final unread = e['unread'] == true;
    final kind = '${e['kind']}';
    Widget lead;
    if (kind == 'order') {
      final tint = _tints['${e['company']}'.codeUnits.fold<int>(0, (a, c) => a + c) % _tints.length];
      lead = LetterAvatar('${e['initial'] ?? ''}', size: 44, bg: Colors.white, fg: tint, border: tint, fontSize: 17);
    } else {
      final done = kind == 'arrived';
      lead = Container(
        width: 44, height: 44,
        decoration: BoxDecoration(color: done ? HC.blue : (unread ? HC.soft : HC.bg), borderRadius: BorderRadius.circular(14)),
        alignment: Alignment.center,
        child: done ? const Svg('<path d="M5 12l5 5 9-10"/>', size: 20, color: Colors.white, stroke: 2.6) : Svg(icTruck, size: 20, color: unread ? HC.blue : HC.muted),
      );
    }
    final title = kind == 'order' ? '${e['title']}' : '${e['short'] ?? e['title']}';
    final sub = kind == 'order' ? '${e['sub'] ?? ''}' : '${e['detail'] ?? ''}';
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(children: [
          lead,
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: hs(14, w: unread ? w7 : w6)),
            if (sub.isNotEmpty) Text(sub, maxLines: 2, overflow: TextOverflow.ellipsis, style: hs(12, color: HC.muted, num: true)),
          ])),
          const SizedBox(width: 8),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(when, style: hs(11, color: HC.muted)),
            if (unread) ...[const SizedBox(height: 4), Container(width: 8, height: 8, decoration: const BoxDecoration(color: HC.blue, shape: BoxShape.circle))],
          ]),
        ]),
      ),
    );
  }
}
