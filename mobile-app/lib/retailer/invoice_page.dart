import 'package:flutter/material.dart';

import '../core/format.dart';
import '../core/printer.dart';
import '../ui/common.dart';

Map<String, dynamic> _m(Object? v) => Map<String, dynamic>.from((v ?? {}) as Map);

/// Invoice (মেমো) of a day's orders. The retailer can print it on a Bluetooth printer.
class InvoicePage extends StatefulWidget {
  const InvoicePage({super.key, required this.date, required this.orders, required this.selectedId});
  final String date;
  final List<Map<String, dynamic>> orders;
  final int selectedId;
  @override
  State<InvoicePage> createState() => _InvoicePageState();
}

class _InvoicePageState extends State<InvoicePage> {
  late int _selected = widget.selectedId;

  Map<String, dynamic>? get _order {
    for (final o in widget.orders) {
      if (int0(o['id']) == _selected) return o;
    }
    return widget.orders.isEmpty ? null : widget.orders.first;
  }

  List<ReceiptLine> _receipt(Map<String, dynamic> o) {
    final shop = _m(o['shop']);
    final partner = _m(o['partner']);
    return [
      ReceiptLine('হ্যাপি বাংলাদেশ', style: ReceiptStyle.title, center: true),
      ReceiptLine('${partner['name']}', center: true, style: ReceiptStyle.bold),
      if ('${partner['phone']}'.isNotEmpty) ReceiptLine('${partner['phone']}', center: true, style: ReceiptStyle.small),
      ReceiptLine.rule(),
      ReceiptLine('মেমো ${o['code']}', right: dateBn(o['date']?.toString())),
      ReceiptLine('${shop['name']}', style: ReceiptStyle.bold),
      ReceiptLine('${o['company']} · SR ${o['sr']}', style: ReceiptStyle.small),
      ReceiptLine.rule(),
      for (final it in (o['items'] as List).map(_m)) ...[
        ReceiptLine('${it['name']}'),
        ReceiptLine('  ${bn(it['pcs'])} × ${num2(it['rate'])}', right: money(it['amount']), style: ReceiptStyle.small),
      ],
      ReceiptLine.rule(),
      ReceiptLine('মোট', right: money(o['subtotal'])),
      if (num0(o['damage']) > 0) ReceiptLine('ড্যামেজ', right: '-${money(o['damage'])}'),
      ReceiptLine('বিল', right: money(o['total']), style: ReceiptStyle.bold),
      if (num0(o['paid']) > 0) ReceiptLine('পরিশোধ', right: money(o['paid'])),
      if (num0(o['due']) > 0) ReceiptLine('বাকি', right: money(o['due']), style: ReceiptStyle.bold),
      ReceiptLine.rule(),
      ReceiptLine('ধন্যবাদ', center: true),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final o = _order;
    return Scaffold(
      appBar: AppBar(
        title: Text('ইনভয়েস · ${dateBn(widget.date)}'),
        actions: [
          if (o != null)
            IconButton(
              icon: const Icon(Icons.print),
              onPressed: () async {
                final err = await busy(context, () => PrinterService.print(_receipt(o)));
                if (context.mounted) toast(context, err ?? 'প্রিন্ট হয়েছে।', error: err != null);
              },
            ),
        ],
      ),
      body: o == null
          ? const Center(child: Text('কোনো ইনভয়েস নেই।'))
          : ListView(padding: const EdgeInsets.all(14), children: [
              if (widget.orders.length > 1)
                SizedBox(
                  height: 44,
                  child: ListView(scrollDirection: Axis.horizontal, children: [
                    for (final x in widget.orders)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          label: Text('${x['company']} · ${x['code']}'),
                          selected: int0(x['id']) == int0(o['id']),
                          onSelected: (_) => setState(() => _selected = int0(x['id'])),
                        ),
                      ),
                  ]),
                ),
              const SizedBox(height: 10),
              _invoice(o),
              const SizedBox(height: 14),
              OutlinedButton.icon(
                onPressed: () async {
                  final err = await busy(context, () => PrinterService.print(_receipt(o)));
                  if (context.mounted) toast(context, err ?? 'প্রিন্ট হয়েছে।', error: err != null);
                },
                icon: const Icon(Icons.print), label: const Text('প্রিন্ট করুন'),
              ),
            ]),
    );
  }

  Widget _invoice(Map<String, dynamic> o) {
    final partner = _m(o['partner']);
    final shop = _m(o['shop']);
    final items = (o['items'] as List).map(_m).toList();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text('${partner['name']}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16))),
            Pill('${o['status']}', color: switch (o['tone']) { 'ok' => kOk, 'warn' => kWarn, _ => kBlue }),
          ]),
          if ('${partner['address']}'.isNotEmpty) Text('${partner['address']}', style: const TextStyle(color: kMuted, fontSize: 12.5)),
          const Divider(height: 24),
          Text('মেমো ${o['code']}', style: const TextStyle(fontWeight: FontWeight.w700)),
          Text('${shop['name']}', style: const TextStyle(fontSize: 15)),
          Text('${o['company']} · SR ${o['sr']}${o['dm'] != null ? ' · DSR ${o['dm']}' : ''}', style: const TextStyle(color: kMuted, fontSize: 12.5)),
          const Divider(height: 24),
          for (final it in items)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${it['name']}', style: const TextStyle(fontWeight: FontWeight.w600)),
                  Text('${bn(it['pcs'])} পিস × ${num2(it['rate'])}${num0(it['short']) > 0 ? ' · কম এসেছে ${bn(it['short'])}' : ''}', style: const TextStyle(color: kMuted, fontSize: 12.5)),
                ])),
                Text(money(it['amount']), style: const TextStyle(fontWeight: FontWeight.w700)),
              ]),
            ),
          const Divider(height: 24),
          _kv('সাবটোটাল', money(o['subtotal'])),
          if (num0(o['damage']) > 0) _kv('ড্যামেজ', '-${money(o['damage'])}'),
          _kv('বিল', money(o['total']), bold: true),
          if (num0(o['paid']) > 0) _kv('পরিশোধ', money(o['paid'])),
          if (num0(o['due']) > 0) _kv('বাকি', money(o['due']), bold: true, color: kDanger),
          if (o['profit'] != null) ...[
            const Divider(height: 24),
            _kv('MRP অনুযায়ী মোট', money(o['mrp_total'])),
            _kv('আপনার লাভ', money(o['profit']), color: kOk),
          ],
          if ('${o['words']}'.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 8), child: Text('কথায়: ${o['words']} টাকা মাত্র', style: const TextStyle(color: kMuted, fontSize: 12.5))),
        ]),
      ),
    );
  }

  Widget _kv(String k, String v, {bool bold = false, Color? color}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(children: [
          Expanded(child: Text(k, style: TextStyle(fontWeight: bold ? FontWeight.w800 : FontWeight.w500))),
          Text(v, style: TextStyle(fontWeight: bold ? FontWeight.w800 : FontWeight.w600, color: color, fontSize: bold ? 16 : 14)),
        ]),
      );
}
