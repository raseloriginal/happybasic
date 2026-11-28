import 'package:flutter/material.dart';

import '../core/api.dart';
import '../core/format.dart';
import '../ui/common.dart';
import '../ui/dkit.dart';
import '../ui/hkit.dart';
import '../ui/pwa_kit.dart';

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

  int _qty(Map<String, dynamic> n) => int.tryParse(_notes[int0(n['value'])]?.text ?? '') ?? int0(n['qty']);
  int _counted(List<Map<String, dynamic>> notes) => notes.fold(0, (a, n) => a + int0(n['value']) * _qty(n));

  Future<void> _submit(List<Map<String, dynamic>> notes, double net) async {
    final counted = _counted(notes);
    final diff = counted - net;
    final ok = await confirm(
      context, 'সেটেলমেন্ট জমা দেবেন?',
      body: 'জমা দেওয়ার কথা ${bnMoney(net, smart: true)}\nগুনে পেয়েছেন ${bnMoney(counted, smart: true)}\n${diff == 0 ? 'হিসাব মিলেছে ✓' : diff < 0 ? '${bnMoney(-diff, smart: true)} কম' : '${bnMoney(diff, smart: true)} বেশি'}',
      yes: 'জমা দিন');
    if (!ok || !mounted) return;
    final body = {
      'notes': {for (final n in notes) '${int0(n['value'])}': _qty(n)},
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
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 20),
      load: () => loadCached('dsr_settlement_${_date ?? 'open'}', () => ApiClient.get('/dsr/settlement', query: {'date': _date})),
      builder: (context, d, reload) {
        final trip = d['trip'] == null ? null : _m(d['trip']);
        final s = d['settlement'] == null ? null : _m(d['settlement']);
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          DDateNav(date: d['selectedDate'].toString(), onChange: (v) => setState(() => _date = v == todayYmd() ? null : v)),
          const SizedBox(height: 14),
          if (trip == null || s == null)
            DCard(padding: const EdgeInsets.fromLTRB(18, 22, 18, 22), child: Center(child: Text('সেটেল করার মতো কোনো ট্রিপ নেই', style: ts(15, w: FontWeight.w600))))
          else
            ..._body(trip, s),
        ]);
      },
    );
  }

  Widget _kpi(String label, double v, {Color color = DC.ink, bool accent = false}) => HCard(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12), radius: 20,
        color: accent ? HC.ink : Colors.white, border: !accent,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: ts(11.5, w: FontWeight.w600, color: accent ? const Color(0xFFCBD5E1) : DC.muted)),
          const SizedBox(height: 4),
          Text(bnMoney(v, smart: true), style: ts(17.5, w: FontWeight.w700, color: accent ? Colors.white : color, ls: -0.17, tabular: true)),
        ]),
      );

  Widget _ledger(String label, String value, {Color color = DC.ink, Widget? sub, bool last = false}) => Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(border: last ? null : const Border(bottom: BorderSide(color: DC.border))),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(label, style: ts(13.5, w: FontWeight.w600)), if (sub != null) sub])),
          const SizedBox(width: 10),
          Text(value, style: ts(13.5, w: FontWeight.w700, color: color, tabular: true)),
        ]),
      );

  List<Widget> _body(Map<String, dynamic> trip, Map<String, dynamic> s) {
    final sum = _m(s['summary']);
    final counts = _m(s['counts']);
    final notes = (s['notes'] as List).map(_m).toList();
    final cash = s['cash'] == null ? null : _m(s['cash']);
    final status = '${trip['settlement_status'] ?? ''}';
    final editable = trip['editable'] == true;
    final pending = int0(counts['pending']);
    final net = num0(sum['net_pay']);
    final dues = (s['due_details'] as List?)?.map(_m).toList() ?? [];
    final srRows = (s['sr_oc_rows'] as List?)?.map(_m).toList() ?? [];
    final readySale = num0(sum['ready_sale']), priorDue = num0(sum['prior_due_collected']), oc = num0(sum['delivery_oc']);
    final counted = notes.isEmpty ? 0 : _counted(notes);
    final diff = counted - net;
    final (diffBg, diffFg, diffBd, diffLabel) = diff < 0
        ? (DC.dangerBg, DC.dangerText, DC.dangerBorder, 'কম')
        : diff > 0
            ? (DC.warnBg, DC.warnText, DC.warnBorder, 'বেশি')
            : (DC.okBg, DC.okText, DC.okBorder, 'মিলেছে');
    return [
      if (!editable && trip['status_key'] != 'settled')
        Padding(padding: const EdgeInsets.only(bottom: 14), child: DBanner('জমা দেওয়া হয়েছে${trip['submitted_at'] != null ? ' (${dateTimeBn('${trip['submitted_at']}')})' : ''} — পার্টনারের যাচাইয়ের অপেক্ষায়।'))
      else if (status == 'returned')
        Padding(padding: const EdgeInsets.only(bottom: 14), child: DBanner('পার্টনার ফেরত পাঠিয়েছেন${'${trip['review_note'] ?? ''}'.isNotEmpty ? ': ${trip['review_note']}' : ''}। যাচাই করে পুনরায় জমা দিন।', returned: true))
      else if (pending > 0)
        Padding(padding: const EdgeInsets.only(bottom: 14), child: DBanner('এখনো ${bn(pending)}টি অর্ডার বাকি আছে। জমা দেওয়ার আগে সব দোকান ডেলিভারি বা বাতিল করুন।')),
      IntrinsicHeight(child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Expanded(child: _kpi('মোট লোড (ডিসপ্যাচ)', num0(sum['total_load']))),
        const SizedBox(width: 10),
        Expanded(child: _kpi('ফেরত মাল', num0(sum['return_amount']), color: DC.warnText)),
      ])),
      const SizedBox(height: 10),
      IntrinsicHeight(child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Expanded(child: _kpi('মোট বিক্রি', num0(sum['total_sales_sr']))),
        const SizedBox(width: 10),
        Expanded(child: _kpi('জমা দেওয়ার কথা', net, accent: true)),
      ])),
      const SizedBox(height: 14),
      DCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(child: DSecTitle('হিসাবের বিবরণ', sub: '${bn('${trip['code']}')} · ${trip['dsr'] ?? ''} · ${bn(int0(counts['orders']))}টি অর্ডার (${bn(int0(counts['cancelled']))}টি বাতিল)')),
            DBadge(dateBn('${trip['date']}'), tone: DTone.info),
          ]),
          const SizedBox(height: 12),
          _ledger('মোট লোড মূল্য', bnMoney(sum['total_load'], smart: true)),
          _ledger('মোট বিক্রি (বিক্রয়মূল্য)', bnMoney(sum['total_sales_sr'], smart: true),
              sub: Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Wrap(spacing: 6, runSpacing: 4, children: [
                  _ratePill('বেজ দর: ${bnMoney(sum['total_sales_base'], smart: true)}', false),
                  _ratePill('SR দর: ${bnMoney(sum['total_sales_sr'], smart: true)}', true),
                ]),
              )),
          if (readySale > 0) _ledger('রেডি সেল (+)', '+ ${bnMoney(readySale, smart: true)}', color: DC.okText),
          if (priorDue > 0) _ledger('আগের বাকি আদায় (+)', '+ ${bnMoney(priorDue, smart: true)}', color: DC.okText),
          _ledger('ফেরত মালের মূল্য', bnMoney(sum['return_amount'], smart: true), color: DC.warnText),
          _ledger('ড্যামেজ পণ্য (−)', '− ${bnMoney(sum['damaged_amount'], smart: true)}', color: DC.dangerText),
          _ledger('দৈনিক খরচ (−)', '− ${bnMoney(sum['daily_expenses'], smart: true)}', color: DC.dangerText),
          _ledger('ডেলিভারি O/C (ওভার / কমিশন)', signedMoney(oc, smart: true), color: oc >= 0 ? DC.okText : DC.warnText),
          _ledger('দোকান বাকি (−)', '− ${bnMoney(sum['retailer_due'], smart: true)}', color: DC.warnText,
              sub: GestureDetector(
                onTap: () => _showDues(dues),
                child: Padding(padding: const EdgeInsets.only(top: 3), child: Text('বিস্তারিত দেখুন (${bn(dues.length)})', style: ts(12, w: FontWeight.w600, color: DC.link).copyWith(decoration: TextDecoration.underline))),
              )),
          Container(
            margin: const EdgeInsets.only(top: 4), padding: const EdgeInsets.only(top: 12),
            decoration: const BoxDecoration(border: Border(top: BorderSide(color: DC.ink, width: 1.5))),
            child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Flexible(child: Text('ক্যাশ জমা (Net Pay)', style: ts(14, w: FontWeight.w700))),
              const SizedBox(width: 8),
              Text(bnMoney(net, smart: true), style: ts(21, w: FontWeight.w800, tabular: true)),
            ]),
          ),
        ]),
      ),
      if (srRows.isNotEmpty) ...[
        const SizedBox(height: 14),
        DCard(
          padding: EdgeInsets.zero,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Padding(padding: EdgeInsets.fromLTRB(16, 14, 16, 10), child: DSecTitle('SR অনুযায়ী ডেলিভারি O/C')),
            Container(
              color: DC.subtle, padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: Row(children: [
                Expanded(flex: 4, child: Text('SR', style: ts(10.5, w: FontWeight.w600, color: DC.muted))),
                Expanded(flex: 2, child: Text('অর্ডার', textAlign: TextAlign.right, style: ts(10.5, w: FontWeight.w600, color: DC.muted))),
                Expanded(flex: 3, child: Text('অর্ডার O/C', textAlign: TextAlign.right, style: ts(10.5, w: FontWeight.w600, color: DC.muted))),
                Expanded(flex: 3, child: Text('ডেলিভারি O/C', textAlign: TextAlign.right, style: ts(10.5, w: FontWeight.w600, color: DC.muted))),
              ]),
            ),
            for (var i = 0; i < srRows.length; i++)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
                decoration: BoxDecoration(border: i == srRows.length - 1 ? null : const Border(bottom: BorderSide(color: DC.border))),
                child: Row(children: [
                  Expanded(flex: 4, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('${srRows[i]['sr_name']}', style: ts(12.5, w: FontWeight.w600)), Text('${srRows[i]['area'] ?? ''}', style: ts(11.5, color: DC.muted))])),
                  Expanded(flex: 2, child: Text(bn(int0(srRows[i]['orders'])), textAlign: TextAlign.right, style: ts(12.5, tabular: true))),
                  Expanded(flex: 3, child: Text(signedMoney(num0(srRows[i]['order_oc']), smart: true), textAlign: TextAlign.right, style: ts(12.5, tabular: true))),
                  Expanded(flex: 3, child: Text(signedMoney(num0(srRows[i]['delivery_oc']), smart: true), textAlign: TextAlign.right, style: ts(12.5, w: FontWeight.w700, color: num0(srRows[i]['delivery_oc']) >= 0 ? DC.okText : DC.warnText, tabular: true))),
                ]),
              ),
          ]),
        ),
      ],
      const SizedBox(height: 14),
      DCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            const DSecTitle('নগদ টাকা গণনা'),
            if (editable) DBtn('রিসেট', kind: DBtnKind.ghost, small: true, onTap: () => setState(() { for (final n in notes) { _c(int0(n['value']), int0(n['qty'])).text = ''; } })),
          ]),
          const SizedBox(height: 10),
          if (editable)
            for (final n in notes)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(color: DC.subtle, borderRadius: BorderRadius.circular(8), border: Border.all(color: DC.border)),
                    child: Text('৳ ${bn(n['value'])}', style: ts(13.5, w: FontWeight.w700, tabular: true)),
                  ),
                  Padding(padding: const EdgeInsets.symmetric(horizontal: 8), child: Text('×', style: ts(14, color: DC.muted))),
                  NumField(controller: _c(int0(n['value']), int0(n['qty'])), dense: true, width: 80, onChanged: (_) => setState(() {})),
                  const Spacer(),
                  Text(bnMoney(int0(n['value']) * _qty(n), smart: true), style: ts(13.5, tabular: true)),
                ]),
              )
          else if (cash != null) ...[
            _ledger('আপনি গুনেছেন', bnMoney(cash['counted'], smart: true)),
            if (cash['partner_received'] != null) _ledger('পার্টনার বুঝে পেয়েছেন', bnMoney(cash['partner_received'], smart: true), last: true),
          ],
          if (editable) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.only(top: 10),
              decoration: const BoxDecoration(border: Border(top: BorderSide(color: DC.border))),
              child: Column(children: [
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Flexible(child: Text('গণনাকৃত মোট ক্যাশ', style: ts(13, color: DC.muted))), Text(bnMoney(counted, smart: true), style: ts(13.5, w: FontWeight.w700, tabular: true))]),
                const SizedBox(height: 6),
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Flexible(child: Text('জমা দেওয়ার কথা (Net Pay)', style: ts(13, color: DC.muted))), Text(bnMoney(net, smart: true), style: ts(13.5, w: FontWeight.w700, tabular: true))]),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(color: diffBg, borderRadius: BorderRadius.circular(8), border: Border.all(color: diffBd)),
                  child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                    Text(diffLabel, style: ts(13, w: FontWeight.w700, color: diffFg)),
                    Text(signedMoney(diff, smart: true), style: ts(15, w: FontWeight.w700, color: diffFg, tabular: true)),
                  ]),
                ),
                const SizedBox(height: 12),
                Align(alignment: Alignment.centerLeft, child: Padding(padding: const EdgeInsets.only(bottom: 5), child: Text('পার্টনারের জন্য নোট (ঐচ্ছিক)', style: ts(12.5, w: FontWeight.w600, color: DC.ink2)))),
                TextField(controller: _note, maxLength: 255, style: ts(13.5), decoration: const InputDecoration(hintText: 'যেমন: খুচরা কম ছিল, কাল দেব', isDense: true, counterText: '')),
                const SizedBox(height: 12),
                DBtn('সেটেলমেন্ট জমা দিন', block: true, height: 44, onTap: pending > 0 ? null : () => _submit(notes, net)),
              ]),
            ),
          ],
        ]),
      ),
    ];
  }

  Widget _ratePill(String t, bool accent) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(color: accent ? DC.accent : DC.subtle, borderRadius: BorderRadius.circular(99), border: Border.all(color: accent ? DC.accent : DC.border)),
        child: Text(t, style: ts(11, color: accent ? Colors.white : DC.ink2, tabular: true)),
      );

  void _showDues(List<Map<String, dynamic>> dues) {
    showHSheet<void>(
      context, scroll: false,
      builder: (c) => Align(
        alignment: Alignment.bottomCenter,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: kFrameW, maxHeight: MediaQuery.of(c).size.height * 0.8),
          child: Container(
            color: DC.surface,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Padding(padding: const EdgeInsets.fromLTRB(16, 14, 14, 12), child: Row(children: [const Expanded(child: DSecTitle('দোকান বাকির তালিকা')), DIconBtn(icon: '<path d="M18 6 6 18M6 6l12 12"/>', onTap: () => Navigator.pop(c))])),
              const Divider(height: 1, color: DC.border),
              Flexible(
                child: dues.isEmpty
                    ? Padding(padding: const EdgeInsets.all(24), child: Text('কোনো বাকি নেই।', style: ts(13, color: DC.muted)))
                    : ListView(padding: const EdgeInsets.all(14), shrinkWrap: true, children: [
                        for (final r in dues)
                          Container(
                            margin: const EdgeInsets.only(bottom: 8), padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(color: DC.subtle, borderRadius: BorderRadius.circular(8), border: Border.all(color: DC.border)),
                            child: Row(children: [
                              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('${r['retailer']}', style: ts(13.5, w: FontWeight.w600)), Text('${r['order_id'] ?? ''}', style: ts(12, color: DC.muted))])),
                              Text(bnMoney(r['due'], smart: true), style: ts(13.5, w: FontWeight.w700, color: DC.warnText, tabular: true)),
                            ]),
                          ),
                      ]),
              ),
              Padding(padding: EdgeInsets.fromLTRB(14, 8, 14, 12 + MediaQuery.of(c).padding.bottom), child: DBtn('বন্ধ', kind: DBtnKind.secondary, block: true, onTap: () => Navigator.pop(c))),
            ]),
          ),
        ),
      ),
    );
  }
}
