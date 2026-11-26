import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/api.dart';
import '../core/format.dart';
import '../core/offline.dart';
import '../ui/common.dart';
import '../ui/pwa_kit.dart';
import '../ui/skit.dart';

Color _tint(Object? hex) {
  final s = (hex ?? '').toString().replaceFirst('#', '');
  final v = int.tryParse(s.length == 6 ? 'FF$s' : s, radix: 16);
  return v == null ? SC.subtle : Color(v);
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
  String get unitBnName => unitBn('${p['unit_type']}');

  String get badge {
    if (mode == 'pcs' || qpu == 1) return '${bn(pcs)} পিস';
    final u = pcs ~/ qpu, e = pcs % qpu;
    if (u > 0 && e > 0) return '${bn(u)} $unitBnName ${bn(e)} পিস';
    if (u > 0) return '${bn(u)} $unitBnName';
    return '${bn(e)} পিস';
  }
}

/// Step 2 of the SR order flow: pick products for one shop (grid / list), review the cart, confirm.
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
  bool _list = false;
  int? _orderId; // set once saved online, so a second save updates the same order

  bool get _editing => _orderId != null;
  bool get _locked => widget.existing != null && widget.existing!['editable'] != true;

  @override
  void initState() {
    super.initState();
    if (widget.existing != null) {
      _orderId = int0(widget.existing!['id']);
      for (final it in (widget.existing!['items'] as List)) {
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

  Future<void> _openProduct(Map<String, dynamic> p) async {
    if (_locked) {
      toast(context, 'এই অর্ডার ট্রিপে চলে গেছে — আর পরিবর্তন করা যাবে না।', error: true);
      return;
    }
    final key = '${p['id']}';
    final res = await showModalBottomSheet<_Line?>(
      context: context, isScrollControlled: true, backgroundColor: Colors.transparent, useSafeArea: true,
      builder: (_) => _ProductSheet(line: _cart[key] ?? _Line(p), existing: _cart.containsKey(key)),
    );
    if (!mounted) return;
    setState(() {
      if (res == null) {
        // dismissed
      } else if (res.pcs <= 0) {
        _cart.remove(key);
      } else {
        _cart[key] = res;
      }
    });
  }

  Future<void> _review() async {
    final go = await showModalBottomSheet<String>(
      context: context, isScrollControlled: true, backgroundColor: Colors.transparent, useSafeArea: true,
      builder: (_) => _CartSheet(lines: _lines, editing: _editing && !_locked),
    );
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
    final r = await busy(context, () => _editing
        ? ApiClient.send('PUT', '/sr/orders/$_orderId', body: body).then((d) => WriteResult(data: d))
        : OfflineQueue.write('POST', '/sr/orders', body: body, label: '${widget.shop['name']}-এর অর্ডার'));
    if (r == null || !mounted) return;
    Map<String, dynamic>? order;
    if (r.queued) {
      toast(context, 'ইন্টারনেট নেই — অর্ডার ফোনে সংরক্ষিত, নেট এলে পাঠানো হবে।');
    } else {
      final warnings = (r.data['warnings'] as List?)?.map((e) => '$e').toList() ?? [];
      if (warnings.isNotEmpty) toast(context, warnings.join('\n'));
      if (r.data['order'] is Map) {
        order = Map<String, dynamic>.from(r.data['order'] as Map);
        _orderId = int0(order['id']);
      }
    }
    final next = await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => _SuccessPage(shop: widget.shop, lines: _lines, order: order, queued: r.queued)));
    if (!mounted) return;
    if (next == true) Navigator.pop(context, true); // "অন্য দোকানে যান"
    // otherwise "সম্পাদনা" — stay here with the cart
  }

  Future<void> _cancel() async {
    if (!await confirm(context, 'অর্ডার বাতিল করবেন?', danger: true, yes: 'বাতিল করুন')) return;
    if (!mounted) return;
    final r = await busy(context, () => ApiClient.send('DELETE', '/sr/orders/$_orderId'));
    if (r != null && mounted) {
      toast(context, (r['message'] ?? 'বাতিল হয়েছে।').toString());
      Navigator.pop(context, true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final q = _q.trim().toLowerCase();
    final shown = widget.products.where((p) => q.isEmpty || '${p['name']} ${p['code']}'.toLowerCase().contains(q)).toList();
    final count = _lines.length;
    return SPage(
      child: Column(children: [
        SSubHead(
          title: '${widget.shop['name']}',
          sub: '${widget.shop['address'] ?? ''}'.isEmpty ? 'পণ্য নির্বাচন করুন' : '${widget.shop['address']}',
          trailing: _ViewSwitch(list: _list, onChanged: (v) => setState(() => _list = v)),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          decoration: const BoxDecoration(color: SC.subtle, border: Border(bottom: BorderSide(color: SC.border))),
          child: Container(
            height: 36, padding: const EdgeInsets.symmetric(horizontal: 11),
            decoration: BoxDecoration(color: SC.surface, borderRadius: BorderRadius.circular(10), border: Border.all(color: SC.border)),
            child: Row(children: [
              const Svg('<circle cx="11" cy="11" r="8"/><path d="m21 21-4.3-4.3"/>', size: 15, color: SC.muted),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _search, onChanged: (v) => setState(() => _q = v),
                  style: ts(13), decoration: InputDecoration(hintText: 'পণ্য খুঁজুন (বাংলা / Banglish)…', hintStyle: ts(13, color: SC.muted), border: InputBorder.none, isDense: true, filled: false, contentPadding: EdgeInsets.zero),
                ),
              ),
              if (_q.isNotEmpty)
                GestureDetector(
                  onTap: () => setState(() { _search.clear(); _q = ''; }),
                  child: Container(width: 20, height: 20, decoration: const BoxDecoration(color: SC.neutralBg, shape: BoxShape.circle), child: Center(child: Text('×', style: ts(14, color: SC.muted, h: 1)))),
                ),
            ]),
          ),
        ),
        if (_locked)
          Container(
            width: double.infinity, margin: const EdgeInsets.fromLTRB(14, 12, 14, 0),
            child: const SDayStatus(Text('এই অর্ডার ট্রিপে চলে গেছে — আর পরিবর্তন করা যাবে না।')),
          ),
        Expanded(
          child: shown.isEmpty
              ? const Padding(padding: EdgeInsets.all(14), child: SEmpty('কোনো পণ্য পাওয়া যায়নি।'))
              : _list
                  ? ListView.separated(
                      padding: const EdgeInsets.fromLTRB(14, 12, 14, 16), itemCount: shown.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8), itemBuilder: (_, i) => _card(shown[i], list: true))
                  : GridView.builder(
                      padding: const EdgeInsets.fromLTRB(14, 12, 14, 16), itemCount: shown.length,
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, mainAxisSpacing: 10, crossAxisSpacing: 10, mainAxisExtent: 196),
                      itemBuilder: (_, i) => _card(shown[i], list: false)),
        ),
        Container(
          padding: EdgeInsets.fromLTRB(16, 10, 16, 12 + MediaQuery.of(context).padding.bottom),
          decoration: const BoxDecoration(color: SC.surface, border: Border(top: BorderSide(color: SC.border)), boxShadow: [BoxShadow(color: Color(0x0F0F172A), blurRadius: 16, offset: Offset(0, -4))]),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('মোট', style: ts(11.5, w: FontWeight.w600, color: SC.muted)),
                Row(children: [
                  Flexible(child: Text(bnMoney(_sum, smart: true), maxLines: 1, overflow: TextOverflow.ellipsis, style: ts(20, w: FontWeight.w800, h: 1.15, tabular: true))),
                  if (count > 0) ...[
                    const SizedBox(width: 7),
                    Container(padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2), decoration: BoxDecoration(color: SC.cobaltSoft, borderRadius: BorderRadius.circular(99)), child: Text('${bn(count)}টি', style: ts(11, w: FontWeight.w700, color: SC.cobalt, h: 1.3))),
                  ],
                ]),
              ]),
            ),
            SBtn(_editing ? 'অর্ডার আপডেট' : 'অর্ডার পাঠান', height: 44, radius: 12, size: 14, onTap: count == 0 || _locked ? null : _review),
          ]),
        ),
      ]),
    );
  }

  Widget _card(Map<String, dynamic> p, {required bool list}) {
    final inCart = _cart['${p['id']}'];
    final avail = int0(p['available_pcs']);
    final qpu = int0(p['qty_per_unit']).clamp(1, 100000);
    final unit = unitBn('${p['unit_type']}');
    final image = ApiClient.asset(p['image']);
    final img = Container(
      width: list ? 58 : double.infinity, height: list ? 58 : 92,
      padding: EdgeInsets.all(list ? 4 : 8),
      decoration: BoxDecoration(color: _tint(p['tint']), borderRadius: list ? BorderRadius.circular(10) : null),
      child: Stack(children: [
        Positioned.fill(child: NetImage(image, fit: BoxFit.contain, fallback: Center(child: Text('${p['code'] ?? ''}', style: ts(14, w: FontWeight.w800))))),
        if (inCart != null && !list)
          Positioned(top: -1, right: -1, child: Container(padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2), decoration: BoxDecoration(color: SC.cobalt, borderRadius: BorderRadius.circular(99)), child: Text(inCart.badge, style: ts(10.5, w: FontWeight.w700, color: Colors.white, h: 1.3)))),
      ]),
    );
    final info = Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
      Text('${p['name']}', maxLines: 2, overflow: TextOverflow.ellipsis, style: ts(13, w: FontWeight.w700, h: 1.3)),
      const SizedBox(height: 3),
      Text.rich(TextSpan(style: ts(12, color: SC.muted, tabular: true), children: [
        TextSpan(text: '${bn(qpu)} পিস / $unit · '),
        TextSpan(text: 'স্টক ${bn(avail < 0 ? 0 : avail)}', style: ts(12, color: avail > 0 ? SC.muted : SC.dangerText)),
      ]), maxLines: 1, overflow: TextOverflow.ellipsis),
      const SizedBox(height: 3),
      if (list)
        Row(children: [
          Text.rich(TextSpan(style: ts(12.5, w: FontWeight.w700, tabular: true), children: [TextSpan(text: bnMoney(p['unit_price'], smart: true)), TextSpan(text: ' /$unit', style: ts(12, color: SC.muted, w: FontWeight.w400))])),
          const SizedBox(width: 8),
          Text('${bnMoney(p['pc_price'], smart: true)} /পিস', style: ts(12, color: SC.muted, tabular: true)),
          if (inCart != null) ...[const Spacer(), Container(padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2), decoration: BoxDecoration(color: SC.cobalt, borderRadius: BorderRadius.circular(99)), child: Text(inCart.badge, style: ts(10.5, w: FontWeight.w700, color: Colors.white, h: 1.3)))],
        ])
      else ...[
        Text.rich(TextSpan(style: ts(12.5, w: FontWeight.w700, tabular: true), children: [TextSpan(text: bnMoney(p['unit_price'], smart: true)), TextSpan(text: ' /$unit', style: ts(12, color: SC.muted, w: FontWeight.w400))])),
        Text('${bnMoney(p['pc_price'], smart: true)} /পিস', style: ts(12, color: SC.muted, tabular: true)),
      ],
    ]);
    return GestureDetector(
      onTap: () => _openProduct(p),
      child: Container(
        decoration: BoxDecoration(color: SC.surface, borderRadius: BorderRadius.circular(14), border: Border.all(color: inCart != null ? SC.cobalt : SC.border, width: 1.5), boxShadow: inCart != null ? const [BoxShadow(color: Color(0x1F1A4FD8), blurRadius: 14, offset: Offset(0, 4))] : null),
        clipBehavior: Clip.antiAlias,
        padding: list ? const EdgeInsets.all(8) : EdgeInsets.zero,
        child: list
            ? Row(children: [ClipRRect(borderRadius: BorderRadius.circular(10), child: img), const SizedBox(width: 10), Expanded(child: info)])
            : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [img, Padding(padding: const EdgeInsets.fromLTRB(10, 9, 10, 10), child: info)]),
      ),
    );
  }
}

