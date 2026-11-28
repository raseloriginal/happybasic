import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/api.dart';
import '../core/format.dart';
import '../core/offline.dart';
import '../core/session.dart';
import '../ui/common.dart';
import '../ui/hkit.dart';
import '../ui/motion.dart';
import '../ui/pwa_kit.dart';
import 'damage_page.dart';
import 'delivery_page.dart' show statusBn;

Map<String, dynamic> _m(Object? v) => Map<String, dynamic>.from((v ?? {}) as Map);

String _fmt(double v) => v == v.roundToDouble() ? v.round().toString() : v.toStringAsFixed(2);

class _Item {
  _Item(Map<String, dynamic> j, bool pending)
      : productId = int0(j['product_id']),
        name = '${j['name']}',
        ordered = int0(j['ordered_qty']),
        stock = int0(j['stock']),
        srRate = num0(j['sr_rate']),
        baseRate = num0(j['base_rate']) {
    qty = pending ? full : int0(j['qty']);
  }
  final int productId;
  final String name;
  final int ordered, stock;
  final double srRate, baseRate;
  late int qty;
  int get full => ordered < stock ? ordered : stock;
  void set(int v) => qty = v < 0 ? 0 : (v > stock ? stock : v);
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
  double get orderedValue => items.fold(0, (a, i) => a + i.ordered * i.srRate);
}

