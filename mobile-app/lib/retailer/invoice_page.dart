import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/format.dart';
import '../core/printer.dart';
import '../ui/common.dart';
import '../ui/hkit.dart';
import '../ui/pwa_kit.dart';

Map<String, dynamic> _m(Object? v) => Map<String, dynamic>.from((v ?? {}) as Map);

enum InvoiceMode { order, delivery }

/// R2 · ইনভয়েস (per company) and R8 · ইনভয়েস · লাভসহ (what arrived, cost vs MRP, profit).
/// "শেয়ার / PDF" of the web is a Bluetooth receipt print on the phone.
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
    final partner = o == null ? const <String, dynamic>{} : _m(o['partner']);
    final kicker = delivery && o != null ? [o['company'], partner['name'], o['code']].where((x) => '${x ?? ''}'.isNotEmpty).join(' · ') : 'প্রতিটা কোম্পানির আলাদা ইনভয়েস';
    final arrived = o != null && '${o['stage']}' == 'arrived';
    return SkyStatusBar(
      child: Scaffold(
        backgroundColor: HC.bg,
        body: Frame(
          color: HC.outer,
          child: ColoredBox(
            color: HC.bg,
            child: HScroll(children: [
              SkyBox(
                height: 240,
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  SkyHead(leading: const SkyBack(), kicker: kicker, title: delivery ? 'ইনভয়েস · লাভসহ' : 'ইনভয়েস'),
                  gap12,
                  HSeg(items: const ['অর্ডার ইনভয়েস', 'ডেলিভারি ইনভয়েস'], index: delivery ? 1 : 0,
                      onTap: (i) => setState(() => _mode = i == 1 ? InvoiceMode.delivery : InvoiceMode.order)),
                  gap12,
                  if (orders.length > 1) ...[
                    HPills(items: [for (final x in orders) '${x['company']} · ${x['sr']}'], index: _cur, onTap: (i) => setState(() => _cur = i)),
                    gap12,
                  ],
                  if (o == null)
                    const HEmpty('এই দিনে কোনো ইনভয়েস নেই')
                  else ...[
                    delivery ? _DeliveryInvoice(o: o, date: widget.date) : _OrderInvoice(o: o, date: widget.date),
                    if (delivery && arrived && o['profit'] != null) ...[
                      gap12,
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                        decoration: BoxDecoration(color: HC.ink, borderRadius: BorderRadius.circular(22)),
                        child: Row(children: [
                          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text('আমার লাভ', style: hs(12, color: HC.onDark)),
                            Text(sMoney(o['profit']), style: hs(28, w: w8, color: HC.lilac, num: true, h: 1.25)),
                          ])),
                          if (o['profit_per_100'] != null)
                            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                              Text('প্রতি ৳১০০ কেনায়', style: hs(11, color: HC.onDark)),
                              Text(sMoney(o['profit_per_100']), style: hs(18, w: w7, color: Colors.white, num: true)),
                            ]),
                        ]),
                      ),
                    ],
                    gap12,
                    Row(children: [
                      Expanded(child: HBtn('সমস্যা জানান', kind: HBtnKind.line, onTap: () => showHSheet<void>(
                            context,
                            builder: (c) => _ProblemSheet(order: o),
                          ))),
                      const SizedBox(width: 10),
                      Expanded(child: HBtn('প্রিন্ট করুন', icon: Ic.print, onTap: () async {
                        final err = await busy(context, () => PrinterService.print(_receipt(o)));
                        if (context.mounted) toast(context, err ?? 'প্রিন্ট হয়েছে।', error: err != null);
                      })),
                    ]),
                  ],
                ]),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

