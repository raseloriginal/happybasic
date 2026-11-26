import 'package:flutter/material.dart';

import '../core/format.dart';
import '../core/printer.dart';
import '../ui/common.dart';
import '../ui/pwa_kit.dart';
import 'rkit.dart';

Map<String, dynamic> _m(Object? v) => Map<String, dynamic>.from((v ?? {}) as Map);

enum InvoiceMode { order, delivery }

/// Order invoice / delivery invoice — same layout as /retailer/invoice and /retailer/delivery-invoice.
/// The PWA's "শেয়ার / PDF" button is a Bluetooth print here.
class InvoicePage extends StatefulWidget {
  const InvoicePage({super.key, required this.date, required this.orders, required this.selectedId, this.mode = InvoiceMode.order});
  final String date;
  final List<Map<String, dynamic>> orders;
  final int selectedId;
  final InvoiceMode mode;
  @override
  State<InvoicePage> createState() => _InvoicePageState();
}

class _InvoicePageState extends State<InvoicePage> {
  late int _cur = _indexOf(widget.selectedId);
  late InvoiceMode _mode = widget.mode;

  int _indexOf(int id) {
    final i = widget.orders.indexWhere((o) => int0(o['id']) == id);
    return i < 0 ? 0 : i;
  }

  List<ReceiptLine> _receipt(Map<String, dynamic> o) {
    final shop = _m(o['shop']);
    final partner = _m(o['partner']);
    return [
      ReceiptLine('হ্যাপি বাংলাদেশ', style: ReceiptStyle.title, center: true),
      ReceiptLine('${partner['name']}', center: true, style: ReceiptStyle.bold),
      if ('${partner['phone'] ?? ''}'.isNotEmpty) ReceiptLine('${partner['phone']}', center: true, style: ReceiptStyle.small),
      ReceiptLine.rule(),
      ReceiptLine('মেমো ${o['code']}', right: dateBn(widget.date)),
      ReceiptLine('${shop['name']}', style: ReceiptStyle.bold),
      ReceiptLine('${o['company']} · SR ${o['sr']}', style: ReceiptStyle.small),
      ReceiptLine.rule(),
      for (final it in (o['items'] as List).map(_m)) ...[
        ReceiptLine('${it['name']}'),
        ReceiptLine('  ${bn(it['pcs'])} × ${numTrim(it['rate'])}', right: money(it['amount']), style: ReceiptStyle.small),
      ],
      ReceiptLine.rule(),
      ReceiptLine('সাবটোটাল', right: money(o['subtotal'])),
      if (num0(o['damage']) > 0) ReceiptLine('ড্যামেজ কর্তন', right: money(o['damage'])),
      ReceiptLine('মোট', right: money(o['total']), style: ReceiptStyle.bold),
      if (num0(o['paid']) > 0) ReceiptLine('নগদ পরিশোধ', right: money(o['paid'])),
      if (num0(o['due']) > 0) ReceiptLine('বাকি', right: money(o['due']), style: ReceiptStyle.bold),
      ReceiptLine.rule(),
      ReceiptLine('ধন্যবাদ', center: true),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final orders = widget.orders;
    final o = orders.isEmpty ? null : orders[_cur.clamp(0, orders.length - 1)];
    final delivery = _mode == InvoiceMode.delivery;
    return Scaffold(
      backgroundColor: RC.outer,
      body: Frame(
        child: Container(
          color: RC.bg,
          child: Column(children: [
            RPlainHead(title: 'ইনভয়েস', subtitle: delivery ? null : 'প্রতিটা কোম্পানির আলাদা ইনভয়েস', onBack: () => Navigator.pop(context)),
            Expanded(
              child: ListView(padding: const EdgeInsets.fromLTRB(14, 14, 14, 40), children: [
                if (delivery) _Seg(mode: _mode, onChanged: (m) => setState(() => _mode = m)),
                if (orders.length > 1)
                  SizedBox(
                    height: 56,
                    child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.fromLTRB(2, 2, 2, 14), children: [
                      for (var i = 0; i < orders.length; i++)
                        Padding(
                          padding: const EdgeInsets.only(right: 10),
                          child: GestureDetector(
                            onTap: () => setState(() => _cur = i),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                              decoration: BoxDecoration(
                                color: _cur == i ? RC.ink : Colors.white, borderRadius: BorderRadius.circular(99),
                                border: Border.all(color: _cur == i ? RC.ink : RC.border),
                              ),
                              alignment: Alignment.center,
                              child: Text('${orders[i]['company']} · ${orders[i]['sr']}', style: ts(14, w: FontWeight.w700, color: _cur == i ? Colors.white : RC.ink)),
                            ),
                          ),
                        ),
                    ]),
                  ),
                if (o == null)
                  const REmpty('এই দিনে কোনো ইনভয়েস নেই')
                else ...[
                  delivery ? _DeliveryInvoice(o: o, date: widget.date) : _OrderInvoice(o: o, date: widget.date),
                  Row(children: [
                    Expanded(child: _ActionBtn('প্রিন্ট করুন', bg: Colors.white, fg: RC.ink, border: true, onTap: () async {
                      final err = await busy(context, () => PrinterService.print(_receipt(o)));
                      if (context.mounted) toast(context, err ?? 'প্রিন্ট হয়েছে।', error: err != null);
                    })),
                    const SizedBox(width: 10),
                    Expanded(child: _ActionBtn('সমস্যা জানান', bg: RC.dangerSoft, fg: RC.danger, onTap: () {
                      showDialog<void>(
                        context: context,
                        builder: (c) => AlertDialog(
                          content: Text('সমস্যা জানাতে আপনার ডেলিভারি ম্যান বা SR-কে ফোন করুন।', style: ts(15)),
                          actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('ঠিক আছে'))],
                        ),
                      );
                    })),
                  ]),
                  if (delivery && '${o['stage']}' == 'arrived' && o['profit_per_100'] != null)
                    Container(
                      margin: const EdgeInsets.only(top: 16),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(color: RC.okSoft, borderRadius: BorderRadius.circular(20)),
                      child: Row(children: [
                        Text('৳', style: ts(26, w: FontWeight.w700)),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Text.rich(TextSpan(style: ts(15, h: 1.5), children: [
                            const TextSpan(text: 'প্রতি '),
                            TextSpan(text: '৳১০০', style: ts(15, w: FontWeight.w700)),
                            const TextSpan(text: ' কেনায় আপনার লাভ '),
                            TextSpan(text: money(o['profit_per_100']), style: ts(15, w: FontWeight.w700, color: RC.ok)),
                          ])),
                        ),
                      ]),
                    ),
                ],
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

class _Seg extends StatelessWidget {
  const _Seg({required this.mode, required this.onChanged});
  final InvoiceMode mode;
  final ValueChanged<InvoiceMode> onChanged;
  @override
  Widget build(BuildContext context) {
    Widget item(String t, InvoiceMode m) => Expanded(
          child: GestureDetector(
            onTap: () => onChanged(m),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 11),
              decoration: BoxDecoration(
                color: mode == m ? Colors.white : Colors.transparent, borderRadius: BorderRadius.circular(16),
                boxShadow: mode == m ? const [BoxShadow(color: Color(0x1A0F172A), blurRadius: 8, offset: Offset(0, 2))] : null,
              ),
              child: Center(child: Text(t, style: ts(14, w: FontWeight.w700, color: mode == m ? RC.ink : RC.ink2))),
            ),
          ),
        );
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(color: const Color(0xFFE6EBF3), borderRadius: BorderRadius.circular(22)),
      child: Row(children: [item('অর্ডার ইনভয়েস', InvoiceMode.order), item('ডেলিভারি ইনভয়েস', InvoiceMode.delivery)]),
    );
  }
}

class _ActionBtn extends StatelessWidget {
  const _ActionBtn(this.text, {required this.bg, required this.fg, required this.onTap, this.border = false});
  final String text;
  final Color bg, fg;
  final bool border;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          height: 52,
          decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(18), border: border ? Border.all(color: RC.border) : null),
          child: Center(child: Text(text, style: ts(15.5, w: FontWeight.w700, color: fg))),
        ),
      );
}