/// DMD — one shop's delivery: pieces per product, "সব দিলাম", damage, cancel with a reason, then the payment sheet.
/// Saving shows DM4 (delivered + undo); works offline through the queue.
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
  }

  double get _gross => _orders.fold(0, (a, o) => a + o.gross);
  double get _ordered => _orders.fold(0, (a, o) => a + o.orderedValue);
  double get _damage => _damages.fold(0, (a, d) => a + num0(d['amount']));
  double get _shouldPay => (_gross - _damage).clamp(0, double.infinity).toDouble();
  double get _over => _orders.fold(0, (a, o) => a + (o.cancelled ? 0 : o.items.fold<double>(0, (b, i) => b + i.qty * (i.srRate - i.baseRate))));

  void _all() {
    HapticFeedback.mediumImpact();
    setState(() {
      for (final o in _orders) {
        o.cancelled = false;
        for (final i in o.items) {
          i.qty = i.full;
        }
      }
    });
  }

  Future<void> _cancelOrder(_Order o) async {
    final picked = await _reasonSheet();
    if (picked == null) return;
    setState(() {
      o.cancelled = true;
      for (final i in o.items) {
        i.set(0);
      }
      _cancelReason = picked;
    });
  }

  Future<String?> _reasonSheet({String title = 'পুরো অর্ডার বাতিল করবেন?', String hint = 'কারণ বাছুন — দোকান ও SR দেখতে পাবে।', String yes = 'হ্যাঁ, বাতিল', String no = 'না', bool danger = true}) {
    var chosen = widget.reasons.isEmpty ? 'অন্যান্য' : widget.reasons.first;
    final note = TextEditingController();
    return showHSheet<String>(context, builder: (c) => StatefulBuilder(
      builder: (c, set) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        Text(title, style: hs(18, w: w8)),
        Text(hint, style: hs(12.5, color: HC.muted)),
        gap12,
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final r in widget.reasons)
            GestureDetector(
              onTap: () => set(() => chosen = r),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(color: chosen == r ? HC.ink : Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: chosen == r ? HC.ink : HC.line)),
                child: Text(cancelReasonBn(r), style: hs(13.5, w: w6, color: chosen == r ? Colors.white : HC.ink)),
              ),
            ),
        ]),
        gap12,
        TextField(controller: note, style: hs(14), decoration: InputDecoration(hintText: 'নোট (ঐচ্ছিক)', hintStyle: hs(14, color: HC.faint), filled: true, fillColor: HC.bg, border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none))),
        gap16,
        Row(children: [
          Expanded(child: HBtn(no, kind: HBtnKind.line, onTap: () => Navigator.pop(c, danger ? null : ''))),
          const SizedBox(width: 10),
          Expanded(child: HBtn(yes, kind: danger ? HBtnKind.danger : HBtnKind.dark, onTap: () => Navigator.pop(c, note.text.trim().isEmpty ? chosen : '$chosen (${note.text.trim()})'))),
        ]),
      ]),
    ));
  }

  Future<void> _pay() async {
    // Took less than ordered (not cancelled): ask why, so the SR and the report know.
    var shortReason = '';
    final short = _orders.any((o) => !o.cancelled && o.items.any((i) => i.qty < i.ordered));
    if (short && _can) {
      final r = await _reasonSheet(title: 'কম নিল কেন?', hint: 'কারণ বাছুন — SR ও রিপোর্টে দেখা যাবে।', yes: 'ঠিক আছে', no: 'এড়িয়ে যান', danger: false);
      if (r == null || !mounted) return;
      shortReason = r;
    }
    final paid = await showHSheet<double>(context, builder: (_) => _PaySheet(name: '${_s['retailer_name']}', bill: _shouldPay, oldDue: _oldDue, initial: _pending ? _shouldPay : num0(_s['paid_amount']) + num0(_s['old_due_collected'])));
    if (paid == null || !mounted) return;
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
      'short_reason': shortReason,
    };
    final r = await busy(context, () => OfflineQueue.write('POST', '/dsr/stops/${_s['id']}', body: body, label: '${_s['retailer_name']}-এর ডেলিভারি'));
    if (r == null || !mounted) return;
    HapticFeedback.heavyImpact();
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => _DeliveredPage(
          stop: _s, orders: _orders, paid: paid, queued: r.queued,
          invoice: () => _invoice(paid),
        )));
    if (mounted) Navigator.pop(context, true);
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

  /// DM7 — what was ordered vs. taken and the cash.
  void _invoice(double paid) => showHSheet(context, builder: (_) => _InvoiceSheet(stop: _s, orders: _orders, paid: paid));

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.of(context).padding.top;
    final status = '${_s['status']}';
    final phone = '${_s['phone'] ?? ''}';
    return SkyStatusBar(
      child: Scaffold(
        backgroundColor: HC.bg,
        body: Column(children: [
          Expanded(
            child: ListView(padding: EdgeInsets.fromLTRB(18, top + 14, 18, 20), children: [
              SkyBox(
                height: 150,
                child: SkyHead(
                  leading: const SkyBack(),
                  kicker: _pending ? 'দোকানে ডেলিভারি' : 'সংরক্ষিত · ${statusBn(status)}',
                  title: '${_s['retailer_name']}',
                  trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                    GlassBtn(icon: Ic.doc, label: 'ডেলিভারি স্লিপ', onTap: () => showHSheet<void>(context, builder: (_) => _SlipSheet(
                          stop: _s, orders: _orders, paid: _pending ? 0 : num0(_s['paid_amount']) + num0(_s['old_due_collected']), bill: _shouldPay, over: _over))),
                    const SizedBox(width: 8),
                    if (phone.isNotEmpty) GlassBtn(icon: '<path d="M22 16.9v3a2 2 0 0 1-2.2 2 19.8 19.8 0 0 1-8.6-3.1 19.5 19.5 0 0 1-6-6A19.8 19.8 0 0 1 2.1 4.2 2 2 0 0 1 4.1 2h3a2 2 0 0 1 2 1.7c.1.9.4 1.8.7 2.7a2 2 0 0 1-.5 2.1L8 9.8a16 16 0 0 0 6 6l1.3-1.3a2 2 0 0 1 2.1-.4c.9.3 1.8.6 2.7.7a2 2 0 0 1 1.7 2z"/>', label: 'কল করুন', onTap: () => launchUrl(Uri.parse('tel:$phone'))),
                    if (num0(_s['lat']) != 0) ...[
                      const SizedBox(width: 8),
                      GlassBtn(icon: '<path d="m3 11 19-9-9 19-2-8-8-2z"/>', label: 'পথ দেখান', onTap: () => launchUrl(Uri.parse('google.navigation:q=${_s['lat']},${_s['lng']}'), mode: LaunchMode.externalApplication)),
                    ],
                  ]),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Text([
                    if ('${_s['address'] ?? ''}'.isNotEmpty) '${_s['address']}',
                    if (_orders.isNotEmpty) 'SR: ${_orders.map((o) => o.sr).toSet().join(', ')}',
                  ].join(' · '), maxLines: 1, overflow: TextOverflow.ellipsis, style: hs(12.5, color: HC.onSky)),
                  const SizedBox(height: 14),
                  if (!_pending && _can)
                    HCard(
                      radius: 18, padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      child: Row(children: [
                        Expanded(child: Text('সংরক্ষিত · ${statusBn(status)}', style: hs(13.5, w: w6))),
                        HBtn('পূর্বাবস্থায় নিন', icon: '<path d="M9 14 4 9l5-5"/><path d="M4 9h10.5a5.5 5.5 0 0 1 0 11H11"/>', kind: HBtnKind.danger, expand: false, height: 38, radius: 12, fontSize: 12.5, onTap: _reset),
                      ]),
                    ),
                  if (_oldDue > 0) ...[
                    gap8,
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                      decoration: BoxDecoration(color: HC.redSoft, borderRadius: BorderRadius.circular(16)),
                      child: Text('আগের বাকি ${tk(_oldDue)} — টাকা দিলে আদায় হবে।', style: hs(13, w: w6, color: HC.red)),
                    ),
                  ],
                  if (_can) ...[
                    gap12,
                    Row(children: [
                      Expanded(child: HBtn('✓ সব দিলাম', kind: HBtnKind.blue, height: 50, onTap: _all)),
                      if (widget.damageProducts.isNotEmpty) ...[
                        const SizedBox(width: 10),
                        Expanded(child: HBtn('+ ড্যামেজ সংগ্রহ', kind: HBtnKind.line, height: 50, onTap: () => Navigator.of(context)
                            .push<bool>(MaterialPageRoute(builder: (_) => DamagePage(products: widget.damageProducts, stops: [_s], selectedId: int0(_s['id']))))
                            .then((v) => v == true && mounted ? Navigator.pop(context, true) : null))),
                      ],
                    ]),
                  ],
                  for (final o in _orders) ...[gap12, _orderCard(o)],
                  if (_damages.isNotEmpty) ...[
                    gap12,
                    HCard(radius: 20, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      Row(children: [
                        Expanded(child: Text('ড্যামেজ সংগ্রহ', style: hs(14.5, w: w7))),
                        Text('−${tk(_damage)}', style: hs(14.5, w: w8, color: HC.red, num: true)),
                      ]),
                      Text('নষ্ট মাল ভ্যানে নিন · বিল থেকে নিজে বাদ যাবে', style: hs(12, color: HC.muted)),
                      for (final d in _damages)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Row(children: [
                            Expanded(child: Text('${d['name'] ?? d['product'] ?? 'পণ্য'}', style: hs(13.5, w: w6))),
                            Text('${bn(d['pcs'])} পিস · ${tk(d['amount'])}', style: hs(12.5, color: HC.ink2, num: true)),
                          ]),
                        ),
                    ])),
                  ],
                  gap12,
                  HStrip([
                    HStat('অর্ডার', tk(_ordered)),
                    HStat('ডেলিভারি ওভার', sMoney(_over), color: _over > 0.009 ? HC.blue : (_over < -0.009 ? HC.red : HC.ink)),
                    HStat('প্রদেয় বিল', tk(_shouldPay)),
                  ]),
                ]),
              ),
            ]),
          ),
          if (_can)
            Container(
              padding: EdgeInsets.fromLTRB(14, 10, 14, 12 + MediaQuery.of(context).padding.bottom),
              color: HC.bg,
              child: Container(
                padding: const EdgeInsets.fromLTRB(16, 10, 10, 10),
                decoration: BoxDecoration(color: HC.ink, borderRadius: BorderRadius.circular(22), boxShadow: HC.lift),
                child: Row(children: [
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                    Text('প্রদেয় বিল', style: hs(12, color: HC.onDark)),
                    Text(tk(_shouldPay), style: hs(20, w: w8, color: Colors.white, num: true, h: 1.2)),
                  ])),
                  HBtn(_pending ? 'ডেলিভারি শেষ · পরের ধাপ' : 'আপডেট · টাকা', kind: HBtnKind.white, expand: false, height: 48, radius: 15, fontSize: 13.5, trailingIcon: '<path d="M5 12h14M13 6l6 6-6 6"/>', onTap: _pay),
                ]),
              ),
            ),
        ]),
      ),
    );
  }

  void _restore(_Order o) => setState(() {
        HapticFeedback.selectionClick();
        o.cancelled = false;
        for (final i in o.items) {
          i.qty = i.full;
        }
      });

  /// One company's order (DMD): name, its amount, a round ✕ to cancel it (↺ brings it back), then its lines.
  Widget _orderCard(_Order o) {
    final cancelled = o.cancelled;
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 260),
      opacity: cancelled ? .55 : 1,
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 2),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20),
            boxShadow: const [BoxShadow(color: Color(0x0F0A1640), blurRadius: 18, offset: Offset(0, 6))]),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
            padding: const EdgeInsets.only(top: 2, bottom: 8),
            child: Row(children: [
              Expanded(child: Text(o.company, maxLines: 1, overflow: TextOverflow.ellipsis, style: hs(15, w: w7))),
              ConstrainedBox(
                constraints: const BoxConstraints(minWidth: 64),
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  child: Text(tk(o.gross), key: ValueKey(o.gross), textAlign: TextAlign.right, style: hs(15, w: w7, num: true)),
                ),
              ),
              if (_can) ...[
                const SizedBox(width: 8),
                Semantics(
                  button: true, label: cancelled ? 'আবার নিন' : 'এই কোম্পানি বাতিল',
                  child: Pressable(
                    scale: .9,
                    child: GestureDetector(
                      onTap: cancelled ? () => _restore(o) : () => _cancelOrder(o),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        width: 30, height: 30, alignment: Alignment.center,
                        decoration: BoxDecoration(color: cancelled ? HC.soft : HC.redSoft, shape: BoxShape.circle),
                        child: Text(cancelled ? '↺' : '✕', style: hs(13, w: w8, color: cancelled ? HC.blue : HC.red, h: 1)),
                      ),
                    ),
                  ),
                ),
              ],
            ]),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 300), curve: kEase, alignment: Alignment.topCenter,
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              if (!cancelled)
                for (final i in o.items)
                  Container(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    decoration: const BoxDecoration(border: Border(top: BorderSide(color: Color(0xFFEEF0F5)))),
                    child: Row(children: [
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(i.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: hs(13.5, w: w6)),
                        Text('অর্ডার ${bn(i.ordered)} · ${tk(i.srRate)}${i.stock < i.ordered ? ' · ভ্যানে ${bn(i.stock)}' : ''}',
                            style: hs(11.5, color: i.stock < i.ordered ? HC.red : HC.muted, num: true)),
                        if (i.qty < i.ordered)
                          Text(i.qty == 0 ? 'কিছুই নেয়নি' : '${bn(i.ordered - i.qty)} পিস কম', style: hs(11.5, w: w7, color: HC.red)),
                      ])),
                      if (_can) _qty(i) else Text('${bn(i.qty)} পিস', style: hs(13.5, w: w7, num: true)),
                    ]),
                  )
              else
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: const BoxDecoration(border: Border(top: BorderSide(color: Color(0xFFEEF0F5)))),
                  child: Text(_cancelReason.isEmpty ? 'বাতিল' : 'বাতিল · $_cancelReason', style: hs(12.5, w: w6, color: HC.red)),
                ),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _qty(_Item i) {
    Widget b(String t, bool plus) => Semantics(
          button: true, label: plus ? 'বাড়ান' : 'কমান',
          child: GestureDetector(
            onTap: () {
              if (plus && i.qty >= i.stock) {
                toast(context, 'ভ্যানে ${i.name}-এর মাত্র ${bn(i.stock)} পিস আছে।', error: true);
                return;
              }
              HapticFeedback.selectionClick();
              setState(() => i.set(i.qty + (plus ? 1 : -1)));
            },
            child: Container(
              width: 36, height: 36, alignment: Alignment.center,
              decoration: BoxDecoration(color: plus ? HC.ink : Colors.white, borderRadius: BorderRadius.circular(11), border: plus ? null : Border.all(color: HC.line2)),
              child: Text(t, style: hs(19, color: plus ? Colors.white : HC.ink, h: 1)),
            ),
          ),
        );
    return Row(mainAxisSize: MainAxisSize.min, children: [
      b('−', false),
      GestureDetector(
        onTap: () async {
          final v = await askNumber(context, i.name, i.qty);
          if (v != null && mounted) setState(() => i.set(v));
        },
        child: SizedBox(width: 40, child: Text(bn(i.qty), textAlign: TextAlign.center, style: hs(16, w: w8, num: true))),
      ),
      b('+', true),
    ]);
  }
}

