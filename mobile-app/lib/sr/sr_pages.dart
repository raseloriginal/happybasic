import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../core/api.dart';
import '../core/format.dart';
import '../core/offline.dart';
import '../core/session.dart';
import '../ui/account.dart';
import '../ui/common.dart';
import '../ui/printer_page.dart';
import '../ui/pwa_kit.dart';
import '../ui/skit.dart';

Map<String, dynamic> _m(Object? v) => Map<String, dynamic>.from((v ?? {}) as Map);

Future<void> signOut(BuildContext context) async {
  final q = OfflineQueue.instance.ops.length;
  if (await confirm(context, 'সাইন আউট করবেন?', body: q > 0 ? 'এখনো ${bn(q)}টি কাজ সিঙ্ক হয়নি। সাইন আউট করলে সেগুলো মুছে যাবে।' : null, danger: true, yes: 'সাইন আউট')) {
    if (context.mounted) await context.read<AuthState>().logout();
  }
}

/// `.progress-track` / `.progress-fill`
class SProgress extends StatelessWidget {
  const SProgress(this.pct, {super.key});
  final double pct;
  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: BorderRadius.circular(99),
        child: Container(
          height: 8, color: SC.border, alignment: Alignment.centerLeft,
          child: FractionallySizedBox(widthFactor: (pct / 100).clamp(0, 1), child: Container(color: SC.ok)),
        ),
      );
}

/// /sr/dashboard — cobalt hero, overlapping sales card, big "নতুন অর্ডার" button, 2x2 mini stats.
class SrDashboardPage extends StatelessWidget {
  const SrDashboardPage({super.key, required this.onNewOrder, required this.onHistory});
  final VoidCallback onNewOrder, onHistory;

