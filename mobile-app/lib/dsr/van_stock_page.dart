import 'package:flutter/material.dart';

import '../core/api.dart';
import '../core/format.dart';
import '../ui/common.dart';

Map<String, dynamic> _m(Object? v) => Map<String, dynamic>.from((v ?? {}) as Map);

class VanStockPage extends StatefulWidget {
  const VanStockPage({super.key});
  @override
  State<VanStockPage> createState() => _VanStockPageState();
}

class _VanStockPageState extends State<VanStockPage> {
  String? _date;

  @override
  Widget build(BuildContext context) {
    return AsyncBody(
      key: ValueKey(_date),
      load: () => loadCached('dsr_van_${_date ?? 'open'}', () => ApiClient.get('/dsr/van-stock', query: {'date': _date})),
      builder: (context, d, reload) {
        final products = (d['products'] as List).map(_m).toList();
        final totalAvail = products.fold<int>(0, (a, p) => a + int0(p['available_pcs']));
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          DateBar(date: d['selectedDate'].toString(), onChange: (v) => setState(() => _date = v)),
          const SizedBox(height: 10),
          if (d['trip'] == null) const Padding(padding: EdgeInsets.all(40), child: Center(child: Text('এই দিনে কোনো ট্রিপ নেই।', style: TextStyle(color: kMuted)))),
          if (products.isNotEmpty) Text('ভ্যানে এখন ${bn(totalAvail)} পিস', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
          for (final p in products)
            Card(
              margin: const EdgeInsets.only(top: 8),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Expanded(child: Text('${p['name']}', style: const TextStyle(fontWeight: FontWeight.w800))),
                    Pill('${bn(p['available_pcs'])} পিস আছে', color: int0(p['available_pcs']) > 0 ? kOk : kMuted),
                  ]),
                  Text('${p['company']} · ${money(p['base_rate'])}/পিস', style: const TextStyle(color: kMuted, fontSize: 12.5)),
                  const SizedBox(height: 10),
                  Row(children: [
                    _cell('লোড', p['dispatched_pcs']),
                    _cell('অর্ডার', p['ordered_pcs']),
                    _cell('ডেলিভারি', p['delivered_pcs']),
                    _cell('রেডি সেল', p['ready_sold_pcs']),
                  ]),
                ]),
              ),
            ),
        ]);
      },
    );
  }

  Widget _cell(String label, Object? v) => Expanded(
        child: Column(children: [
          Text(bn(v), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
          Text(label, style: const TextStyle(color: kMuted, fontSize: 11.5)),
        ]),
      );
}
