import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/api.dart';
import '../core/format.dart';
import '../core/printer.dart';
import '../ui/common.dart';
import '../ui/hkit.dart';
import '../ui/pwa_kit.dart';

Map<String, dynamic> _m(Object? v) => Map<String, dynamic>.from((v ?? {}) as Map);
List<Map<String, dynamic>> _items(Map o) => ((o['items'] as List?) ?? const []).map(_m).toList();

/// Sum of the positive (ওভার) and negative (কমিশন) O/C of an order's lines.
({double over, double comm}) _ocSplit(Map o) {
  var over = 0.0, comm = 0.0;
  for (final it in _items(o)) {
    final v = num0(it['oc']);
    if (v > 0) over += v;
    if (v < 0) comm += v;
  }
  return (over: over, comm: comm);
}

/// Short delivery state of an order (history rows / memo chip).
({String text, Color bg, Color fg}) _state(Map o) {
  final st = '${o['status_key'] ?? ''}'.toLowerCase();
  final trip = '${o['trip'] ?? ''}'.isNotEmpty;
  return switch (st) {
    'cancelled' => (text: 'বাতিল', bg: HC.redSoft, fg: HC.red),
    'delivered' => (text: 'ডেলিভারি হয়েছে', bg: HC.soft, fg: HC.blue),
    'partial' => (text: 'আংশিক', bg: HC.redSoft, fg: HC.red),
    'due' => (text: 'বাকি ${tk(o['due'])}', bg: HC.redSoft, fg: HC.red),
    'dispatched' => (text: 'পথে আছে', bg: HC.soft, fg: HC.blue),
    _ => trip || st == 'assigned' ? (text: 'ভ্যানে উঠেছে', bg: HC.chip, fg: HC.ink2) : (text: 'ডেলিভারির অপেক্ষায়', bg: HC.chip, fg: HC.ink2),
  };
}

/// 4-step timeline: অর্ডার → ভ্যান → পথে → পৌঁছেছে.
class SrTimeline extends StatelessWidget {
  const SrTimeline(this.o, {super.key});
  final Map<String, dynamic> o;

  @override
  Widget build(BuildContext context) {
    final st = '${o['status_key'] ?? ''}'.toLowerCase();
    final cancelled = st == 'cancelled';
    final done = st == 'delivered';
    final partial = st == 'partial' || st == 'due';
    final hasTrip = '${o['trip'] ?? ''}'.isNotEmpty || st == 'assigned' || st == 'dispatched' || done || partial;
    final onRoad = st == 'dispatched' || done || partial || (cancelled && hasTrip);
    final s2 = done || partial || onRoad || hasTrip;
    final s3 = done || partial || (cancelled && hasTrip) || st == 'dispatched';
    final s4 = done || partial || cancelled;
    final s4Text = cancelled ? 'ফেরত' : (partial ? (st == 'partial' ? 'আংশিক' : 'বাকি') : 'পৌঁছেছে');
    final bad = cancelled || partial;
    Widget step(bool on, String text, {bool warn = false}) => Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 22, height: 22,
            decoration: BoxDecoration(shape: BoxShape.circle, color: on ? (warn ? HC.red : HC.blue) : HC.chip),
            child: Center(child: on ? Svg(warn ? '<path d="M12 7v6M12 17h.01"/>' : '<polyline points="20 6 9 17 4 12"/>', size: 12, color: Colors.white, stroke: 3) : null),
          ),
          const SizedBox(height: 4),
          Text(text, style: hs(11, w: on ? w7 : w5, color: on ? (warn ? HC.red : HC.ink) : HC.muted)),
        ]);
    Widget line(bool on) => Expanded(child: Container(height: 2, margin: const EdgeInsets.only(bottom: 18), color: on ? HC.blue : HC.line));
    return Row(children: [
      step(true, 'অর্ডার'),
      line(s2),
      step(s2, 'ভ্যান'),
      line(s3),
      step(s3, 'পথে'),
      line(s4),
      step(s4, s4Text, warn: bad),
    ]);
  }
}

