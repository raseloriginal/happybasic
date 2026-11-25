import 'package:flutter/material.dart';

import '../core/api.dart';
import '../core/format.dart';
import '../core/offline.dart';
import '../ui/common.dart';

class _Line {
  _Line(this.p) : qpu = int0(p['qty_per_unit']).clamp(1, 100000);
  final Map<String, dynamic> p;
  final int qpu;
  final unit = TextEditingController();
  final loose = TextEditingController();
  final total = TextEditingController();
  bool manualTotal = false;

  double get rate => num0(p['pc_price']);
  int get pcs => (int.tryParse(unit.text) ?? 0) * qpu + (int.tryParse(loose.text) ?? 0);
  double get totalVal => double.tryParse(total.text) ?? 0;
  double get base => pcs * rate;

  void autoTotal() {
    if (!manualTotal) total.text = pcs == 0 ? '' : _trim(base);
  }

  static String _trim(double v) => v == v.roundToDouble() ? v.round().toString() : v.toStringAsFixed(2);

  void setPcs(int n) {
    if (qpu > 1) {
      unit.text = n ~/ qpu == 0 ? '' : '${n ~/ qpu}';
      loose.text = n % qpu == 0 ? '' : '${n % qpu}';
    } else {
      loose.text = n == 0 ? '' : '$n';
    }
  }
}

/// Take / change one shop's order. Price per line can be changed (the difference is the SR's O/C).
class OrderEditorPage extends StatefulWidget {
  const OrderEditorPage({super.key, required this.shop, required this.products, this.existing});
  final Map<String, dynamic> shop;
  final List<Map<String, dynamic>> products;
  final Map<String, dynamic>? existing;
  @override
  State<OrderEditorPage> createState() => _OrderEditorPageState();
}

class _OrderEditorPageState extends State<OrderEditorPage> {
  late final List<_Line> _lines;
  final _search = TextEditingController();
  String _q = '';

  bool get _editing => widget.existing != null;
  bool get _locked => _editing && widget.existing!['editable'] != true;

  @override
  void initState() {
    super.initState();
    _lines = widget.products.map(_Line.new).toList();
    if (_editing) {
      for (final it in (widget.existing!['items'] as List)) {
        final m = Map<String, dynamic>.from(it as Map);
        for (final l in _lines) {
          if ('${l.p['id']}' == '${m['product_id']}') {
            l.setPcs(int0(m['pcs']));
            l.total.text = _Line._trim(num0(m['total']));
            l.manualTotal = (num0(m['total']) - l.base).abs() > 0.009;
          }
        }
      }
    }
  }

  double get _sum => _lines.where((l) => l.pcs > 0).fold(0, (a, l) => a + l.totalVal);
  double get _oc => _lines.where((l) => l.pcs > 0).fold(0, (a, l) => a + (l.totalVal - l.base));
  int get _count => _lines.where((l) => l.pcs > 0).length;

  Future<void> _save() async {
    final items = [
      for (final l in _lines)
        if (l.pcs > 0) {'product_id': int0(l.p['id']), 'pcs': l.pcs, 'total': l.totalVal}
    ];
    if (items.isEmpty) {
      toast(context, 'কমপক্ষে একটি পণ্য যোগ করুন।', error: true);
      return;
    }
    for (final l in _lines) {
      if (l.pcs > 0 && l.totalVal <= 0) {
        toast(context, '${l.p['name']}-এর মোট টাকা দিন।', error: true);
        return;
      }
    }
    final body = {
      'retailer_id': int0(widget.shop['id']),
      'items': items,
      'at': DateTime.now().millisecondsSinceEpoch ~/ 1000,
    };
    final r = await busy(context, () => _editing
        ? ApiClient.send('PUT', '/sr/orders/${widget.existing!['id']}', body: body).then((d) => WriteResult(data: d))
        : OfflineQueue.write('POST', '/sr/orders', body: body, label: '${widget.shop['name']}-এর অর্ডার'));
    if (r == null || !mounted) return;
    if (r.queued) {
      toast(context, 'ইন্টারনেট নেই — অর্ডার ফোনে সংরক্ষিত, নেট এলে পাঠানো হবে।');
    } else {
      final warnings = (r.data['warnings'] as List?)?.map((e) => '$e').toList() ?? [];
      toast(context, warnings.isEmpty ? (r.data['message'] ?? 'অর্ডার সংরক্ষিত হয়েছে।').toString() : warnings.join('\n'));
    }
    Navigator.pop(context, true);
  }

