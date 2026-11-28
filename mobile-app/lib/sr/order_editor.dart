import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/api.dart';
import '../core/format.dart';
import '../core/offline.dart';
import '../ui/common.dart';
import '../ui/hkit.dart';
import '../ui/pwa_kit.dart';
import 'sr_history.dart';

Color _tint(Object? hex) {
  final s = (hex ?? '').toString().replaceFirst('#', '');
  final v = int.tryParse(s.length == 6 ? 'FF$s' : s, radix: 16);
  return v == null ? HC.bg : Color(v);
}

String _trim(double v) => v == v.roundToDouble() ? v.round().toString() : v.toStringAsFixed(2);

/// One product in the cart: pieces + the money the SR settles on (the difference to the base price is the O/C).
class _Line {
  _Line(this.p, {this.pcs = 0, this.total = 0, this.mode = 'unit'}) : qpu = int0(p['qty_per_unit']).clamp(1, 100000);
  final Map<String, dynamic> p;
  final int qpu;
  int pcs;
  double total;
  String mode; // unit | pcs  (only how the quantity was typed)

  double get rate => num0(p['pc_price']);
  double get base => pcs * rate;
  double get oc => total - base;
  double get perPc => pcs > 0 ? total / pcs : rate;
  String get unitBnName => unitBn('${p['unit_type']}');

  String get badge {
    if (mode == 'pcs' || qpu == 1) return '${bn(pcs)} পিস';
    final u = pcs ~/ qpu, e = pcs % qpu;
    if (u > 0 && e > 0) return '${bn(u)} $unitBnName ${bn(e)} পিস';
    if (u > 0) return '${bn(u)} $unitBnName';
    return '${bn(e)} পিস';
  }
}

Widget _thumb(Map<String, dynamic> p, double size, double radius) => Container(
      width: size, height: size,
      decoration: BoxDecoration(color: _tint(p['tint']), borderRadius: BorderRadius.circular(radius)),
      clipBehavior: Clip.antiAlias,
      padding: EdgeInsets.all(size > 50 ? 6 : 3),
      child: NetImage(ApiClient.asset(p['image']), fit: BoxFit.contain,
          fallback: Center(child: Text('${p['code'] ?? '${p['name']}'.characters.first}', style: hs(size > 50 ? 15 : 12, w: w8, color: HC.ink2)))),
    );

/// Number pad entry for a stepper value (long counts are faster to type than to tap).
Future<int?> _askNumber(BuildContext context, String title, int value) async {
  final c = TextEditingController(text: value == 0 ? '' : '$value');
  final r = await showDialog<int>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title, style: hs(16, w: w7)),
      content: TextField(
        controller: c, autofocus: true, keyboardType: TextInputType.number, textAlign: TextAlign.center,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly], style: hs(24, w: w8, num: true),
        onSubmitted: (v) => Navigator.pop(ctx, int.tryParse(v) ?? 0),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('বাতিল')),
        FilledButton(onPressed: () => Navigator.pop(ctx, int.tryParse(c.text) ?? 0), child: const Text('ঠিক আছে')),
      ],
    ),
  );
  c.dispose();
  return r;
}

/// SR3 — product catalogue for one shop (category rail, grid / list), floating cart bar; SR3b product sheet; SR4 success.
class OrderEditorPage extends StatefulWidget {
  const OrderEditorPage({super.key, required this.shop, required this.products, this.existing});
  final Map<String, dynamic> shop;
  final List<Map<String, dynamic>> products;
  final Map<String, dynamic>? existing;
  @override
  State<OrderEditorPage> createState() => _OrderEditorPageState();
}

class _OrderEditorPageState extends State<OrderEditorPage> {
  final Map<String, _Line> _cart = {};
  final _search = TextEditingController();
  String _q = '';
  String? _cat;
  bool _list = false;
  int? _orderId; // set once saved online, so a second save updates the same order

  bool get _editing => _orderId != null;
  bool get _locked => widget.existing != null && widget.existing!['editable'] != true;

