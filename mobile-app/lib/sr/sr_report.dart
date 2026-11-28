import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart' as pw;
import 'package:pdf/widgets.dart' as pw;
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../core/api.dart';
import '../core/format.dart';
import '../core/session.dart';
import '../ui/common.dart';
import '../ui/hkit.dart';
import '../ui/motion.dart';
import '../ui/pwa_kit.dart';

Map<String, dynamic> _m(Object? v) => Map<String, dynamic>.from((v ?? {}) as Map);

/// SR · দিনের রিপোর্ট: a paper report of one day (order → delivery, shops, reasons, products, signatures),
/// shared as a picture or a PDF.
class SrReportPage extends StatefulWidget {
  const SrReportPage({super.key, this.date});
  final String? date;
  @override
  State<SrReportPage> createState() => _SrReportPageState();
}

class _SrReportPageState extends State<SrReportPage> {
  late String _date = widget.date ?? todayYmd();
  final _paper = GlobalKey();

  Future<File?> _png() async {
    final b = _paper.currentContext?.findRenderObject() as RenderRepaintBoundary?;
    if (b == null) return null;
    final img = await b.toImage(pixelRatio: 3);
    final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
    if (bytes == null) return null;
    final f = File('${(await getTemporaryDirectory()).path}/sr-report-$_date.png');
    await f.writeAsBytes(bytes.buffer.asUint8List());
    return f;
  }

  Future<void> _share() async {
    final f = await busy(context, _png);
    if (f == null) return;
    await SharePlus.instance.share(ShareParams(files: [XFile(f.path)], text: 'SR দিনের রিপোর্ট · ${dateBn(_date)}'));
  }

  Future<void> _pdf() async {
    final f = await busy(context, () async {
      final png = await _png();
      if (png == null) return null;
      final doc = pw.Document();
      final image = pw.MemoryImage(await png.readAsBytes());
      doc.addPage(pw.Page(pageFormat: pw.PdfPageFormat.a4, margin: const pw.EdgeInsets.all(24), build: (_) => pw.Center(child: pw.Image(image, fit: pw.BoxFit.contain))));
      final out = File('${(await getTemporaryDirectory()).path}/sr-report-$_date.pdf');
      await out.writeAsBytes(await doc.save());
      return out;
    });
    if (f == null) return;
    await SharePlus.instance.share(ShareParams(files: [XFile(f.path, mimeType: 'application/pdf')], text: 'SR দিনের রিপোর্ট · ${dateBn(_date)}'));
  }