  @override
  Widget build(BuildContext context) {
    return AsyncBody(
      padding: EdgeInsets.zero,
      load: () => loadCached('sr_dashboard', () => ApiClient.get('/sr/dashboard')),
      builder: (context, d, reload) {
        final profile = _m(d['profile']);
        final today = _m(d['today']);
        final month = _m(d['month']);
        final done = d['day_completed'] == true;
        final todayValue = num0(today['value']);
        final target = num0(profile['daily_target']);
        final pct = target > 0 ? (todayValue / target * 100).round().clamp(0, 100) : 0;
        final remaining = (target - todayValue).clamp(0, double.infinity);
        final monthTarget = num0(profile['monthly_target']);
        final monthPct = monthTarget > 0 ? (num0(month['value']) / monthTarget * 100).round().clamp(0, 100) : 0;
        final area = '${profile['area'] ?? ''}'.trim().isEmpty ? 'আজকের রুট' : '${profile['area']}'.trim();
        final oc = num0(today['oc']);
        final orders = int0(today['orders']);
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          SHero(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Expanded(child: Text('${profile['name']} · SR · ${profile['company']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: ts(12.5, w: FontWeight.w500, color: const Color(0xDBFFFFFF)))),
                HeroLogout(onTap: () => signOut(context)),
              ]),
              const SizedBox(height: 10),
              Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Expanded(child: Text('আজ · $area', style: ts(22, w: FontWeight.w800, color: Colors.white, ls: -0.44, h: 1.2))),
                const SizedBox(width: 10),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                  decoration: BoxDecoration(color: const Color(0x29FFFFFF), borderRadius: BorderRadius.circular(99)),
                  child: Text(dateBn(d['date']?.toString() ?? todayYmd()), style: ts(11.5, w: FontWeight.w600, color: const Color(0xEBFFFFFF), tabular: true)),
                ),
              ]),
            ]),
          ),
          NegativeTop(
            overlap: 28,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                SCard(
                  radius: 18, padding: const EdgeInsets.all(18),
                  shadow: const [BoxShadow(color: Color(0x140F172A), blurRadius: 26, offset: Offset(0, 10))],
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                      Text('আজকের বিক্রি', style: ts(13, w: FontWeight.w600, color: SC.muted)),
                      if (done) const SBadge('দিন সম্পন্ন ✓', tone: BadgeTone.success) else if (orders > 0) const SBadge('অর্ডার চলমান', tone: BadgeTone.info),
                    ]),
                    const SizedBox(height: 10),
                    FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text(bnMoney(todayValue, smart: true), style: ts(36, w: FontWeight.w800, ls: -1.08, h: 1.08, tabular: true))),
                    const SizedBox(height: 12),
                    SProgress(pct.toDouble()),
                    const SizedBox(height: 7),
                    if (target > 0)
                      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                        Flexible(child: Text.rich(TextSpan(style: ts(12, color: SC.ink2, tabular: true), children: [
                          TextSpan(text: 'লক্ষ্য ${bnMoney(target, smart: true)} · '),
                          TextSpan(text: '${bn(pct)}%', style: ts(12, w: FontWeight.w700, color: SC.ink2)),
                          const TextSpan(text: ' হয়েছে'),
                        ]))),
                        if (remaining > 0) Text('আরও ${bnMoney(remaining, smart: true)} বাকি', style: ts(12, color: SC.muted, tabular: true)) else Text('লক্ষ্য অর্জিত', style: ts(12, w: FontWeight.w700, color: SC.ok)),
                      ])
                    else
                      Text('দৈনিক লক্ষ্য নির্ধারিত নেই', style: ts(12, color: SC.muted)),
                  ]),
                ),
                const SizedBox(height: 12),
                SBtn('নতুন অর্ডার', onTap: onNewOrder, height: 50, radius: 14, size: 15, block: true, shadow: true, icon: const Svg(Ic.plus, size: 18, color: Colors.white, stroke: 2.4)),
                if (done || orders > 0) ...[
                  const SizedBox(height: 12),
                  SDayStatus(
                    done: done,
                    Text(done
                        ? 'আজকের অর্ডার সম্পন্ন হয়েছে${int0(today['assigned']) > 0 ? ' এবং ডেলিভারি ট্রিপে দেওয়া হয়েছে।' : ' — ডেলিভারি ট্রিপের অপেক্ষায়।'}'
                        : 'আজকের অর্ডার খোলা আছে। কাজ শেষে অর্ডার পেজের "আজ" থেকে দিন সম্পন্ন করুন চাপুন।'),
                  ),
                ],
                const SizedBox(height: 12),
                IntrinsicHeight(child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Expanded(child: _Mini('আজকের অর্ডার', '${bn(orders)}টি', '${bn(int0(today['retailers']))}টি দোকান ভিজিট')),
                  const SizedBox(width: 10),
                  Expanded(child: _Mini('আজকের O/C', signedMoney(oc, smart: true), 'ব্যালেন্স ${signedMoney(num0(profile['oc_balance']), smart: true)}', valueColor: oc < 0 ? SC.dangerText : (oc > 0 ? SC.ok : SC.ink))),
                ])),
                const SizedBox(height: 10),
                IntrinsicHeight(child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Expanded(child: _Mini('এই মাসে বিক্রি', bnMoney(month['value'], smart: true), '${bn(int0(month['orders']))}টি অর্ডার${monthTarget > 0 ? ' · ${bn(monthPct)}%' : ''}')),
                  const SizedBox(width: 10),
                  Expanded(child: _Mini('অর্ডার হিস্ট্রি', 'সব দেখুন →', 'তারিখ অনুযায়ী মেমো ও O/C', valueColor: SC.cobalt, onTap: onHistory)),
                ])),
              ]),
            ),
          ),
        ]);
      },
    );
  }
}