  @override
  void initState() {
    super.initState();
    if (widget.existing != null) {
      _orderId = int0(widget.existing!['id']);
      for (final it in (widget.existing!['items'] as List? ?? const [])) {
        final m = Map<String, dynamic>.from(it as Map);
        for (final p in widget.products) {
          if ('${p['id']}' == '${m['product_id']}') _cart['${p['id']}'] = _Line(p, pcs: int0(m['pcs']), total: num0(m['total']));
        }
      }
    }
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<_Line> get _lines => _cart.values.where((l) => l.pcs > 0).toList();
  double get _sum => _lines.fold(0, (a, l) => a + l.total);
  int get _pcs => _lines.fold(0, (a, l) => a + l.pcs);

  List<String> get _cats {
    final s = <String>{};
    for (final p in widget.products) {
      final c = '${p['category'] ?? ''}'.trim();
      if (c.isNotEmpty) s.add(c);
    }
    return s.toList();
  }

  Future<void> _openProduct(Map<String, dynamic> p) async {
    if (_locked) {
      toast(context, 'এই অর্ডার ট্রিপে চলে গেছে — আর পরিবর্তন করা যাবে না।', error: true);
      return;
    }
    final key = '${p['id']}';
    final res = await showHSheet<_Line>(context, builder: (_) => _ProductSheet(line: _cart[key] ?? _Line(p), existing: _cart.containsKey(key)));
    if (!mounted || res == null) return;
    setState(() => res.pcs <= 0 ? _cart.remove(key) : _cart[key] = res);
  }

  Future<void> _review() async {
    final go = await showHSheet<String>(context, builder: (_) => _CartSheet(shop: widget.shop, lines: _lines, editing: _editing && !_locked));
    if (go == 'confirm') {
      await _save();
    } else if (go == 'cancel') {
      await _cancel();
    }
  }

  Future<void> _save() async {
    final lines = _lines;
    if (lines.isEmpty) {
      toast(context, 'কমপক্ষে একটি পণ্য যোগ করুন।', error: true);
      return;
    }
    for (final l in lines) {
      if (l.total <= 0) {
        toast(context, '${l.p['name']}-এর মোট টাকা দিন।', error: true);
        return;
      }
    }
    final body = {
      'retailer_id': int0(widget.shop['id']),
      'items': [for (final l in lines) {'product_id': int0(l.p['id']), 'pcs': l.pcs, 'total': l.total}],
      'at': DateTime.now().millisecondsSinceEpoch ~/ 1000,
    };
    // The server keeps one open order per shop and day, so an offline save (queued) safely replaces it later.
    final r = await busy(context, () => _editing
        ? OfflineQueue.write('PUT', '/sr/orders/$_orderId', body: body, label: '${widget.shop['name']}-এর অর্ডার পরিবর্তন')
        : OfflineQueue.write('POST', '/sr/orders', body: body, label: '${widget.shop['name']}-এর অর্ডার'));
    if (r == null || !mounted) return;
    HapticFeedback.mediumImpact();
    Map<String, dynamic>? order;
    if (!r.queued) {
      final warnings = (r.data['warnings'] as List?)?.map((e) => '$e').toList() ?? [];
      if (warnings.isNotEmpty) toast(context, warnings.join('\n'));
      if (r.data['order'] is Map) {
        order = Map<String, dynamic>.from(r.data['order'] as Map);
        _orderId = int0(order['id']);
      }
    }
    final next = await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => _SuccessPage(shop: widget.shop, lines: lines, order: order, queued: r.queued)));
    if (!mounted) return;
    if (next == true) Navigator.pop(context, true); // "অন্য দোকানে যান"
    // otherwise "সম্পাদনা" — stay here with the cart
  }

  Future<void> _cancel() async {
    if (!await confirm(context, 'অর্ডার বাতিল করবেন?', body: '${widget.shop['name']}-এর আজকের অর্ডার মুছে যাবে।', danger: true, yes: 'বাতিল করুন')) return;
    if (!mounted) return;
    final r = await busy(context, () => OfflineQueue.write('DELETE', '/sr/orders/$_orderId', label: '${widget.shop['name']}-এর অর্ডার বাতিল'));
    if (r != null && mounted) {
      toast(context, r.queued ? 'ইন্টারনেট এলে বাতিল হবে।' : (r.data['message'] ?? 'বাতিল হয়েছে।').toString());
      Navigator.pop(context, true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final q = _q.trim().toLowerCase();
    final shown = widget.products.where((p) {
      if (_cat != null && '${p['category'] ?? ''}' != _cat) return false;
      return q.isEmpty || '${p['name']} ${p['code']}'.toLowerCase().contains(q);
    }).toList();
    final cats = _cats;
    final count = _lines.length;
    final bottom = MediaQuery.of(context).padding.bottom;
    final dist = widget.shop['_dist'];
    return SkyStatusBar(
      child: Scaffold(
        backgroundColor: HC.bg,
        body: Stack(children: [
          CustomScrollView(slivers: [
            SliverPadding(
              padding: EdgeInsets.fromLTRB(18, MediaQuery.of(context).padding.top + 14, 18, 8),
              sliver: SliverToBoxAdapter(
              child: SkyBox(
                height: _cart.isEmpty ? 150 : 176,
                child: Padding(
                  padding: EdgeInsets.zero,
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    SkyHead(
                      leading: const SkyBack(),
                      kicker: _editing ? 'অর্ডার সম্পাদনা' : (dist == null ? 'নতুন অর্ডার' : 'নতুন অর্ডার · $dist'),
                      title: '${widget.shop['name']}',
                      trailing: GlassBtn(
                        icon: _list
                            ? '<rect x="3" y="3" width="7" height="7" rx="1"/><rect x="14" y="3" width="7" height="7" rx="1"/><rect x="3" y="14" width="7" height="7" rx="1"/><rect x="14" y="14" width="7" height="7" rx="1"/>'
                            : '<path d="M8 6h13M8 12h13M8 18h13"/><circle cx="3.5" cy="6" r="1"/><circle cx="3.5" cy="12" r="1"/><circle cx="3.5" cy="18" r="1"/>',
                        label: _list ? 'গ্রিড ভিউ' : 'লিস্ট ভিউ',
                        onTap: () => setState(() => _list = !_list),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Container(
                      height: 48, padding: const EdgeInsets.symmetric(horizontal: 14),
                      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), boxShadow: HC.liftSm),
                      child: Row(children: [
                        const Svg('<circle cx="11" cy="11" r="7"/><path d="m20 20-3.5-3.5"/>', size: 18, color: HC.muted),
                        const SizedBox(width: 10),
                        Expanded(
                          child: TextField(
                            controller: _search, onChanged: (v) => setState(() => _q = v), textInputAction: TextInputAction.search,
                            style: hs(14.5), decoration: InputDecoration(hintText: 'পণ্য খুঁজুন…', hintStyle: hs(14.5, color: HC.faint), border: InputBorder.none, enabledBorder: InputBorder.none, focusedBorder: InputBorder.none, isDense: true, filled: false, contentPadding: EdgeInsets.zero),
                          ),
                        ),
                        if (_q.isNotEmpty)
                          Semantics(button: true, label: 'মুছুন', child: GestureDetector(
                            onTap: () => setState(() {
                              _search.clear();
                              _q = '';
                            }),
                            child: const Padding(padding: EdgeInsets.all(6), child: Svg('<path d="M18 6 6 18M6 6l12 12"/>', size: 16, color: HC.muted, stroke: 2.2)),
                          )),
                      ]),
                    ),
                    if (_cart.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Text('কার্টে: ${_lines.map((l) => '${l.p['name']}').join(' · ')}', maxLines: 1, overflow: TextOverflow.ellipsis, style: hs(12.5, w: w5, color: HC.onSky)),
                    ],
                  ]),
                ),
              ),
            )),
            if (cats.length > 1)
              SliverToBoxAdapter(
                child: SizedBox(
                  height: 54,
                  child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.fromLTRB(18, 10, 18, 6), children: [
                    for (final c in [null, ...cats])
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: Semantics(button: true, selected: _cat == c, child: GestureDetector(
                          onTap: () => setState(() => _cat = c),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            alignment: Alignment.center,
                            decoration: BoxDecoration(color: _cat == c ? HC.ink : Colors.white, borderRadius: BorderRadius.circular(99), border: Border.all(color: _cat == c ? HC.ink : HC.line)),
                            child: Text(c ?? 'সব', style: hs(13.5, w: w6, color: _cat == c ? Colors.white : HC.ink2)),
                          ),
                        )),
                      ),
                  ]),
                ),
              ),
            if (_locked)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(18, 10, 18, 0),
                  child: HCard(color: HC.redSoft, border: false, child: Text('এই অর্ডার ট্রিপে চলে গেছে — আর পরিবর্তন করা যাবে না।', style: hs(13, w: w6, color: HC.red))),
                ),
              ),
            SliverToBoxAdapter(child: Padding(padding: const EdgeInsets.fromLTRB(18, 12, 18, 10), child: HSec(_cat ?? 'সব পণ্য', trailing: '${bn(shown.length)}টি'))),
            if (shown.isEmpty)
              const SliverToBoxAdapter(child: Padding(padding: EdgeInsets.symmetric(horizontal: 18), child: HEmpty('কোনো পণ্য পাওয়া যায়নি', body: 'অন্য নামে খুঁজুন বা "সব" বাছুন।')))
            else if (_list)
              SliverPadding(
                padding: EdgeInsets.fromLTRB(18, 0, 18, 110 + bottom),
                sliver: SliverList.separated(itemCount: shown.length, separatorBuilder: (_, _) => gap8, itemBuilder: (_, i) => _listCard(shown[i])),
              )
            else
              SliverPadding(
                padding: EdgeInsets.fromLTRB(18, 0, 18, 110 + bottom),
                sliver: SliverGrid.builder(
                  itemCount: shown.length,
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, mainAxisSpacing: 12, crossAxisSpacing: 12, mainAxisExtent: 206),
                  itemBuilder: (_, i) => _gridCard(shown[i]),
                ),
              ),
          ]),
          if (count > 0)
            Positioned(
              left: 14, right: 14, bottom: 12 + bottom,
              child: _CartBar(count: count, pcs: _pcs, sum: _sum, label: _editing ? 'আপডেট' : 'অর্ডার পাঠান', onTap: _locked ? null : _review),
            ),
        ]),
      ),
    );
  }

  ({String text, bool low}) _stock(Map<String, dynamic> p) {
    final avail = int0(p['available_pcs']);
    final low = avail <= int0(p['qty_per_unit']).clamp(1, 100000) * 2;
    return (text: 'স্টক ${bn(avail < 0 ? 0 : avail)}${low ? ' · কম' : ''}', low: low);
  }

  Widget _badge(_Line l) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(color: HC.blue, borderRadius: BorderRadius.circular(99)),
        child: Text(l.badge, style: hs(11, w: w7, color: Colors.white, h: 1.3)),
      );

  Widget _gridCard(Map<String, dynamic> p) {
    final inCart = _cart['${p['id']}'];
    final st = _stock(p);
    final unit = unitBn('${p['unit_type']}');
    return HCard(
      padding: EdgeInsets.zero, radius: 20, onTap: () => _openProduct(p), border: inCart == null,
      child: Container(
        decoration: inCart == null ? null : BoxDecoration(borderRadius: BorderRadius.circular(20), border: Border.all(color: HC.blue, width: 2)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Container(
            height: 104, margin: const EdgeInsets.all(6), padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: _tint(p['tint']), borderRadius: BorderRadius.circular(15)),
            child: Stack(children: [
              Positioned.fill(child: NetImage(ApiClient.asset(p['image']), fit: BoxFit.contain, fallback: Center(child: Text('${p['code'] ?? ''}', style: hs(15, w: w8, color: HC.ink2))))),
              if (inCart != null) Positioned(top: 0, left: 0, child: _badge(inCart)),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 2, 12, 10),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${p['name']}', maxLines: 2, overflow: TextOverflow.ellipsis, style: hs(13.5, w: w6, h: 1.3)),
              const SizedBox(height: 4),
              Row(children: [
                Text(tk(p['pc_price']), style: hs(15, w: w8, num: true)),
                Text(' /পিস', style: hs(11, color: HC.muted)),
              ]),
              Text('${tk(p['unit_price'])}/$unit · ${st.text}', maxLines: 1, overflow: TextOverflow.ellipsis, style: hs(11.5, color: st.low ? HC.red : HC.muted, num: true)),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _listCard(Map<String, dynamic> p) {
    final inCart = _cart['${p['id']}'];
    final st = _stock(p);
    final unit = unitBn('${p['unit_type']}');
    return HCard(
      padding: const EdgeInsets.all(10), radius: 18, onTap: () => _openProduct(p),
      child: Row(children: [
        _thumb(p, 56, 14),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${p['name']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: hs(14, w: w6)),
          Text('${tk(p['pc_price'])}/পিস · ${tk(p['unit_price'])}/$unit', style: hs(12, color: HC.muted, num: true)),
          Text(st.text, style: hs(11.5, color: st.low ? HC.red : HC.muted, num: true)),
        ])),
        if (inCart != null) _badge(inCart) else const Svg('<path d="M12 5v14M5 12h14"/>', size: 20, color: HC.blue, stroke: 2.4),
      ]),
    );
  }
}

/// Floating dark cart bar (SR3).
class _CartBar extends StatelessWidget {
  const _CartBar({required this.count, required this.pcs, required this.sum, required this.label, required this.onTap});
  final int count, pcs;
  final double sum;
  final String label;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
        decoration: BoxDecoration(color: HC.ink, borderRadius: BorderRadius.circular(22), boxShadow: HC.lift),
        child: Row(children: [
          Container(
            width: 44, height: 44, alignment: Alignment.center,
            decoration: BoxDecoration(color: const Color(0x1FFFFFFF), borderRadius: BorderRadius.circular(14)),
            child: Text(bn(count), style: hs(17, w: w8, color: Colors.white, num: true)),
          ),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Text('${bn(pcs)} পিস · ${bn(count)}টি পণ্য', style: hs(12, color: HC.onDark, num: true)),
            Text(tk(sum), maxLines: 1, overflow: TextOverflow.ellipsis, style: hs(19, w: w8, color: Colors.white, num: true, h: 1.2)),
          ])),
          HBtn(label, kind: HBtnKind.white, expand: false, height: 46, radius: 15, fontSize: 14, trailingIcon: '<path d="M5 12h14M13 6l6 6-6 6"/>', onTap: onTap),
        ]),
      );
}

