import 'package:flutter/material.dart';

import '../core/api.dart';
import '../core/format.dart';
import '../ui/common.dart';
import '../ui/dkit.dart';
import '../ui/pwa_kit.dart';

Map<String, dynamic> _m(Object? v) => Map<String, dynamic>.from((v ?? {}) as Map);

/// /dsr/van-stock — date nav, 4 KPI tiles, search, one card list with লোডকৃত / ডেলিভারি / অবশিষ্ট.
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
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 20),
      load: () => loadCached('dsr_van_${_date ?? 'open'}', () => ApiClient.get('/dsr/van-stock', query: {'date': _date})),
      builder: (context, d, reload) {
        final all = (d['products'] as List).map(_m).toList();
        final trip = d['trip'] == null ? null : _m(d['trip']);
        final q = _q.trim().toLowerCase();
        final list = all.where((p) => q.isEmpty || '${p['name']} ${p['company']}'.toLowerCase().contains(q)).toList();
        var disp = 0, deliv = 0, avail = 0;
        double oc = 0;
        for (final p in all) {
          final a = int0(p['dispatched_pcs']), b = int0(p['delivered_pcs']);
          disp += a;
          deliv += b;
          avail += (a - b) < 0 ? 0 : a - b;
          oc += num0(p['delivery_oc']);
        }
        final date = d['selectedDate'].toString();
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          DDateNav(date: date, onChange: (v) => setState(() => _date = v == todayYmd() ? null : v)),
          const SizedBox(height: 14),
          if (trip == null) ...[
            DCard(padding: const EdgeInsets.fromLTRB(18, 22, 18, 22), child: Center(child: Text('কোনো ডিসপ্যাচ করা ট্রিপ নেই', style: ts(15, w: FontWeight.w600)))),
            const SizedBox(height: 14),
          ],
          IntrinsicHeight(child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Expanded(child: _Kpi('মোট লোড', '${bn(disp)} পিস')),
            const SizedBox(width: 10),
            Expanded(child: _Kpi('মোট ডেলিভারি', '${bn(deliv)} পিস', color: DC.okText)),
          ])),
          const SizedBox(height: 10),
          IntrinsicHeight(child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Expanded(child: _Kpi('ভ্যানে বাকি', '${bn(avail)} পিস')),
            const SizedBox(width: 10),
            Expanded(child: _Kpi('ডেলিভারি O/C', signedMoney(oc.round(), smart: true), color: oc >= 0 ? DC.okText : DC.warnText)),
          ])),
          const SizedBox(height: 14),
          DCard(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(children: [
              Expanded(
                child: Container(
                  height: 36, padding: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: BoxDecoration(color: DC.subtle, borderRadius: BorderRadius.circular(8), border: Border.all(color: DC.borderStrong)),
                  child: Row(children: [
                    const Svg('<circle cx="11" cy="11" r="8"/><path d="m21 21-4.3-4.3"/>', size: 15, color: DC.muted),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        onChanged: (v) => setState(() => _q = v), style: ts(13.5),
                        decoration: InputDecoration(hintText: 'পণ্য বা কোম্পানি খুঁজুন…', hintStyle: ts(13.5, color: DC.muted), border: InputBorder.none, enabledBorder: InputBorder.none, focusedBorder: InputBorder.none, isDense: true, filled: false, contentPadding: EdgeInsets.zero),
                      ),
                    ),
                  ]),
                ),
              ),
              const SizedBox(width: 8),
              Text('${bn(list.length)}টি পণ্য${trip != null ? ' · ${bn('${trip['code']}')}' : ''}', style: ts(12, color: DC.muted, tabular: true)),
            ]),
          ),
          const SizedBox(height: 14),
          DCard(
            padding: EdgeInsets.zero,
            child: Column(children: [for (var i = 0; i < list.length; i++) _Card(list[i], last: i == list.length - 1)]),
          ),
        ]);
      },
    );
  }
}

class _Kpi extends StatelessWidget {
  const _Kpi(this.label, this.value, {this.color = DC.ink});
  final String label, value;
  final Color color;
  @override
  Widget build(BuildContext context) => DCard(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: ts(11.5, w: FontWeight.w600, color: DC.muted)),
          const SizedBox(height: 4),
          Text(value, style: ts(17.5, w: FontWeight.w700, color: color, ls: -0.17, tabular: true)),
        ]),
      );
}

class _Card extends StatelessWidget {
  const _Card(this.p, {required this.last});
  final Map<String, dynamic> p;
  final bool last;
  @override
  Widget build(BuildContext context) {
    final qpu = int0(p['qty_per_unit']) < 1 ? 1 : int0(p['qty_per_unit']);
    final unit = '${p['unit_type'] ?? 'Unit'}';
    final disp = int0(p['dispatched_pcs']), deliv = int0(p['delivered_pcs']);
    final avail = (disp - deliv) < 0 ? 0 : disp - deliv;
    final oc = num0(p['delivery_oc']);
    Widget cell(String label, int pcs, {Color color = DC.ink}) => Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: ts(12, color: DC.muted)),
            Text('${bn(pcs)} পিস', style: ts(12.5, w: FontWeight.w700, color: color, tabular: true)),
            Text(unitPcsBn(pcs, qpu, unit), style: ts(10.5, color: DC.muted, tabular: true)),
          ]),
        );
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(border: last ? null : const Border(bottom: BorderSide(color: DC.border))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${p['name']}', style: ts(14, w: FontWeight.w700)),
              Text('${p['company']} · ১ ${unitBn(unit)} = ${bn(qpu)} পিস', style: ts(12, color: DC.muted, tabular: true)),
            ]),
          ),
          const SizedBox(width: 8),
          DBadge('O/C ${signedMoney(oc.round(), smart: true)}', tone: oc > 0 ? DTone.success : (oc < 0 ? DTone.warning : DTone.neutral)),
        ]),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(color: DC.subtle, borderRadius: BorderRadius.circular(8), border: Border.all(color: DC.border)),
          child: Row(children: [cell('লোডকৃত', disp), cell('ডেলিভারি', deliv, color: DC.okText), cell('অবশিষ্ট', avail)]),
        ),
      ]),
    );
  }
}