/// SR5 — order history: date bar on the sky, day totals, one row per memo; a row opens the memo (SR6).
class SrHistoryPage extends StatefulWidget {
  const SrHistoryPage({super.key});
  @override
  State<SrHistoryPage> createState() => _SrHistoryPageState();
}

class _SrHistoryPageState extends State<SrHistoryPage> {
  String? _date;

  @override
  Widget build(BuildContext context) {
    return AsyncBody(
      key: ValueKey(_date),
      sky: true,
      padding: EdgeInsets.zero,
      load: () => loadCached('sr_history_${_date ?? 'last'}', () => ApiClient.get('/sr/history', query: {'date': _date})),
      builder: (context, d, reload) {
        final date = d['date'].toString();
        final orders = ((d['orders'] as List?) ?? const []).map(_m).toList();
        final active = orders.where((o) => o['status_key'] != 'cancelled').toList();
        final total = active.fold<double>(0, (a, o) => a + num0(o['sr_total']));
        final shops = orders.map((o) => '${o['retailer_id']}').toSet().length;
        final wd = DateTime.tryParse(date);
        final weekday = wd == null ? '' : const ['সোমবার', 'মঙ্গলবার', 'বুধবার', 'বৃহস্পতিবার', 'শুক্রবার', 'শনিবার', 'রবিবার'][wd.weekday - 1];
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          SkyBox(
            height: 156,
            child: Padding(
              padding: EdgeInsets.zero,
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Text('অর্ডার হিস্ট্রি', style: hs(22, w: w8, color: Colors.white)),
                const SizedBox(height: 14),
                SkyDateBar(
                  date: date, today: d['today']?.toString(), onChange: (v) => setState(() => _date = v),
                  sub: '$weekday · ${bn(shops)}টি দোকানে গেছি',
                ),
              ]),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 18),
            child: Padding(
              padding: EdgeInsets.zero,
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                HCard(
                  lift: true, radius: 22,
                  child: Row(children: [
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('মোট অর্ডার', style: hs(12, color: HC.muted)),
                      Text(tk(total), style: hs(24, w: w8, num: true, h: 1.2)),
                    ])),
                    _mini(bn(active.length), 'মেমো'),
                    const SizedBox(width: 18),
                    _mini(bn(orders.length - active.length), 'বাতিল', color: orders.length > active.length ? HC.red : HC.ink),
                  ]),
                ),
                gap16,
                if (orders.isEmpty)
                  const HEmpty('এই দিনে কোনো অর্ডার নেই', body: 'আগের দিন দেখতে ‹ চাপুন।')
                else
                  HList(children: [
                    for (final o in orders) _row(context, o, date),
                  ]),
              ]),
            ),
          ),
        ]);
      },
    );
  }

  Widget _mini(String v, String label, {Color color = HC.ink}) => Column(children: [
        Text(v, style: hs(20, w: w8, color: color, num: true, h: 1.2)),
        Text(label, style: hs(11.5, color: HC.muted)),
      ]);

  Widget _row(BuildContext context, Map<String, dynamic> o, String date) {
    final cancelled = '${o['status_key']}' == 'cancelled';
    final oc = _ocSplit(o);
    final s = _state(o);
    return InkWell(
      onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => SrOrderDetailPage(order: o, date: date))),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(children: [
          LetterAvatar('${o['retailer']}', size: 42, radius: 13, bg: cancelled ? HC.chip : HC.soft, fg: cancelled ? HC.muted : HC.blue, fontSize: 16),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${o['retailer']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: hs(14.5, w: w6, color: cancelled ? HC.muted : HC.ink)),
            Text('মেমো #${bn(o['code'])}', maxLines: 1, overflow: TextOverflow.ellipsis, style: hs(12, color: HC.muted, num: true)),
            Text.rich(TextSpan(style: hs(12, color: HC.muted, num: true), children: [
              const TextSpan(text: 'ওভার '),
              TextSpan(text: sMoney(oc.over), style: hs(12, w: w7, color: oc.over > 0 ? HC.blue : HC.muted, num: true)),
              const TextSpan(text: ' · কমিশন '),
              TextSpan(text: sMoney(oc.comm), style: hs(12, w: w7, color: oc.comm < 0 ? HC.red : HC.muted, num: true)),
            ]), maxLines: 1, overflow: TextOverflow.ellipsis),
          ])),
          const SizedBox(width: 8),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(tk(o['sr_total']), style: hs(15, w: w7, num: true).copyWith(decoration: cancelled ? TextDecoration.lineThrough : null)),
            const SizedBox(height: 3),
            HChip(s.text, bg: s.bg, fg: s.fg, size: 10.5),
          ]),
        ]),
      ),
    );
  }
}

