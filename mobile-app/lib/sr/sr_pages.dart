import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../core/api.dart';
import '../core/format.dart';
import '../core/offline.dart';
import '../core/session.dart';
import '../ui/account.dart';
import '../ui/common.dart';
import '../ui/hkit.dart';
import '../ui/printer_page.dart';
import '../ui/pwa_kit.dart';

Map<String, dynamic> _m(Object? v) => Map<String, dynamic>.from((v ?? {}) as Map);

const icLogout = '<path d="M9 21H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h4M16 17l5-5-5-5M21 12H9"/>';

Future<void> signOut(BuildContext context) async {
  final q = OfflineQueue.instance.ops.length;
  if (await confirm(context, 'সাইন আউট করবেন?', body: q > 0 ? 'এখনো ${bn(q)}টি কাজ সিঙ্ক হয়নি। সাইন আউট করলে সেগুলো মুছে যাবে।' : null, danger: true, yes: 'সাইন আউট')) {
    if (context.mounted) await context.read<AuthState>().logout();
  }
}

/// Thin progress bar.
class SProgress extends StatelessWidget {
  const SProgress(this.pct, {super.key});
  final double pct;
  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: BorderRadius.circular(99),
        child: LinearProgressIndicator(value: (pct / 100).clamp(0, 1), minHeight: 6, backgroundColor: HC.bg, color: HC.blue),
      );
}

/// Ring with "৫৯% লক্ষ্য" in the middle (SR1).
class _Ring extends StatelessWidget {
  const _Ring(this.pct);
  final int pct;
  @override
  Widget build(BuildContext context) => Semantics(
        label: 'দৈনিক লক্ষ্যের ${bn(pct)}% হয়েছে',
        child: SizedBox(
          width: 84, height: 84,
          child: CustomPaint(
            painter: _RingPainter(pct / 100),
            child: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text('${bn(pct)}%', style: hs(18, w: w7, color: Colors.white, h: 1.1)),
              Text('লক্ষ্য', style: hs(10, color: HC.onSky, h: 1.1)),
            ])),
          ),
        ),
      );
}

class _RingPainter extends CustomPainter {
  _RingPainter(this.v);
  final double v;
  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    const r = 36.0;
    final base = Paint()..color = const Color(0x33FFFFFF)..style = PaintingStyle.stroke..strokeWidth = 8;
    final fg = Paint()..color = Colors.white..style = PaintingStyle.stroke..strokeWidth = 8..strokeCap = StrokeCap.round;
    canvas.drawCircle(c, r, base);
    if (v > 0) canvas.drawArc(Rect.fromCircle(center: c, radius: r), -math.pi / 2, 2 * math.pi * v.clamp(0, 1), false, fg);
  }

  @override
  bool shouldRepaint(covariant _RingPainter o) => o.v != v;
}

/// SR1 · আজ: who, today's order value + target ring, memo / shop / over / commission, "নতুন অর্ডার".
class SrDashboardPage extends StatelessWidget {
  const SrDashboardPage({super.key, required this.onNewOrder, required this.onHistory});
  final VoidCallback onNewOrder, onHistory;

