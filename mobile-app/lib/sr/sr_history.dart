import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/api.dart';
import '../core/format.dart';
import '../core/printer.dart';
import '../ui/common.dart';
import '../ui/pwa_kit.dart';
import '../ui/skit.dart';

Map<String, dynamic> _m(Object? v) => Map<String, dynamic>.from((v ?? {}) as Map);

const _checkIc = '<polyline points="20 6 9 17 4 12"/>';
const _alertIc = '<line x1="12" y1="8" x2="12" y2="12"/><line x1="12" y1="16" x2="12.01" y2="16"/>';
const _undoIc = '<path d="M9 14 4 9l5-5"/><path d="M4 9h10.5a5.5 5.5 0 0 1 0 11H11"/>';

/// 4-step timeline: অর্ডার → ভ্যান → পথে → পৌঁছেছে (sr.js `buildTimelineHtml`).
class SrTimeline extends StatelessWidget {
  const SrTimeline(this.o, {super.key});
  final Map<String, dynamic> o;

  @override
  Widget build(BuildContext context) {
    final st = '${o['status_key'] ?? ''}'.toLowerCase();
    final cancelled = st == 'cancelled';
    final done = st == 'delivered';
    final partial = st == 'partial' || st == 'due';
    final hasTrip = (o['trip'] != null && '${o['trip']}'.isNotEmpty) || st == 'assigned' || st == 'dispatched' || done || partial;
    final onRoad = st == 'dispatched' || done || partial || (cancelled && hasTrip);
    final s2 = done || partial || onRoad ? 'done' : (hasTrip ? 'active' : '');
    final s3 = done || partial || (cancelled && hasTrip) ? 'done' : (st == 'dispatched' ? 'active' : '');
    final s4 = done ? 'done' : (partial ? 'warn' : (cancelled ? 'danger' : ''));
    final s4Dot = done ? '✓' : (partial ? '!' : (cancelled ? '✕' : '•'));
    final s4Text = cancelled ? 'ফেরত' : (partial ? (st == 'partial' ? 'আংশিক' : 'বাকি') : 'পৌঁছেছে');
    Widget step(String state, String dot, String text) {
      final (dotBg, fg) = switch (state) {
        'done' => (SC.ok, SC.ok),
        'active' => (SC.cobalt, SC.cobalt),
        'warn' => (SC.warn, SC.warnText),
        'danger' => (SC.danger, SC.dangerText),
        _ => (const Color(0xFFE2E8F0), SC.muted),
      };
      return Row(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 16, height: 16,
          decoration: BoxDecoration(shape: BoxShape.circle, color: dotBg),
          child: Center(child: Text(dot, style: ts(10, w: FontWeight.w800, color: state.isEmpty ? SC.muted : Colors.white, h: 1))),
        ),
        const SizedBox(width: 4),
        Text(text, style: ts(11, w: FontWeight.w600, color: fg, h: 1.3)),
      ]);
    }

    Widget line(bool on) => Expanded(child: Container(height: 1.5, margin: const EdgeInsets.symmetric(horizontal: 3), color: on ? SC.okBorder : const Color(0xFFE2E8F0)));
    return Row(children: [
      step('done', '✓', 'অর্ডার'),
      line(s2.isNotEmpty),
      step(s2, hasTrip ? '✓' : '•', 'ভ্যান'),
      line(s3.isNotEmpty),
      step(s3, s3 == 'done' ? '✓' : '•', 'পথে'),
      line(s4.isNotEmpty),
      step(s4, s4Dot, s4Text),
    ]);
  }
}

/// /sr/history — date nav, one card per memo with the 4-step timeline; tap opens the memo detail.
class SrHistoryPage extends StatefulWidget {
  const SrHistoryPage({super.key});
  @override
  State<SrHistoryPage> createState() => _SrHistoryPageState();
}