class _ViewSwitch extends StatelessWidget {
  const _ViewSwitch({required this.list, required this.onChanged});
  final bool list;
  final ValueChanged<bool> onChanged;
  @override
  Widget build(BuildContext context) {
    Widget b(String label, bool on, bool value) => GestureDetector(
          onTap: () => onChanged(value),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
            decoration: BoxDecoration(color: on ? SC.ink : Colors.transparent, borderRadius: BorderRadius.circular(7)),
            child: Text(label, style: ts(11.5, w: FontWeight.w600, color: on ? Colors.white : SC.ink2, h: 1.3)),
          ),
        );
    return Container(
      padding: const EdgeInsets.all(3), decoration: BoxDecoration(color: SC.neutralBg, borderRadius: BorderRadius.circular(10), border: Border.all(color: SC.border)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [b('গ্রিড', !list, false), const SizedBox(width: 2), b('লিস্ট', list, true)]),
    );
  }
}

/// Bottom-sheet scaffold used by the product / cart sheets (`.modal-panel`).
class _Sheet extends StatelessWidget {
  const _Sheet({required this.title, this.sub, required this.body, required this.footer, this.icon});
  final String title;
  final String? sub;
  final Widget body, footer;
  final Widget? icon;
  @override
  Widget build(BuildContext context) => Align(
        alignment: Alignment.bottomCenter,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: kFrameW, maxHeight: MediaQuery.of(context).size.height * 0.88),
          child: Container(
            decoration: const BoxDecoration(color: SC.surface, borderRadius: BorderRadius.vertical(top: Radius.circular(20)), border: Border(top: BorderSide(color: SC.border))),
            clipBehavior: Clip.antiAlias,
            padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Padding(padding: const EdgeInsets.only(top: 9, bottom: 3), child: Container(width: 38, height: 4, decoration: BoxDecoration(color: SC.borderStrong, borderRadius: BorderRadius.circular(99)))),
              Container(
                padding: const EdgeInsets.fromLTRB(16, 10, 14, 12),
                decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: SC.border))),
                child: Row(children: [
                  if (icon != null) ...[icon!, const SizedBox(width: 9)],
                  Expanded(child: SSecTitle(title, sub: sub)),
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Container(width: 34, height: 34, decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: SC.border)), child: const Center(child: Svg('<path d="M18 6 6 18M6 6l12 12"/>', size: 16, color: SC.ink2, stroke: 2.2))),
                  ),
                ]),
              ),
              Flexible(child: body),
              footer,
            ]),
          ),
        ),
      );
}