  @override
  Widget build(BuildContext context) {
    final photo = ApiClient.asset(context.watch<AuthState>().profile['photo']);
    return AsyncBody(
      sky: true,
      load: () => loadCached('sr_dashboard', () => ApiClient.get('/sr/dashboard')),
      builder: (context, d, reload) {
        final profile = _m(d['profile']);
        final today = _m(d['today']);
        final month = _m(d['month']);
        final done = d['day_completed'] == true;
        final todayValue = num0(today['value']);
        final target = num0(profile['daily_target']);
        final pct = target > 0 ? (todayValue / target * 100).round().clamp(0, 100) : 0;
        final remaining = math.max(0, target - todayValue);
        final monthTarget = num0(profile['monthly_target']);
        final monthPct = monthTarget > 0 ? (num0(month['value']) / monthTarget * 100).round().clamp(0, 100) : 0;
        final orders = int0(today['orders']);
        final ocBal = num0(profile['oc_balance']);
        final name = '${profile['name'] ?? ''}';
        return SkyBox(
          height: 290,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            SkyHead(
              leading: LetterAvatar(name, size: 44, bg: HC.lilac, fg: HC.ink, fontSize: 17, image: photo == null ? null : NetImage(photo)),
              kicker: 'SR · ${profile['company']} · ${profile['partner'] ?? ''}',
              title: name,
              trailing: GlassBtn(icon: icLogout, label: 'সাইন আউট', onTap: () => signOut(context)),
            ),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('আজকের অর্ডার${done ? ' · দিন সম্পন্ন ✓' : ''}', style: hs(12, color: HC.onSky)),
                FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft,
                    child: Text(tk(todayValue), style: hs(36, w: w8, color: Colors.white, ls: -.5, h: 1.15, num: true))),
                Text(target > 0 ? (remaining > 0 ? 'লক্ষ্য ${tk(target)} · আরও ${tk(remaining)} বাকি' : 'লক্ষ্য অর্জিত ✓') : 'দৈনিক লক্ষ্য নির্ধারিত নেই',
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: hs(12, color: HC.onSky)),
              ])),
              if (target > 0) ...[const SizedBox(width: 16), _Ring(pct)],
            ]),
            gap12,
            HCard(
              lift: true, padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 4),
              child: HStrip(style: StripStyle.plain, valueSize: 18, [
                HStat('মেমো', bn(orders), labelOnTop: false),
                HStat('দোকান', bn(int0(today['retailers'])), color: HC.ink2, labelOnTop: false),
                HStat('ওভার', '+${tk(today['over_oc'])}', color: HC.blue, labelOnTop: false),
                HStat('কমিশন', '−${tk(num0(today['comm_oc']).abs())}', color: HC.red, labelOnTop: false),
              ]),
            ),
            gap12,
            HBtn('নতুন অর্ডার', icon: Ic.plus, onTap: onNewOrder, height: 52, radius: 18, fontSize: 17),
            if (done || orders > 0) ...[
              gap12,
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(color: done ? Colors.white : HC.soft, borderRadius: BorderRadius.circular(16), border: done ? Border.all(color: HC.line) : null),
                child: Text(done
                    ? 'আজকের অর্ডার সম্পন্ন হয়েছে${int0(today['assigned']) > 0 ? ' এবং ডেলিভারি ট্রিপে দেওয়া হয়েছে।' : ' — ডেলিভারি ট্রিপের অপেক্ষায়।'}'
                    : 'আজকের অর্ডার খোলা আছে। কাজ শেষে অর্ডার পেজের "আজ" থেকে দিন সম্পন্ন করুন।', style: hs(13)),
              ),
            ],
            gap12,
            IntrinsicHeight(child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Expanded(child: _Mini('এই মাসে অর্ডার', tk(month['value']), '${bn(int0(month['orders']))}টি মেমো${monthTarget > 0 ? ' · লক্ষ্যের ${bn(monthPct)}%' : ''}')),
              const SizedBox(width: 10),
              Expanded(child: _Mini('O/C ব্যালেন্স', sMoney(ocBal), 'হিস্ট্রি দেখুন ›', valueColor: ocBal < 0 ? HC.red : HC.blue, link: true, onTap: onHistory)),
            ])),
          ]),
        );
      },
    );
  }
}

class _Mini extends StatelessWidget {
  const _Mini(this.label, this.value, this.sub, {this.valueColor = HC.ink, this.onTap, this.link = false});
  final String label, value, sub;
  final Color valueColor;
  final VoidCallback? onTap;
  final bool link;
  @override
  Widget build(BuildContext context) => HCard(
        radius: 20, padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12), onTap: onTap,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: hs(12, color: HC.muted)),
          FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text(value, style: hs(18, w: w7, color: valueColor, num: true))),
          Text(sub, maxLines: 2, overflow: TextOverflow.ellipsis, style: hs(12, w: link ? w7 : FontWeight.w400, color: link ? HC.blue : HC.muted)),
        ]),
      );
}

/// SR7 · আমি: photo, date bar, net (my due), memo · total, over / commission, product table, month, account.
class SrProfilePage extends StatefulWidget {
  const SrProfilePage({super.key});
  @override
  State<SrProfilePage> createState() => _SrProfilePageState();
}

class _SrProfilePageState extends State<SrProfilePage> {
  String? _date;

