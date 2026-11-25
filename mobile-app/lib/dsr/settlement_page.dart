import 'package:flutter/material.dart';

import '../core/api.dart';
import '../core/format.dart';
import '../ui/common.dart';

Map<String, dynamic> _m(Object? v) => Map<String, dynamic>.from((v ?? {}) as Map);

/// End-of-day: the DSR counts the cash by note, the partner approves (or sends it back).
class SettlementPage extends StatefulWidget {
  const SettlementPage({super.key});
  @override
  State<SettlementPage> createState() => _SettlementPageState();
}

class _SettlementPageState extends State<SettlementPage> {
  String? _date;
  final Map<int, TextEditingController> _notes = {};
  final _note = TextEditingController();
  final _key = GlobalKey<AsyncBodyState>();

  TextEditingController _c(int v, int initial) => _notes.putIfAbsent(v, () => TextEditingController(text: initial == 0 ? '' : '$initial'));

  int _counted(List<Map<String, dynamic>> notes) => notes.fold(0, (a, n) => a + int0(n['value']) * (int.tryParse(_notes[int0(n['value'])]?.text ?? '') ?? int0(n['qty'])));

  Future<void> _submit(List<Map<String, dynamic>> notes, double net) async {
    final counted = _counted(notes);
    final diff = counted - net;
    final ok = await confirm(
      context, 'সেটেলমেন্ট জমা দেবেন?',
      body: 'জমা দেওয়ার কথা ${money(net)}\nগুনে পেয়েছেন ${money(counted)}\n${diff == 0 ? 'হিসাব মিলেছে ✓' : diff < 0 ? '${money(-diff)} কম' : '${money(diff)} বেশি'}',
      yes: 'জমা দিন');
    if (!ok || !mounted) return;
    final body = {
      'notes': {for (final n in notes) '${int0(n['value'])}': int.tryParse(_notes[int0(n['value'])]?.text ?? '') ?? int0(n['qty'])},
      'note': _note.text.trim(),
    };
    final r = await busy(context, () => ApiClient.send('POST', '/dsr/settlement', body: body, opId: ApiClient.newOpId()));
    if (r != null && mounted) {
      toast(context, (r['message'] ?? 'সেটেলমেন্ট জমা হয়েছে।').toString());
      _key.currentState?.reload();
    }
  }