/// SR3b — quantity (unit / pcs), rate and total of one product; the difference to the base price is the O/C.
class _ProductSheet extends StatefulWidget {
  const _ProductSheet({required this.line, required this.existing});
  final _Line line;
  final bool existing;
  @override
  State<_ProductSheet> createState() => _ProductSheetState();
}

class _ProductSheetState extends State<_ProductSheet> {
  late String _mode = widget.line.qpu == 1 ? 'pcs' : widget.line.mode;
  int _units = 0, _extra = 0, _pcsOnly = 0;
  late final _rate = TextEditingController();
  late final _total = TextEditingController();
  bool _manual = false;

  _Line get l => widget.line;
  int get _pcs => _mode == 'unit' ? _units * l.qpu + _extra : _pcsOnly;
  double get _base => _pcs * l.rate;
  double get _totalVal => double.tryParse(_total.text) ?? 0;

  @override
  void initState() {
    super.initState();
    if (widget.existing) {
      _setQty(l.pcs);
      _total.text = _trim(l.total);
      _manual = (l.total - l.pcs * l.rate).abs() > 0.009;
    } else {
      if (l.qpu > 1) {
        _units = 1;
      } else {
        _pcsOnly = 1;
      }
      _total.text = _trim(_base);
    }
    _syncRate();
  }