/// Quantity (ইউনিট / পিস), rate and total of one product — the difference to the base price is the O/C.
class _ProductSheet extends StatefulWidget {
  const _ProductSheet({required this.line, required this.existing});
  final _Line line;
  final bool existing;
  @override
  State<_ProductSheet> createState() => _ProductSheetState();
}

class _ProductSheetState extends State<_ProductSheet> {
  late String _mode = widget.line.qpu == 1 ? 'pcs' : widget.line.mode;
  late final _unit = TextEditingController();
  late final _extra = TextEditingController();
  late final _pcsC = TextEditingController();
  late final _rate = TextEditingController();
  late final _total = TextEditingController();
  bool _manual = false;

  _Line get l => widget.line;
  int get _pcs => _mode == 'unit' ? (int.tryParse(_unit.text) ?? 0) * l.qpu + (int.tryParse(_extra.text) ?? 0) : (int.tryParse(_pcsC.text) ?? 0);
  double get _base => _pcs * l.rate;
  double get _totalVal => double.tryParse(_total.text) ?? 0;

  @override
  void initState() {
    super.initState();
    final pcs = widget.existing ? l.pcs : 0;
    if (widget.existing) {
      _setQty(pcs);
      _total.text = _trim(l.total);
      _manual = (l.total - pcs * l.rate).abs() > 0.009;
    } else {
      if (l.qpu > 1) {
        _unit.text = '1';
        _extra.text = '0';
      } else {
        _pcsC.text = '1';
      }
      _total.text = _trim(_base);
    }
    _syncRate();
  }

