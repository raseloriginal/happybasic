import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/api.dart';
import '../core/format.dart';
import '../core/offline.dart';
import '../ui/common.dart';
import 'delivery_page.dart' show statusBn, statusColor;

Map<String, dynamic> _m(Object? v) => Map<String, dynamic>.from((v ?? {}) as Map);

class _Item {
  _Item(Map<String, dynamic> j, bool pending)
      : productId = int0(j['product_id']),
        name = '${j['name']}',
        ordered = int0(j['ordered_qty']),
        stock = int0(j['stock']),
        srRate = num0(j['sr_rate']),
        baseRate = num0(j['base_rate']) {
    qty = pending ? (ordered < stock ? ordered : stock) : int0(j['qty']);
    ctl.text = '$qty';
  }
  final int productId;
  final String name;
  final int ordered, stock;
  final double srRate, baseRate;
  late int qty;
  final ctl = TextEditingController();

  void set(int v) {
    qty = v < 0 ? 0 : (v > stock ? stock : v);
    ctl.text = '$qty';
  }
}

class _Order {
  _Order(Map<String, dynamic> j, bool pending)
      : id = int0(j['id']),
        code = '${j['order_code']}',
        company = '${j['name']}',
        sr = '${j['sr']}',
        cancelled = j['cancelled'] == true,
        items = (j['items'] as List).map((e) => _Item(_m(e), pending)).toList();
  final int id;
  final String code, company, sr;
  bool cancelled;
  final List<_Item> items;
  double get gross => cancelled ? 0 : items.fold(0, (a, i) => a + i.qty * i.srRate);
}

/// One shop's delivery: delivered pieces per product, cancel with a reason, payment.
class StopPage extends StatefulWidget {
  const StopPage({super.key, required this.stop, required this.reasons, required this.editable, required this.damageProducts});
  final Map<String, dynamic> stop;
  final List<String> reasons;
  final bool editable;
  final List<Map<String, dynamic>> damageProducts;
  @override
  State<StopPage> createState() => _StopPageState();
}

class _StopPageState extends State<StopPage> {
  late final List<_Order> _orders;
  late final List<Map<String, dynamic>> _damages;
  final _paid = TextEditingController();
  String _cancelReason = '';

  Map<String, dynamic> get _s => widget.stop;
  bool get _pending => _s['status'] == 'Pending';
  bool get _can => widget.editable && _s['editable'] != false;
  double get _oldDue => num0(_s['existing_due']);

  @override
  void initState() {
    super.initState();
    _orders = (_s['companies'] as List).map(_m).where((c) => c['ready_sale'] != true).map((c) => _Order(c, _pending)).toList();
    _damages = (_s['damages'] as List?)?.map(_m).toList() ?? [];
    _cancelReason = '${_s['cancel_reason'] ?? ''}';
    final shouldPay = _shouldPay;
    _paid.text = _pending ? _fmt(shouldPay) : _fmt(num0(_s['paid_amount']) + num0(_s['old_due_collected']));
  }

  static String _fmt(double v) => v == v.roundToDouble() ? v.round().toString() : v.toStringAsFixed(2);

  double get _gross => _orders.fold(0, (a, o) => a + o.gross);
  double get _damage => _damages.fold(0, (a, d) => a + num0(d['amount']));
  double get _shouldPay => (_gross - _damage).clamp(0, double.infinity);
  double get _cap => _shouldPay + _oldDue;
  double get _paidVal => (double.tryParse(_paid.text) ?? 0).clamp(0, _cap).toDouble();

  Future<void> _cancelOrder(_Order o) async {
    final picked = await _reasonDialog();
    if (picked == null) return;
    setState(() {
      o.cancelled = true;
      for (final i in o.items) {
        i.set(0);
      }
      _cancelReason = picked;
      _paid.text = _fmt(_shouldPay);
    });
  }

