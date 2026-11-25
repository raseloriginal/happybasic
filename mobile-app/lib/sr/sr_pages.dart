import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/api.dart';
import '../core/format.dart';
import '../core/session.dart';
import '../ui/account.dart';
import '../ui/common.dart';

Map<String, dynamic> _m(Object? v) => Map<String, dynamic>.from((v ?? {}) as Map);

class _StatGrid extends StatelessWidget {
  const _StatGrid(this.s);
  final Map<String, dynamic> s;
  @override
  Widget build(BuildContext context) {
    final tiles = [
      StatTile('অর্ডার', bn(s['orders']), icon: Icons.receipt_long),
      StatTile('দোকান', bn(s['retailers']), icon: Icons.storefront),
      StatTile('অর্ডারের মূল্য', money(s['value']), color: kBlue),
      StatTile('ডেলিভারি হয়েছে', money(s['delivered']), color: kOk),
      StatTile('O/C', money(s['oc']), color: num0(s['oc']) < 0 ? kDanger : kOk),
      StatTile('ডেলিভারি O/C', money(s['delivery_oc']), color: num0(s['delivery_oc']) < 0 ? kDanger : kOk),
    ];
    return GridView.count(
      crossAxisCount: 2, shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), mainAxisSpacing: 10, crossAxisSpacing: 10, childAspectRatio: 1.9,
      children: tiles,
    );
  }
}

class SrDashboardPage extends StatelessWidget {
  const SrDashboardPage({super.key});
  @override
  Widget build(BuildContext context) {
    return AsyncBody(
      load: () => loadCached('sr_dashboard', () => ApiClient.get('/sr/dashboard')),
      builder: (context, d, reload) {
        final profile = _m(d['profile']);
        final today = _m(d['today']);
        final month = _m(d['month']);
        final dailyTarget = num0(profile['daily_target']);
        final monthlyTarget = num0(profile['monthly_target']);
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${profile['name']}', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
          Text('${profile['company']} · ${profile['area'] ?? ''}', style: const TextStyle(color: kMuted)),
          const SizedBox(height: 10),
          Row(children: [
            Pill(d['day_completed'] == true ? 'আজকের দিন সম্পন্ন' : 'আজকের দিন চলছে', color: d['day_completed'] == true ? kOk : kWarn),
            const SizedBox(width: 8),
            Pill('O/C ব্যালেন্স ${money(profile['oc_balance'])}', color: num0(profile['oc_balance']) < 0 ? kDanger : kBlue),
          ]),
          SectionTitle('আজ · ${dateBn(d['date']?.toString())}'),
          if (dailyTarget > 0) _Progress('দৈনিক টার্গেট', num0(today['value']), dailyTarget),
          _StatGrid(today),
          SectionTitle('এই মাস'),
          if (monthlyTarget > 0) _Progress('মাসিক টার্গেট', num0(month['value']), monthlyTarget),
          _StatGrid(month),
          const SizedBox(height: 10),
          Card(child: ListTile(title: const Text('ডেলিভারির হার'), trailing: Text('${bn(month['delivery_rate'])}%', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)))),
        ]);
      },
    );
  }
}

class _Progress extends StatelessWidget {
  const _Progress(this.label, this.value, this.target);
  final String label;
  final double value, target;
  @override
  Widget build(BuildContext context) {
    final p = (value / target).clamp(0.0, 1.0);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text(label, style: const TextStyle(fontWeight: FontWeight.w700))),
            Text('${money(value)} / ${money(target)}', style: const TextStyle(color: kMuted, fontSize: 12.5)),
          ]),
          const SizedBox(height: 8),
          ClipRRect(borderRadius: BorderRadius.circular(8), child: LinearProgressIndicator(value: p, minHeight: 10, color: p >= 1 ? kOk : kBlue, backgroundColor: kBorder)),
        ]),
      ),
    );
  }
}

class SrHistoryPage extends StatefulWidget {
  const SrHistoryPage({super.key});
  @override
  State<SrHistoryPage> createState() => _SrHistoryPageState();
}

class _SrHistoryPageState extends State<SrHistoryPage> {
  String? _date;