/// টাকা গ্রহণ — received cash, quick full / zero, bill + old due split, new due.
class _PaySheet extends StatefulWidget {
  const _PaySheet({required this.name, required this.bill, required this.oldDue, required this.initial});
  final String name;
  final double bill, oldDue, initial;
  @override
  State<_PaySheet> createState() => _PaySheetState();
}

class _PaySheetState extends State<_PaySheet> {
  late final _c = TextEditingController(text: _fmt(widget.initial.clamp(0, widget.bill + widget.oldDue).toDouble()));

  double get _cap => widget.bill + widget.oldDue;
  double get _paid => (double.tryParse(_c.text) ?? 0).clamp(0, _cap).toDouble();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _set(double v) => setState(() => _c.text = _fmt(v));

  @override
  Widget build(BuildContext context) {
    final paid = _paid;
    final forBill = paid < widget.bill ? paid : widget.bill;
    final oldCollected = paid - forBill;
    final newDue = widget.bill - forBill;
    final over = (double.tryParse(_c.text) ?? 0) > _cap + 0.009;
    Widget quick(String t, double v) => Expanded(
          child: GestureDetector(
            onTap: () => _set(v),
            child: Container(
              height: 44, alignment: Alignment.center,
              decoration: BoxDecoration(color: (paid - v).abs() < 0.01 ? HC.soft : HC.bg, borderRadius: BorderRadius.circular(14), border: Border.all(color: (paid - v).abs() < 0.01 ? HC.blue : Colors.transparent)),
              child: Text(t, maxLines: 1, overflow: TextOverflow.ellipsis, style: hs(12.5, w: w7, color: (paid - v).abs() < 0.01 ? HC.blue : HC.ink2, num: true)),
            ),
          ),
        );
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      Row(children: [
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('টাকা গ্রহণ', style: hs(18, w: w8)),
          Text(widget.name, style: hs(12.5, color: HC.muted)),
        ])),
        Semantics(button: true, label: 'বন্ধ করুন', child: GestureDetector(
          onTap: () => Navigator.pop(context),
          child: Container(width: 40, height: 40, decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: HC.line)),
              child: const Center(child: Svg('<path d="M18 6 6 18M6 6l12 12"/>', size: 16, color: HC.ink, stroke: 2.2))),
        )),
      ]),
      gap16,
      Text('প্রাপ্ত টাকা', style: hs(13, w: w6, color: HC.ink2)),
      const SizedBox(height: 6),
      TextField(
        controller: _c, autofocus: false, onChanged: (_) => setState(() {}),
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
        style: hs(28, w: w8, num: true),
        decoration: InputDecoration(
          prefixText: '৳ ', prefixStyle: hs(22, w: w7, color: HC.muted), filled: true, fillColor: HC.bg,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: BorderSide.none),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: const BorderSide(color: HC.blue, width: 1.5)),
        ),
      ),
      if (over) Padding(padding: const EdgeInsets.only(top: 6), child: Text('সর্বোচ্চ ${tk(_cap)} নেওয়া যাবে।', style: hs(12, w: w6, color: HC.red))),
      gap8,
      Row(children: [
        quick('পুরো বাকি · ৳০', 0),
        const SizedBox(width: 8),
        quick('পুরো পেমেন্ট · ${tk(widget.bill)}', widget.bill),
        if (widget.oldDue > 0) ...[const SizedBox(width: 8), quick('আগের বাকিসহ · ${tk(_cap)}', _cap)],
      ]),
      gap16,
      HCard(radius: 18, color: HC.bg, border: false, child: Column(children: [
        HKv('মোট প্রদেয় বিল', tk(widget.bill)),
        const SizedBox(height: 6),
        HKv('আগের বাকি আদায়', tk(oldCollected), bold: false),
        const SizedBox(height: 6),
        HKv('মোট জমা', tk(paid)),
        const SizedBox(height: 6),
        HKv('নতুন বাকি', tk(newDue), valueColor: newDue > 0.009 ? HC.red : HC.ink),
      ])),
      if (newDue > 0.009) Padding(padding: const EdgeInsets.only(top: 8), child: Text('বাকি ${tk(newDue)} দোকানের হিসাবে যোগ হবে।', style: hs(12, color: HC.muted))),
      gap16,
      Row(children: [
        Expanded(flex: 10, child: HBtn('বাতিল', kind: HBtnKind.line, onTap: () => Navigator.pop(context))),
        const SizedBox(width: 10),
        Expanded(flex: 16, child: HBtn('নিশ্চিত করুন', onTap: () => Navigator.pop(context, paid))),
      ]),
    ]);
  }
}