/// R2 card: brand + INVOICE, bill-to / meta box, items with MRP and profit, totals, profit strip, words.
class _OrderInvoice extends StatelessWidget {
  const _OrderInvoice({required this.o, required this.date});
  final Map<String, dynamic> o;
  final String date;
  @override
  Widget build(BuildContext context) {
    final shop = _m(o['shop']);
    final partner = _m(o['partner']);
    final items = (o['items'] as List).map(_m).toList();
    final tone = '${o['tone']}';
    final people = [o['company'], o['sr'] == 'রেডি সেল' ? 'রেডি সেল' : 'SR ${o['sr']}', if (o['dm'] != null) 'DM ${o['dm']}'].join(' · ');
    return HCard(
      lift: true, radius: 22, padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Happy Bangladesh', style: hs(16, w: w7, color: HC.blue)),
            Text([partner['name'], partner['address']].where((x) => '${x ?? ''}'.isNotEmpty).join(' · '), style: hs(11, color: HC.muted)),
          ])),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text('INVOICE', style: const TextStyle(fontFamily: 'Inter', fontSize: 14, fontWeight: FontWeight.w700, letterSpacing: 1, color: HC.ink)),
            const SizedBox(height: 4),
            HChip('${o['status']}', bg: tone == 'ok' || tone == 'info' ? HC.soft : HC.chip, fg: tone == 'ok' || tone == 'info' ? HC.blue : HC.ink2, size: 11),
          ]),
        ]),
        gap8,
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(color: HC.bg, borderRadius: BorderRadius.circular(14)),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(child: Text.rich(TextSpan(style: hs(11, color: HC.muted, h: 1.55), children: [
              const TextSpan(text: 'বিল টু\n'),
              TextSpan(text: '${shop['name']}', style: hs(13, w: w7, h: 1.55)),
              if ('${shop['address'] ?? ''}'.isNotEmpty) TextSpan(text: '\n${shop['address']}'),
            ]))),
            const SizedBox(width: 12),
            Expanded(child: Text.rich(textAlign: TextAlign.right, TextSpan(style: hs(11, color: HC.muted, h: 1.55), children: [
              const TextSpan(text: 'ইনভয়েস নং '),
              TextSpan(text: '${o['code']}', style: hs(11, w: w7, h: 1.55)),
              const TextSpan(text: '\nতারিখ '),
              TextSpan(text: dateLongBn(date), style: hs(11, w: w7, h: 1.55)),
              TextSpan(text: '\n$people'),
            ]))),
          ]),
        ),
        gap8,
        _TableRow(cells: const ['বিবরণ', 'পিস', 'দর', 'টাকা · লাভ'], head: true),
        for (final it in items)
          _TableRow(cells: [
            '${it['name']}', bn(it['pcs']), tk(it['rate']), tk(it['amount']),
          ], sub0: it['mrp'] != null ? 'MRP ${tk(it['mrp'])}' : null, sub3: it['gain'] != null ? sMoney(it['gain']) : null),
        gap8,
        const HDashed(),
        gap8,
        if (num0(o['damage']) > 0) ...[HKv('সাবটোটাল', tk(o['subtotal'])), HKv('ড্যামেজ কর্তন', '−${tk(o['damage'])}')],
        HKv('মোট', tk(o['total']), big: true),
        if (num0(o['paid']) > 0) HKv('নগদ পরিশোধ', tk(o['paid'])),
        if (num0(o['due']) > 0) HKv('বাকি', tk(o['due']), valueColor: HC.red),
        if (o['profit'] != null) ...[
          gap8,
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(color: HC.soft, borderRadius: BorderRadius.circular(14)),
            child: Row(children: [
              Expanded(child: Text('আপনার লাভ · সব MRP-তে বেচলে', style: hs(12, w: w6, color: HC.blue))),
              Text(sMoney(o['profit']), style: hs(18, w: w7, color: HC.blue, num: true)),
            ]),
          ),
        ],
        gap8,
        Text('কথায়: ${o['words']}', style: hs(11, color: HC.muted)),
      ]),
    );
  }
}

/// R8 card: who delivered when, items with cost / MRP / profit, shortfalls in red, totals.
class _DeliveryInvoice extends StatelessWidget {
  const _DeliveryInvoice({required this.o, required this.date});
  final Map<String, dynamic> o;
  final String date;
  @override
  Widget build(BuildContext context) {
    if ('${o['stage']}' != 'arrived') {
      return HCard(lift: true, padding: const EdgeInsets.fromLTRB(18, 26, 18, 26), child: Column(children: [
        const Svg('<path d="M3 6h11v10H3zM14 10h4l3 3v3h-7"/><circle cx="7" cy="18" r="2"/><circle cx="17" cy="18" r="2"/>', size: 30, color: HC.faint, stroke: 1.6),
        gap8,
        Text('মাল এখনো আসেনি', style: hs(16, w: w7)),
        Text('${o['status']} · মাল পৌঁছালে ডেলিভারি ইনভয়েস এখানে দেখা যাবে।', textAlign: TextAlign.center, style: hs(13, color: HC.muted)),
      ]));
    }
    final items = (o['items'] as List).map(_m).toList();
    return HCard(
      lift: true, radius: 24, padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(child: Text.rich(TextSpan(style: hs(11, color: HC.muted), children: [
            const TextSpan(text: 'ডেলিভারি '),
            TextSpan(text: '${o['dm'] != null ? 'DM ${o['dm']}' : '—'}${o['time'] != null ? ' · ${bn(o['time'])}' : ''}', style: hs(11, w: w7)),
          ]))),
          Text(dateLongBn(date), style: hs(11, color: HC.muted)),
        ]),
        gap8,
        _TableRow(cells: const ['পণ্য', 'পিস', 'কেনা', 'MRP', 'লাভ'], head: true, five: true),
        for (final it in items)
          _TableRow(
            five: true,
            cells: ['${it['name']}', bn(it['pcs']), numTrim(it['rate']), it['mrp'] != null ? numTrim(it['mrp']) : '—', it['gain'] != null ? sMoney(it['gain']) : '—'],
            sub0: int0(it['short']) > 0 ? '${bn(it['short'])}টি কম · ভ্যানে ছিল না' : null,
            short: int0(it['short']) > 0,
          ),
        gap8,
        const HDashed(),
        gap8,
        HKv('আমার কেনা (বিল)', tk(o['subtotal'])),
        if (num0(o['damage']) > 0) ...[HKv('ড্যামেজ কর্তন', '−${tk(o['damage'])}'), HKv('মোট বিল', tk(o['total']))],
        if (o['mrp_total'] != null) HKv('MRP-তে বিক্রি করলে', tk(o['mrp_total'])),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 2.5),
          child: Row(children: [
            Expanded(child: Text(num0(o['due']) > 0 ? 'নগদ দিয়েছেন · বাকি রইল' : 'নগদ দিয়েছেন', style: hs(13, color: HC.muted))),
            Text.rich(TextSpan(style: hs(13, w: w7, num: true), children: [
              TextSpan(text: tk(o['paid'])),
              if (num0(o['due']) > 0) ...[const TextSpan(text: ' · '), TextSpan(text: tk(o['due']), style: hs(13, w: w7, color: HC.red, num: true))],
            ])),
          ]),
        ),
      ]),
    );
  }
}