  @override
  void dispose() {
    _rate.dispose();
    _total.dispose();
    super.dispose();
  }

  void _setQty(int pcs) {
    _units = pcs ~/ l.qpu;
    _extra = pcs % l.qpu;
    _pcsOnly = pcs;
  }

  /// rate shown per unit (unit mode) or per piece
  void _syncRate() {
    final pcs = _pcs;
    final perPc = pcs > 0 ? _totalVal / pcs : l.rate;
    _rate.text = _trim(_mode == 'unit' ? perPc * l.qpu : perPc);
  }

  void _onQty() {
    if (_manual && _pcs > 0) {
      // keep the agreed rate, scale the total
      final r = double.tryParse(_rate.text) ?? 0;
      _total.text = _trim((_mode == 'unit' ? r / l.qpu : r) * _pcs);
    } else {
      _total.text = _pcs == 0 ? '' : _trim(_base);
    }
    _syncRate();
    setState(() {});
  }

  void _onRate(String v) {
    final r = double.tryParse(v) ?? 0;
    final perPc = _mode == 'unit' ? r / l.qpu : r;
    _manual = true;
    _total.text = _pcs == 0 ? '' : _trim(perPc * _pcs);
    setState(() {});
  }

  void _onTotal(String v) {
    _manual = true;
    _syncRate();
    setState(() {});
  }