class _SrHistoryPageState extends State<SrHistoryPage> {
  String? _date;

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.of(context).padding.top;
    return AsyncBody(
      key: ValueKey(_date),
      padding: EdgeInsets.fromLTRB(14, 16 + top, 14, 18),
      load: () => loadCached('sr_history_${_date ?? 'last'}', () => ApiClient.get('/sr/history', query: {'date': _date})),
      builder: (context, d, reload) {
        final date = d['date'].toString();
        final orders = (d['orders'] as List).map(_m).toList();
        final active = orders.where((o) => o['status_key'] != 'cancelled');
        final total = active.fold<double>(0, (a, o) => a + num0(o['sr_total']));
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const SPlainHead('অর্ডার হিস্ট্রি'),
          const SizedBox(height: 12),
          SDateNav(
            date: date, today: d['today']?.toString(), onChange: (v) => setState(() => _date = v),
            sub: Text('${bn(orders.length)}টি মেমো · ${bnMoney(total, smart: true)}'),
          ),
          const SizedBox(height: 12),
          if (orders.isEmpty) const SEmpty('এই তারিখে কোনো দোকানের অর্ডার পাওয়া যায়নি।'),
          for (final o in orders) ...[
            _HistoryCard(o, onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => SrOrderDetailPage(order: o, date: date)))),
            const SizedBox(height: 10),
          ],
        ]);
      },
    );
  }
}

class _HistoryCard extends StatelessWidget {
  const _HistoryCard(this.o, {required this.onTap});
  final Map<String, dynamic> o;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final st = '${o['status_key'] ?? ''}'.toLowerCase();
    final cancelled = st == 'cancelled';
    final done = st == 'delivered';
    final partial = st == 'partial' || st == 'due';
    final trip = (o['trip'] != null && '${o['trip']}'.isNotEmpty) || st == 'assigned' || st == 'dispatched';
    final due = num0(o['due']);
    final (icoBg, icoFg, icoBd, icon) = cancelled
        ? (SC.dangerBg, SC.dangerText, SC.dangerBorder, _undoIc)
        : partial
            ? (SC.warnBg, SC.warnText, Colors.transparent, _alertIc)
            : (done || trip)
                ? (SC.ok, Colors.white, Colors.transparent, _checkIc)
                : (SC.cobaltSoft, SC.cobalt, Colors.transparent, _checkIc);
    String sub;
    if (done) {
      sub = 'পুরো নিয়েছে';
    } else if (cancelled) {
      sub = 'পুরো ফেরত এসেছে';
    } else if (st == 'partial') {
      sub = 'কম নিয়েছে${due > 0 ? ' · বাকি ${bnMoney(due, smart: true)}' : ''}';
    } else if (st == 'due') {
      sub = 'বকেয়ায় ডেলিভারি · বাকি ${bnMoney(due, smart: true)}';
    } else if (trip) {
      sub = 'ডেলিভারির পথে';
    } else {
      sub = 'অর্ডার নেওয়া হয়েছে';
    }
    Widget? strip;
    if (cancelled && '${o['cancel_reason'] ?? ''}'.isNotEmpty) {
      strip = _Strip('দোকানের কারণ: "${o['cancel_reason']}"', danger: true);
    } else if (partial && (due > 0 || num0(o['damage']) > 0)) {
      final msg = num0(o['damage']) > 0 ? 'ক্ষতি ${bnMoney(o['damage'], smart: true)}' : 'বকেয়া ${bnMoney(due, smart: true)}';
      strip = _Strip('ডেলিভারি: ${bnMoney(o['delivered_total'], smart: true)} · $msg', danger: false);
    }
    return Opacity(
      opacity: cancelled ? 0.6 : 1,
      child: SCard(
        onTap: onTap,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        shadow: const [BoxShadow(color: Color(0x080F172A), blurRadius: 8, offset: Offset(0, 2))],
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Container(
              width: 34, height: 34,
              decoration: BoxDecoration(color: icoBg, borderRadius: BorderRadius.circular(10), border: Border.all(color: icoBd)),
              child: Center(child: Svg(icon, size: 16, color: icoFg, stroke: 2.5)),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${o['retailer']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: ts(14, w: FontWeight.w700, h: 1.35)),
                Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: ts(11.5, color: SC.muted, h: 1.4, tabular: true)),
              ]),
            ),
            const SizedBox(width: 10),
            Text(bnMoney(o['sr_total'], smart: true), style: ts(14.5, w: FontWeight.w800, tabular: true).copyWith(decoration: cancelled ? TextDecoration.lineThrough : null)),
            const SizedBox(width: 4),
            Text('›', style: ts(16, w: FontWeight.w600, color: SC.muted, h: 1)),
          ]),
          const SizedBox(height: 11),
          Container(
            padding: const EdgeInsets.only(top: 8),
            decoration: const BoxDecoration(border: Border(top: BorderSide(color: SC.border))),
            child: SrTimeline(o),
          ),
          if (strip != null) ...[const SizedBox(height: 11), strip],
        ]),
      ),
    );
  }
}