  Future<void> _cancel() async {
    if (!await confirm(context, 'অর্ডার বাতিল করবেন?', danger: true, yes: 'বাতিল করুন')) return;
    if (!mounted) return;
    final r = await busy(context, () => ApiClient.send('DELETE', '/sr/orders/${widget.existing!['id']}'));
    if (r != null && mounted) {
      toast(context, (r['message'] ?? 'বাতিল হয়েছে।').toString());
      Navigator.pop(context, true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final q = _q.trim().toLowerCase();
    final shown = _lines.where((l) => q.isEmpty || l.p['name'].toString().toLowerCase().contains(q)).toList();
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.shop['name'].toString(), overflow: TextOverflow.ellipsis),
        actions: [if (_editing && !_locked) IconButton(icon: const Icon(Icons.delete_outline, color: kDanger), onPressed: _cancel)],
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 4),
          child: TextField(
            controller: _search, onChanged: (v) => setState(() => _q = v),
            decoration: const InputDecoration(hintText: 'পণ্য খুঁজুন', prefixIcon: Icon(Icons.search), isDense: true),
          ),
        ),
        if (_locked)
          Container(
            width: double.infinity, margin: const EdgeInsets.all(14), padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: const Color(0xFFFEF3C7), borderRadius: BorderRadius.circular(10)),
            child: const Text('এই অর্ডার ট্রিপে চলে গেছে — আর পরিবর্তন করা যাবে না।'),
          ),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 12),
            itemCount: shown.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (_, i) => _row(shown[i]),
          ),
        ),
        SafeArea(
          top: false,
          child: Container(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
            decoration: const BoxDecoration(color: Colors.white, border: Border(top: BorderSide(color: kBorder))),
            child: Row(children: [
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                Text('${bn(_count)}টি পণ্য · ${money(_sum)}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                Text('O/C ${money(_oc)}', style: TextStyle(color: _oc < 0 ? kDanger : kOk, fontSize: 12.5)),
              ])),
              SizedBox(width: 150, child: FilledButton(onPressed: _locked ? null : _save, child: Text(_editing ? 'আপডেট' : 'সংরক্ষণ'))),
            ]),
          ),
        ),
      ]),
    );
  }

  Widget _row(_Line l) {
    final active = l.pcs > 0;
    final avail = int0(l.p['available_pcs']);
    return Card(
      color: active ? const Color(0xFFEFF4FF) : null,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            _thumb(l.p),
            const SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(l.p['name'].toString(), style: const TextStyle(fontWeight: FontWeight.w700)),
              Text('পিস ${money(l.rate)} · ${l.p['unit_type']} ${money(l.p['unit_price'])} · স্টক ${bn(avail)}', style: const TextStyle(color: kMuted, fontSize: 12)),
            ])),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            if (l.qpu > 1) ...[
              NumField(controller: l.unit, label: '${l.p['unit_type']}', dense: true, width: 74, onChanged: (_) => setState(l.autoTotal)),
              const SizedBox(width: 8),
            ],
            NumField(controller: l.loose, label: 'পিস', dense: true, width: 74, onChanged: (_) => setState(l.autoTotal)),
            const SizedBox(width: 8),
            Expanded(
              child: NumField(
                controller: l.total, label: 'মোট টাকা', decimal: true, dense: true,
                onChanged: (v) => setState(() => l.manualTotal = true),
              ),
            ),
          ]),
          if (active)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                '${bn(l.pcs)} পিস${l.pcs > avail ? ' · স্টকের চেয়ে বেশি!' : ''} · O/C ${money(l.totalVal - l.base)}',
                style: TextStyle(fontSize: 12, color: l.pcs > avail ? kWarn : kMuted),
              ),
            ),
        ]),
      ),
    );
  }

  Widget _thumb(Map<String, dynamic> p) {
    final url = ApiClient.asset(p['image']);
    return Container(
      width: 44, height: 44,
      decoration: BoxDecoration(color: _tint(p['tint']), borderRadius: BorderRadius.circular(10)),
      clipBehavior: Clip.antiAlias,
      child: NetImage(url, fallback: Center(child: Text((p['code'] ?? '').toString(), style: const TextStyle(fontWeight: FontWeight.w800)))),
    );
  }

  Color _tint(Object? hex) {
    final s = (hex ?? '').toString().replaceFirst('#', '');
    final v = int.tryParse(s.length == 6 ? 'FF$s' : s, radix: 16);
    return v == null ? const Color(0xFFF1F5F9) : Color(v);
  }
}