  void _save() {
    final pcs = _pcs;
    if (pcs <= 0) {
      toast(context, 'পরিমাণ দিন।', error: true);
      return;
    }
    if (_totalVal <= 0) {
      toast(context, 'মোট টাকা দিন।', error: true);
      return;
    }
    Navigator.pop(context, _Line(l.p, pcs: pcs, total: _totalVal, mode: _mode));
  }

  Widget _stepper(String label, int value, ValueChanged<int> set, {String? hint}) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text.rich(TextSpan(style: hs(13, w: w6, color: HC.ink2), children: [TextSpan(text: label), if (hint != null) TextSpan(text: ' · $hint', style: hs(12, color: HC.muted))])),
        const SizedBox(height: 6),
        HStepper(
          value: value,
          onChanged: (v) {
            set(v);
            _onQty();
          },
          onTapValue: () async {
            final v = await _askNumber(context, label, value);
            if (v != null && mounted) {
              set(v);
              _onQty();
            }
          },
        ),
      ]);

  Widget _money(String label, TextEditingController c, ValueChanged<String> onChanged, String sub) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: hs(13, w: w6, color: HC.ink2)),
        const SizedBox(height: 6),
        TextField(
          controller: c, onChanged: onChanged,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
          style: hs(17, w: w7, num: true),
          decoration: InputDecoration(
            prefixText: '৳ ', prefixStyle: hs(15, w: w6, color: HC.muted),
            isDense: true, filled: true, fillColor: HC.bg, contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: HC.blue, width: 1.5)),
          ),
        ),
        Padding(padding: const EdgeInsets.only(top: 5), child: Text(sub, style: hs(11.5, color: HC.muted, num: true))),
      ]);

  @override
  Widget build(BuildContext context) {
    final p = l.p;
    final unit = unitBn('${p['unit_type']}');
    final oc = _totalVal - _base;
    final over = oc > 0.009, comm = oc < -0.009;
    final avail = int0(p['available_pcs']);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      Row(children: [
        _thumb(p, 56, 16),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${p['name']}', maxLines: 2, overflow: TextOverflow.ellipsis, style: hs(17, w: w8, h: 1.25)),
          Text.rich(TextSpan(style: hs(12.5, color: HC.muted, num: true), children: [
            TextSpan(text: '${bn(l.qpu)} পিস / $unit · '),
            TextSpan(text: 'স্টক ${bn(avail < 0 ? 0 : avail)}', style: hs(12.5, color: avail > 0 ? HC.muted : HC.red, num: true)),
          ])),
        ])),
        Semantics(button: true, label: 'বন্ধ করুন', child: GestureDetector(
          onTap: () => Navigator.pop(context),
          child: Container(width: 40, height: 40, decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: HC.line)),
              child: const Center(child: Svg('<path d="M18 6 6 18M6 6l12 12"/>', size: 16, color: HC.ink, stroke: 2.2))),
        )),
      ]),
      const SizedBox(height: 16),
      if (l.qpu > 1) ...[
        HSeg(
          onSky: false, index: _mode == 'unit' ? 0 : 1, items: ['$unit (ইউনিট)', 'শুধু পিস'],
          onTap: (i) {
            final m = i == 0 ? 'unit' : 'pcs';
            if (_mode == m) return;
            final pcs = _pcs;
            _mode = m;
            _setQty(pcs);
            _syncRate();
            setState(() {});
          },
        ),
        const SizedBox(height: 14),
      ],
      if (_mode == 'unit')
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: _stepper(unit, _units, (v) => _units = v, hint: '${bn(l.qpu)} পিস')),
          const SizedBox(width: 12),
          Expanded(child: _stepper('খোলা পিস', _extra, (v) => _extra = v)),
        ])
      else
        _stepper('পিস', _pcsOnly, (v) => _pcsOnly = v),
      if (_pcs > avail && avail >= 0)
        Padding(padding: const EdgeInsets.only(top: 8), child: Text('${bn(_pcs)} পিস — স্টকের চেয়ে বেশি!', style: hs(12.5, w: w6, color: HC.red))),
      const SizedBox(height: 14),
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(child: _money(_mode == 'unit' ? 'প্রতি $unit দর' : 'প্রতি পিস দর', _rate, _onRate, 'বেজ ${tk(_mode == 'unit' ? l.rate * l.qpu : l.rate)}')),
        const SizedBox(width: 12),
        Expanded(child: _money('মোট টাকা', _total, _onTotal, 'নির্ধারিত ${tk(_base)}')),
      ]),
      const SizedBox(height: 12),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        decoration: BoxDecoration(color: over ? HC.soft : (comm ? HC.redSoft : HC.bg), borderRadius: BorderRadius.circular(16)),
        child: Row(children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('আমার ওভার / কমিশন', style: hs(13, w: w6, color: HC.ink2)),
            Text(over ? 'বেশি দামে বিক্রি — ওভার' : (comm ? 'কম দামে বিক্রি — কমিশন' : 'নির্ধারিত দরে'), style: hs(11.5, color: HC.muted)),
          ])),
          Text(sMoney(oc), style: hs(19, w: w8, color: over ? HC.blue : (comm ? HC.red : HC.ink), num: true)),
        ]),
      ),
      const SizedBox(height: 16),
      Row(children: [
        if (widget.existing) ...[
          HBtn('সরান', kind: HBtnKind.danger, expand: false, height: 52, radius: 16, fontSize: 14, onTap: () => Navigator.pop(context, _Line(l.p))),
          const SizedBox(width: 8),
        ] else ...[
          HBtn('বাতিল', kind: HBtnKind.line, expand: false, height: 52, radius: 16, fontSize: 14, onTap: () => Navigator.pop(context)),
          const SizedBox(width: 8),
        ],
        Expanded(child: HBtn('${widget.existing ? 'আপডেট' : 'অর্ডারে যোগ করুন'} · ${tk(_totalVal)}', height: 52, fontSize: 14.5, onTap: _save)),
      ]),
    ]);
  }
}