class _Mini extends StatelessWidget {
  const _Mini(this.label, this.value, this.sub, {this.valueColor = SC.ink, this.onTap});
  final String label, value, sub;
  final Color valueColor;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => SCard(
        radius: 14, padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13), onTap: onTap,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: ts(12, color: SC.muted)),
          const SizedBox(height: 3),
          FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text(value, style: ts(18.5, w: FontWeight.w800, color: valueColor, h: 1.25, tabular: true))),
          const SizedBox(height: 3),
          Text(sub, maxLines: 2, overflow: TextOverflow.ellipsis, style: ts(12, color: SC.muted, tabular: true)),
        ]),
      );
}

/// /sr/profile ("আমি") — cobalt header with photo, date nav, order summary, product table, monthly performance.
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
      padding: EdgeInsets.zero,
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
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          SHero(
            top: 18, bottom: 22,
            child: Row(children: [
              GestureDetector(
                onTap: () => _pickPhoto(reload),
                child: Container(
                  width: 58, height: 58,
                  decoration: BoxDecoration(shape: BoxShape.circle, color: const Color(0x33FFFFFF), border: Border.all(color: const Color(0x73FFFFFF), width: 2)),
                  child: Stack(clipBehavior: Clip.none, children: [
                    Positioned.fill(
                      child: ClipOval(
                        child: photo != null
                            ? NetImage(photo, fallback: Center(child: Text('${p['initials']}', style: ts(21, w: FontWeight.w800, color: Colors.white))))
                            : Center(child: Text('${p['initials']}', style: ts(21, w: FontWeight.w800, color: Colors.white))),
                      ),
                    ),
                    Positioned(right: -2, bottom: -2, child: Container(padding: const EdgeInsets.all(2), decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle), child: const Text('📷', style: TextStyle(fontSize: 11, height: 1)))),
                  ]),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Wrap(spacing: 8, runSpacing: 2, crossAxisAlignment: WrapCrossAlignment.center, children: [
                    Text('${p['name']}', style: ts(17, w: FontWeight.w800, color: Colors.white)),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(color: const Color(0x38DCFCE7), borderRadius: BorderRadius.circular(99), border: Border.all(color: const Color(0x7386EFAC))),
                      child: Text(statusBnKey('${p['status']}'), style: ts(11, w: FontWeight.w700, color: SC.okBg)),
                    ),
                  ]),
                  const SizedBox(height: 2),
                  Text('SR · ${p['company']} · ${p['partner']}', style: ts(12, color: const Color(0xD9FFFFFF))),
                ]),
              ),
              const SizedBox(width: 8),
              HeroLogout(onTap: () => signOut(context)),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              SDateNav(
                date: date, today: today, onChange: (v) => setState(() => _date = v),
                sub: const Text('আজকের অর্ডার · ডেলিভারি হিসাব'),
              ),
              const SizedBox(height: 12),
              SCard(
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  const SSecTitle('অর্ডার সারাংশ'),
                  const SizedBox(height: 12),
                  Row(children: [
                    Expanded(child: _SumBox('${bn(int0(s['orders']))}টি', 'মেমো')),
                    const SizedBox(width: 10),
                    Expanded(child: _SumBox(bnMoney(s['value'], smart: true), 'মোট অর্ডার')),
                  ]),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
                    decoration: BoxDecoration(color: SC.subtle, borderRadius: BorderRadius.circular(12), border: Border.all(color: SC.border)),
                    child: Column(children: [
                      _OcRow('ওভার', '+${bnMoney(s['over_oc'])}', SC.ok),
                      const SizedBox(height: 7),
                      _OcRow('কমিশন', '−${bnMoney(num0(s['comm_oc']).abs())}', SC.dangerText),
                      const SizedBox(height: 9),
                      Container(
                        padding: const EdgeInsets.only(top: 8),
                        decoration: const BoxDecoration(border: Border(top: BorderSide(color: SC.borderStrong))),
                        child: _OcRow('নিট · আমার পাওনা', signedMoney(net), net < 0 ? SC.dangerText : SC.ok, bold: true),
                      ),
                    ]),
                  ),
                ]),
              ),
              const SizedBox(height: 12),
              SCard(
                padding: EdgeInsets.zero,
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Container(
                    padding: const EdgeInsets.fromLTRB(15, 14, 15, 10),
                    decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: SC.border))),
                    child: const SSecTitle('পণ্য · কতটা গেছে, কতটা নিয়েছে'),
                  ),
                  _prodHead(),
                  if (products.isEmpty)
                    Padding(padding: const EdgeInsets.all(18), child: Center(child: Text('এই তারিখে কোনো পণ্যের হিসাব নেই।', style: ts(12, color: SC.muted))))
                  else
                    for (var i = 0; i < products.length; i++) _prodRow(products[i], last: i == products.length - 1),
                ]),
              ),
              const SizedBox(height: 12),
              SCard(
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Expanded(child: SSecTitle('মাসিক পারফরম্যান্স · ${monthYearBn()}', sub: 'মাসিক লক্ষ্য অর্জন ও ডেলিভারি')),
                    if (monthTarget > 0) SBadge('${bn(monthPct)}% অর্জিত', tone: BadgeTone.info),
                  ]),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                    decoration: BoxDecoration(color: SC.subtle, borderRadius: BorderRadius.circular(10), border: Border.all(color: SC.border)),
                    child: Column(children: [
                      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                        Text('মাসিক অর্ডার মূল্য', style: ts(12, color: SC.muted)),
                        const SizedBox(width: 8),
                        Flexible(child: Text.rich(TextSpan(style: ts(14, w: FontWeight.w700, tabular: true), children: [
                          TextSpan(text: bnMoney(monthValue)),
                          if (monthTarget > 0) TextSpan(text: ' / ${bnMoney(monthTarget)}', style: ts(12, color: SC.muted)),
                        ]), textAlign: TextAlign.right)),
                      ]),
                      const SizedBox(height: 7),
                      SProgress(monthPct.toDouble()),
                    ]),
                  ),
                  const SizedBox(height: 12),
                  Row(children: [
                    Expanded(child: _Metric('মাসের অর্ডার', bn(int0(month['orders'])))),
                    const SizedBox(width: 9),
                    Expanded(child: _Metric('সক্রিয় দোকান', bn(int0(month['retailers'])))),
                  ]),
                  const SizedBox(height: 9),
                  Row(children: [
                    Expanded(child: _Metric('ডেলিভারি হার', int0(month['done']) > 0 ? '${bn(month['delivery_rate'])}%' : '—')),
                    const SizedBox(width: 9),
                    Expanded(child: _Metric('মোট O/C ব্যালেন্স', signedMoney(ocBal), color: ocBal < 0 ? SC.dangerText : SC.ok)),
                  ]),
                ]),
              ),
              const SizedBox(height: 12),
              SCard(
                padding: EdgeInsets.zero,
                child: Column(children: [
                  _Row('পাসওয়ার্ড পরিবর্তন', () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ChangePasswordPage()))),
                  _Row('ব্লুটুথ প্রিন্টার', () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const PrinterPage()))),
                  _Row('সিঙ্ক অবস্থা', () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const PendingPage()))),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    child: Row(children: [
                      Expanded(child: Text('অ্যাপ সংস্করণ', style: ts(13.5, color: SC.ink2))),
                      Text('${ApiClient.versionName} (${ApiClient.buildNumber})', style: ts(12.5, color: SC.muted, tabular: true)),
                    ]),
                  ),
                ]),
              ),
              const SizedBox(height: 12),
              SBtn('সাইন আউট', kind: SBtnKind.secondary, block: true, onTap: () => signOut(context)),
            ]),
          ),
        ]);
      },
    );
  }

  Widget _prodHead() {
    Widget h(String t, {int flex = 1, TextAlign a = TextAlign.center}) => Expanded(flex: flex, child: Text(t, textAlign: a, style: ts(11, w: FontWeight.w700, color: SC.muted)));
    return Container(
      color: SC.subtle,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: Row(children: [h('পণ্য', flex: 4, a: TextAlign.left), h('অর্ডার'), h('গেছে'), h('নিয়েছে'), h('ফেরত')]),
    );
  }

  Widget _prodRow(Map<String, dynamic> p, {required bool last}) {
    Widget c(num v, {Color? color}) => Expanded(child: Text(v > 0 ? bn(v.round()) : '—', textAlign: TextAlign.center, style: ts(12.5, color: color ?? SC.ink, tabular: true)));
    final tint = _tint(p['tint']);
    final image = ApiClient.asset(p['image']);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 9),
      decoration: BoxDecoration(border: last ? null : const Border(bottom: BorderSide(color: SC.border))),
      child: Row(children: [
        Expanded(
          flex: 4,
          child: Row(children: [
            Container(
              width: 30, height: 30,
              decoration: BoxDecoration(color: tint, borderRadius: BorderRadius.circular(8), border: Border.all(color: SC.border)),
              clipBehavior: Clip.antiAlias,
              child: image != null
                  ? Padding(padding: const EdgeInsets.all(3), child: NetImage(image, fit: BoxFit.contain))
                  : Center(child: Text('${p['code'] ?? ''}', style: ts(10, w: FontWeight.w800, h: 1))),
            ),
            const SizedBox(width: 8),
            Expanded(child: Text('${p['name']}', maxLines: 2, overflow: TextOverflow.ellipsis, style: ts(12.5, w: FontWeight.w600, h: 1.25))),
          ]),
        ),
        c(num0(p['ordered_pcs'])),
        c(num0(p['dispatched_pcs'])),
        c(num0(p['delivered_pcs']), color: SC.ok),
        c(num0(p['returned_pcs']), color: SC.dangerText),
      ]),
    );
  }
}