  Future<void> _pickPhoto(VoidCallback reload) async {
    final auth = context.read<AuthState>();
    final x = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 800, imageQuality: 85);
    if (x == null || !mounted) return;
    final r = await busy(context, () => ApiClient.upload('/sr/profile/photo', 'photo', File(x.path)));
    if (r != null && mounted) {
      toast(context, (r['message'] ?? 'ছবি সংরক্ষিত হয়েছে।').toString());
      await auth.refreshProfile();
      reload();
    }
  }

  @override
  Widget build(BuildContext context) {
    context.watch<AuthState>();
    return AsyncBody(
      key: ValueKey(_date),
      sky: true,
      load: () => loadCached('sr_profile_${_date ?? 'last'}', () => ApiClient.get('/sr/profile', query: {'date': _date})),
      builder: (context, d, reload) {
        final p = _m(d['profile']);
        final photo = ApiClient.asset(p['photo']);
        final date = d['date'].toString();
        final day = _m(d['day_summary']);
        final s = _m(day['stats']);
        final products = (day['products'] as List?)?.map(_m).toList() ?? [];
        final month = _m(d['month']);
        final monthValue = num0(month['value']);
        final monthTarget = num0(p['monthly_target']);
        final monthPct = monthTarget > 0 ? (monthValue / monthTarget * 100).round().clamp(0, 100) : 0;
        final net = num0(s['oc']);
        final ocBal = num0(p['oc_balance']);
        final today = d['today']?.toString() ?? todayYmd();
        final name = '${p['name'] ?? ''}';
        return SkyBox(
          height: 270,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Semantics(
                button: true, label: 'ছবি পরিবর্তন করুন',
                child: GestureDetector(
                  onTap: () => _pickPhoto(reload),
                  child: Stack(clipBehavior: Clip.none, children: [
                    LetterAvatar(name, size: 54, ring: true, fontSize: 22, image: photo == null ? null : NetImage(photo)),
                    Positioned(right: -2, bottom: -2, child: Container(
                      width: 20, height: 20,
                      decoration: BoxDecoration(color: HC.ink, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 2)),
                      child: const Icon(Icons.photo_camera_rounded, size: 10, color: Colors.white),
                    )),
                  ]),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: hs(19, w: w7, color: Colors.white)),
                Text('SR · ${p['company']} · ${p['partner']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: hs(12, color: HC.onSky)),
              ])),
              GestureDetector(
                onTap: () => signOut(context),
                child: Container(
                  height: 40, padding: const EdgeInsets.symmetric(horizontal: 12), alignment: Alignment.center,
                  decoration: BoxDecoration(color: const Color(0x24FFFFFF), border: Border.all(color: const Color(0x38FFFFFF)), borderRadius: BorderRadius.circular(12)),
                  child: Text('লগআউট', style: hs(12, w: w6, color: Colors.white)),
                ),
              ),
            ]),
            gap12,
            SkyDateBar(date: date, today: today, sub: 'অর্ডার সারাংশ', onChange: (v) => setState(() => _date = v)),
            gap12,
            HCard(
              lift: true, padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('নিট · আমার পাওনা', style: hs(12, color: HC.muted)),
                    Text(sMoney(net), style: hs(30, w: w8, color: net < 0 ? HC.red : HC.blue, h: 1.15, num: true)),
                  ])),
                  Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                    Text('${bn(int0(s['orders']))}টি মেমো · মোট অর্ডার', style: hs(12, color: HC.muted)),
                    Text(tk(s['value']), style: hs(17, w: w7, num: true)),
                  ]),
                ]),
                gap12,
                HStrip(style: StripStyle.soft, [
                  HStat('ওভার', '+${tk(s['over_oc'])}', color: HC.blue),
                  HStat('কমিশন', '−${tk(num0(s['comm_oc']).abs())}', color: HC.red),
                  HStat('নিট', sMoney(net)),
                ]),
              ]),
            ),
            gap12,
            HCard(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                _ProdRow(const ['পণ্য', 'অর্ডার', 'গেছে', 'নিয়েছে', 'ফেরত'], head: true),
                if (products.isEmpty)
                  Padding(padding: const EdgeInsets.symmetric(vertical: 16), child: Text('এই তারিখে কোনো পণ্যের হিসাব নেই।', textAlign: TextAlign.center, style: hs(12, color: HC.muted)))
                else
                  for (var i = 0; i < products.length; i++)
                    _ProdRow([
                      '${products[i]['name']}',
                      bn(int0(products[i]['ordered_pcs'])),
                      int0(products[i]['dispatched_pcs']) > 0 ? bn(int0(products[i]['dispatched_pcs'])) : '—',
                      int0(products[i]['delivered_pcs']) > 0 ? bn(int0(products[i]['delivered_pcs'])) : '—',
                      int0(products[i]['returned_pcs']) > 0 ? bn(int0(products[i]['returned_pcs'])) : '—',
                    ], first: i == 0, soft: i.isOdd),
                if (products.isNotEmpty && products.every((x) => int0(x['dispatched_pcs']) == 0))
                  Padding(padding: const EdgeInsets.only(top: 6), child: Text('ডেলিভারি হলে গেছে / নিয়েছে এখানে আসবে', style: hs(11, color: HC.muted))),
              ]),
            ),
            gap12,
            HCard(
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                HSec('মাসিক পারফরম্যান্স · ${monthYearBn()}', trailing: monthTarget > 0 ? '${bn(monthPct)}% অর্জিত' : null, size: 15),
                gap8,
                Row(children: [
                  Expanded(child: Text('মাসিক অর্ডার', style: hs(12, color: HC.muted))),
                  Text.rich(TextSpan(style: hs(14, w: w7, num: true), children: [
                    TextSpan(text: tk(monthValue)),
                    if (monthTarget > 0) TextSpan(text: ' / ${tk(monthTarget)}', style: hs(12, color: HC.muted, num: true)),
                  ])),
                ]),
                const SizedBox(height: 6),
                SProgress(monthPct.toDouble()),
                gap12,
                HStrip(style: StripStyle.soft, valueSize: 16, [
                  HStat('মেমো', bn(int0(month['orders']))),
                  HStat('দোকান', bn(int0(month['retailers']))),
                  HStat('ডেলিভারি হার', int0(month['done']) > 0 ? '${bn(month['delivery_rate'])}%' : '—'),
                  HStat('O/C ব্যালেন্স', sMoney(ocBal), color: ocBal < 0 ? HC.red : HC.blue),
                ]),
              ]),
            ),
            gap12,
            HList(padding: const EdgeInsets.symmetric(horizontal: 16), children: [
              _Link('পাসওয়ার্ড পরিবর্তন', () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ChangePasswordPage()))),
              _Link('ব্লুটুথ প্রিন্টার', () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const PrinterPage()))),
              _Link('সিঙ্ক অবস্থা', () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const PendingPage()))),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 14),
                child: Row(children: [
                  Expanded(child: Text('অ্যাপ সংস্করণ', style: hs(14, color: HC.ink2))),
                  Text('${ApiClient.versionName} (${ApiClient.buildNumber})', style: hs(12, color: HC.muted, num: true)),
                ]),
              ),
            ]),
          ]),
        );
      },
    );
  }
}