/// Cart review before sending: lines with O/C, totals, confirm (and cancel for a saved order).
class _CartSheet extends StatelessWidget {
  const _CartSheet({required this.shop, required this.lines, required this.editing});
  final Map<String, dynamic> shop;
  final List<_Line> lines;
  final bool editing;
  @override
  Widget build(BuildContext context) {
    final oc = lines.fold<double>(0, (a, l) => a + l.oc);
    final sum = lines.fold<double>(0, (a, l) => a + l.total);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      Text('অর্ডার দেখে নিন', style: hs(18, w: w8)),
      Text('${shop['name']} · ${bn(lines.length)}টি পণ্য', style: hs(12.5, color: HC.muted)),
      gap12,
      HList(children: [
        for (final l in lines)
          HItemRow(
            name: '${l.p['name']}', sub: '${l.badge} · ${tk(l.perPc)}/পিস', amount: tk(l.total),
            tag: l.oc.abs() > 0.009 ? sMoney(l.oc) : null, tagOver: l.oc > 0, image: _thumb(l.p, 38, 11),
          ),
      ]),
      gap12,
      HStrip(style: StripStyle.soft, [
        HStat('মোট', tk(sum)),
        HStat('ওভার / কমিশন', sMoney(oc), color: oc > 0.009 ? HC.blue : (oc < -0.009 ? HC.red : HC.ink)),
      ]),
      gap16,
      HBtn(editing ? 'অর্ডার আপডেট করুন' : 'অর্ডার কনফার্ম করুন', trailingIcon: '<path d="M5 12h14M13 6l6 6-6 6"/>', onTap: () => Navigator.pop(context, 'confirm')),
      if (editing) ...[
        gap8,
        HBtn('অর্ডারটি বাতিল করুন', kind: HBtnKind.danger, height: 48, onTap: () => Navigator.pop(context, 'cancel')),
      ],
    ]);
  }
}