Color _tint(Object? v) {
  final s = '${v ?? ''}'.replaceFirst('#', '');
  if (s.length == 6) {
    final n = int.tryParse(s, radix: 16);
    if (n != null) return Color(0xFF000000 | n);
  }
  return SC.subtle;
}

class _SumBox extends StatelessWidget {
  const _SumBox(this.big, this.label);
  final String big, label;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
        decoration: BoxDecoration(color: SC.subtle, borderRadius: BorderRadius.circular(12), border: Border.all(color: SC.border)),
        child: Column(children: [
          FittedBox(fit: BoxFit.scaleDown, child: Text(big, style: ts(22, w: FontWeight.w800, h: 1.15, tabular: true))),
          const SizedBox(height: 2),
          Text(label, style: ts(12, color: SC.muted)),
        ]),
      );
}

class _OcRow extends StatelessWidget {
  const _OcRow(this.k, this.v, this.color, {this.bold = false});
  final String k, v;
  final Color color;
  final bool bold;
  @override
  Widget build(BuildContext context) => Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Flexible(child: Text(k, style: ts(bold ? 14 : 13, w: bold ? FontWeight.w700 : FontWeight.w400, color: bold ? SC.ink : SC.muted))),
        const SizedBox(width: 8),
        Text(v, style: ts(bold ? 14 : 13, w: FontWeight.w700, color: color, tabular: true)),
      ]);
}

class _Metric extends StatelessWidget {
  const _Metric(this.label, this.value, {this.color = SC.ink});
  final String label, value;
  final Color color;
  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        decoration: BoxDecoration(color: SC.subtle, borderRadius: BorderRadius.circular(10), border: Border.all(color: SC.border)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: ts(12, color: SC.muted)),
          const SizedBox(height: 2),
          FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text(value, style: ts(16.5, w: FontWeight.w800, color: color, tabular: true))),
        ]),
      );
}

class _Row extends StatelessWidget {
  const _Row(this.label, this.onTap);
  final String label;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: SC.border))),
          child: Row(children: [
            Expanded(child: Text(label, style: ts(13.5, w: FontWeight.w600))),
            const Svg(Ic.chevRight2, size: 18, color: SC.muted, stroke: 2.2),
          ]),
        ),
      );
}