  void _setQty(int pcs) {
    if (_mode == 'unit') {
      _unit.text = '${pcs ~/ l.qpu}';
      _extra.text = '${pcs % l.qpu}';
    } else {
      _pcsC.text = '$pcs';
    }
  }

  /// rate shown per ইউনিট (unit mode) or per পিস
  void _syncRate() {
    final pcs = _pcs;
    final perPc = pcs > 0 ? _totalVal / pcs : l.rate;
    _rate.text = _trim(_mode == 'unit' ? perPc * l.qpu : perPc);
  }

  void _onQty() {
    if (!_manual) _total.text = _pcs == 0 ? '' : _trim(_base);
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

  void _step(TextEditingController c, int d, {int min = 0}) {
    final n = ((int.tryParse(c.text) ?? 0) + d).clamp(min, 1000000);
    c.text = '$n';
    _onQty();
  }

  Widget _stepper(TextEditingController c, {int min = 0}) => Row(children: [
        _stepBtn('−', () => _step(c, -1, min: min)),
        const SizedBox(width: 5),
        Expanded(child: _field(c, onChanged: (_) => _onQty(), center: true)),
        const SizedBox(width: 5),
        _stepBtn('+', () => _step(c, 1, min: min)),
      ]);

  Widget _stepBtn(String t, VoidCallback onTap) => GestureDetector(
        onTap: onTap,
        child: Container(width: 38, height: 38, decoration: BoxDecoration(color: SC.subtle, borderRadius: BorderRadius.circular(10), border: Border.all(color: SC.borderStrong)), child: Center(child: Text(t, style: ts(18, w: FontWeight.w600, h: 1)))),
      );

  Widget _field(TextEditingController c, {ValueChanged<String>? onChanged, bool center = false, bool decimal = false}) => SizedBox(
        height: 40,
        child: TextField(
          controller: c, onChanged: onChanged,
          textAlign: center ? TextAlign.center : TextAlign.start,
          keyboardType: TextInputType.numberWithOptions(decimal: decimal),
          inputFormatters: [FilteringTextInputFormatter.allow(decimal ? RegExp(r'[0-9.]') : RegExp(r'[0-9]'))],
          style: ts(13.5, w: center ? FontWeight.w700 : FontWeight.w400, tabular: true),
          decoration: InputDecoration(
            isDense: true, filled: true, fillColor: SC.surface, contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: SC.borderStrong)),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: SC.borderStrong)),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: SC.cobalt)),
          ),
        ),
      );

  Widget _label(String t) => Padding(padding: const EdgeInsets.only(bottom: 5), child: Text(t, style: ts(12.5, w: FontWeight.w600, color: SC.ink2)));

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

  @override
  Widget build(BuildContext context) {
    final p = l.p;
    final unit = unitBn('${p['unit_type']}');
    final oc = _totalVal - _base;
    final over = oc > 0.009, comm = oc < -0.009;
    final avail = int0(p['available_pcs']);
    return _Sheet(
      title: '${p['name']}',
      sub: '${bn(l.qpu)} পিস / $unit · স্টক ${bn(avail < 0 ? 0 : avail)}',
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (l.qpu > 1) ...[
            _label('অর্ডারের ধরন'),
            Container(
              padding: const EdgeInsets.all(3), decoration: BoxDecoration(color: SC.neutralBg, borderRadius: BorderRadius.circular(10), border: Border.all(color: SC.border)),
              child: Row(children: [
                for (final m in [('unit', 'ইউনিট'), ('pcs', 'পিস')])
                  Expanded(
                    child: GestureDetector(
                      onTap: () {
                        if (_mode == m.$1) return;
                        final pcs = _pcs;
                        _mode = m.$1;
                        _setQty(pcs);
                        _syncRate();
                        setState(() {});
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        decoration: BoxDecoration(color: _mode == m.$1 ? SC.surface : Colors.transparent, borderRadius: BorderRadius.circular(8), border: Border.all(color: _mode == m.$1 ? const Color(0xFFC7D7FE) : Colors.transparent)),
                        child: Center(child: Text(m.$2, style: ts(13, w: FontWeight.w600, color: _mode == m.$1 ? SC.cobalt : SC.ink2))),
                      ),
                    ),
                  ),
              ]),
            ),
            const SizedBox(height: 12),
          ],
          if (_mode == 'unit')
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [_label(unit), _stepper(_unit)])),
              const SizedBox(width: 10),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [_label('পিস'), _stepper(_extra)])),
            ])
          else
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [_label('পরিমাণ (পিস)'), _stepper(_pcsC)]),
          const SizedBox(height: 12),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                _label(_mode == 'unit' ? 'প্রতি ইউনিট দর (৳)' : 'প্রতি পিস দর (৳)'),
                _field(_rate, onChanged: _onRate, decimal: true),
                Padding(padding: const EdgeInsets.only(top: 5), child: Text('বেজ: ${bnMoney(_mode == 'unit' ? l.rate * l.qpu : l.rate, smart: true)}', style: ts(12, color: SC.muted, tabular: true))),
              ]),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                _label('মোট টাকা (৳)'),
                _field(_total, onChanged: _onTotal, decimal: true),
                Padding(padding: const EdgeInsets.only(top: 5), child: Text('নির্ধারিত: ${bnMoney(_base, smart: true)}', style: ts(12, color: SC.muted, tabular: true))),
              ]),
            ),
          ]),
          if (_pcs > avail && avail >= 0)
            Padding(padding: const EdgeInsets.only(top: 10), child: Text('${bn(_pcs)} পিস — স্টকের চেয়ে বেশি!', style: ts(12, w: FontWeight.w600, color: SC.warnText))),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
            decoration: BoxDecoration(color: over ? SC.okBg : (comm ? SC.warnBg : SC.subtle), borderRadius: BorderRadius.circular(10), border: Border.all(color: over ? SC.okBorder : (comm ? SC.warnBorder : SC.border))),
            child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('হিসাবকৃত O/C', style: ts(12, color: SC.muted)),
                Text(over ? 'ওভার (বেশি দামে)' : (comm ? 'কমিশন (কম দামে)' : 'নির্ধারিত দর'), style: ts(11.5, color: SC.ink2)),
              ]),
              Text(bnMoney(oc.abs(), smart: true), style: ts(17, w: FontWeight.w800, color: over ? SC.ok : (comm ? SC.warnText : SC.ink), tabular: true)),
            ]),
          ),
        ]),
      ),
      footer: Container(
        padding: EdgeInsets.fromLTRB(16, 12, 16, 12 + MediaQuery.of(context).padding.bottom),
        decoration: const BoxDecoration(border: Border(top: BorderSide(color: SC.border))),
        child: Row(children: [
          if (widget.existing) SBtn('সরান', kind: SBtnKind.dangerGhost, size: 12.5, onTap: () => Navigator.pop(context, _Line(l.p))),
          const Spacer(),
          SBtn('বাতিল', kind: SBtnKind.secondary, onTap: () => Navigator.pop(context)),
          const SizedBox(width: 8),
          SBtn('অর্ডারে যোগ করুন', onTap: _save),
        ]),
      ),
    );
  }
}

