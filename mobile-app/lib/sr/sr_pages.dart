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
import '../ui/motion.dart';
import 'sr_notifications.dart';
import 'sr_report.dart';

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
              trailing: GlassBtn(
                icon: Ic.bell, label: 'নোটিফিকেশন',
                badge: int0(d['notif_unread']) > 0 ? (int0(d['notif_unread']) > 9 ? '৯+' : bn(int0(d['notif_unread']))) : null,
                onTap: () async {
                  await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SrNotificationsPage()));
                  reload();
                },
              ),
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
                HStat('দেয়নি', bn(((d['no_order'] as List?) ?? const []).length), color: HC.ink2, labelOnTop: false),
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

  static const _months = ['জানুয়ারি', 'ফেব্রুয়ারি', 'মার্চ', 'এপ্রিল', 'মে', 'জুন', 'জুলাই', 'আগস্ট', 'সেপ্টেম্বর', 'অক্টোবর', 'নভেম্বর', 'ডিসেম্বর'];

  /// SR7 · আমি: photo and ID, this month's target, the day report, account links, logout.
  @override
  Widget build(BuildContext context) {
    context.watch<AuthState>();
    return AsyncBody(
      sky: true,
      load: () => loadCached('sr_profile_me', () => ApiClient.get('/sr/profile')),
      builder: (context, d, reload) {
        final p = _m(d['profile']);
        final photo = ApiClient.asset(p['photo']);
        final month = _m(d['month']);
        final sold = num0(month['value']);
        final goal = num0(d['month_goal']);
        final pct = goal > 0 ? (sold / goal * 100).round() : 0;
        final now = DateTime.now();
        final daysLeft = DateTime(now.year, now.month + 1, 0).day - now.day;
        final name = '${p['name'] ?? ''}';
        Widget link(String label, VoidCallback onTap, {bool first = false, Color color = HC.ink}) => Pressable(
              scale: .99,
              child: InkWell(
                onTap: onTap,
                child: Container(
                  constraints: const BoxConstraints(minHeight: 50),
                  decoration: BoxDecoration(border: first ? null : const Border(top: BorderSide(color: HC.line))),
                  child: Row(children: [
                    Expanded(child: Text(label, style: hs(15, w: w7, color: color))),
                    if (color == HC.ink) Text('›', style: hs(20, color: HC.muted)),
                  ]),
                ),
              ),
            );
        return SkyBox(
          height: 250,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Column(children: [
              Semantics(
                button: true, label: 'ছবি পরিবর্তন করুন',
                child: GestureDetector(
                  onTap: () => _pickPhoto(reload),
                  child: Container(
                    width: 72, height: 72,
                    decoration: const BoxDecoration(shape: BoxShape.circle, boxShadow: [BoxShadow(color: Color(0x38FFFFFF), spreadRadius: 5)]),
                    child: LetterAvatar(name, size: 72, fontSize: 28, image: photo == null ? null : NetImage(photo)),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Text(name, textAlign: TextAlign.center, style: hs(20, w: w7, color: Colors.white)),
              Text('SR · ${p['company'] ?? ''} · ${p['partner'] ?? ''} · ID ${p['code'] ?? ''}', textAlign: TextAlign.center,
                  maxLines: 2, overflow: TextOverflow.ellipsis, style: hs(12, color: HC.onSky)),
            ]),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24),
                  boxShadow: const [BoxShadow(color: Color(0x240A1640), blurRadius: 40, offset: Offset(0, 18))]),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Row(children: [
                  Expanded(child: Text('${_months[now.month - 1]}ের লক্ষ্য', style: hs(14, w: w7))),
                  if (goal > 0)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                      decoration: BoxDecoration(color: HC.soft, borderRadius: BorderRadius.circular(999)),
                      child: Text('${bn(pct)}%', style: hs(12, w: w7, color: HC.blue)),
                    ),
                ]),
                const SizedBox(height: 12),
                Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Expanded(child: FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text(tk(sold), style: hs(26, w: w8, num: true, h: 1.1)))),
                  if (goal > 0) Text('/ ${tk(goal)}', style: hs(13, color: HC.muted, num: true)),
                ]),
                const SizedBox(height: 12),
                ClipRRect(
                  borderRadius: BorderRadius.circular(5),
                  child: Container(
                    height: 10, color: HC.chip,
                    alignment: Alignment.centerLeft,
                    child: TweenAnimationBuilder<double>(
                      tween: Tween(begin: 0, end: goal > 0 ? (sold / goal).clamp(0, 1).toDouble() : 0),
                      duration: const Duration(milliseconds: 900), curve: kEase,
                      builder: (_, v, __) => FractionallySizedBox(
                        widthFactor: v,
                        child: Container(decoration: const BoxDecoration(gradient: LinearGradient(colors: [HC.sky, Color(0xFF5B8CFF)]))),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  goal <= 0
                      ? 'লক্ষ্য এখনো ঠিক করা হয়নি'
                      : (sold >= goal ? 'লক্ষ্য পূরণ হয়েছে ✓ · ${bn(daysLeft)} দিন আছে' : 'আর ${tk(goal - sold)} বাকি · ${bn(daysLeft)} দিন আছে'),
                  style: hs(12, color: HC.muted, num: true),
                ),
              ]),
            ),
            gap12,
            HBtn('দিনের রিপোর্ট তৈরি করুন', icon: Ic.doc, onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SrReportPage()))),
            gap12,
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(22), border: Border.all(color: HC.line)),
              child: Column(children: [
                link('পাসওয়ার্ড পরিবর্তন', () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ChangePasswordPage())), first: true),
                link('ব্লুটুথ প্রিন্টার', () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const PrinterPage()))),
                link('সিঙ্ক অবস্থা', () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const PendingPage()))),
                Container(
                  constraints: const BoxConstraints(minHeight: 46),
                  decoration: const BoxDecoration(border: Border(top: BorderSide(color: HC.line))),
                  child: Row(children: [
                    Expanded(child: Text('অ্যাপ সংস্করণ', style: hs(13, color: HC.muted))),
                    Text('${ApiClient.versionName} (${ApiClient.buildNumber})', style: hs(13, color: HC.muted, num: true)),
                  ]),
                ),
                link('লগআউট', () => signOut(context), color: HC.red),
              ]),
            ),
            const SizedBox(height: 12),
          ]),
        );
      },
    );
  }
}