  Future<String?> _reasonDialog() async {
    String chosen = widget.reasons.first;
    final note = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => AlertDialog(
          title: const Text('বাতিলের কারণ'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              RadioGroup<String>(
                groupValue: chosen,
                onChanged: (v) => set(() => chosen = v!),
                child: Column(children: [for (final r in widget.reasons) RadioListTile<String>(dense: true, value: r, title: Text(r, style: const TextStyle(fontSize: 14)))]),
              ),
              TextField(controller: note, decoration: const InputDecoration(hintText: 'নোট (ঐচ্ছিক)', isDense: true)),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c), child: const Text('বাতিল')),
            FilledButton(
              style: FilledButton.styleFrom(minimumSize: const Size(90, 42)),
              onPressed: () => Navigator.pop(c, note.text.trim().isEmpty ? chosen : '$chosen (${note.text.trim()})'),
              child: const Text('নিশ্চিত'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _save() async {
    final paid = _paidVal;
    final forBill = paid < _shouldPay ? paid : _shouldPay;
    final due = _shouldPay - forBill;
    final oldCollected = paid - forBill;
    final ok = await confirm(
      context, 'ডেলিভারি সংরক্ষণ করবেন?',
      body: 'বিল ${money(_shouldPay)} · আদায় ${money(paid)}'
          '${oldCollected > 0 ? ' (পুরনো বাকি ${money(oldCollected)} সহ)' : ''}'
          '${due > 0 ? '\nনতুন বাকি ${money(due)}' : ''}',
      yes: 'সংরক্ষণ');
    if (!ok || !mounted) return;

    final body = {
      'orders': [
        for (final o in _orders)
          {
            'id': o.id,
            'cancelled': o.cancelled,
            'items': [for (final i in o.items) {'product_id': i.productId, 'pcs': o.cancelled ? 0 : i.qty}],
          }
      ],
      'damages': [
        for (final d in _damages)
          if (!_orders.any((o) => o.cancelled && o.id == int0(d['order_id'])))
            {'order_id': int0(d['order_id']), 'product_id': int0(d['product_id']), 'pcs': int0(d['pcs'])}
      ],
      'paid': paid,
      'cancel_reason': _orders.any((o) => o.cancelled) ? _cancelReason : '',
    };
    final r = await busy(context, () => OfflineQueue.write('POST', '/dsr/stops/${_s['id']}', body: body, label: '${_s['retailer_name']}-এর ডেলিভারি'));
    if (r != null && mounted) {
      toast(context, r.queued ? 'ইন্টারনেট নেই — ফোনে সংরক্ষিত, নেট এলে পাঠানো হবে।' : (r.data['message'] ?? 'ডেলিভারি সংরক্ষিত হয়েছে।').toString());
      Navigator.pop(context, true);
    }
  }

  Future<void> _reset() async {
    if (!await confirm(context, 'ডেলিভারি পূর্বাবস্থায় নেবেন?', body: 'দোকানটি আবার "বাকি আছে" তালিকায় যাবে।', yes: 'হ্যাঁ', danger: true)) return;
    if (!mounted) return;
    final r = await busy(context, () => ApiClient.send('POST', '/dsr/stops/${_s['id']}/reset', opId: ApiClient.newOpId()));
    if (r != null && mounted) {
      toast(context, (r['message'] ?? 'হয়েছে।').toString());
      Navigator.pop(context, true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = '${_s['status']}';
    return Scaffold(
      appBar: AppBar(
        title: Text('${_s['retailer_name']}', overflow: TextOverflow.ellipsis),
        actions: [
          if ('${_s['phone']}'.isNotEmpty) IconButton(icon: const Icon(Icons.call), onPressed: () => launchUrl(Uri.parse('tel:${_s['phone']}'))),
          if (num0(_s['lat']) != 0)
            IconButton(icon: const Icon(Icons.navigation_outlined), onPressed: () => launchUrl(Uri.parse('google.navigation:q=${_s['lat']},${_s['lng']}'), mode: LaunchMode.externalApplication)),
        ],
      ),
      body: Column(children: [
        Expanded(
          child: ListView(padding: const EdgeInsets.all(14), children: [
            Row(children: [
              Pill(statusBn(status), color: statusColor(status)),
              const SizedBox(width: 8),
              if ('${_s['address']}'.isNotEmpty) Expanded(child: Text('${_s['address']}', style: const TextStyle(color: kMuted, fontSize: 13), overflow: TextOverflow.ellipsis)),
            ]),
            if (_oldDue > 0)
              Container(
                margin: const EdgeInsets.only(top: 10), padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: const Color(0xFFFEF3C7), borderRadius: BorderRadius.circular(12)),
                child: Row(children: [
                  const Icon(Icons.warning_amber, color: kWarn),
                  const SizedBox(width: 8),
                  Expanded(child: Text('এই দোকানের পুরনো বাকি ${money(_oldDue)} — টাকা দিলে আদায় করতে পারবেন।')),
                ]),
              ),
            for (final o in _orders) _orderCard(o),
            if (_damages.isNotEmpty) ...[
              const SectionTitle('ড্যামেজ (বিল থেকে বাদ)'),
              for (final d in _damages)
                Card(child: ListTile(dense: true, title: Text('${d['name'] ?? d['product'] ?? 'পণ্য'}'), subtitle: Text('${bn(d['pcs'])} পিস'), trailing: Text('-${money(d['amount'])}', style: const TextStyle(color: kDanger, fontWeight: FontWeight.w700)))),
            ],
            const SizedBox(height: 10),
            if (_can && !_pending)
              TextButton.icon(onPressed: _reset, icon: const Icon(Icons.undo, color: kDanger), label: const Text('পূর্বাবস্থায় নিন', style: TextStyle(color: kDanger))),
            const SizedBox(height: 120),
          ]),
        ),
        if (_can) _footer(),
      ]),
    );
  }

  Widget _orderCard(_Order o) {
    return Card(
      margin: const EdgeInsets.only(top: 12),
      color: o.cancelled ? const Color(0xFFF1F5F9) : null,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text('${o.company} · SR ${o.sr}', style: const TextStyle(fontWeight: FontWeight.w800))),
            if (o.cancelled) const Pill('বাতিল', color: kDanger),
          ]),
          Text(o.code, style: const TextStyle(color: kMuted, fontSize: 12)),
          const SizedBox(height: 6),
          if (!o.cancelled)
            for (final i in o.items)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(children: [
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(i.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                    Text('অর্ডার ${bn(i.ordered)} · ভ্যানে ${bn(i.stock)} · ${money(i.srRate)}', style: const TextStyle(color: kMuted, fontSize: 12)),
                  ])),
                  if (_can) ...[
                    IconButton(visualDensity: VisualDensity.compact, icon: const Icon(Icons.remove_circle_outline), onPressed: () => setState(() { i.set(i.qty - 1); _paid.text = _fmt(_shouldPay); })),
                    SizedBox(
                      width: 52,
                      child: NumField(controller: i.ctl, dense: true, onChanged: (v) => setState(() { i.qty = (int.tryParse(v) ?? 0).clamp(0, i.stock); _paid.text = _fmt(_shouldPay); })),
                    ),
                    IconButton(visualDensity: VisualDensity.compact, icon: const Icon(Icons.add_circle_outline, color: kBlue), onPressed: () {
                      if (i.qty >= i.stock) toast(context, 'ভ্যানে ${i.name}-এর মাত্র ${bn(i.stock)} পিস আছে।', error: true);
                      setState(() { i.set(i.qty + 1); _paid.text = _fmt(_shouldPay); });
                    }),
                  ] else
                    Text('${bn(i.qty)} পিস', style: const TextStyle(fontWeight: FontWeight.w700)),
                ]),
              ),
          if (o.cancelled && _cancelReason.isNotEmpty) Text(_cancelReason, style: const TextStyle(color: kDanger, fontSize: 13)),
          if (_can)
            Align(
              alignment: Alignment.centerRight,
              child: o.cancelled
                  ? TextButton(onPressed: () => setState(() { o.cancelled = false; for (final i in o.items) { i.set(i.ordered < i.stock ? i.ordered : i.stock); } _paid.text = _fmt(_shouldPay); }), child: const Text('বাতিল ফিরিয়ে আনুন'))
                  : TextButton(onPressed: () => _cancelOrder(o), child: const Text('এই অর্ডার বাতিল', style: TextStyle(color: kDanger))),
            ),
        ]),
      ),
    );
  }

  Widget _footer() {
    final paid = _paidVal;
    final forBill = paid < _shouldPay ? paid : _shouldPay;
    final due = _shouldPay - forBill;
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
        decoration: const BoxDecoration(color: Colors.white, border: Border(top: BorderSide(color: kBorder))),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Row(children: [
            Expanded(child: Text('বিল ${money(_shouldPay)}${_damage > 0 ? ' (ড্যামেজ বাদে)' : ''}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16))),
            if (due > 0) Text('বাকি ${money(due)}', style: const TextStyle(color: kDanger, fontWeight: FontWeight.w700)),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: NumField(controller: _paid, label: 'আদায় (সর্বোচ্চ ${money(_cap)})', decimal: true, dense: true, onChanged: (_) => setState(() {}))),
            const SizedBox(width: 10),
            SizedBox(width: 130, child: FilledButton(onPressed: _save, child: const Text('সংরক্ষণ'))),
          ]),
        ]),
      ),
    );
  }
}