/// Cart review (`#orderCartModal`): lines with O/C tag, total, confirm.
class _CartSheet extends StatelessWidget {
  const _CartSheet({required this.lines, required this.editing});
  final List<_Line> lines;
  final bool editing;
  @override
  Widget build(BuildContext context) {
    final oc = lines.fold<double>(0, (a, l) => a + l.oc);
    final sum = lines.fold<double>(0, (a, l) => a + l.total);
    final over = oc > 0.009, comm = oc < -0.009;
    return _Sheet(
      title: 'অর্ডার সারাংশ',
      icon: const Svg('<circle cx="9" cy="21" r="1"/><circle cx="20" cy="21" r="1"/><path d="M1 1h4l2.68 13.39a2 2 0 0 0 2 1.61h9.72a2 2 0 0 0 2-1.61L23 6H6"/>', size: 20, color: SC.cobalt, stroke: 2.1),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Container(
          decoration: BoxDecoration(color: SC.surface, borderRadius: BorderRadius.circular(16), border: Border.all(color: SC.border)),
          clipBehavior: Clip.antiAlias,
          child: Column(children: [
            Container(
              color: SC.subtle, padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 9),
              child: Row(children: [
                Expanded(flex: 5, child: Text('পণ্য', style: ts(10.5, w: FontWeight.w700, color: SC.muted))),
                Expanded(flex: 3, child: Text('পরিমাণ', textAlign: TextAlign.center, style: ts(10.5, w: FontWeight.w700, color: SC.muted))),
                Expanded(flex: 3, child: Text('মূল্য', textAlign: TextAlign.right, style: ts(10.5, w: FontWeight.w700, color: SC.muted))),
              ]),
            ),
            for (var i = 0; i < lines.length; i++) _row(lines[i], last: i == lines.length - 1),
          ]),
        ),
      ),
      footer: Container(
        padding: EdgeInsets.fromLTRB(14, 12, 14, 14 + MediaQuery.of(context).padding.bottom),
        decoration: const BoxDecoration(border: Border(top: BorderSide(color: SC.border))),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(color: SC.subtle, borderRadius: BorderRadius.circular(14), border: Border.all(color: SC.border)),
            child: Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('O/C ${bnMoney(oc.abs(), smart: true)}', style: ts(12, w: FontWeight.w700, color: over ? SC.ok : (comm ? SC.warnText : SC.ink2), tabular: true)),
                  Text.rich(TextSpan(style: ts(12.5, color: SC.ink2, tabular: true), children: [const TextSpan(text: 'মোট: '), TextSpan(text: bnMoney(sum, smart: true), style: ts(16, w: FontWeight.w700))])),
                ]),
              ),
              SBtn('অর্ডার কনফার্ম', height: 42, onTap: () => Navigator.pop(context, 'confirm')),
            ]),
          ),
          if (editing) Padding(padding: const EdgeInsets.only(top: 8), child: Center(child: SBtn('অর্ডারটি বাতিল করুন', kind: SBtnKind.dangerGhost, size: 12.5, onTap: () => Navigator.pop(context, 'cancel')))),
        ]),
      ),
    );
  }

  Widget _row(_Line l, {required bool last}) {
    final oc = l.oc;
    final image = ApiClient.asset(l.p['image']);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      decoration: BoxDecoration(border: last ? null : const Border(top: BorderSide(color: SC.border))),
      child: Row(children: [
        Expanded(
          flex: 5,
          child: Row(children: [
            Container(width: 36, height: 36, decoration: BoxDecoration(color: _tint(l.p['tint']), borderRadius: BorderRadius.circular(9), border: Border.all(color: SC.border)), clipBehavior: Clip.antiAlias, child: NetImage(image, fallback: Center(child: Text('${l.p['code'] ?? ''}', style: ts(10, w: FontWeight.w800, h: 1))))),
            const SizedBox(width: 9),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${l.p['name']}', maxLines: 2, overflow: TextOverflow.ellipsis, style: ts(12.5, w: FontWeight.w700, h: 1.25)),
                if (oc.abs() > 0.009)
                  Container(
                    margin: const EdgeInsets.only(top: 3), padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                    decoration: BoxDecoration(color: oc > 0 ? SC.okBg : SC.warnBg, borderRadius: BorderRadius.circular(5), border: Border.all(color: oc > 0 ? SC.okBorder : SC.warnBorder)),
                    child: Text('${oc > 0 ? '+' : '−'}${bn(num2(oc.abs()))} O/C', style: ts(10.5, w: FontWeight.w700, color: oc > 0 ? SC.ok : SC.warnText, h: 1.4)),
                  ),
              ]),
            ),
          ]),
        ),
        Expanded(
          flex: 3,
          child: Center(child: Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), decoration: BoxDecoration(color: SC.subtle, borderRadius: BorderRadius.circular(8), border: Border.all(color: SC.border)), child: Text(l.badge, style: ts(11.5, w: FontWeight.w700)))),
        ),
        Expanded(flex: 3, child: Text(bnMoney(l.total, smart: true), textAlign: TextAlign.right, style: ts(12.5, w: FontWeight.w700, tabular: true))),
      ]),
    );
  }
}