/// SR4 — "অর্ডার পাঠানো হয়েছে": items with rate and O/C, total, over/commission/net.
class _SuccessPage extends StatelessWidget {
  const _SuccessPage({required this.shop, required this.lines, required this.order, required this.queued});
  final Map<String, dynamic> shop;
  final List<_Line> lines;
  final Map<String, dynamic>? order;
  final bool queued;

  @override
  Widget build(BuildContext context) {
    final total = lines.fold<double>(0, (a, l) => a + l.total);
    final over = lines.fold<double>(0, (a, l) => a + (l.oc > 0 ? l.oc : 0));
    final comm = lines.fold<double>(0, (a, l) => a + (l.oc < 0 ? l.oc : 0));
    final code = order?['code'];
    final top = MediaQuery.of(context).padding.top;
    return SkyStatusBar(
      child: Scaffold(
        backgroundColor: HC.bg,
        body: Column(children: [
          Expanded(
            child: ListView(padding: EdgeInsets.fromLTRB(18, top + 14, 18, 16), children: [
              SkyBox(
                height: 260,
                child: Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Column(children: [
                    Container(
                      width: 68, height: 68,
                      decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle, boxShadow: HC.liftSm),
                      child: Center(child: queued
                          ? const Svg('<circle cx="12" cy="12" r="9"/><path d="M12 7v5l3 2"/>', size: 30, color: HC.blue, stroke: 2.4)
                          : const Svg('<polyline points="20 6 9 17 4 12"/>', size: 32, color: HC.blue, stroke: 3)),
                    ),
                    const SizedBox(height: 14),
                    Text(queued ? 'অর্ডার ফোনে সংরক্ষিত' : 'অর্ডার পাঠানো হয়েছে', style: hs(22, w: w8, color: Colors.white)),
                    const SizedBox(height: 4),
                    Text('${shop['name']}${code == null ? '' : ' · মেমো #${bn(code)}'} · আজ', style: hs(13, color: HC.onSky, num: true)),
                    const SizedBox(height: 12),
                    Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                      HChip('${bn(lines.length)}টি পণ্য', bg: const Color(0x26FFFFFF), fg: Colors.white),
                      const SizedBox(width: 8),
                      HChip(queued ? 'নেট এলে পাঠানো হবে' : 'ডেলিভারিতে নগদ', bg: const Color(0x26FFFFFF), fg: Colors.white),
                    ]),
                  ]),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 22),
                child: Padding(
                  padding: EdgeInsets.zero,
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    HCard(
                      lift: true, radius: 24, padding: const EdgeInsets.fromLTRB(16, 6, 16, 16),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                        for (var i = 0; i < lines.length; i++) ...[
                          if (i > 0) const Divider(height: 1, color: HC.line),
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 11),
                            child: Row(children: [
                              LetterAvatar('${lines[i].p['name']}', size: 38, radius: 12, bg: HC.soft, fg: HC.blue, fontSize: 15),
                              const SizedBox(width: 12),
                              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Text('${lines[i].p['name']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: hs(14, w: w6)),
                                Text('${bn(lines[i].pcs)} × ${tk(lines[i].perPc)}', style: hs(12, color: HC.muted, num: true)),
                              ])),
                              if (lines[i].oc.abs() > 0.009) ...[
                                HChip(sMoney(lines[i].oc), bg: lines[i].oc > 0 ? HC.soft : HC.redSoft, fg: lines[i].oc > 0 ? HC.blue : HC.red, size: 11),
                                const SizedBox(width: 8),
                              ],
                              Text(tk(lines[i].total), style: hs(14, w: w7, num: true)),
                            ]),
                          ),
                        ],
                        const HDashed(),
                        const SizedBox(height: 12),
                        Row(children: [
                          Expanded(child: Text('মোট · ডেলিভারিতে নগদ', style: hs(13.5, w: w6, color: HC.ink2))),
                          Text(tk(total), style: hs(24, w: w8, num: true)),
                        ]),
                      ]),
                    ),
                    gap12,
                    HStrip(style: StripStyle.dark, [
                      HStat('ওভার', sMoney(over), color: over > 0.009 ? HC.lilac : Colors.white),
                      HStat('কমিশন', sMoney(comm), color: comm < -0.009 ? HC.redOnDark : Colors.white),
                      HStat('নিট', sMoney(over + comm), color: Colors.white),
                    ]),
                  ]),
                ),
              ),
            ]),
          ),
          Container(
            padding: EdgeInsets.fromLTRB(18, 10, 18, 12 + MediaQuery.of(context).padding.bottom),
            color: HC.bg,
            child: Row(children: [
              Expanded(
                flex: 10,
                child: order != null
                    ? HBtn('মেমো', kind: HBtnKind.line, height: 52, onTap: () => Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => SrOrderDetailPage(order: order!, date: DateTime.now().toIso8601String().substring(0, 10)))))
                    : HBtn('সম্পাদনা', kind: HBtnKind.line, height: 52, onTap: () => Navigator.pop(context, false)),
              ),
              const SizedBox(width: 10),
              Expanded(flex: 14, child: HBtn('অন্য দোকানে যান', height: 52, onTap: () => Navigator.pop(context, true))),
            ]),
          ),
        ]),
      ),
    );
  }
}