class _ProdRow extends StatelessWidget {
  const _ProdRow(this.cells, {this.head = false, this.first = false, this.soft = false});
  final List<String> cells;
  final bool head, first, soft;
  @override
  Widget build(BuildContext context) => Container(
        padding: EdgeInsets.symmetric(vertical: head ? 0 : 9).copyWith(bottom: head ? 4 : 9),
        decoration: BoxDecoration(border: head || first ? null : const Border(top: BorderSide(color: HC.line))),
        child: Row(children: [
          Expanded(
            flex: 11,
            child: head
                ? Text(cells[0], style: hs(11, color: HC.muted))
                : Row(children: [
                    LetterAvatar(cells[0], size: 26, radius: 8, bg: soft ? HC.soft : HC.chip, fg: soft ? HC.blue : HC.ink2, fontSize: 10),
                    const SizedBox(width: 8),
                    Expanded(child: Text(cells[0], maxLines: 2, overflow: TextOverflow.ellipsis, style: hs(13, w: w6))),
                  ]),
          ),
          for (var i = 1; i < cells.length; i++)
            Expanded(flex: 4, child: Text(cells[i], textAlign: TextAlign.right,
                style: head ? hs(11, color: HC.muted) : hs(13, w: i == 1 ? w7 : FontWeight.w400, color: i == 1 ? HC.ink : (i == 4 && cells[i] != '—' ? HC.red : HC.muted), num: true))),
        ]),
      );
}

class _Link extends StatelessWidget {
  const _Link(this.label, this.onTap);
  final String label;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14),
          child: Row(children: [
            Expanded(child: Text(label, style: hs(14, w: w6))),
            const Svg('<path d="M9 5l7 7-7 7"/>', size: 16, color: HC.muted, stroke: 1.8),
          ]),
        ),
      );
}
