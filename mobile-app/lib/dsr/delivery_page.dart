import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/api.dart';
import '../core/format.dart';
import '../core/offline.dart';
import '../ui/common.dart';
import 'damage_page.dart';
import 'ready_sale_page.dart';
import 'stop_page.dart';

Map<String, dynamic> _m(Object? v) => Map<String, dynamic>.from((v ?? {}) as Map);

Color statusColor(String s) => switch (s) {
      'Delivered' => kOk,
      'Due' => kDanger,
      'Partial' => kWarn,
      'Cancelled' => kMuted,
      _ => kBlue,
    };

String statusBn(String s) => switch (s) {
      'Delivered' => 'ডেলিভারি হয়েছে',
      'Due' => 'বাকি',
      'Partial' => 'আংশিক',
      'Cancelled' => 'বাতিল',
      'Pending' => 'বাকি আছে',
      _ => s,
    };

class DeliveryPage extends StatefulWidget {
  const DeliveryPage({super.key});
  @override
  State<DeliveryPage> createState() => _DeliveryPageState();
}

class _DeliveryPageState extends State<DeliveryPage> {
  String? _date; // null = the open trip
  String _q = '';

  Set<String> get _pendingStops => OfflineQueue.instance.ops
      .where((o) => o.path.startsWith('/dsr/stops/'))
      .map((o) => o.path.split('/')[3])
      .toSet();

  @override
  Widget build(BuildContext context) {
    return Stack(children: [
      AsyncBody(
        key: ValueKey('$_date'),
        load: () => loadCached('dsr_delivery_${_date ?? 'open'}', () => ApiClient.get('/dsr/delivery', query: {'date': _date})),
        builder: (context, d, reload) {
          final trip = d['trip'] == null ? null : _m(d['trip']);
          final date = d['selectedDate'].toString();
          final stops = (d['orders'] as List).map(_m).toList();
          final vanStock = (d['vanStock'] as List).map(_m).toList();
          final damageProducts = (d['damageProducts'] as List).map(_m).toList();
          final reasons = (d['cancelReasons'] as List).map((e) => '$e').toList();
          final editable = trip != null && trip['editable'] == true;
          final q = _q.trim().toLowerCase();
          final shown = stops.where((s) => q.isEmpty || '${s['retailer_name']} ${s['phone']} ${s['address']}'.toLowerCase().contains(q)).toList()
            ..sort((a, b) {
              int rank(Map s) => s['status'] == 'Pending' ? 0 : 1;
              return rank(a).compareTo(rank(b));
            });

          return ListenableBuilder(
            listenable: OfflineQueue.instance,
            builder: (context, _) {
              final pend = _pendingStops;
              return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                DateBar(date: date, onChange: (v) => setState(() => _date = v)),
                const SizedBox(height: 10),
                if (trip == null)
                  const Padding(padding: EdgeInsets.all(40), child: Center(child: Text('এই দিনে কোনো ট্রিপ নেই।', style: TextStyle(color: kMuted)))),
                if (trip != null) ...[
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.route, color: kBlue),
                      title: Text('${trip['code']}', style: const TextStyle(fontWeight: FontWeight.w800)),
                      subtitle: Text('${bn(stops.where((s) => s['status'] != 'Pending').length)}/${bn(stops.length)} দোকান শেষ'),
                      trailing: Pill(editable ? 'চলছে' : (trip['status_key'] == 'settled' ? 'সেটেলড' : 'জমা হয়েছে'), color: editable ? kBlue : kOk),
                    ),
                  ),
                  if (editable)
                    Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: Row(children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ReadySalePage(vanStock: vanStock))).then((v) => v == true ? reload() : null),
                            icon: const Icon(Icons.flash_on), label: const Text('রেডি সেল')),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => DamagePage(products: damageProducts, stops: stops))).then((v) => v == true ? reload() : null),
                            icon: const Icon(Icons.broken_image_outlined), label: const Text('ড্যামেজ')),
                        ),
                      ]),
                    ),
                  const SizedBox(height: 10),
                  TextField(
                    onChanged: (v) => setState(() => _q = v),
                    decoration: const InputDecoration(hintText: 'দোকান খুঁজুন', prefixIcon: Icon(Icons.search), isDense: true),
                  ),
                  for (final s in shown)
                    Card(
                      margin: const EdgeInsets.only(top: 8),
                      child: ListTile(
                        title: Text('${s['retailer_name']}', style: const TextStyle(fontWeight: FontWeight.w700)),
                        subtitle: Text([
                          if ('${s['address']}'.isNotEmpty) '${s['address']}',
                          if (num0(s['existing_due']) > 0) 'পুরনো বাকি ${money(s['existing_due'])}',
                        ].join(' · '), maxLines: 2, overflow: TextOverflow.ellipsis),
                        trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
                          Pill(statusBn('${s['status']}'), color: statusColor('${s['status']}')),
                          if (pend.contains('${s['id']}')) const Padding(padding: EdgeInsets.only(top: 4), child: Text('সিঙ্ক বাকি', style: TextStyle(fontSize: 11, color: kWarn))),
                        ]),
                        onTap: () => Navigator.of(context)
                            .push<bool>(MaterialPageRoute(builder: (_) => StopPage(stop: s, reasons: reasons, editable: editable, damageProducts: damageProducts)))
                            .then((v) => v == true ? reload() : null),
                        onLongPress: () {
                          final lat = num0(s['lat']), lng = num0(s['lng']);
                          if (lat != 0) launchUrl(Uri.parse('google.navigation:q=$lat,$lng'), mode: LaunchMode.externalApplication);
                        },
                      ),
                    ),
                  const SizedBox(height: 8),
                  const Text('দোকানে চেপে ধরলে ম্যাপে রাস্তা দেখাবে।', textAlign: TextAlign.center, style: TextStyle(color: kMuted, fontSize: 12)),
                ],
              ]);
            },
          );
        },
      ),
    ]);
  }
}