class _Strip extends StatelessWidget {
  const _Strip(this.text, {required this.danger});
  final String text;
  final bool danger;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(color: danger ? SC.dangerBg : SC.warnBg, borderRadius: BorderRadius.circular(9), border: Border.all(color: danger ? SC.dangerBorder : SC.warnBorder)),
        child: Text(text, style: ts(11.5, w: FontWeight.w600, color: danger ? SC.dangerText : SC.warnText, h: 1.35)),
      );
}

/// Memo detail: আমার কপি (timeline, per-item cards with ওভার/কমিশন, summary) and দোকানের কপি (formal memo).
class SrOrderDetailPage extends StatefulWidget {
  const SrOrderDetailPage({super.key, required this.order, required this.date});
  final Map<String, dynamic> order;
  final String date;
  @override
  State<SrOrderDetailPage> createState() => _SrOrderDetailPageState();
}

class _SrOrderDetailPageState extends State<SrOrderDetailPage> {
  bool _shop = false;

  Map<String, dynamic> get o => widget.order;

  String get _pay => num0(o['delivered_total']) > 0
      ? '${bnMoney(o['paid'], smart: true)} জমা${num0(o['due']) > 0 ? ' · ${bnMoney(o['due'], smart: true)} বাকি' : ' · পূর্ণ আদায়'}'
      : 'ডেলিভারির সময়';

  String get _delivery => (o['trip'] != null && '${o['trip']}'.isNotEmpty)
      ? '${o['dsr'] ?? '—'} (${bn(o['trip'])}${o['trip_date'] != null ? ' · ${dateBn(o['trip_date'].toString())}' : ''})'
      : 'অপেক্ষমান (ট্রিপ হয়নি)';

  List<Map<String, dynamic>> get _items => (o['items'] as List).map(_m).toList();

  List<ReceiptLine> _receipt() => [
        ReceiptLine('${o['company']}', style: ReceiptStyle.title, center: true),
        ReceiptLine('মেমো ${o['code']}', right: dateBn(o['date']?.toString() ?? widget.date)),
        ReceiptLine('দোকান: ${o['retailer']}', style: ReceiptStyle.bold),
        ReceiptLine.rule(),
        for (final it in _items) ...[
          ReceiptLine('${it['name']}'),
          ReceiptLine('  ${bn(it['pcs'])} × ${num2(it['sr_rate_pc'])}', right: bnMoney(it['total'], smart: true), style: ReceiptStyle.small),
        ],
        ReceiptLine.rule(),
        ReceiptLine('মোট', right: bnMoney(o['sr_total'], smart: true), style: ReceiptStyle.bold),
        ReceiptLine.rule(),
        ReceiptLine('ধন্যবাদ', center: true),
      ];

  Future<void> _shareShop() async {
    final lines = [
      '${o['company']}',
      'মেমো নং: ${bn(o['code'])} | তারিখ: ${dateBn(o['date']?.toString() ?? widget.date)}',
      'দোকান: ${o['retailer']}',
      '----------------',
      for (final it in _items) '${it['name']}: ${bn(it['pcs'])} পিস — ${bnMoney(it['total'], smart: true)}',
      '----------------',
      'মোট: ${bnMoney(o['sr_total'], smart: true)}',
    ].join('\n');
    await Clipboard.setData(ClipboardData(text: lines));
    if (mounted) toast(context, 'দোকানের কপি কপি করা হয়েছে।');
  }

  Future<void> _print() async {
    final err = await busy(context, () => PrinterService.print(_receipt()));
    if (mounted) toast(context, err ?? 'প্রিন্ট হয়েছে।', error: err != null);
  }