  @override
  Widget build(BuildContext context) {
    return AsyncBody(
      key: ValueKey(_date),
      load: () => loadCached('sr_history_${_date ?? 'last'}', () => ApiClient.get('/sr/history', query: {'date': _date})),
      builder: (context, d, reload) {
        final date = d['date'].toString();
        final orders = (d['orders'] as List).map(_m).toList();
        final total = orders.fold<double>(0, (a, o) => a + num0(o['sr_total']));
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          DateBar(date: date, onChange: (v) => setState(() => _date = v)),
          const SizedBox(height: 10),
          if (orders.isEmpty) const Padding(padding: EdgeInsets.all(40), child: Center(child: Text('এই দিনে কোনো অর্ডার নেই।', style: TextStyle(color: kMuted)))),
          if (orders.isNotEmpty) Text('${bn(orders.length)}টি অর্ডার · ${money(total)}', style: const TextStyle(fontWeight: FontWeight.w800)),
          for (final o in orders)
            Card(
              margin: const EdgeInsets.only(top: 8),
              child: ExpansionTile(
                shape: const Border(), collapsedShape: const Border(),
                title: Text(o['retailer'].toString(), style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text('${o['code']} · ${money(o['sr_total'])}'),
                trailing: Pill(o['status'].toString(), color: switch (o['status_key']) { 'delivered' => kOk, 'cancelled' => kDanger, _ => kWarn }),
                children: [
                  for (final it in (o['items'] as List).map(_m))
                    ListTile(
                      dense: true,
                      title: Text(it['name'].toString()),
                      subtitle: Text('${bn(it['pcs'])} পিস${num0(it['delivered_pcs']) > 0 ? ' · পৌঁছেছে ${bn(it['delivered_pcs'])}' : ''}'),
                      trailing: Text(money(it['total']), style: const TextStyle(fontWeight: FontWeight.w700)),
                    ),
                  if (o['dsr'] != null) ListTile(dense: true, leading: const Icon(Icons.local_shipping_outlined, size: 18), title: Text('DSR: ${o['dsr']}')),
                  if (o['cancel_reason'] != null) ListTile(dense: true, title: Text('বাতিলের কারণ: ${o['cancel_reason']}', style: const TextStyle(color: kDanger))),
                ],
              ),
            ),
        ]);
      },
    );
  }
}

class SrProfilePage extends StatefulWidget {
  const SrProfilePage({super.key});
  @override
  State<SrProfilePage> createState() => _SrProfilePageState();
}

class _SrProfilePageState extends State<SrProfilePage> {
  String? _date;

  @override
  Widget build(BuildContext context) {
    context.watch<AuthState>();
    return AsyncBody(
      key: ValueKey(_date),
      load: () => loadCached('sr_profile_${_date ?? 'last'}', () => ApiClient.get('/sr/profile', query: {'date': _date})),
      builder: (context, d, reload) {
        final p = _m(d['profile']);
        final photo = ApiClient.asset(p['photo']);
        final day = _m(d['day_summary']);
        final products = (day['products'] as List?)?.map(_m).toList() ?? [];
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(children: [
                CircleAvatar(radius: 34, backgroundImage: photo == null ? null : CachedNetworkImageProvider(photo), child: photo == null ? Text('${p['initials']}', style: const TextStyle(fontSize: 22)) : null),
                const SizedBox(width: 14),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${p['name']}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                  Text('${p['code']} · ${p['phone']}', style: const TextStyle(color: kMuted)),
                  Text('${p['company']} · ${p['partner']}', style: const TextStyle(color: kMuted, fontSize: 12.5)),
                ])),
              ]),
            ),
          ),
          SectionTitle('${d['month_label']} মাসের পারফরম্যান্স'),
          _StatGrid(_m(d['month'])),
          const SectionTitle('দিনের হিসাব'),
          DateBar(date: d['date'].toString(), onChange: (v) => setState(() => _date = v)),
          const SizedBox(height: 10),
          _StatGrid(_m(day['stats'])),
          for (final pr in products)
            Card(
              margin: const EdgeInsets.only(top: 8),
              child: ListTile(
                title: Text(pr['name'].toString()),
                subtitle: Text('অর্ডার ${bn(pr['ordered_pcs'])} · ডেলিভারি ${bn(pr['delivered_pcs'])} · ফেরত ${bn(pr['returned_pcs'])} পিস'),
              ),
            ),
          const SectionTitle('অ্যাকাউন্ট'),
          AccountCard(canChangePhoto: true, onPhotoChanged: reload),
        ]);
      },
    );
  }
}