class _TableRow extends StatelessWidget {
  const _TableRow({required this.cells, this.head = false, this.five = false, this.sub0, this.sub3, this.short = false});
  final List<String> cells;
  final bool head, five, short;
  final String? sub0, sub3;
  @override
  Widget build(BuildContext context) {
    final flex = five ? const [23, 7, 9, 9, 10] : const [23, 8, 10, 12];
    final base = head ? hs(10, color: HC.muted) : hs(13, num: true);
    return Container(
      padding: EdgeInsets.symmetric(vertical: head ? 0 : 9).copyWith(bottom: head ? 4 : 9),
      decoration: BoxDecoration(border: head ? null : const Border(top: BorderSide(color: HC.line))),
      child: Row(children: [
        for (var i = 0; i < cells.length; i++)
          Expanded(
            flex: flex[i],
            child: i == 0
                ? Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(cells[i], style: head ? base : hs(13, w: w7)),
                    if (sub0 != null) Text(sub0!, style: hs(10, color: short ? HC.red : HC.muted, w: short ? w7 : FontWeight.w400)),
                  ])
                : Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                    Text(cells[i], textAlign: TextAlign.right, style: head ? base : base.copyWith(
                      fontWeight: (five && i == 4) || (!five && i == 3) ? w7 : null,
                      color: five && i == 4 ? HC.blue : (five && i == 3 ? HC.muted : (short && i == 1 ? HC.red : null)),
                    )),
                    if (i == 3 && sub3 != null) Text(sub3!, style: hs(10, w: w7, color: HC.blue, num: true)),
                  ]),
          ),
      ]),
    );
  }
}

/// সমস্যা জানান: call the delivery man, the SR or the partner straight from the invoice.
class _ProblemSheet extends StatelessWidget {
  const _ProblemSheet({required this.order});
  final Map<String, dynamic> order;
  @override
  Widget build(BuildContext context) {
    final partner = _m(order['partner']);
    final people = [
      if ('${order['dm_phone'] ?? ''}'.isNotEmpty) ('ডেলিভারি ম্যান', '${order['dm'] ?? ''}', '${order['dm_phone']}'),
      if ('${order['sr_phone'] ?? ''}'.isNotEmpty) ('SR', '${order['sr'] ?? ''}', '${order['sr_phone']}'),
      if ('${partner['phone'] ?? ''}'.isNotEmpty) ('পার্টনার', '${partner['name'] ?? ''}', '${partner['phone']}'),
    ];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text('সমস্যা জানান', style: hs(18, w: w7)),
      const SizedBox(height: 4),
      Text('মাল কম, নষ্ট বা দাম ভুল হলে সরাসরি ফোন করুন। ২৪ ঘণ্টার মধ্যে জানালে ঠিক করা হবে।', style: hs(13.5, color: HC.muted)),
      const SizedBox(height: 14),
      if (people.isEmpty) Text('ফোন নম্বর পাওয়া যায়নি।', style: hs(13.5, color: HC.muted)),
      for (final (role, name, phone) in people)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: HCard(
            onTap: () => launchUrl(Uri.parse('tel:${phone.replaceAll(RegExp(r'[^0-9+]'), '')}')),
            child: Row(children: [
              LetterAvatar(name.isEmpty ? role : name, size: 42),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(name.isEmpty ? role : name, maxLines: 1, overflow: TextOverflow.ellipsis, style: hs(15, w: w7)),
                Text('$role · $phone', style: hs(12.5, color: HC.muted, num: true)),
              ])),
              Container(
                width: 44, height: 44, decoration: BoxDecoration(color: HC.soft, borderRadius: BorderRadius.circular(14)), alignment: Alignment.center,
                child: const Svg('<path d="M22 16.9v3a2 2 0 0 1-2.2 2 19.8 19.8 0 0 1-8.6-3.1 19.5 19.5 0 0 1-6-6A19.8 19.8 0 0 1 2.1 4.2 2 2 0 0 1 4.1 2h3a2 2 0 0 1 2 1.7c.1.9.4 1.8.7 2.7a2 2 0 0 1-.5 2.1L8 9.8a16 16 0 0 0 6 6l1.3-1.3a2 2 0 0 1 2.1-.4c.9.3 1.8.6 2.7.7a2 2 0 0 1 1.7 2z"/>', size: 20, color: HC.blue, stroke: 1.9),
              ),
            ]),
          ),
        ),
    ]);
  }
}