  @override
  Widget build(BuildContext context) {
    final key = '${o['status_key'] ?? ''}';
    return SPage(
      child: Column(children: [
        SSubHead(
          title: '${o['retailer']}',
          sub: 'মেমো ${bn(o['code'])} · ${dateBn(o['date']?.toString() ?? widget.date)} · ${bn(o['time'] ?? '')}',
          trailing: SBadge(statusBnKey(key.isEmpty ? '${o['status']}' : key), tone: toneOfStatus(key)),
        ),
        Container(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
          decoration: const BoxDecoration(color: SC.surface, border: Border(bottom: BorderSide(color: SC.border))),
          child: Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(color: SC.tabBg, borderRadius: BorderRadius.circular(12)),
            child: Row(children: [
              _Tab('আমার কপি', !_shop, () => setState(() => _shop = false)),
              const SizedBox(width: 5),
              _Tab('দোকানের কপি', _shop, () => setState(() => _shop = true)),
            ]),
          ),
        ),
        Expanded(child: ListView(padding: const EdgeInsets.fromLTRB(14, 12, 14, 18), children: _shop ? [_shopCopy()] : _myCopy())),
        Container(
          padding: EdgeInsets.fromLTRB(14, 12, 14, 14 + MediaQuery.of(context).padding.bottom),
          decoration: const BoxDecoration(color: SC.surface, border: Border(top: BorderSide(color: SC.border))),
          child: Row(children: [
            Expanded(flex: 10, child: SBtn(_shop ? 'দোকানে পাঠান' : 'দোকানের কপি', kind: SBtnKind.secondary, height: 44, radius: 12, onTap: _shop ? _shareShop : () => setState(() => _shop = true))),
            const SizedBox(width: 10),
            Expanded(flex: 13, child: SBtn('প্রিন্ট', kind: SBtnKind.navy, height: 44, radius: 12, icon: const Svg(Ic.print, size: 15, color: Colors.white), onTap: _print)),
          ]),
        ),
      ]),
    );
  }

  List<Widget> _myCopy() {
    final oc = num0(o['oc']);
    return [
      SCard(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12), child: SrTimeline(o)),
      const SizedBox(height: 11),
      for (final it in _items) ...[_ItemCard(it), const SizedBox(height: 9)],
      const SizedBox(height: 2),
      SCard(
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 13),
        child: Column(children: [
          Container(
            padding: const EdgeInsets.only(bottom: 9),
            decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: SC.border))),
            child: _Sum('মোট অর্ডার', bnMoney(o['sr_total'], smart: true), head: true),
          ),
          const SizedBox(height: 8),
          _Sum('বেজ (ডিলার) মূল্য', bnMoney(o['base_total'], smart: true), muted: true),
          const SizedBox(height: 8),
          _Sum('নিট O/C', signedMoney(oc, smart: true), muted: true, bold: true, color: oc > 0 ? SC.ok : (oc < 0 ? SC.dangerText : SC.ink)),
          const SizedBox(height: 8),
          _Sum('ডেলিভারি', _delivery, muted: true, bold: true),
          const SizedBox(height: 8),
          _Sum('টাকা নেওয়া', _pay, muted: true, bold: true),
          if ('${o['cancel_reason'] ?? ''}'.isNotEmpty) ...[const SizedBox(height: 8), _Strip('বাতিল কারণ: ${o['cancel_reason']}', danger: true)],
        ]),
      ),
    ];
  }

  Widget _shopCopy() {
    final partner = '${o['partner'] ?? o['company'] ?? ''}';
    Widget kvText(String t, {bool muted = false}) => Text(t, style: ts(11.5, color: muted ? SC.muted : SC.ink, h: 1.5, tabular: true));
    final addr = '${o['retailer_address'] ?? ''}'.isEmpty ? '—' : '${o['retailer_address']}';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
      decoration: BoxDecoration(color: SC.surface, borderRadius: BorderRadius.circular(14), border: Border.all(color: SC.borderStrong), boxShadow: const [BoxShadow(color: Color(0x0F0F172A), blurRadius: 18, offset: Offset(0, 4))]),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Container(
          padding: const EdgeInsets.only(bottom: 10),
          decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: SC.border))),
          child: Column(children: [
            Text(partner, textAlign: TextAlign.center, style: ts(16, w: FontWeight.w800)),
            Text('${o['company']}', style: ts(11.5, color: SC.muted)),
            Container(
              margin: const EdgeInsets.only(top: 4),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
              decoration: BoxDecoration(color: SC.subtle, borderRadius: BorderRadius.circular(99), border: Border.all(color: SC.borderStrong)),
              child: Text('আসল মেমো', style: ts(11, w: FontWeight.w700, color: SC.ink2)),
            ),
          ]),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.only(bottom: 10),
          decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: SC.borderStrong))),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text.rich(TextSpan(style: ts(11.5, h: 1.5), children: [const TextSpan(text: 'দোকান: '), TextSpan(text: '${o['retailer']}', style: ts(11.5, w: FontWeight.w700))])),
                kvText('$addr${'${o['retailer_phone'] ?? ''}'.isNotEmpty ? ' · ${bn(o['retailer_phone'])}' : ''}', muted: true),
              ]),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text.rich(TextSpan(style: ts(11.5, h: 1.5, tabular: true), children: [const TextSpan(text: 'মেমো: '), TextSpan(text: bn(o['code']), style: ts(11.5, w: FontWeight.w700))])),
                kvText('${dateBn(o['date']?.toString() ?? widget.date)} · ${bn(o['time'] ?? '')}', muted: true),
                kvText('${o['company']}', muted: true),
              ]),
            ),
          ]),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.symmetric(vertical: 6),
          decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: SC.borderStrong))),
          child: Row(children: [
            Expanded(flex: 5, child: Text('পণ্য', style: ts(11, w: FontWeight.w700, color: SC.muted))),
            Expanded(flex: 3, child: Text('পরিমাণ', textAlign: TextAlign.center, style: ts(11, w: FontWeight.w700, color: SC.muted))),
            Expanded(flex: 2, child: Text('দর', textAlign: TextAlign.right, style: ts(11, w: FontWeight.w700, color: SC.muted))),
            Expanded(flex: 3, child: Text('টাকা', textAlign: TextAlign.right, style: ts(11, w: FontWeight.w700, color: SC.muted))),
          ]),
        ),
        for (var i = 0; i < _items.length; i++)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 7),
            decoration: BoxDecoration(border: i == _items.length - 1 ? null : const Border(bottom: BorderSide(color: SC.border))),
            child: Row(children: [
              Expanded(flex: 5, child: Text('${_items[i]['name']}', style: ts(12, w: FontWeight.w600, h: 1.35))),
              Expanded(flex: 3, child: Text('${bn(_items[i]['pcs'])} পিস', textAlign: TextAlign.center, style: ts(12, w: FontWeight.w600, tabular: true))),
              Expanded(flex: 2, child: Text(bnMoney(_items[i]['sr_rate_pc'], smart: true), textAlign: TextAlign.right, style: ts(12, w: FontWeight.w600, tabular: true))),
              Expanded(flex: 3, child: Text(bnMoney(_items[i]['total'], smart: true), textAlign: TextAlign.right, style: ts(12, w: FontWeight.w600, tabular: true))),
            ]),
          ),
        const SizedBox(height: 4),
        Container(
          padding: const EdgeInsets.only(top: 9),
          decoration: const BoxDecoration(border: Border(top: BorderSide(color: SC.ink, width: 1.5))),
          child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text('মোট', style: ts(15.5, w: FontWeight.w800)),
            Text(bnMoney(o['sr_total'], smart: true), style: ts(15.5, w: FontWeight.w800, tabular: true)),
          ]),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(color: SC.subtle, borderRadius: BorderRadius.circular(8), border: Border.all(color: SC.border)),
          child: Text('$_pay${o['trip'] != null && '${o['trip']}'.isNotEmpty ? ' · ট্রিপ ${bn(o['trip'])}' : ''}', textAlign: TextAlign.center, style: ts(11.5, w: FontWeight.w600, color: SC.ink2, h: 1.4)),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 22),
          child: Row(children: [
            for (final t in ['দোকানদার', 'এসআর (${o['sr'] ?? ''})']) ...[
              if (!t.startsWith('দোকান')) const SizedBox(width: 20),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.only(top: 5),
                  decoration: const BoxDecoration(border: Border(top: BorderSide(color: SC.borderStrong))),
                  child: Text(t, textAlign: TextAlign.center, style: ts(11, w: FontWeight.w600, color: SC.muted)),
                ),
              ),
            ],
          ]),
        ),
      ]),
    );
  }
}