/// SR6 (আমার কপি: items with O/C, total, dark "আমার হিসাব") and SR6b (দোকানের কপি: cash memo without O/C).
class SrOrderDetailPage extends StatefulWidget {
  const SrOrderDetailPage({super.key, required this.order, required this.date, this.shopCopy = false});
  final Map<String, dynamic> order;
  final String date;
  final bool shopCopy;
  @override
  State<SrOrderDetailPage> createState() => _SrOrderDetailPageState();
}

class _SrOrderDetailPageState extends State<SrOrderDetailPage> {
  late bool _shop = widget.shopCopy;

  Map<String, dynamic> get o => widget.order;
  String get _date => o['date']?.toString() ?? widget.date;
  bool get _today => _date == todayYmd();

  String get _pay => num0(o['delivered_total']) > 0
      ? '${tk(o['paid'])} জমা${num0(o['due']) > 0 ? ' · ${tk(o['due'])} বাকি' : ' · পূর্ণ আদায়'}'
      : 'ডেলিভারির সময় নগদ';

  String get _delivery => '${o['trip'] ?? ''}'.isNotEmpty
      ? '${o['dsr'] ?? '—'} · ট্রিপ ${bn(o['trip'])}${o['trip_date'] != null ? ' · ${dateBn(o['trip_date'].toString())}' : ''}'
      : 'ট্রিপ এখনো হয়নি';

  double _rate(Map it) => num0(it['sr_rate_pc']) > 0 ? num0(it['sr_rate_pc']) : (int0(it['pcs']) > 0 ? num0(it['total']) / int0(it['pcs']) : 0);

  List<ReceiptLine> _receipt() => [
        ReceiptLine('${o['partner'] ?? o['company']}', style: ReceiptStyle.title, center: true),
        if (o['partner'] != null) ReceiptLine('${o['company']}', center: true, style: ReceiptStyle.small),
        ReceiptLine('ক্যাশ মেমো #${o['code']}', right: dateBn(_date)),
        ReceiptLine('দোকান: ${o['retailer']}', style: ReceiptStyle.bold),
        ReceiptLine.rule(),
        for (final it in _items(o)) ...[
          ReceiptLine('${it['name']}'),
          ReceiptLine('  ${bn(it['pcs'])} × ${num2(_rate(it))}', right: tk(it['total']), style: ReceiptStyle.small),
        ],
        ReceiptLine.rule(),
        ReceiptLine('মোট', right: tk(o['sr_total']), style: ReceiptStyle.bold),
        ReceiptLine(takaWords(o['sr_total']), style: ReceiptStyle.small),
        ReceiptLine.rule(),
        ReceiptLine('SR: ${o['sr'] ?? ''}', style: ReceiptStyle.small),
        ReceiptLine('ধন্যবাদ', center: true),
      ];

  String get _shareText => [
        '${o['partner'] ?? o['company']}',
        'ক্যাশ মেমো #${bn(o['code'])} · ${dateBn(_date)}',
        'দোকান: ${o['retailer']}',
        '----------------',
        for (final it in _items(o)) '${it['name']}: ${bn(it['pcs'])} × ${tk(_rate(it))} = ${tk(it['total'])}',
        '----------------',
        'মোট: ${tk(o['sr_total'])}',
        'কথায়: ${takaWords(o['sr_total'])}',
      ].join('\n');