/// DM4 — delivered: what was handed over, cash received, a short undo window.
class _DeliveredPage extends StatefulWidget {
  const _DeliveredPage({required this.stop, required this.orders, required this.paid, required this.queued, required this.invoice});
  final Map<String, dynamic> stop;
  final List<_Order> orders;
  final double paid;
  final bool queued;
  final VoidCallback invoice;
  @override
  State<_DeliveredPage> createState() => _DeliveredPageState();
}

class _DeliveredPageState extends State<_DeliveredPage> {
  static const _window = 300;
  int _left = _window;
  Timer? _t;

  @override
  void initState() {
    super.initState();
    if (!widget.queued) {
      _t = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
        setState(() => _left--);
        if (_left <= 0) _t?.cancel();
      });
    }
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  Future<void> _undo() async {
    final r = await busy(context, () => ApiClient.send('POST', '/dsr/stops/${widget.stop['id']}/reset', opId: ApiClient.newOpId()));
    if (r != null && mounted) {
      toast(context, (r['message'] ?? 'পূর্বাবস্থায় নেওয়া হয়েছে।').toString());
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.of(context).padding.top;
    final lines = [for (final o in widget.orders) if (!o.cancelled) for (final i in o.items) if (i.qty > 0) i];
    final allCancelled = widget.orders.every((o) => o.cancelled);
    final mm = (_left ~/ 60), ss = (_left % 60).toString().padLeft(2, '0');
    return SkyStatusBar(
      child: Scaffold(
        backgroundColor: HC.bg,
        body: Column(children: [
          Expanded(
            child: ListView(padding: EdgeInsets.fromLTRB(18, top + 14, 18, 16), children: [
              SkyBox(
                height: 230,
                child: Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Column(children: [
                    Container(
                      width: 68, height: 68, decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle, boxShadow: HC.liftSm),
                      child: Center(child: Svg(widget.queued ? '<circle cx="12" cy="12" r="9"/><path d="M12 7v5l3 2"/>' : (allCancelled ? '<path d="M18 6 6 18M6 6l12 12"/>' : '<polyline points="20 6 9 17 4 12"/>'), size: 30, color: allCancelled ? HC.red : HC.blue, stroke: 3)),
                    ),
                    const SizedBox(height: 14),
                    Text(widget.queued ? 'ফোনে সংরক্ষিত' : (allCancelled ? 'অর্ডার বাতিল হয়েছে' : 'ডেলিভারি হয়েছে'), style: hs(22, w: w8, color: Colors.white)),
                    const SizedBox(height: 4),
                    Text('${widget.stop['retailer_name']} · ${widget.queued ? 'নেট এলে পাঠানো হবে' : 'এইমাত্র'}', style: hs(13, color: HC.onSky)),
                  ]),
                ),
              ),
              const SizedBox(height: 22),
              HCard(lift: true, radius: 24, padding: const EdgeInsets.fromLTRB(16, 6, 16, 16), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                if (lines.isEmpty)
                  Padding(padding: const EdgeInsets.symmetric(vertical: 14), child: Text('কোনো মাল দেওয়া হয়নি।', style: hs(13.5, color: HC.muted)))
                else
                  for (var k = 0; k < lines.length; k++) ...[
                    if (k > 0) const Divider(height: 1, color: HC.line),
                    HItemRow(name: lines[k].name, sub: '× ${bn(lines[k].qty)}', amount: tk(lines[k].qty * lines[k].srRate), soft: true),
                  ],
                const HDashed(),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(child: Text('নগদ পেয়েছি', style: hs(14, w: w6, color: HC.ink2))),
                  Text(tk(widget.paid), style: hs(24, w: w8, num: true)),
                ]),
              ])),
              if (!widget.queued && _left > 0) ...[
                gap12,
                HCard(
                  radius: 18, onTap: _undo, padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  child: Row(children: [
                    Container(width: 36, height: 36, decoration: const BoxDecoration(color: HC.redSoft, shape: BoxShape.circle), child: const Center(child: Svg('<path d="M9 14 4 9l5-5"/><path d="M4 9h10.5a5.5 5.5 0 0 1 0 11H11"/>', size: 17, color: HC.red, stroke: 2.2))),
                    const SizedBox(width: 12),
                    Expanded(child: Text('ভুল হয়েছে? Undo করুন', style: hs(14, w: w6))),
                    Text('${bn(mm)}:${bn(ss)} বাকি', style: hs(12.5, w: w6, color: HC.muted, num: true)),
                  ]),
                ),
              ],
            ]),
          ),
          Container(
            padding: EdgeInsets.fromLTRB(18, 10, 18, 12 + MediaQuery.of(context).padding.bottom),
            color: HC.bg,
            child: Row(children: [
              Expanded(flex: 10, child: HBtn('ইনভয়েস', kind: HBtnKind.line, height: 52, onTap: widget.invoice)),
              const SizedBox(width: 10),
              Expanded(flex: 14, child: HBtn('পরের দোকান', height: 52, trailingIcon: '<path d="M5 12h14M13 6l6 6-6 6"/>', onTap: () => Navigator.pop(context))),
            ]),
          ),
        ]),
      ),
    );
  }
}

