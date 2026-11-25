import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/api.dart';
import '../core/format.dart';
import '../core/offline.dart';
import '../core/tracker.dart';
import '../ui/common.dart';
import '../ui/tracker_banner.dart';
import 'add_retailer.dart';
import 'order_editor.dart';

/// SR home: pick a shop → take the order. Works offline from the last downloaded shop list + catalog.
class OrderPage extends StatefulWidget {
  const OrderPage({super.key});
  @override
  State<OrderPage> createState() => _OrderPageState();
}

class _OrderPageState extends State<OrderPage> {
  final _search = TextEditingController();
  double? _lat, _lng;
  String _q = '';
  final GlobalKey<AsyncBodyState> _body = GlobalKey();

  @override
  void initState() {
    super.initState();
    Tracker.currentOnce().then((p) {
      if (p != null && mounted) setState(() {
        _lat = p.latitude;
        _lng = p.longitude;
      });
    });
  }

  double? _dist(Map r) {
    if (_lat == null) return null;
    final lat = num0(r['lat']), lng = num0(r['lng']);
    if (lat == 0 && lng == 0) return null;
    const k = 0.017453292519943295;
    final a = 0.5 - cos((lat - _lat!) * k) / 2 + cos(_lat! * k) * cos(lat * k) * (1 - cos((lng - _lng!) * k)) / 2;
    return 12742 * asin(sqrt(a)); // km
  }

  String _distText(double km) => km < 1 ? '${bn((km * 1000).round())} মি' : '${bn(km.toStringAsFixed(1))} কিমি';

  List<Map<String, dynamic>> _visible(List retailers) {
    final q = _q.trim().toLowerCase();
    var rows = retailers.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    if (q.isNotEmpty) {
      rows = rows.where((r) => '${r['name']} ${r['phone']} ${r['address']}'.toLowerCase().contains(q)).toList();
    }
    if (_lat != null) {
      for (final r in rows) {
        r['_d'] = _dist(r);
      }
      rows.sort((a, b) => ((a['_d'] as double?) ?? 9e9).compareTo((b['_d'] as double?) ?? 9e9));
    }
    return rows.take(60).toList();
  }

  List<QueuedOp> get _pendingOrders =>
      OfflineQueue.instance.ops.where((o) => o.method == 'POST' && o.path == '/sr/orders').toList();