Widget _tot(String k, String v, {bool grand = false, Color? vColor, bool muted = false, bool boldK = false}) => Container(
      margin: EdgeInsets.only(top: grand ? 6 : 0),
      padding: EdgeInsets.only(top: grand ? 8 : 4, bottom: 4),
      decoration: grand ? const BoxDecoration(border: Border(top: BorderSide(color: RC.ink))) : null,
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Flexible(child: Text(k, style: ts(grand ? 17 : 14, w: grand || boldK ? FontWeight.w700 : FontWeight.w400, color: grand ? RC.ink : (muted ? RC.muted : RC.ink2)))),
        const SizedBox(width: 10),
        Text(v, style: ts(grand ? 20 : 14, w: grand ? FontWeight.w700 : FontWeight.w400, color: vColor ?? (grand ? RC.ink : (muted ? RC.muted : RC.ink2)), tabular: true)),
      ]),
    );

class _OrderInvoice extends StatelessWidget {
  const _OrderInvoice({required this.o, required this.date});
  final Map<String, dynamic> o;
  final String date;

  @override
  Widget build(BuildContext context) {
    final partner = _m(o['partner']);
    final shop = _m(o['shop']);
    final items = (o['items'] as List).map(_m).toList();
    final ok = '${o['tone']}' == 'ok';
    final badgeBg = ok ? RC.okSoft : RC.warnSoft;
    final badgeFg = ok ? RC.ok : RC.warn;
    Widget kv(String k, String v) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(k, style: ts(12, color: RC.muted, h: 1.4)),
          Text(v, style: ts(14, w: FontWeight.w600, h: 1.4)),
        ]);
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 22),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: RC.blue, width: 6)),
        borderRadius: BorderRadius.only(topLeft: Radius.circular(10), topRight: Radius.circular(10), bottomLeft: Radius.circular(22), bottomRight: Radius.circular(22)),
        boxShadow: RC.shadow,
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Container(
            width: 46, height: 46,
            decoration: BoxDecoration(color: RC.blue, borderRadius: BorderRadius.circular(12)),
            child: const Center(child: Svg(Ic.logoMark, size: 26, color: Colors.white, stroke: 2.4)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Happy Bangladesh', style: ts(16, w: FontWeight.w700, h: 1.2)),
              Text([partner['name'], partner['phone']].where((x) => x != null && '$x'.isNotEmpty).join(' · '), style: ts(12, color: RC.muted, h: 1.4)),
            ]),
          ),
        ]),
        Padding(
          padding: const EdgeInsets.only(top: 14),
          child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text('INVOICE', style: ts(18, w: FontWeight.w700, ls: 1.5, h: 1.2)),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(color: badgeBg, borderRadius: BorderRadius.circular(6)),
              child: Text('${o['status']}', style: ts(12.5, w: FontWeight.w700, color: badgeFg)),
            ),
          ]),
        ),
        Container(
          margin: const EdgeInsets.symmetric(vertical: 14),
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: const BoxDecoration(border: Border.symmetric(horizontal: BorderSide(color: RC.border))),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('বিল টু', style: ts(12, w: FontWeight.w700, color: RC.ink2)),
                Text('${shop['name']}', style: ts(18, w: FontWeight.w700, h: 1.3)),
                if ('${shop['address'] ?? ''}'.isNotEmpty) Text('${shop['address']}', style: ts(13.5, color: RC.ink2, h: 1.4)),
                if ('${shop['phone'] ?? ''}'.isNotEmpty) Text('${shop['phone']}', style: ts(13.5, color: RC.ink2, h: 1.4)),
              ]),
            ),
            Wrap(runSpacing: 8, children: [
              for (final p in [
                ('ইনভয়েস নং', '${o['code']}'),
                ('তারিখ', dateLongBn(date)),
                ('কোম্পানি', '${o['company']}'),
                ('SR', '${o['sr']}'),
                ('ডেলিভারি', '${o['dm'] ?? '—'}'),
              ])
                FractionallySizedBox(widthFactor: 0.5, child: Padding(padding: const EdgeInsets.only(right: 7), child: kv(p.$1, p.$2))),
            ]),
          ]),
        ),
        for (var n = 0; n < items.length; n++)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: RC.border))),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SizedBox(width: 18, child: Text(bn(n + 1), style: ts(13, color: RC.muted))),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${items[n]['name']}', style: ts(15, w: FontWeight.w700, h: 1.35)),
                  Text('${numTrim(items[n]['pcs'])} পিস × ${money(items[n]['rate'])}${items[n]['mrp'] != null ? ' · MRP ${money(items[n]['mrp'])}' : ''}', style: ts(12.5, color: RC.muted, h: 1.4)),
                ]),
              ),
              const SizedBox(width: 10),
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text(money(items[n]['amount']), style: ts(15, w: FontWeight.w700, tabular: true)),
                if (items[n]['gain'] != null) Text('+${money(items[n]['gain'])}', style: ts(12.5, w: FontWeight.w700, color: RC.ok)),
              ]),
            ]),
          ),
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            _tot('সাবটোটাল', money(o['subtotal'])),
            _tot(num0(o['damage']) > 0 ? 'ড্যামেজ কর্তন' : 'ছাড়', money(o['damage'])),
            _tot('মোট', money(o['total']), grand: true),
            if (num0(o['paid']) > 0) _tot('নগদ পরিশোধ', money(o['paid'])),
            if (num0(o['due']) > 0) _tot('বাকি', money(o['due'])),
            if (o['profit'] != null)
              Container(
                margin: const EdgeInsets.only(top: 10),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(color: RC.okSoft, borderRadius: BorderRadius.circular(10)),
                child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('আপনার লাভ', style: ts(16, w: FontWeight.w700, color: RC.ok)),
                    Text('সব MRP-তে বেচলে', style: ts(12, color: RC.ok)),
                  ]),
                  Text('+${money(o['profit'])}', style: ts(21, w: FontWeight.w700, color: RC.ok)),
                ]),
              ),
          ]),
        ),
        Padding(padding: const EdgeInsets.only(top: 14, bottom: 28), child: Text('কথায়: ${o['words'] ?? ''}', style: ts(13.5, color: RC.ink2, h: 1.5))),
        Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: Row(children: [
            for (final t in ['গ্রাহকের স্বাক্ষর', 'ডেলিভারি ম্যান']) ...[
              if (t != 'গ্রাহকের স্বাক্ষর') const SizedBox(width: 26),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.only(top: 6),
                  decoration: const BoxDecoration(border: Border(top: BorderSide(color: RC.ink2))),
                  child: Text(t, textAlign: TextAlign.center, style: ts(12.5, color: RC.muted)),
                ),
              ),
            ],
          ]),
        ),
        Container(
          padding: const EdgeInsets.only(top: 12),
          decoration: const BoxDecoration(border: Border(top: BorderSide(color: RC.border))),
          child: Text('মাল বুঝে নিয়ে স্বাক্ষর করুন · নষ্ট বা কম হলে ২৪ ঘণ্টার মধ্যে জানান · ধন্যবাদ', textAlign: TextAlign.center, style: ts(12.5, color: RC.ink2, h: 1.5)),
        ),
      ]),
    );
  }
}

