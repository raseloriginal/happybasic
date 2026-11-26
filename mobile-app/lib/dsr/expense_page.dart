import 'package:flutter/material.dart';

import '../core/api.dart';
import '../core/format.dart';
import '../core/offline.dart';
import '../ui/common.dart';
import '../ui/dkit.dart';
import '../ui/pwa_kit.dart';

Map<String, dynamic> _m(Object? v) => Map<String, dynamic>.from((v ?? {}) as Map);

/// /dsr/expense — date nav, total card with "+ খরচ যোগ", category chips, list.
class ExpensePage extends StatefulWidget {
  const ExpensePage({super.key});
  @override
  State<ExpensePage> createState() => _ExpensePageState();
}

class _ExpensePageState extends State<ExpensePage> {
  String? _date;
  String _cat = 'all';
  final _key = GlobalKey<AsyncBodyState>();

  Future<void> _add(List<String> categories) async {
    final title = TextEditingController();
    final amount = TextEditingController();
    final note = TextEditingController();
    var cat = categories.first;
    String? error;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => Dialog(
          backgroundColor: Colors.white, insetPadding: const EdgeInsets.all(14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: const BorderSide(color: DC.border)),
          child: SingleChildScrollView(
            padding: EdgeInsets.only(bottom: MediaQuery.of(c).viewInsets.bottom),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 14, 12),
                child: Row(children: [
                  const Expanded(child: DSecTitle('দৈনিক খরচ যোগ করুন')),
                  DIconBtn(icon: '<path d="M18 6 6 18M6 6l12 12"/>', onTap: () => Navigator.pop(c, false)),
                ]),
              ),
              const Divider(height: 1, color: DC.border),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  _lbl('খরচের বিবরণ'),
                  TextField(controller: title, style: ts(13.5), decoration: const InputDecoration(hintText: 'যেমন: সিএনজি / তেল খরচ', isDense: true)),
                  const SizedBox(height: 12),
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        _lbl('ক্যাটাগরি'),
                        DropdownButtonFormField<String>(
                          initialValue: cat, isExpanded: true, isDense: true, style: ts(13.5),
                          items: [for (final k in categories) DropdownMenuItem(value: k, child: Text(expenseCatBn(k), overflow: TextOverflow.ellipsis))],
                          onChanged: (v) => set(() => cat = v!),
                        ),
                      ]),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [_lbl('টাকার পরিমাণ (৳)'), NumField(controller: amount, decimal: true)]),
                    ),
                  ]),
                  const SizedBox(height: 12),
                  _lbl('নোট (ঐচ্ছিক)'),
                  TextField(controller: note, style: ts(13.5), decoration: const InputDecoration(hintText: 'স্লিপ নম্বর বা মন্তব্য', isDense: true)),
                  if (error != null)
                    Container(
                      margin: const EdgeInsets.only(top: 10), padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(color: DC.dangerBg, borderRadius: BorderRadius.circular(8), border: Border.all(color: DC.dangerBorder)),
                      child: Text(error!, style: ts(12.5, color: DC.dangerText)),
                    ),
                ]),
              ),
              const Divider(height: 1, color: DC.border),
              Padding(
                padding: const EdgeInsets.all(12),
                child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                  DBtn('বাতিল', kind: DBtnKind.secondary, onTap: () => Navigator.pop(c, false)),
                  const SizedBox(width: 8),
                  DBtn('খরচ সংরক্ষণ করুন', onTap: () {
                    final amt = double.tryParse(amount.text) ?? 0;
                    if (title.text.trim().isEmpty || amt <= 0) {
                      set(() => error = 'বিবরণ ও টাকার পরিমাণ দিন।');
                      return;
                    }
                    Navigator.pop(c, true);
                  }),
                ]),
              ),
            ]),
          ),
        ),
      ),
    );
    if (ok != true || !mounted) return;
    final amt = double.tryParse(amount.text) ?? 0;
    final r = await busy(context, () => OfflineQueue.write('POST', '/dsr/expenses',
        body: {'title': title.text.trim(), 'category': cat, 'amount': amt, 'note': note.text.trim()}, label: 'খরচ: ${title.text.trim()}'));
    if (r != null && mounted) {
      toast(context, r.queued ? 'ফোনে সংরক্ষিত, নেট এলে পাঠানো হবে।' : (r.data['message'] ?? 'খরচ যোগ হয়েছে।').toString());
      _key.currentState?.reload();
    }
  }

  Widget _lbl(String t) => Padding(padding: const EdgeInsets.only(bottom: 5), child: Text(t, style: ts(12.5, w: FontWeight.w600, color: DC.ink2)));

  @override
  Widget build(BuildContext context) {
    return AsyncBody(
      key: _key,
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 20),
      load: () => loadCached('dsr_expense_${_date ?? 'open'}', () => ApiClient.get('/dsr/expenses', query: {'date': _date})),
      builder: (context, d, reload) {
        final trip = d['trip'] == null ? null : _m(d['trip']);
        final all = (d['expenses'] as List).map(_m).toList();
        final categories = (d['categories'] as List).map((e) => '$e').toList();
        final total = all.fold<double>(0, (a, e) => a + num0(e['amount']));
        final editable = trip != null && trip['editable'] == true;
        final list = _cat == 'all' ? all : all.where((e) => '${e['category']}' == _cat).toList();
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          DDateNav(date: d['selectedDate'].toString(), onChange: (v) => setState(() => _date = v == todayYmd() ? null : v)),
          const SizedBox(height: 14),
          if (trip == null)
            DCard(padding: const EdgeInsets.fromLTRB(18, 22, 18, 22), child: Center(child: Text('কোনো ডিসপ্যাচ করা ট্রিপ নেই', style: ts(15, w: FontWeight.w600))))
          else if (!editable)
            const DBanner('সেটেলমেন্ট জমা দেওয়া হয়েছে — পার্টনার যাচাই শেষ না হওয়া পর্যন্ত খরচ লক থাকবে।'),
          const SizedBox(height: 14),
          DCard(
            child: Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('মোট দৈনিক খরচ', style: ts(11.5, w: FontWeight.w600, color: DC.muted)),
                  const SizedBox(height: 4),
                  Text(bnMoney(total, smart: true), style: ts(32, w: FontWeight.w700, ls: -0.8, h: 1.1, tabular: true)),
                  Text(trip != null ? '${bn('${trip['code']}')} · ${dateBn('${trip['date']}')}' : '—', style: ts(12, color: DC.muted, tabular: true)),
                ]),
              ),
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                DBadge('${bn(all.length)}টি আইটেম'),
                const SizedBox(height: 10),
                DBtn('+ খরচ যোগ', small: true, onTap: editable ? () => _add(categories) : null),
              ]),
            ]),
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 32,
            child: ListView(scrollDirection: Axis.horizontal, children: [
              _chip('সব', 'all'),
              for (final c in categories) _chip(expenseCatBn(c), c),
            ]),
          ),
          const SizedBox(height: 14),
          DCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const DSecTitle('দৈনিক খরচের তালিকা'),
              const SizedBox(height: 12),
              for (var i = 0; i < list.length; i++) _row(list[i], editable, reload, last: i == list.length - 1),
            ]),
          ),
        ]);
      },
    );
  }

  Widget _chip(String label, String key) {
    final on = _cat == key;
    return Padding(
      padding: const EdgeInsets.only(right: 7),
      child: GestureDetector(
        onTap: () => setState(() => _cat = key),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12), alignment: Alignment.center,
          decoration: BoxDecoration(color: on ? DC.accent : DC.surface, borderRadius: BorderRadius.circular(99), border: Border.all(color: on ? DC.accent : DC.borderStrong)),
          child: Text(label, style: ts(12, w: FontWeight.w600, color: on ? Colors.white : DC.ink2, h: 1.2)),
        ),
      ),
    );
  }

  Widget _row(Map<String, dynamic> e, bool editable, VoidCallback reload, {required bool last}) => Container(
        padding: EdgeInsets.only(top: 10, bottom: last ? 0 : 10),
        decoration: BoxDecoration(border: last ? null : const Border(bottom: BorderSide(color: DC.border))),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Wrap(spacing: 8, runSpacing: 2, crossAxisAlignment: WrapCrossAlignment.center, children: [
                Text('${e['title']}', style: ts(14, w: FontWeight.w700)),
                DBadge(expenseCatBn('${e['category']}')),
              ]),
              const SizedBox(height: 3),
              Text('${bn(e['time'] ?? '')}${'${e['note'] ?? ''}'.isNotEmpty ? ' · ${e['note']}' : ''}', style: ts(12, color: DC.muted, tabular: true)),
            ]),
          ),
          const SizedBox(width: 10),
          Text(bnMoney(e['amount'], smart: true), style: ts(14, w: FontWeight.w700, tabular: true)),
          if (editable && e['id'] != null) ...[
            const SizedBox(width: 10),
            GestureDetector(
              onTap: () async {
                if (!await confirm(context, 'খরচটি মুছবেন?', danger: true, yes: 'মুছুন')) return;
                if (!mounted) return;
                final r = await busy(context, () => ApiClient.send('DELETE', '/dsr/expenses/${e['id']}', opId: ApiClient.newOpId()));
                if (r != null) reload();
              },
              child: Container(
                width: 28, height: 28,
                decoration: BoxDecoration(color: DC.dangerBg, borderRadius: BorderRadius.circular(7), border: Border.all(color: DC.dangerBorder)),
                child: const Center(child: Svg('<polyline points="3 6 5 6 21 6"/><path d="M19 6l-1 14a2 2 0 0 1-2 2H8a2 2 0 0 1-2-2L5 6"/>', size: 14, color: DC.dangerText)),
              ),
            ),
          ],
        ]),
      );
}