  Future<void> _complete(bool reopen) async {
    final ok = await confirm(context, reopen ? 'আজকের দিন আবার খুলবেন?' : 'আজকের অর্ডার সম্পন্ন করবেন?',
        body: reopen ? 'খুললে অর্ডার যোগ বা পরিবর্তন করতে পারবেন।' : 'সম্পন্ন করলে অর্ডারগুলো ডেলিভারি ট্রিপের জন্য প্রস্তুত হবে।', yes: reopen ? 'খুলুন' : 'সম্পন্ন করুন');
    if (!ok || !mounted) return;
    final r = await busy(context, () => OfflineQueue.write('POST', reopen ? '/sr/orders/reopen' : '/sr/orders/complete',
        body: {'at': DateTime.now().millisecondsSinceEpoch ~/ 1000}, label: reopen ? 'দিন আবার খোলা' : 'আজকের অর্ডার সম্পন্ন', queueable: !reopen));
    if (r != null && mounted) {
      toast(context, r.queued ? 'ইন্টারনেট এলে সম্পন্ন হবে।' : (r.data['message'] ?? 'হয়েছে।').toString());
      _body.currentState?.reload();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(children: [
      AsyncBody(
        key: _body,
        load: () => loadCached('sr_bootstrap', () => ApiClient.get('/sr/bootstrap')),
        builder: (context, data, reload) {
          final day = Map<String, dynamic>.from(data['day'] as Map);
          final orders = (day['orders'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
          final completed = day['completed'] == true;
          final totals = Map<String, dynamic>.from(day['totals'] as Map);
          final products = data['products'] as List;
          final retailers = data['retailers'] as List;
          final shown = _visible(retailers);

          return ListenableBuilder(
            listenable: OfflineQueue.instance,
            builder: (context, _) {
              final pend = _pendingOrders;
              return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const TrackerBanner(role: 'sr'),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Row(children: [
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(dateBn(day['date']?.toString()), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                        const SizedBox(height: 4),
                        Text('${bn(totals['orders'])}টি অর্ডার · ${money(totals['value'])}', style: const TextStyle(color: kMuted)),
                      ])),
                      Pill(completed ? 'সম্পন্ন' : 'চলছে', color: completed ? kOk : kWarn),
                    ]),
                  ),
                ),
                if (products.isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Text('আপনার কোম্পানির কোনো পণ্যের দাম এখনো নির্ধারিত নেই। পার্টনারের সাথে কথা বলুন।', style: TextStyle(color: kWarn)),
                  ),
                if (pend.isNotEmpty) ...[
                  const SectionTitle('সিঙ্ক বাকি অর্ডার'),
                  for (final o in pend)
                    Card(
                      color: const Color(0xFFFEF3C7),
                      child: ListTile(
                        leading: const Icon(Icons.schedule, color: kWarn),
                        title: Text(_retailerName(retailers, (o.body as Map)['retailer_id'])),
                        subtitle: Text('${bn(((o.body as Map)['items'] as List).length)}টি পণ্য · ইন্টারনেট এলে যাবে'),
                      ),
                    ),
                ],
                if (orders.isNotEmpty) ...[
                  const SectionTitle('আজকের অর্ডার'),
                  for (final o in orders)
                    Card(
                      child: ListTile(
                        title: Text(o['retailer'].toString(), style: const TextStyle(fontWeight: FontWeight.w700)),
                        subtitle: Text('${bn((o['items'] as List).length)}টি পণ্য · ${money(o['sr_total'])}'),
                        trailing: Pill(o['status'].toString(), color: o['editable'] == true ? kWarn : kOk),
                        onTap: () => _openEditor(retailers, products, o['retailer_id'], existing: o),
                      ),
                    ),
                ],
                const SectionTitle('দোকান বেছে অর্ডার নিন'),
                TextField(
                  controller: _search,
                  onChanged: (v) => setState(() => _q = v),
                  decoration: InputDecoration(
                    hintText: 'দোকানের নাম / ফোন / ঠিকানা', prefixIcon: const Icon(Icons.search),
                    suffixIcon: _q.isEmpty ? null : IconButton(icon: const Icon(Icons.clear), onPressed: () => setState(() { _search.clear(); _q = ''; })),
                  ),
                ),
                const SizedBox(height: 8),
                if (_lat == null) const Text('ফোনের লোকেশন চালু থাকলে কাছের দোকান আগে দেখাবে।', style: TextStyle(color: kMuted, fontSize: 12)),
                for (final r in shown)
                  Card(
                    margin: const EdgeInsets.only(top: 8),
                    child: ListTile(
                      title: Text(r['name'].toString(), style: const TextStyle(fontWeight: FontWeight.w700)),
                      subtitle: Text([
                        if ((r['address'] ?? '').toString().isNotEmpty) r['address'],
                        if (r['_d'] != null) _distText(r['_d'] as double),
                      ].join(' · '), maxLines: 1, overflow: TextOverflow.ellipsis),
                      trailing: num0(r['due']) > 0 ? Pill('বাকি ${money(r['due'])}', color: kDanger) : const Icon(Icons.chevron_right),
                      onTap: completed ? () => toast(context, 'আজকের দিন সম্পন্ন। নতুন অর্ডার নিতে দিনটি আবার খুলুন।', error: true) : () => _openEditor(retailers, products, r['id']),
                      onLongPress: () {
                        final lat = num0(r['lat']), lng = num0(r['lng']);
                        if (lat != 0) launchUrl(Uri.parse('geo:$lat,$lng?q=$lat,$lng'), mode: LaunchMode.externalApplication);
                      },
                    ),
                  ),
                const SizedBox(height: 18),
                if (orders.isNotEmpty || completed)
                  completed
                      ? OutlinedButton.icon(onPressed: () => _complete(true), icon: const Icon(Icons.lock_open), label: const Text('দিন আবার খুলুন'))
                      : FilledButton.icon(onPressed: () => _complete(false), icon: const Icon(Icons.check_circle_outline), label: const Text('আজকের অর্ডার সম্পন্ন করুন')),
                const SizedBox(height: 80),
              ]);
            },
          );
        },
      ),
      Positioned(
        right: 16, bottom: 16,
        child: FloatingActionButton.extended(
          onPressed: () async {
            final added = await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => const AddRetailerPage()));
            if (added == true) _body.currentState?.reload();
          },
          icon: const Icon(Icons.add_business), label: const Text('নতুন দোকান'),
        ),
      ),
    ]);
  }

  String _retailerName(List retailers, Object? id) {
    for (final r in retailers) {
      if ('${(r as Map)['id']}' == '$id') return r['name'].toString();
    }
    return 'দোকান #$id';
  }

  Future<void> _openEditor(List retailers, List products, Object? retailerId, {Map<String, dynamic>? existing}) async {
    Map<String, dynamic>? shop;
    for (final r in retailers) {
      if ('${(r as Map)['id']}' == '$retailerId') shop = Map<String, dynamic>.from(r);
    }
    shop ??= {'id': retailerId, 'name': existing?['retailer'] ?? 'দোকান', 'address': existing?['retailer_address'] ?? ''};
    final saved = await Navigator.of(context).push<bool>(MaterialPageRoute(
      builder: (_) => OrderEditorPage(shop: shop!, products: products.map((e) => Map<String, dynamic>.from(e as Map)).toList(), existing: existing),
    ));
    if (saved == true) _body.currentState?.reload();
  }
}
