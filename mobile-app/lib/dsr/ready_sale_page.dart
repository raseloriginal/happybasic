import 'package:flutter/material.dart';

import '../core/api.dart';
import '../core/format.dart';
import '../core/offline.dart';
import '../core/printer.dart';
import '../core/tracker.dart';
import '../ui/common.dart';
import '../ui/dkit.dart';

Map<String, dynamic> _m(Object? v) => Map<String, dynamic>.from((v ?? {}) as Map);

/// Sell van stock on the spot at the loaded dealer price (the DSR cannot change the price).
class ReadySalePage extends StatefulWidget {
  const ReadySalePage({super.key, required this.vanStock});
  final List<Map<String, dynamic>> vanStock;
  @override
  State<ReadySalePage> createState() => _ReadySalePageState();
}

class _ReadySalePageState extends State<ReadySalePage> {
  bool _newShop = false;
  Map<String, dynamic>? _shop;
  List<Map<String, dynamic>> _directory = [];
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _address = TextEditingController();
  double? _lat, _lng;
  final Map<int, TextEditingController> _qty = {};

  @override
  void initState() {
    super.initState();
    _loadDirectory();
  }

  Future<void> _loadDirectory() async {
    try {
      final l = await loadCached('dsr_retailers', () => ApiClient.get('/dsr/retailers'));
      if (mounted) setState(() => _directory = (l.data['retailers'] as List).map(_m).toList());
    } catch (_) {}
  }

  TextEditingController _c(int pid) => _qty.putIfAbsent(pid, () => TextEditingController());
  List<Map<String, dynamic>> get _stock => widget.vanStock.where((p) => int0(p['available_pcs']) > 0).toList();

  double get _total => _stock.fold(0.0, (a, p) => a + (int.tryParse(_qty[int0(p['id'])]?.text ?? '') ?? 0) * num0(p['base_rate']));

  Future<void> _locate() async {
    final p = await Tracker.currentOnce();
    if (!mounted) return;
    setState(() {
      _lat = p?.latitude;
      _lng = p?.longitude;
    });
    if (p == null) toast(context, 'লোকেশন পাওয়া যায়নি।', error: true);
  }

  Future<void> _pickShop() async {
    final picked = await showModalBottomSheet<Map<String, dynamic>>(
      context: context, isScrollControlled: true,
      builder: (c) => _ShopPicker(directory: _directory),
    );
    if (picked != null) setState(() => _shop = picked);
  }

  Future<void> _save() async {
    final items = [
      for (final p in _stock)
        if ((int.tryParse(_qty[int0(p['id'])]?.text ?? '') ?? 0) > 0) {'product_id': int0(p['id']), 'pcs': int.parse(_qty[int0(p['id'])]!.text)}
    ];
    for (final p in _stock) {
      final n = int.tryParse(_qty[int0(p['id'])]?.text ?? '') ?? 0;
      if (n > int0(p['available_pcs'])) {
        toast(context, '${p['name']}: ভ্যানে মাত্র ${bn(p['available_pcs'])} পিস আছে।', error: true);
        return;
      }
    }
    if (items.isEmpty) {
      toast(context, 'কমপক্ষে একটি পণ্য দিন।', error: true);
      return;
    }
    final Map<String, dynamic> body;
    if (_newShop) {
      if (_name.text.trim().isEmpty) return toast(context, 'দোকানের নাম দিন।', error: true);
      if (_lat == null) return toast(context, 'দোকানের লোকেশন নিন।', error: true);
      body = {'mode': 'new', 'name': _name.text.trim(), 'phone': _phone.text.trim(), 'address': _address.text.trim(), 'lat': _lat, 'lng': _lng, 'items': items};
    } else {
      if (_shop == null) return toast(context, 'দোকান বাছুন।', error: true);
      body = {'mode': 'existing', 'retailer_id': int0(_shop!['id']), 'items': items};
    }
    final label = 'রেডি সেল · ${_newShop ? _name.text.trim() : _shop!['name']}';
    final r = await busy(context, () => OfflineQueue.write('POST', '/dsr/ready-sales', body: body, label: label, queueable: !_newShop));
    if (r == null || !mounted) return;
    if (r.queued) {
      toast(context, 'ফোনে সংরক্ষিত, ইন্টারনেট এলে পাঠানো হবে।');
      Navigator.pop(context, true);
      return;
    }
    final receipt = r.data['receipt'] == null ? null : _m(r.data['receipt']);
    toast(context, (r.data['message'] ?? 'রেডি সেল হয়েছে।').toString());
    if (receipt != null && mounted) {
      final print = await confirm(context, 'রসিদ প্রিন্ট করবেন?', yes: 'প্রিন্ট');
      if (print && mounted) {
        final err = await busy(context, () => PrinterService.print(_receiptLines(receipt)));
        if (mounted && err != null) toast(context, err, error: true);
      }
    }
    if (mounted) Navigator.pop(context, true);
  }