  /// Copies the shop copy and opens an SMS to the shop with it (falls back to copy only).
  Future<void> _send() async {
    await Clipboard.setData(ClipboardData(text: _shareText));
    final phone = '${o['retailer_phone'] ?? ''}'.replaceAll(RegExp(r'[^0-9+]'), '');
    var opened = false;
    if (phone.isNotEmpty) {
      try {
        opened = await launchUrl(Uri(scheme: 'sms', path: phone, queryParameters: {'body': _shareText}));
      } catch (_) {}
    }
    if (mounted && !opened) toast(context, 'দোকানের কপি কপি হয়েছে — যেকোনো অ্যাপে পেস্ট করে পাঠান।');
  }

  Future<void> _print() async {
    final err = await busy(context, () => PrinterService.print(_receipt()));
    if (mounted) toast(context, err ?? 'প্রিন্ট হয়েছে।', error: err != null);
  }

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.of(context).padding.top;
    final s = _state(o);
    return PopScope(
      canPop: !_shop || widget.shopCopy,
      onPopInvokedWithResult: (did, _) {
        if (!did) setState(() => _shop = false); // back from the shop copy returns to my copy
      },
      child: SkyStatusBar(
        child: Scaffold(
          backgroundColor: HC.bg,
          body: Column(children: [
            Expanded(
              child: ListView(padding: EdgeInsets.fromLTRB(18, top + 14, 18, 16), children: [
                SkyBox(
                  height: 130,
                  child: Padding(
                    padding: EdgeInsets.zero,
                    child: SkyHead(
                      leading: SkyBack(onTap: () {
                        if (_shop && !widget.shopCopy) {
                          setState(() => _shop = false);
                        } else {
                          Navigator.maybePop(context);
                        }
                      }),
                      kicker: _shop ? 'দোকানদার এটাই পাবে · ওভার/কমিশন নেই' : 'মেমো #${bn(o['code'])} · ${_today ? 'আজ' : dateBn(_date)}',
                      title: _shop ? 'দোকানের কপি' : '${o['retailer']}',
                      trailing: _shop ? null : HChip(s.text, bg: Colors.white, fg: s.fg, size: 11),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 18),
                  child: Padding(
                    padding: EdgeInsets.zero,
                    child: _shop ? _shopCopy() : _myCopy(),
                  ),
                ),
              ]),
            ),
            Container(
              padding: EdgeInsets.fromLTRB(18, 10, 18, 12 + MediaQuery.of(context).padding.bottom),
              color: HC.bg,
              child: Row(children: [
                Expanded(flex: 10, child: HBtn('প্রিন্ট', kind: HBtnKind.line, height: 52, icon: Ic.print, onTap: _print)),
                const SizedBox(width: 10),
                Expanded(
                  flex: 14,
                  child: _shop
                      ? HBtn('দোকানে পাঠান', height: 52, icon: '<path d="M22 2 11 13"/><path d="M22 2 15 22l-4-9-9-4z"/>', onTap: _send)
                      : HBtn('দোকানের কপি', height: 52, onTap: () => setState(() => _shop = true)),
                ),
              ]),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _myCopy() {
    final oc = _ocSplit(o);
    final items = _items(o);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      HCard(
        lift: true, radius: 24, padding: const EdgeInsets.fromLTRB(16, 6, 16, 16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          for (var i = 0; i < items.length; i++) ...[
            if (i > 0) const Divider(height: 1, color: HC.line),
            HItemRow(
              name: '${items[i]['name']}', sub: '${bn(items[i]['pcs'])} × ${tk(_rate(items[i]))}', amount: tk(items[i]['total']),
              tag: num0(items[i]['oc']).abs() >= 0.01 ? sMoney(items[i]['oc']) : null, tagOver: num0(items[i]['oc']) > 0, soft: true,
            ),
          ],
          const HDashed(),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: Text('মোট অর্ডার', style: hs(14, w: w6, color: HC.ink2))),
            Text(tk(o['sr_total']), style: hs(24, w: w8, num: true).copyWith(decoration: '${o['status_key']}' == 'cancelled' ? TextDecoration.lineThrough : null)),
          ]),
        ]),
      ),
      gap12,
      HStrip(style: StripStyle.dark, title: 'আমার হিসাব · শুধু আপনি দেখবেন', [
        HStat('ওভার', sMoney(oc.over), color: oc.over > 0.009 ? HC.lilac : Colors.white),
        HStat('কমিশন', sMoney(oc.comm), color: oc.comm < -0.009 ? HC.redOnDark : Colors.white),
        HStat('নিট', sMoney(oc.over + oc.comm), color: Colors.white),
      ]),
      gap12,
      HCard(radius: 20, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SrTimeline(o),
        const SizedBox(height: 12),
        HKv('ডেলিভারি', _delivery, bold: false),
        const SizedBox(height: 6),
        HKv('টাকা', _pay, bold: false),
        if ('${o['cancel_reason'] ?? ''}'.isNotEmpty) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(color: HC.redSoft, borderRadius: BorderRadius.circular(12)),
            child: Text('দোকানের কারণ: ${o['cancel_reason']}', style: hs(12.5, w: w6, color: HC.red)),
          ),
        ],
      ])),
    ]);
  }

  Widget _shopCopy() {
    final partner = '${o['partner'] ?? o['company'] ?? ''}';
    final items = _items(o);
    return HCard(
      lift: true, radius: 24, padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          LetterAvatar(partner, size: 44, radius: 14, bg: HC.ink, fg: Colors.white, fontSize: 18),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(partner, maxLines: 1, overflow: TextOverflow.ellipsis, style: hs(16, w: w8)),
            Text('${o['company'] ?? ''}', maxLines: 1, overflow: TextOverflow.ellipsis, style: hs(12, color: HC.muted)),
          ])),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text('ক্যাশ মেমো', style: hs(11, color: HC.muted)),
            Text('#${bn(o['code'])}', style: hs(15, w: w8, num: true)),
          ]),
        ]),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(color: HC.bg, borderRadius: BorderRadius.circular(14)),
          child: Row(children: [
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${o['retailer']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: hs(14, w: w7)),
              if ('${o['retailer_address'] ?? ''}'.isNotEmpty) Text('${o['retailer_address']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: hs(11.5, color: HC.muted)),
            ])),
            Text(dateBn(_date), style: hs(12.5, w: w6, color: HC.ink2, num: true)),
          ]),
        ),
        const SizedBox(height: 6),
        for (final it in items)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 9),
            child: Row(children: [
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${it['name']}', style: hs(14, w: w6)),
                Text('${bn(it['pcs'])} × ${tk(_rate(it))}', style: hs(12, color: HC.muted, num: true)),
              ])),
              Text(tk(it['total']), style: hs(14, w: w7, num: true)),
            ]),
          ),
        const SizedBox(height: 4),
        const HDashed(),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: Text('মোট', style: hs(16, w: w8))),
          Text(tk(o['sr_total']), style: hs(24, w: w8, num: true)),
        ]),
        const SizedBox(height: 4),
        Text('কথায়: ${takaWords(o['sr_total'])}', style: hs(12, color: HC.ink2)),
        const SizedBox(height: 26),
        Row(children: [
          for (final t in ['দোকানদার', 'SR · ${o['sr'] ?? ''}']) ...[
            if (!t.startsWith('দোকান')) const SizedBox(width: 20),
            Expanded(
              child: Container(
                padding: const EdgeInsets.only(top: 6),
                decoration: const BoxDecoration(border: Border(top: BorderSide(color: HC.line2))),
                child: Text(t, maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center, style: hs(11.5, w: w6, color: HC.muted)),
              ),
            ),
          ],
        ]),
        const SizedBox(height: 14),
        Text('ধন্যবাদ · $partner', textAlign: TextAlign.center, style: hs(12, color: HC.muted)),
      ]),
    );
  }
}