class _DeliveryInvoice extends StatelessWidget {
  const _DeliveryInvoice({required this.o, required this.date});
  final Map<String, dynamic> o;
  final String date;

  @override
  Widget build(BuildContext context) {
    final box = BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8), border: Border.all(color: RC.border));
    if ('${o['stage']}' != 'arrived') {
      return Container(
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.fromLTRB(20, 28, 20, 28),
        decoration: box,
        child: Column(children: [
          Text('মাল এখনো আসেনি', style: ts(17, w: FontWeight.w700), textAlign: TextAlign.center),
          Text('${o['status']} · ডেলিভারি ইনভয়েস মাল পৌঁছালে এখানে দেখা যাবে।', style: ts(14, color: RC.ink2), textAlign: TextAlign.center),
        ]),
      );
    }
    final partner = _m(o['partner']);
    final shop = _m(o['shop']);
    final items = (o['items'] as List).map(_m).toList();
    Widget kv(String k, Widget v) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(k, style: ts(14, color: RC.ink2, h: 1.5)),
            const SizedBox(width: 12),
            Flexible(child: v),
          ]),
        );
    final time = '${o['time'] ?? ''}';
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.fromLTRB(14, 16, 14, 18),
      decoration: box,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Container(
          padding: const EdgeInsets.only(bottom: 12),
          margin: const EdgeInsets.only(bottom: 10),
          decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: RC.ink))),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${o['company']} · ${partner['name']}', style: ts(16.5, w: FontWeight.w700, h: 1.35)),
            Text('Happy Bangladesh', style: ts(13, color: RC.muted, h: 1.4)),
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Text('ডেলিভারি ইনভয়েস', style: ts(16.5, w: FontWeight.w700)),
                Text('${o['code']}', style: ts(13, color: RC.muted)),
              ]),
            ),
          ]),
        ),
        kv('দোকান', Text('${shop['name']}', textAlign: TextAlign.right, style: ts(15.5, w: FontWeight.w700, h: 1.4))),
        kv('ডেলিভারি', Text('${o['dm'] ?? '—'}${time.isNotEmpty ? ' · ${bn(time)}' : ''}', textAlign: TextAlign.right, style: ts(14, color: RC.ink2, h: 1.5))),
        kv('তারিখ', Text(dateLongBn(date), style: ts(14, color: RC.ink2, h: 1.5))),
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Column(children: [
            for (final it in items)
              Container(
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: RC.border))),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('${it['name']}', style: ts(15, w: FontWeight.w700, h: 1.35)),
                      Text('${numTrim(it['pcs'])} পিস × ${money(it['rate'])} কেনা${it['mrp'] != null ? ' · MRP ${money(it['mrp'])}' : ''}', style: ts(12.5, color: RC.muted, h: 1.4)),
                      if (num0(it['short']) > 0) Text('${numTrim(it['short'])}টি কম · ভ্যানে ছিল না', style: ts(12.5, color: RC.warn, h: 1.4)),
                    ]),
                  ),
                  const SizedBox(width: 10),
                  Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                    Text(money(num0(it['pcs']) * num0(it['rate'])), style: ts(15, w: FontWeight.w700, tabular: true)),
                    if (it['gain'] != null) Text('লাভ ${money(it['gain'])}', style: ts(12.5, w: FontWeight.w700, color: RC.ok)),
                  ]),
                ]),
              ),
          ]),
        ),
        const SizedBox(height: 4),
        _tot('আমার কেনা (বিল)', money(o['total']), boldK: true),
        if (o['mrp_total'] != null) _tot('MRP-তে বিক্রি করলে', money(o['mrp_total'])),
        if (o['profit'] != null) _tot('আমার লাভ', money(o['profit']), grand: true, vColor: RC.ok),
        if (num0(o['damage']) > 0) _tot('ড্যামেজ কর্তন', money(o['damage'])),
        _tot('নগদ দিয়েছেন', money(o['paid'])),
        if (num0(o['due']) > 0) _tot('নোট: বাকি রইল', money(o['due']), muted: true),
        Container(
          margin: const EdgeInsets.only(top: 14),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: const Color(0xFFF1F3F6), borderRadius: BorderRadius.circular(10)),
          child: Text('মাল পেয়েছেন', textAlign: TextAlign.center, style: ts(14, w: FontWeight.w700)),
        ),
      ]),
    );
  }
}