  List<ReceiptLine> _receiptLines(Map<String, dynamic> r) => [
        ReceiptLine('হ্যাপি বাংলাদেশ', style: ReceiptStyle.title, center: true),
        ReceiptLine('রেডি সেল', center: true),
        ReceiptLine.rule(),
        ReceiptLine('${r['retailer']}', style: ReceiptStyle.bold),
        ReceiptLine(dateBn(todayYmd()), style: ReceiptStyle.small),
        ReceiptLine.rule(),
        for (final it in (r['items'] as List? ?? []).map(_m)) ...[
          ReceiptLine('${it['name']}'),
          ReceiptLine('  ${bn(it['pcs'] ?? it['qty'])} × ${num2(it['rate'] ?? it['base_rate'])}', right: money(it['amount'] ?? it['total']), style: ReceiptStyle.small),
        ],
        ReceiptLine.rule(),
        ReceiptLine('মোট', right: money(r['total']), style: ReceiptStyle.bold),
        ReceiptLine.rule(),
        ReceiptLine('ধন্যবাদ', center: true),
      ];

  @override
  Widget build(BuildContext context) {
    return DPage(
      title: 'রেডি সেল',
      child: Column(children: [
        Expanded(
          child: ListView(padding: const EdgeInsets.all(14), children: [
            SegmentedButton<bool>(
              segments: const [ButtonSegment(value: false, label: Text('আগের দোকান')), ButtonSegment(value: true, label: Text('নতুন দোকান'))],
              selected: {_newShop},
              onSelectionChanged: (s) => setState(() => _newShop = s.first),
            ),
            const SizedBox(height: 12),
            if (!_newShop)
              Card(
                child: ListTile(
                  leading: const Icon(Icons.storefront),
                  title: Text(_shop == null ? 'দোকান বাছুন' : '${_shop!['name']}'),
                  subtitle: _shop == null ? null : Text('${_shop!['address'] ?? ''}'),
                  trailing: const Icon(Icons.search),
                  onTap: _pickShop,
                ),
              )
            else ...[
              TextField(controller: _name, decoration: const InputDecoration(labelText: 'দোকানের নাম *')),
              const SizedBox(height: 10),
              TextField(controller: _phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'মোবাইল (ঐচ্ছিক)')),
              const SizedBox(height: 10),
              TextField(controller: _address, decoration: const InputDecoration(labelText: 'ঠিকানা (ঐচ্ছিক)')),
              const SizedBox(height: 10),
              Card(
                child: ListTile(
                  leading: Icon(_lat == null ? Icons.location_off : Icons.my_location, color: _lat == null ? kDanger : kOk),
                  title: Text(_lat == null ? 'লোকেশন নেওয়া হয়নি' : 'বর্তমান লোকেশন নেওয়া হয়েছে'),
                  trailing: TextButton(onPressed: _locate, child: const Text('লোকেশন নিন')),
                ),
              ),
            ],
            const SectionTitle('ভ্যানের মাল'),
            if (_stock.isEmpty) const Text('ভ্যানে বিক্রির মতো মাল নেই।', style: TextStyle(color: kMuted)),
            for (final p in _stock)
              Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  title: Text('${p['name']}', style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text('${money(p['base_rate'])}/পিস · ভ্যানে ${bn(p['available_pcs'])} পিস'),
                  trailing: NumField(controller: _c(int0(p['id'])), dense: true, width: 70, onChanged: (_) => setState(() {})),
                ),
              ),
          ]),
        ),
        SafeArea(
          top: false,
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: const BoxDecoration(color: Colors.white, border: Border(top: BorderSide(color: kBorder))),
            child: Row(children: [
              Expanded(child: Text('মোট ${money(_total)}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17))),
              SizedBox(width: 150, child: FilledButton(onPressed: _save, child: const Text('বিক্রি করুন'))),
            ]),
          ),
        ),
      ]),
    );
  }
}

class _ShopPicker extends StatefulWidget {
  const _ShopPicker({required this.directory});
  final List<Map<String, dynamic>> directory;
  @override
  State<_ShopPicker> createState() => _ShopPickerState();
}

class _ShopPickerState extends State<_ShopPicker> {
  String _q = '';
  @override
  Widget build(BuildContext context) {
    final q = _q.trim().toLowerCase();
    final rows = widget.directory.where((r) => q.isNotEmpty && '${r['name']} ${r['phone']} ${r['address']}'.toLowerCase().contains(q)).take(40).toList();
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.75,
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.all(14),
            child: TextField(autofocus: true, onChanged: (v) => setState(() => _q = v), decoration: const InputDecoration(hintText: 'দোকানের নাম বা ফোন লিখুন', prefixIcon: Icon(Icons.search))),
          ),
          Expanded(
            child: ListView(children: [
              if (q.isEmpty) const Padding(padding: EdgeInsets.all(30), child: Center(child: Text('খুঁজতে লিখুন…', style: TextStyle(color: kMuted)))),
              for (final r in rows)
                ListTile(title: Text('${r['name']}'), subtitle: Text('${r['address'] ?? ''}', maxLines: 1, overflow: TextOverflow.ellipsis), onTap: () => Navigator.pop(context, r)),
            ]),
          ),
        ]),
      ),
    );
  }
}