/// DM7 — ordered vs. taken per product, and the cash.
class _InvoiceSheet extends StatelessWidget {
  const _InvoiceSheet({required this.stop, required this.orders, required this.paid});
  final Map<String, dynamic> stop;
  final List<_Order> orders;
  final double paid;
  @override
  Widget build(BuildContext context) {
    final items = [for (final o in orders) for (final i in o.items) (i: i, cancelled: o.cancelled)];
    Widget cell(String t, {int flex = 2, bool head = false, TextAlign align = TextAlign.right, Color color = HC.ink}) =>
        Expanded(flex: flex, child: Text(t, textAlign: align, style: hs(head ? 11.5 : 13, w: head ? w6 : w5, color: head ? HC.muted : color, num: true)));
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      Text('কী অর্ডার · কী নিয়েছে · কত টাকা', style: hs(12.5, color: HC.muted)),
      Text('${stop['retailer_name']}', style: hs(18, w: w8)),
      gap12,
      Row(children: [cell('পণ্য', flex: 5, head: true, align: TextAlign.left), cell('অর্ডার', head: true), cell('নিয়েছে', head: true), cell('টাকা', flex: 3, head: true)]),
      const Divider(color: HC.line),
      for (final x in items)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 7),
          child: Row(children: [
            cell(x.i.name, flex: 5, align: TextAlign.left),
            cell(bn(x.i.ordered)),
            cell(bn(x.cancelled ? 0 : x.i.qty), color: (x.cancelled ? 0 : x.i.qty) < x.i.ordered ? HC.red : HC.ink),
            cell(tk(x.cancelled ? 0 : x.i.qty * x.i.srRate), flex: 3),
          ]),
        ),
      const HDashed(),
      const SizedBox(height: 10),
      Row(children: [
        Expanded(child: Text('নগদ দিয়েছে', style: hs(14, w: w6))),
        Text(tk(paid), style: hs(20, w: w8, num: true)),
      ]),
      if ((stop['timeline'] as List?)?.isNotEmpty ?? false) ...[
        const SizedBox(height: 18),
        Row(children: [
          Expanded(child: Text('হিস্ট্রি', style: hs(16, w: w7))),
          const HChip('অটো', bg: HC.soft, fg: HC.blue, size: 11),
        ]),
        const SizedBox(height: 8),
        for (final (i, e) in ((stop['timeline'] as List).map((x) => Map<String, dynamic>.from(x as Map))).indexed)
          IntrinsicHeight(
            child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              SizedBox(
                width: 22,
                child: Column(children: [
                  Container(
                    margin: const EdgeInsets.only(top: 4), width: 12, height: 12,
                    decoration: BoxDecoration(color: i == 0 ? HC.blue : Colors.white, shape: BoxShape.circle, border: Border.all(color: HC.blue, width: 2)),
                  ),
                  if (i < (stop['timeline'] as List).length - 1) Expanded(child: Container(width: 2, color: HC.line)),
                ]),
              ),
              const SizedBox(width: 10),
              Expanded(child: Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${e['title']}', style: hs(14, w: w7)),
                  if ('${e['sub'] ?? ''}'.isNotEmpty) Text('${e['sub']}', style: hs(12, color: HC.muted)),
                ]),
              )),
              Text('${e['time'] ?? ''}', style: hs(12, color: HC.muted, num: true)),
            ]),
          ),
      ],
    ]);
  }
}

