import 'package:flutter/material.dart';

import '../core/format.dart';
import '../core/offline.dart';
import '../ui/common.dart';

/// Damaged goods returned by a shop: deducted from that shop's bill at the dealer price.
class DamagePage extends StatefulWidget {
  const DamagePage({super.key, required this.products, required this.stops, this.selectedId});
  final List<Map<String, dynamic>> products;
  final List<Map<String, dynamic>> stops;
  final int? selectedId; // open straight on this shop (from the shop's delivery screen)
  @override
  State<DamagePage> createState() => _DamagePageState();
}

class _DamagePageState extends State<DamagePage> {
  int? _retailer;
  final Map<int, TextEditingController> _ctl = {};
  String _q = '';

  @override
  void initState() {
    super.initState();
    if (widget.selectedId != null) WidgetsBinding.instance.addPostFrameCallback((_) => mounted ? _pick(widget.selectedId!) : null);
  }

  void _pick(int id) {
    _retailer = id;
    for (final c in _ctl.values) {
      c.dispose();
    }
    _ctl.clear();
    final stop = widget.stops.firstWhere((s) => int0(s['id']) == id, orElse: () => {});
    for (final d in (stop['damages'] as List? ?? [])) {
      final m = Map<String, dynamic>.from(d as Map);
      final pid = int0(m['product_id']);
      final cur = int.tryParse(_ctl[pid]?.text ?? '') ?? 0;
      _ctl.putIfAbsent(pid, () => TextEditingController()).text = '${cur + int0(m['pcs'])}';
    }
    setState(() {});
  }

  TextEditingController _c(int pid) => _ctl.putIfAbsent(pid, () => TextEditingController());

  double get _total {
    var t = 0.0;
    for (final p in widget.products) {
      t += (int.tryParse(_ctl[int0(p['id'])]?.text ?? '') ?? 0) * num0(p['rate']);
    }
    return t;
  }

  Future<void> _save() async {
    if (_retailer == null) {
      toast(context, 'আগে দোকান বাছুন।', error: true);
      return;
    }
    final items = [
      for (final p in widget.products)
        if ((int.tryParse(_ctl[int0(p['id'])]?.text ?? '') ?? 0) > 0) {'product_id': int0(p['id']), 'pcs': int.parse(_ctl[int0(p['id'])]!.text)}
    ];
    final name = widget.stops.firstWhere((s) => int0(s['id']) == _retailer)['retailer_name'];
    final r = await busy(context, () => OfflineQueue.write('POST', '/dsr/damages', body: {'retailer_id': _retailer, 'items': items}, label: '$name-এর ড্যামেজ'));
    if (r != null && mounted) {
      toast(context, r.queued ? 'ফোনে সংরক্ষিত, নেট এলে পাঠানো হবে।' : (r.data['message'] ?? 'ড্যামেজ সাবমিট হয়েছে।').toString());
      Navigator.pop(context, true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final q = _q.trim().toLowerCase();
    final products = widget.products.where((p) => q.isEmpty || '${p['name']}'.toLowerCase().contains(q)).toList();
    return Scaffold(
      appBar: AppBar(title: const Text('ড্যামেজ')),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.all(14),
          child: DropdownButtonFormField<int>(
            initialValue: _retailer,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'কোন দোকানের ড্যামেজ?'),
            items: [for (final s in widget.stops) DropdownMenuItem(value: int0(s['id']), child: Text('${s['retailer_name']}', overflow: TextOverflow.ellipsis))],
            onChanged: (v) => v == null ? null : _pick(v),
          ),
        ),
        if (_retailer != null) ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: TextField(onChanged: (v) => setState(() => _q = v), decoration: const InputDecoration(hintText: 'পণ্য খুঁজুন', prefixIcon: Icon(Icons.search), isDense: true)),
          ),
          Expanded(
            child: ListView(padding: const EdgeInsets.all(14), children: [
              for (final p in products)
                Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    title: Text('${p['name']}', style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text('${p['company']} · ${money(p['rate'])}/পিস'),
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
                Expanded(child: Text('বাদ যাবে ${money(_total)}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16))),
                SizedBox(width: 150, child: FilledButton(onPressed: _save, child: const Text('সাবমিট'))),
              ]),
            ),
          ),
        ] else
          const Expanded(child: Center(child: Text('উপরে দোকান বাছুন।', style: TextStyle(color: kMuted)))),
      ]),
    );
  }
}