class _Tab extends StatelessWidget {
  const _Tab(this.label, this.on, this.onTap);
  final String label;
  final bool on;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Expanded(
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(color: on ? SC.ink : Colors.transparent, borderRadius: BorderRadius.circular(9), boxShadow: on ? const [BoxShadow(color: Color(0x2E0F172A), blurRadius: 6, offset: Offset(0, 2))] : null),
            child: Center(child: Text(label, style: ts(13, w: FontWeight.w700, color: on ? Colors.white : SC.ink2))),
          ),
        ),
      );
}

class _ItemCard extends StatelessWidget {
  const _ItemCard(this.it);
  final Map<String, dynamic> it;
  @override
  Widget build(BuildContext context) {
    final oc = (num0(it['oc']) * 100).round() / 100;
    final unit = num0(it['sr_rate_pc']) * (num0(it['qty_per_unit']) == 0 ? 1 : num0(it['qty_per_unit']));
    final image = ApiClient.asset(it['image']);
    final tintStr = '${it['tint'] ?? ''}'.replaceFirst('#', '');
    final tint = tintStr.length == 6 ? Color(0xFF000000 | (int.tryParse(tintStr, radix: 16) ?? 0xF8FAFC)) : SC.subtle;
    return SCard(
      radius: 14, padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      shadow: const [],
      child: Row(children: [
        Container(
          width: 42, height: 42,
          decoration: BoxDecoration(color: tint, borderRadius: BorderRadius.circular(10), border: Border.all(color: SC.border)),
          clipBehavior: Clip.antiAlias,
          child: image != null ? Padding(padding: const EdgeInsets.all(4), child: NetImage(image, fit: BoxFit.contain)) : Center(child: Text('${it['code'] ?? 'PR'}', style: ts(12, w: FontWeight.w800, h: 1))),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${it['name']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: ts(13.5, w: FontWeight.w700)),
            const SizedBox(height: 3),
            Wrap(spacing: 6, runSpacing: 2, crossAxisAlignment: WrapCrossAlignment.center, children: [
              Text('${bn(it['pcs'])} পিস × ${bnMoney(it['sr_rate_pc'], smart: true)} (ইউনিট ${bnMoney(unit, smart: true)})', style: ts(11.5, w: FontWeight.w600, color: SC.muted, tabular: true)),
              if (oc.abs() >= 0.01)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
                  decoration: BoxDecoration(color: oc > 0 ? SC.okBg : SC.dangerBg, borderRadius: BorderRadius.circular(99)),
                  child: Text(oc > 0 ? 'ওভার +${bnMoney(oc, smart: true)}' : 'কমিশন −${bnMoney(oc.abs(), smart: true)}', style: ts(10.5, w: FontWeight.w700, color: oc > 0 ? SC.ok : SC.dangerText, h: 1.4)),
                ),
            ]),
          ]),
        ),
        const SizedBox(width: 10),
        Text(bnMoney(it['total'], smart: true), style: ts(14.5, w: FontWeight.w800, tabular: true)),
      ]),
    );
  }
}

class _Sum extends StatelessWidget {
  const _Sum(this.k, this.v, {this.head = false, this.muted = false, this.bold = false, this.color});
  final String k, v;
  final bool head, muted, bold;
  final Color? color;
  @override
  Widget build(BuildContext context) => Row(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text(k, style: ts(head ? 15 : 13, w: head ? FontWeight.w800 : FontWeight.w400, color: muted ? SC.muted : SC.ink)),
        const SizedBox(width: 10),
        Flexible(child: Text(v, textAlign: TextAlign.right, style: ts(head ? 15 : 13, w: head || bold ? FontWeight.w700 : FontWeight.w400, color: color ?? SC.ink, tabular: true))),
      ]);
}
