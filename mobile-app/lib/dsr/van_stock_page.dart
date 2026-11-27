import 'package:flutter/material.dart';

import '../core/api.dart';
import '../core/format.dart';
import '../ui/common.dart';
import '../ui/hkit.dart';
import '../ui/pwa_kit.dart';
import 'ready_sale_page.dart';

Map<String, dynamic> _m(Object? v) => Map<String, dynamic>.from((v ?? {}) as Map);

/// DM5 — ভ্যানের মাল: load = sold + still on the van, per-product table, রেডি সেল.
class VanStockPage extends StatefulWidget {
  const VanStockPage({super.key});
  @override
  State<VanStockPage> createState() => _VanStockPageState();
}

class _VanStockPageState extends State<VanStockPage> {
  String? _date;
  String _q = '';

  @override
  Widget build(BuildContext context) {
    return AsyncBody(
      key: ValueKey(_date),
      sky: true,
      load: () => loadCached('dsr_van_${_date ?? 'open'}', () => ApiClient.get('/dsr/van-stock', query: {'date': _date})),
      builder: (context, d, reload) {
        final all = ((d['products'] as List?) ?? const []).map(_m).toList();
        final trip = d['trip'] == null ? null : _m(d['trip']);
        final editable = trip != null && trip['editable'] == true;
        final q = _q.trim().toLowerCase();
        final list = all.where((p) => q.isEmpty || '${p['name']} ${p['company']}'.toLowerCase().contains(q)).toList();
        var load = 0, sold = 0, ready = 0, left = 0;
        double oc = 0;
        for (final p in all) {
          final a = int0(p['dispatched_pcs']), b = int0(p['delivered_pcs']);
          load += a;
          sold += b;
          ready += int0(p['ready_sold_pcs']);
          left += (a - b) < 0 ? 0 : a - b;
          oc += num0(p['delivery_oc']);
        }
        final date = d['selectedDate'].toString();
        final balanced = load == sold + left;
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          SkyBox(
            height: 196,
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              SkyHead(
                kicker: 'লোড = বিক্রি + এখনো ভ্যানে',
                title: 'ভ্যানের মাল',
                trailing: GlassBtn(
                  icon: Ic.plus, label: 'রেডি সেল',
                  onTap: editable
                      ? () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ReadySalePage(vanStock: all))).then((v) => v == true ? reload() : null)
                      : () => toast(context, 'খোলা ট্রিপ ছাড়া রেডি সেল করা যাবে না।', error: true),
                ),
              ),
              const SizedBox(height: 14),
              SkyDateBar(date: date, onChange: (v) => setState(() => _date = v == todayYmd() ? null : v), sub: trip == null ? 'ট্রিপ নেই' : 'ট্রিপ ${bn('${trip['code']}')}'),
            ]),
          ),
          gap12,
          HCard(
            lift: true, radius: 24, padding: const EdgeInsets.fromLTRB(8, 14, 8, 12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              HStrip(style: StripStyle.plain, valueSize: 22, [
                HStat('সকালে লোড', bn(load)),
                HStat('বিক্রি', bn(sold), color: HC.blue),
                HStat('রেডি সেল', bn(ready)),
                HStat('বাকি', bn(left)),
              ]),
              const SizedBox(height: 12),
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 8),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                decoration: BoxDecoration(color: balanced ? HC.soft : HC.redSoft, borderRadius: BorderRadius.circular(14)),
                child: Text(
                  balanced ? 'হিসাব মিলছে · ${bn(load)} = ${bn(sold)} + ${bn(left)}' : 'হিসাব মিলছে না · ${bn(load)} ≠ ${bn(sold)} + ${bn(left)}',
                  textAlign: TextAlign.center, style: hs(12.5, w: w7, color: balanced ? HC.blue : HC.red, num: true),
                ),
              ),
            ]),
          ),
          if (trip == null) ...[gap12, const HEmpty('কোনো ডিসপ্যাচ করা ট্রিপ নেই', body: 'অন্য তারিখ বাছুন।')],
          if (all.isNotEmpty) ...[
            gap16,
            Row(children: [
              Expanded(child: HSec('পণ্য (পিস)', trailing: 'ডেলিভারি O/C ${sMoney(oc)}')),
            ]),
            gap8,
            Container(
              height: 46, padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: HC.line)),
              child: Row(children: [
                const Svg('<circle cx="11" cy="11" r="7"/><path d="m20 20-3.5-3.5"/>', size: 17, color: HC.muted),
                const SizedBox(width: 10),
                Expanded(child: TextField(
                  onChanged: (v) => setState(() => _q = v), style: hs(14),
                  decoration: InputDecoration(hintText: 'পণ্য বা কোম্পানি খুঁজুন…', hintStyle: hs(14, color: HC.faint), border: InputBorder.none, enabledBorder: InputBorder.none, focusedBorder: InputBorder.none, isDense: true, filled: false, contentPadding: EdgeInsets.zero),
                )),
              ]),
            ),
            gap8,
            HCard(
              radius: 22, padding: const EdgeInsets.fromLTRB(14, 10, 14, 6),
              child: Column(children: [
                Row(children: [
                  Expanded(flex: 5, child: Text('পণ্য', style: hs(11.5, w: w6, color: HC.muted))),
                  for (final h in ['লোড', 'বিক্রি', 'বাকি']) Expanded(flex: 2, child: Text(h, textAlign: TextAlign.right, style: hs(11.5, w: w6, color: HC.muted))),
                ]),
                for (final p in list) _row(p),
              ]),
            ),
          ],
        ]);
      },
    );
  }

  Widget _row(Map<String, dynamic> p) {
    final qpu = int0(p['qty_per_unit']) < 1 ? 1 : int0(p['qty_per_unit']);
    final unit = '${p['unit_type'] ?? 'Unit'}';
    final a = int0(p['dispatched_pcs']), b = int0(p['delivered_pcs']);
    final left = (a - b) < 0 ? 0 : a - b;
    Widget n(int v, {Color color = HC.ink}) => Expanded(flex: 2, child: Text(bn(v), textAlign: TextAlign.right, style: hs(14, w: w7, color: color, num: true)));
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: const BoxDecoration(border: Border(top: BorderSide(color: HC.line))),
      child: Row(children: [
        Expanded(flex: 5, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${p['name']}', maxLines: 2, overflow: TextOverflow.ellipsis, style: hs(13.5, w: w6)),
          Text('${p['company']} · বাকি ${unitPcsBn(left, qpu, unit)}', maxLines: 1, overflow: TextOverflow.ellipsis, style: hs(11, color: HC.muted, num: true)),
        ])),
        n(a),
        n(b, color: HC.blue),
        n(left, color: left > 0 ? HC.ink : HC.muted),
      ]),
    );
  }
}