  @override
  Widget build(BuildContext context) {
    return AsyncBody(
      key: _key,
      load: () => loadCached('dsr_settlement_${_date ?? 'open'}', () => ApiClient.get('/dsr/settlement', query: {'date': _date})),
      builder: (context, d, reload) {
        final trip = d['trip'] == null ? null : _m(d['trip']);
        final s = d['settlement'] == null ? null : _m(d['settlement']);
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          DateBar(date: d['selectedDate'].toString(), onChange: (v) => setState(() => _date = v)),
          const SizedBox(height: 10),
          if (trip == null || s == null)
            const Padding(padding: EdgeInsets.all(40), child: Center(child: Text('এই দিনে কোনো ট্রিপ নেই।', style: TextStyle(color: kMuted))))
          else ..._body(trip, s),
        ]);
      },
    );
  }

  List<Widget> _body(Map<String, dynamic> trip, Map<String, dynamic> s) {
    final sum = _m(s['summary']);
    final counts = _m(s['counts']);
    final notes = (s['notes'] as List).map(_m).toList();
    final cash = s['cash'] == null ? null : _m(s['cash']);
    final status = '${trip['settlement_status'] ?? ''}';
    final editable = trip['editable'] == true;
    final pending = int0(counts['pending']);
    final net = num0(sum['net_pay']);
    final returns = (s['return_items'] as List?)?.map(_m).toList() ?? [];
    final dues = (s['due_details'] as List?)?.map(_m).toList() ?? [];

    Widget row(String k, String v, {bool bold = false, Color? color}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(children: [
            Expanded(child: Text(k, style: TextStyle(fontWeight: bold ? FontWeight.w800 : FontWeight.w500))),
            Text(v, style: TextStyle(fontWeight: bold ? FontWeight.w800 : FontWeight.w600, fontSize: bold ? 17 : 14, color: color)),
          ]),
        );

    return [
      Row(children: [
        Expanded(child: Text('${trip['code']}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16))),
        Pill(switch (trip['status_key']) { 'settled' => 'সেটেলড', 'in_review' => 'যাচাইয়ে আছে', _ => 'চলছে' }, color: trip['status_key'] == 'settled' ? kOk : kBlue),
      ]),
      if (status == 'returned' && trip['review_note'] != null)
        Container(
          margin: const EdgeInsets.only(top: 10), padding: const EdgeInsets.all(12), width: double.infinity,
          decoration: BoxDecoration(color: const Color(0xFFFEF2F2), borderRadius: BorderRadius.circular(12)),
          child: Text('পার্টনার ফেরত পাঠিয়েছেন: ${trip['review_note']}', style: const TextStyle(color: kDanger)),
        ),
      if (pending > 0 && editable)
        Container(
          margin: const EdgeInsets.only(top: 10), padding: const EdgeInsets.all(12), width: double.infinity,
          decoration: BoxDecoration(color: const Color(0xFFFEF3C7), borderRadius: BorderRadius.circular(12)),
          child: Text('এখনো ${bn(pending)}টি অর্ডার ডেলিভারি বা বাতিল করা হয়নি। সেটেলমেন্টের আগে সব দোকান শেষ করুন।', style: const TextStyle(color: Color(0xFFB45309))),
        ),
      const SectionTitle('হিসাব'),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(children: [
            row('ডেলিভারির বিল (SR দামে)', money(sum['total_sales_sr'])),
            row('রেডি সেল', money(sum['ready_sale'])),
            row('পুরনো বাকি আদায়', money(sum['prior_due_collected'])),
            row('ড্যামেজ', '-${money(sum['damaged_amount'])}', color: kDanger),
            row('খরচ', '-${money(sum['daily_expenses'])}', color: kDanger),
            row('নতুন বাকি', '-${money(sum['retailer_due'])}', color: kDanger),
            const Divider(),
            row('জমা দেওয়ার টাকা', money(net), bold: true, color: kBlue),
          ]),
        ),
      ),
      if (returns.isNotEmpty) ...[
        const SectionTitle('গোডাউনে ফেরত দেওয়ার মাল'),
        for (final r in returns)
          Card(
            margin: const EdgeInsets.only(bottom: 6),
            child: ListTile(dense: true, title: Text('${r['name']}'), subtitle: Text('${r['reason'] ?? ''}'), trailing: Text('${bn(r['expected_return_pcs'])} পিস', style: const TextStyle(fontWeight: FontWeight.w800))),
          ),
      ],
      if (dues.isNotEmpty) ...[
        const SectionTitle('বাকিতে দেওয়া দোকান'),
        for (final r in dues)
          Card(margin: const EdgeInsets.only(bottom: 6), child: ListTile(dense: true, title: Text('${r['retailer']}'), subtitle: Text('${r['order_id']}'), trailing: Text(money(r['due']), style: const TextStyle(color: kDanger, fontWeight: FontWeight.w800)))),
      ],
      if (editable) ...[
        const SectionTitle('ক্যাশ গোনা'),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(children: [
              for (final n in notes)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(children: [
                    SizedBox(width: 70, child: Text('৳${bn(n['value'])}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16))),
                    const Text('×'),
                    const SizedBox(width: 8),
                    NumField(controller: _c(int0(n['value']), int0(n['qty'])), dense: true, width: 80, onChanged: (_) => setState(() {})),
                    const Spacer(),
                    Text(money(int0(n['value']) * (int.tryParse(_notes[int0(n['value'])]?.text ?? '') ?? int0(n['qty']))), style: const TextStyle(color: kMuted)),
                  ]),
                ),
              const Divider(),
              row('মোট গোনা', money(_counted(notes)), bold: true),
              row('পার্থক্য', _counted(notes) - net == 0 ? 'মিলেছে ✓' : money(_counted(notes) - net), color: _counted(notes) - net == 0 ? kOk : kDanger),
            ]),
          ),
        ),
        const SizedBox(height: 10),
        TextField(controller: _note, decoration: const InputDecoration(labelText: 'পার্টনারের জন্য নোট (ঐচ্ছিক)')),
        const SizedBox(height: 14),
        FilledButton(onPressed: pending > 0 ? null : () => _submit(notes, net), child: const Text('সেটেলমেন্ট জমা দিন')),
      ] else if (cash != null) ...[
        const SectionTitle('ক্যাশ'),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(children: [
              row('আপনি গুনেছেন', money(cash['counted'])),
              if (cash['partner_received'] != null) row('পার্টনার বুঝে পেয়েছেন', money(cash['partner_received'])),
            ]),
          ),
        ),
      ],
    ];
  }
}
