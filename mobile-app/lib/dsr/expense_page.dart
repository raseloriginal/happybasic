import 'package:flutter/material.dart';

import '../core/api.dart';
import '../core/format.dart';
import '../core/offline.dart';
import '../ui/common.dart';

Map<String, dynamic> _m(Object? v) => Map<String, dynamic>.from((v ?? {}) as Map);

const _catBn = {
  'Fuel': 'জ্বালানি',
  'Helper': 'হেলপার',
  'Food': 'খাবার',
  'Toll & Parking': 'টোল ও পার্কিং',
  'Van Repair': 'ভ্যান মেরামত',
  'Mobile / Communication': 'মোবাইল / যোগাযোগ',
  'Other': 'অন্যান্য',
};

class ExpensePage extends StatefulWidget {
  const ExpensePage({super.key});
  @override
  State<ExpensePage> createState() => _ExpensePageState();
}

class _ExpensePageState extends State<ExpensePage> {
  String? _date;
  final _key = GlobalKey<AsyncBodyState>();

  Future<void> _add(List<String> categories) async {
    final title = TextEditingController();
    final amount = TextEditingController();
    final note = TextEditingController();
    var cat = categories.first;
    final ok = await showModalBottomSheet<bool>(
      context: context, isScrollControlled: true,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => Padding(
          padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + MediaQuery.of(c).viewInsets.bottom),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('নতুন খরচ', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: cat, isExpanded: true,
              decoration: const InputDecoration(labelText: 'ধরন'),
              items: [for (final k in categories) DropdownMenuItem(value: k, child: Text(_catBn[k] ?? k))],
              onChanged: (v) => set(() => cat = v!),
            ),
            const SizedBox(height: 10),
            TextField(controller: title, decoration: const InputDecoration(labelText: 'বিবরণ')),
            const SizedBox(height: 10),
            NumField(controller: amount, label: 'টাকা', decimal: true),
            const SizedBox(height: 10),
            TextField(controller: note, decoration: const InputDecoration(labelText: 'নোট (ঐচ্ছিক)')),
            const SizedBox(height: 16),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('যোগ করুন')),
          ]),
        ),
      ),
    );
    if (ok != true || !mounted) return;
    final amt = double.tryParse(amount.text) ?? 0;
    if (title.text.trim().isEmpty || amt <= 0) {
      toast(context, 'বিবরণ ও টাকার পরিমাণ দিন।', error: true);
      return;
    }
    final r = await busy(context, () => OfflineQueue.write('POST', '/dsr/expenses',
        body: {'title': title.text.trim(), 'category': cat, 'amount': amt, 'note': note.text.trim()}, label: 'খরচ: ${title.text.trim()}'));
    if (r != null && mounted) {
      toast(context, r.queued ? 'ফোনে সংরক্ষিত, নেট এলে পাঠানো হবে।' : (r.data['message'] ?? 'খরচ যোগ হয়েছে।').toString());
      _key.currentState?.reload();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(children: [
      AsyncBody(
        key: _key,
        load: () => loadCached('dsr_expense_${_date ?? 'open'}', () => ApiClient.get('/dsr/expenses', query: {'date': _date})),
        builder: (context, d, reload) {
          final trip = d['trip'] == null ? null : _m(d['trip']);
          final expenses = (d['expenses'] as List).map(_m).toList();
          final categories = (d['categories'] as List).map((e) => '$e').toList();
          final total = expenses.fold<double>(0, (a, e) => a + num0(e['amount']));
          final editable = trip != null && trip['editable'] == true;
          return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            DateBar(date: d['selectedDate'].toString(), onChange: (v) => setState(() => _date = v)),
            const SizedBox(height: 10),
            if (trip == null) const Padding(padding: EdgeInsets.all(40), child: Center(child: Text('এই দিনে কোনো ট্রিপ নেই।', style: TextStyle(color: kMuted)))),
            if (trip != null) ...[
              StatTile('মোট খরচ', money(total), color: kDanger, icon: Icons.payments_outlined),
              const SizedBox(height: 6),
              for (final e in expenses)
                Card(
                  margin: const EdgeInsets.only(top: 8),
                  child: ListTile(
                    title: Text('${e['title']}', style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text('${_catBn[e['category']] ?? e['category']}${e['note'] != null ? ' · ${e['note']}' : ''}'),
                    trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                      Text(money(e['amount']), style: const TextStyle(fontWeight: FontWeight.w800)),
                      if (editable && e['id'] != null)
                        IconButton(
                          icon: const Icon(Icons.delete_outline, color: kDanger),
                          onPressed: () async {
                            if (!await confirm(context, 'খরচটি মুছবেন?', danger: true, yes: 'মুছুন')) return;
                            if (!context.mounted) return;
                            final r = await busy(context, () => ApiClient.send('DELETE', '/dsr/expenses/${e['id']}', opId: ApiClient.newOpId()));
                            if (r != null) reload();
                          },
                        ),
                    ]),
                  ),
                ),
              if (editable) Padding(padding: const EdgeInsets.only(top: 14), child: FilledButton.icon(onPressed: () => _add(categories), icon: const Icon(Icons.add), label: const Text('খরচ যোগ করুন'))),
            ],
          ]);
        },
      ),
    ]);
  }
}