/// DMDslip · ডেলিভারি স্লিপ: the paper slip the shop gets (what was ordered, what it took, bill, paid, due).
class _SlipSheet extends StatelessWidget {
  const _SlipSheet({required this.stop, required this.orders, required this.paid, required this.bill, required this.over});
  final Map<String, dynamic> stop;
  final List<_Order> orders;
  final double paid, bill, over;

  @override
  Widget build(BuildContext context) {
    final me = context.read<AuthState>();
    final items = [for (final o in orders) for (final i in o.items) (i: i, cancelled: o.cancelled)];
    final now = DateTime.now();
    final d2 = (int n) => n.toString().padLeft(2, '0');
    final slipNo = 'HB-${'${stop['id']}'.padLeft(4, '0')}-${d2(now.year % 100)}${d2(now.month)}${d2(now.day)}';
    final ordered = items.fold<int>(0, (a, x) => a + x.i.ordered);
    final taken = items.fold<int>(0, (a, x) => a + (x.cancelled ? 0 : x.i.qty));
    Widget kv(String k, String v, {bool bold = false}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(children: [
            Expanded(child: Text(k, style: hs(13, w: bold ? w8 : w5, color: bold ? HC.ink : HC.ink2))),
            Text(v, style: hs(bold ? 15 : 13, w: bold ? w8 : w6, num: true)),
          ]),
        );
    Widget cell(String t, {int flex = 2, bool head = false, TextAlign align = TextAlign.right, bool strong = false}) => Expanded(
        flex: flex,
        child: Text(t, textAlign: align, maxLines: 2, overflow: TextOverflow.ellipsis,
            style: hs(head ? 11 : 12.5, w: head ? w7 : (strong ? w8 : w5), color: head ? HC.muted : HC.ink, num: true)
                .copyWith(decoration: strong ? TextDecoration.underline : null)));
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Column(children: [
        Container(
          width: 34, height: 34, alignment: Alignment.center,
          decoration: BoxDecoration(color: HC.sky, borderRadius: BorderRadius.circular(10)),
          child: Image.asset('assets/images/mark_white.png', width: 20, errorBuilder: (_, __, ___) => const SizedBox()),
        ),
        const SizedBox(height: 4),
        Text('HAPPY BANGLADESH', style: hs(14, w: w8).copyWith(letterSpacing: 1)),
        Text('${me.profile['partner'] ?? ''}', style: hs(12, color: HC.muted)),
        const SizedBox(height: 6),
        Text('ডেলিভারি স্লিপ', style: hs(16, w: w8)),
      ]),
      const SizedBox(height: 10),
      const HDashed(),
      const SizedBox(height: 8),
      kv('দোকান', '${stop['retailer_name']}'),
      kv('মেমো', orders.map((o) => o.code).join(', ')),
      kv('তারিখ', bn('${d2(now.day)}/${d2(now.month)}/${now.year} ${d2(now.hour)}:${d2(now.minute)}')),
      kv('DM', me.name),
      const SizedBox(height: 8),
      const HDashed(),
      const SizedBox(height: 6),
      Row(children: [cell('পণ্য', flex: 5, head: true, align: TextAlign.left), cell('অর্ডার', head: true), cell('দিল', head: true), cell('টাকা', flex: 3, head: true)]),
      for (final x in items)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Row(children: [
            cell(x.i.name, flex: 5, align: TextAlign.left),
            cell(bn(x.i.ordered)),
            cell(bn(x.cancelled ? 0 : x.i.qty), strong: (x.cancelled ? 0 : x.i.qty) < x.i.ordered),
            cell(tk(x.cancelled ? 0 : x.i.qty * x.i.srRate), flex: 3),
          ]),
        ),
      const SizedBox(height: 6),
      const HDashed(),
      const SizedBox(height: 6),
      kv('মোট পিস', '${bn(taken)} / ${bn(ordered)}'),
      if (over.abs() >= .5) kv('ডেলিভারি ওভার', sMoney(over)),
      kv('মোট বিল', tk(bill), bold: true),
      kv('জমা', tk(paid)),
      kv('বাকি', tk((bill - paid).clamp(0, double.infinity))),
      const SizedBox(height: 10),
      Text(slipNo, textAlign: TextAlign.center, style: hs(12, w: w7, color: HC.muted, num: true)),
      Text('ধন্যবাদ · আবার দেখা হবে', textAlign: TextAlign.center, style: hs(12, color: HC.muted)),
    ]);
  }
}