/// Step 3: "অর্ডার পাঠানো হয়েছে" + memo receipt.
class _SuccessPage extends StatelessWidget {
  const _SuccessPage({required this.shop, required this.lines, required this.order, required this.queued});
  final Map<String, dynamic> shop;
  final List<_Line> lines;
  final Map<String, dynamic>? order;
  final bool queued;

  @override
  Widget build(BuildContext context) {
    final total = lines.fold<double>(0, (a, l) => a + l.total);
    final oc = lines.fold<double>(0, (a, l) => a + l.oc);
    final code = order?['code'];
    return SPage(
      child: Column(children: [
        Expanded(
          child: ListView(padding: EdgeInsets.fromLTRB(14, 18 + MediaQuery.of(context).padding.top, 14, 18), children: [
            Column(children: [
              Container(width: 60, height: 60, decoration: const BoxDecoration(color: SC.ok, shape: BoxShape.circle, boxShadow: [BoxShadow(color: Color(0x4715803D), blurRadius: 20, offset: Offset(0, 8))]), child: const Center(child: Svg('<polyline points="20 6 9 17 4 12"/>', size: 28, color: Colors.white, stroke: 2.8))),
              const SizedBox(height: 9),
              Text(queued ? 'অর্ডার ফোনে সংরক্ষিত' : 'অর্ডার পাঠানো হয়েছে', style: ts(19, w: FontWeight.w800)),
              Text(queued ? 'ইন্টারনেট এলে পাঠানো হবে' : 'অর্ডার কনফার্ম হয়েছে', style: ts(12.5, w: FontWeight.w600, color: SC.muted)),
            ]),
            const SizedBox(height: 14),
            Container(
              decoration: BoxDecoration(color: SC.surface, borderRadius: BorderRadius.circular(16), border: Border.all(color: SC.border), boxShadow: const [BoxShadow(color: Color(0x140F172A), blurRadius: 24, offset: Offset(0, 8))]),
              clipBehavior: Clip.antiAlias,
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
                  decoration: const BoxDecoration(gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF1B44C2), Color(0xFF1A4FD8)])),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('অর্ডার রসিদ', style: ts(10.5, w: FontWeight.w600, color: const Color(0xC7FFFFFF))), Text('${shop['name']}', style: ts(16, w: FontWeight.w800, color: Colors.white))])),
                    Column(crossAxisAlignment: CrossAxisAlignment.end, children: [Text('মেমো নং', style: ts(10.5, w: FontWeight.w600, color: const Color(0xC7FFFFFF))), Text(code == null ? '—' : bn(code), style: ts(15, w: FontWeight.w700, color: Colors.white, tabular: true))]),
                  ]),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: const BoxDecoration(color: SC.subtle, border: Border(bottom: BorderSide(color: SC.border))),
                  child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                    Text(dateTimeBn(order?['created_at']?.toString() ?? DateTime.now().toIso8601String()), style: ts(11.5, w: FontWeight.w600, color: SC.ink2, tabular: true)),
                    if (order?['sr'] != null) Flexible(child: Text('SR: ${order!['sr']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: ts(11.5, w: FontWeight.w600, color: SC.ink2))),
                  ]),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: SC.border))),
                  child: Row(children: [
                    Expanded(flex: 5, child: Text('বিবরণ', style: ts(11, w: FontWeight.w700, color: SC.muted))),
                    Expanded(flex: 3, child: Text('পরিমাণ', textAlign: TextAlign.center, style: ts(11, w: FontWeight.w700, color: SC.muted))),
                    Expanded(flex: 3, child: Text('টাকা', textAlign: TextAlign.right, style: ts(11, w: FontWeight.w700, color: SC.muted))),
                  ]),
                ),
                for (var i = 0; i < lines.length; i++)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                    decoration: BoxDecoration(border: i == lines.length - 1 ? null : const Border(bottom: BorderSide(color: SC.border))),
                    child: Row(children: [
                      Expanded(flex: 5, child: Text('${lines[i].p['name']}', style: ts(12.5, w: FontWeight.w700, h: 1.3))),
                      Expanded(flex: 3, child: Text(lines[i].badge, textAlign: TextAlign.center, style: ts(12.5, tabular: true))),
                      Expanded(flex: 3, child: Text(bnMoney(lines[i].total, smart: true), textAlign: TextAlign.right, style: ts(12.5, tabular: true))),
                    ]),
                  ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13), color: SC.ink,
                  child: Row(children: [
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('দোকানের মোট', style: ts(13, w: FontWeight.w700, color: Colors.white)),
                        Text.rich(TextSpan(style: ts(11, color: const Color(0xB8FFFFFF), tabular: true), children: [
                          const TextSpan(text: 'ডেলিভারিতে নগদ · O/C '),
                          TextSpan(text: bnMoney(oc.abs(), smart: true), style: ts(11, w: FontWeight.w700, color: oc > 0 ? const Color(0xFF86EFAC) : (oc < 0 ? const Color(0xFFFDE68A) : Colors.white))),
                        ])),
                      ]),
                    ),
                    Text(bnMoney(total, smart: true), style: ts(22, w: FontWeight.w800, color: Colors.white, h: 1.1, tabular: true)),
                  ]),
                ),
              ]),
            ),
          ]),
        ),
        Container(
          padding: EdgeInsets.fromLTRB(14, 12, 14, 14 + MediaQuery.of(context).padding.bottom),
          decoration: const BoxDecoration(color: SC.surface, border: Border(top: BorderSide(color: SC.border))),
          child: Row(children: [
            Expanded(flex: 100, child: SBtn('সম্পাদনা / ফেরত', kind: SBtnKind.secondary, height: 44, radius: 12, icon: const Svg('<path d="M3 7v6h6"/><path d="M21 17a9 9 0 0 0-9-9 9 9 0 0 0-6 2.3L3 13"/>', size: 15, color: SC.ink), onTap: () => Navigator.pop(context, false))),
            const SizedBox(width: 10),
            Expanded(flex: 135, child: SBtn('অন্য দোকানে যান', height: 44, radius: 12, icon: null, onTap: () => Navigator.pop(context, true))),
          ]),
        ),
      ]),
    );
  }
}