  void _move(int days) {
    final d = DateTime.parse(_date).add(Duration(days: days));
    if (d.isAfter(DateTime.now())) return;
    setState(() => _date = ymd(d));
  }

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.of(context).padding.top;
    final isToday = _date == todayYmd();
    Widget topBtn(String t, VoidCallback onTap, {bool fill = false}) => Pressable(
          child: GestureDetector(
            onTap: onTap,
            child: Container(
              height: 40, padding: const EdgeInsets.symmetric(horizontal: 12), alignment: Alignment.center,
              decoration: BoxDecoration(color: fill ? HC.blue : Colors.white, borderRadius: BorderRadius.circular(10), border: fill ? null : Border.all(color: HC.line2)),
              child: Text(t, style: hs(13, w: fill ? w7 : w6, color: fill ? Colors.white : HC.ink)),
            ),
          ),
        );
    Widget dayBtn(String t, String label, bool on, VoidCallback onTap) => Semantics(
          button: true, label: label, enabled: on,
          child: Pressable(
            enabled: on,
            child: GestureDetector(
              onTap: on ? onTap : null,
              child: Opacity(
                opacity: on ? 1 : .35,
                child: Container(
                  width: 44, height: 44, alignment: Alignment.center,
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: HC.line2)),
                  child: Text(t, style: hs(18, w: w7, h: 1)),
                ),
              ),
            ),
          ),
        );
    return Scaffold(
      backgroundColor: HC.outer,
      body: Frame(
        color: HC.outer,
        child: ColoredBox(
          color: const Color(0xFFE9ECF2),
          child: Column(children: [
            Container(
              padding: EdgeInsets.fromLTRB(12, top + 14, 12, 14),
              decoration: const BoxDecoration(color: Colors.white, border: Border(bottom: BorderSide(color: HC.line))),
              child: Row(children: [
                Semantics(
                  button: true, label: 'পেছনে',
                  child: Pressable(
                    child: GestureDetector(
                      onTap: () => Navigator.of(context).maybePop(),
                      child: Container(width: 44, height: 44, decoration: const BoxDecoration(color: HC.bg, shape: BoxShape.circle), alignment: Alignment.center,
                          child: const Svg(Ic.back, size: 20, color: HC.ink, stroke: 2)),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(child: Text('দিনের রিপোর্ট', style: hs(17, w: w7))),
                topBtn('শেয়ার', _share),
                const SizedBox(width: 8),
                topBtn('PDF', _pdf, fill: true),
              ]),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: const BoxDecoration(color: Colors.white, border: Border(bottom: BorderSide(color: HC.line))),
              child: Row(children: [
                dayBtn('‹', 'আগের দিন', true, () => _move(-1)),
                const SizedBox(width: 6),
                Expanded(
                  child: GestureDetector(
                    onTap: () async {
                      final p = await showDatePicker(context: context, initialDate: DateTime.parse(_date), firstDate: DateTime(2024), lastDate: DateTime.now());
                      if (p != null) setState(() => _date = ymd(p));
                    },
                    child: _DayHead(date: _date, isToday: isToday),
                  ),
                ),
                const SizedBox(width: 6),
                dayBtn('›', 'পরের দিন', !isToday, () => _move(1)),
              ]),
            ),
            Expanded(
              child: AsyncBody(
                key: ValueKey(_date),
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
                load: () => loadCached('sr_report_$_date', () => ApiClient.get('/sr/report', query: {'date': _date})),
                builder: (context, d, reload) => RepaintBoundary(key: _paper, child: _Paper(d)),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

class _DayHead extends StatelessWidget {
  const _DayHead({required this.date, required this.isToday});
  final String date;
  final bool isToday;
  @override
  Widget build(BuildContext context) {
    const days = ['সোম', 'মঙ্গল', 'বুধ', 'বৃহস্পতি', 'শুক্র', 'শনি', 'রবি'];
    final d = DateTime.parse(date);
    return Column(children: [
      Text('${days[d.weekday - 1]}, ${dateBn(date)}', textAlign: TextAlign.center, style: hs(15, w: w7, num: true)),
      Text(isToday ? 'আজ · ছুঁয়ে তারিখ বদলান' : 'ছুঁয়ে তারিখ বদলান', textAlign: TextAlign.center, style: hs(12, color: HC.muted)),
    ]);
  }
}

const _ink = Color(0xFF121A2B);
const _rule = Color(0xFF9AA3B2);
const _cellLine = Color(0xFFE1E5EC);
const _head = Color(0xFFEEF1F6);
const _sub = Color(0xFF4A5468);

String _n(Object? v) => bn(NumberFormatBn.group(num0(v).round()));

/// The report sheet itself (white paper, tables with thin grey rules).
class _Paper extends StatelessWidget {
  const _Paper(this.d);
  final Map<String, dynamic> d;

  TextStyle t(double s, {FontWeight w = FontWeight.w400, Color c = _ink, bool num = false}) => hs(s, w: w, color: c, num: num);

  Widget _title(String s) => Text(s, style: t(12.5, w: w7));

  Widget _kv(List<(String, String, bool)> rows) => Container(
        margin: const EdgeInsets.only(top: 4),
        decoration: BoxDecoration(border: Border.all(color: _rule)),
        child: Column(children: [
          for (var i = 0; i < rows.length; i++)
            Container(
              color: rows[i].$3 ? _head : null,
              decoration: null,
              child: Container(
                decoration: BoxDecoration(border: i == 0 ? null : const Border(top: BorderSide(color: _rule))),
                child: Row(children: [
                  Expanded(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4), child: Text(rows[i].$1, style: t(12, w: rows[i].$3 ? w8 : FontWeight.w400)))),
                  Container(width: 1, height: 24, color: _rule),
                  SizedBox(width: 110, child: Padding(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                      child: Text(rows[i].$2, textAlign: TextAlign.right, style: t(12, w: rows[i].$3 ? w8 : FontWeight.w400, num: true)))),
                ]),
              ),
            ),
        ]),
      );

  Widget _dotted(String a, String b) => Container(
        padding: const EdgeInsets.symmetric(vertical: 3),
        decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFFC3C9D4), style: BorderStyle.solid, width: .6))),
        child: Row(children: [Expanded(child: Text(a, style: t(12.5))), Text(b, style: t(12.5, num: true))]),
      );

  @override
  Widget build(BuildContext context) {
    final auth = context.read<AuthState>();
    final p = auth.profile;
    final flow = d['flow'] == null ? null : _m(d['flow']);
    final waiting = d['waiting'] == true;
    final shops = ((d['shops'] as List?) ?? const []).map(_m).toList();
    final reasons = ((d['reasons'] as List?) ?? const []).map(_m).toList();
    final products = ((d['products'] as List?) ?? const []).map(_m).toList();
    final noOrder = ((d['no_order'] as List?) ?? const []).map(_m).toList();
    final tot = _m(d['totals']);
    String money(Object? v) => '৳${_n(v)}';
    String signed(num v) => v.abs() < .5 ? '—' : '${v > 0 ? '+' : '−'}${_n(v.abs())}';

    Widget shopRow(List<String> c, {bool head = false, bool sub = false, bool odd = false, List<Color?> colors = const []}) => Container(
          decoration: BoxDecoration(
            color: head || sub ? _head : (odd ? const Color(0xFFFAFBFD) : null),
            border: Border(bottom: BorderSide(color: head || sub ? _rule : _cellLine), top: sub ? const BorderSide(color: _rule) : BorderSide.none),
          ),
          child: IntrinsicHeight(
            child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              for (var i = 0; i < c.length; i++)
                Container(
                  width: i == 0 ? null : const [0.0, 54.0, 54.0, 50.0, 40.0][i],
                  padding: EdgeInsets.symmetric(horizontal: 6, vertical: head ? 6 : 7),
                  decoration: BoxDecoration(border: i == 0 ? null : const Border(left: BorderSide(color: _cellLine))),
                  child: i == 0
                      ? Text(c[i], maxLines: 1, overflow: TextOverflow.ellipsis, style: t(11.5, w: head || sub ? w8 : w6, c: head ? _sub : _ink))
                      : Text(c[i], maxLines: 1, overflow: TextOverflow.clip, textAlign: TextAlign.right,
                          style: t(11.5, w: head || sub ? w8 : (colors.length > i && colors[i] != null && colors[i] != const Color(0xFFD92D20) ? w7 : FontWeight.w400),
                              c: head ? _sub : (colors.length > i ? colors[i] ?? _ink : _ink), num: true)),
                ).let((w) => i == 0 ? Expanded(child: w) : w),
            ]),
          ),
        );

    var sumO = 0.0, sumD = 0.0, sumC = 0.0, sumOc = 0.0;
    for (final s in shops) {
      sumO += num0(s['order']);
      sumD += num0(s['delivered']);
      sumC += num0(s['cancel']);
      sumOc += num0(s['oc']);
    }
    Color? ocColor(num v) => v > .5 ? HC.blue : (v < -.5 ? HC.red : null);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 18),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(4),
          boxShadow: const [BoxShadow(color: Color(0x1F121A2B), blurRadius: 20, offset: Offset(0, 6))]),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Container(
          padding: const EdgeInsets.only(bottom: 10),
          decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: _rule, width: 2))),
          child: Column(children: [
            Text('${p['partner'] ?? ''}', textAlign: TextAlign.center, style: t(16, w: w8)),
            const SizedBox(height: 4),
            Text('SR DAY REPORT', style: t(13, w: w8).copyWith(letterSpacing: 1)),
            Text('নং: ${d['no'] ?? ''} · ${d['label'] ?? ''}', textAlign: TextAlign.center, style: t(11.5, w: w6, c: _sub, num: true)),
            Text('${p['name'] ?? ''} (${p['code'] ?? ''}) · ${p['company'] ?? ''}${'${p['area'] ?? ''}'.isEmpty ? '' : ' · ${p['area']}'}',
                textAlign: TextAlign.center, style: t(11.5)),
          ]),
        ),
        const SizedBox(height: 12),
        if (d['empty'] == true)
          Padding(padding: const EdgeInsets.symmetric(vertical: 30), child: Text('এই দিনে কোনো অর্ডার নেই।', textAlign: TextAlign.center, style: t(13, c: _sub)))
        else ...[
          _title('অর্ডার → ডেলিভারি'),
          _kv([
            ('মোট অর্ডার', money(flow?['order']), false),
            ('(−) বাতিল', waiting ? '—' : money(flow?['cancel']), false),
            ('(−) কম নিয়েছে', waiting ? '—' : money(flow?['part']), false),
            ('= ডেলিভারি হয়েছে', waiting ? 'বাকি' : money(flow?['delivered']), true),
          ]),
          const SizedBox(height: 12),
          _title('১. দোকান অনুযায়ী · অর্ডার / ডেলিভারি / বাতিল'),
          Container(
            margin: const EdgeInsets.only(top: 4),
            decoration: BoxDecoration(border: Border.all(color: _rule), borderRadius: BorderRadius.circular(6)),
            clipBehavior: Clip.antiAlias,
            child: Column(children: [
              shopRow(const ['দোকান', 'অর্ডার', 'ডেলি.', 'বাতিল', 'ও/ক'], head: true),
              for (var i = 0; i < shops.length; i++)
                shopRow([
                  '${shops[i]['name']}',
                  _n(shops[i]['order']),
                  shops[i]['delivered'] == null ? '—' : _n(shops[i]['delivered']),
                  num0(shops[i]['cancel']) > .5 ? _n(shops[i]['cancel']) : '—',
                  signed(num0(shops[i]['oc'])),
                ], odd: i.isEven, colors: [null, null, null, num0(shops[i]['cancel']) > .5 ? HC.red : null, ocColor(num0(shops[i]['oc']))]),
              shopRow(['সাবটোটাল', _n(sumO), waiting ? '—' : _n(sumD), sumC > .5 ? _n(sumC) : '—', signed(sumOc)], sub: true,
                  colors: [null, null, null, sumC > .5 ? HC.red : null, ocColor(sumOc)]),
            ]),
          ),
          const SizedBox(height: 8),
          Row(children: [Expanded(child: Text('মোট ওভার', style: t(12.5))), Text('+৳${_n(tot['over'])}', style: t(12.5, w: w7, c: HC.blue, num: true))]),
          const SizedBox(height: 3),
          Row(children: [Expanded(child: Text('মোট কমিশন', style: t(12.5))), Text('−৳${_n(tot['commission'])}', style: t(12.5, w: w7, c: HC.red, num: true))]),
          Container(
            margin: const EdgeInsets.only(top: 6),
            padding: const EdgeInsets.symmetric(vertical: 5),
            decoration: const BoxDecoration(border: Border(top: BorderSide(color: HC.ink, width: 2), bottom: BorderSide(color: HC.ink, width: 2))),
            child: Row(children: [
              Expanded(child: Text(' আমার পাওনা', style: t(12.5, w: w8))),
              Text(sMoney(tot['net']), style: t(12.5, w: w8, num: true)),
            ]),
          ),
          const SizedBox(height: 12),
          _title('২. বাতিল / কম নেওয়ার কারণ'),
          if (reasons.isEmpty) _dotted(waiting ? 'ডেলিভারি এখনো হয়নি' : 'কোনো বাতিল নেই', '')
          else for (final r in reasons) _dotted('${r['name']}', money(r['amount'])),
          const SizedBox(height: 12),
          _title(waiting ? '৩. পণ্য অনুযায়ী (অর্ডার)' : '৩. পণ্য অনুযায়ী (ডেলিভারি)'),
          for (final r in products) _dotted('${r['name']}', money(r['value'])),
          if (noOrder.isNotEmpty) ...[
            const SizedBox(height: 12),
            _title('৪. ভিজিট · অর্ডার দেয়নি'),
            for (final r in noOrder) _dotted('${r['name']}', '${r['time']}'),
          ],
        ],
        const SizedBox(height: 30),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          for (final s in const ['SR স্বাক্ষর', 'পার্টনার / ম্যানেজার'])
            Container(
              width: 130, padding: const EdgeInsets.only(top: 4),
              decoration: const BoxDecoration(border: Border(top: BorderSide(color: _ink))),
              child: Text(s, textAlign: TextAlign.center, style: t(11.5)),
            ),
        ]),
      ]),
    );
  }
}

extension _Let<T> on T {
  R let<R>(R Function(T) f) => f(this);
}

/// Indian-style digit grouping (১২,৩৪,৫৬৭) without decimals.
class NumberFormatBn {
  static String group(int n) {
    final neg = n < 0;
    var s = n.abs().toString();
    if (s.length > 3) {
      final last = s.substring(s.length - 3);
      var rest = s.substring(0, s.length - 3);
      final parts = <String>[];
      while (rest.length > 2) {
        parts.insert(0, rest.substring(rest.length - 2));
        rest = rest.substring(0, rest.length - 2);
      }
      if (rest.isNotEmpty) parts.insert(0, rest);
      s = '${parts.join(',')},$last';
    }
    return neg ? '-$s' : s;
  }
}
