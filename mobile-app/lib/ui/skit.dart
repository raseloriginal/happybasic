import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/format.dart';
import 'pwa_kit.dart';

/// SR / DSR panel design tokens — copied from public/assets/sr/css/sr.css (and dsr.css, which shares them).
class SC {
  static const outer = Color(0xFFE7ECF3);
  static const bg = Color(0xFFF3F6FB);
  static const surface = Colors.white;
  static const subtle = Color(0xFFF8FAFC);
  static const border = Color(0xFFE2E8F0);
  static const borderStrong = Color(0xFFCBD5E1);
  static const ink = Color(0xFF0F172A);
  static const ink2 = Color(0xFF475569);
  static const muted = Color(0xFF64748B);
  static const cobalt = Color(0xFF1A4FD8);
  static const cobaltHover = Color(0xFF1642B8);
  static const cobaltSoft = Color(0xFFEFF4FF);
  static const ok = Color(0xFF15803D);
  static const okBg = Color(0xFFDCFCE7);
  static const okBorder = Color(0xFF86EFAC);
  static const warn = Color(0xFFD97706);
  static const warnBg = Color(0xFFFEF3C7);
  static const warnText = Color(0xFFB45309);
  static const warnBorder = Color(0xFFFDE68A);
  static const danger = Color(0xFFDC2626);
  static const dangerBg = Color(0xFFFEF2F2);
  static const dangerText = Color(0xFFB91C1C);
  static const dangerBorder = Color(0xFFFECACA);
  static const infoBorder = Color(0xFFBFDBFE);
  static const neutralBg = Color(0xFFF1F5F9);
  static const neutralText = Color(0xFF334155);
  static const tabBg = Color(0xFFEEF2F7);
}

/// `.card`: white, 1px border, radius 16, very soft shadow.
class SCard extends StatelessWidget {
  const SCard({super.key, required this.child, this.padding = const EdgeInsets.all(16), this.margin = EdgeInsets.zero, this.radius = 16, this.onTap, this.shadow, this.color = Colors.white, this.borderColor = SC.border});
  final Widget child;
  final EdgeInsets padding, margin;
  final double radius;
  final VoidCallback? onTap;
  final List<BoxShadow>? shadow;
  final Color color, borderColor;
  @override
  Widget build(BuildContext context) {
    Widget inner = Padding(padding: padding, child: child);
    if (onTap != null) inner = Material(color: Colors.transparent, child: InkWell(borderRadius: BorderRadius.circular(radius), onTap: onTap, child: inner));
    return Container(
      margin: margin,
      decoration: BoxDecoration(
        color: color, borderRadius: BorderRadius.circular(radius), border: Border.all(color: borderColor),
        boxShadow: shadow ?? const [BoxShadow(color: Color(0x080F172A), blurRadius: 10, offset: Offset(0, 2))],
      ),
      clipBehavior: onTap != null ? Clip.antiAlias : Clip.none,
      child: inner,
    );
  }
}

enum BadgeTone { success, info, cobalt, warning, danger, neutral }

/// `.badge`: pill with border.
class SBadge extends StatelessWidget {
  const SBadge(this.text, {super.key, this.tone = BadgeTone.neutral});
  final String text;
  final BadgeTone tone;
  @override
  Widget build(BuildContext context) {
    final (bg, fg, bd) = switch (tone) {
      BadgeTone.success => (SC.okBg, SC.ok, SC.okBorder),
      BadgeTone.info => (SC.cobaltSoft, SC.cobalt, SC.infoBorder),
      BadgeTone.cobalt => (SC.cobaltSoft, SC.cobalt, SC.infoBorder),
      BadgeTone.warning => (SC.warnBg, SC.warnText, SC.warnBorder),
      BadgeTone.danger => (SC.dangerBg, SC.dangerText, SC.dangerBorder),
      BadgeTone.neutral => (SC.neutralBg, SC.neutralText, SC.border),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(99), border: Border.all(color: bd)),
      child: Text(text, style: ts(11, w: FontWeight.w600, color: fg, h: 1.45)),
    );
  }
}

/// Status key → badge tone (sr.js `badgeClass`).
BadgeTone toneOfStatus(String? key) => switch (key) {
      'delivered' => BadgeTone.success,
      'assigned' || 'dispatched' => BadgeTone.info,
      'partial' || 'due' || 'pending' => BadgeTone.warning,
      'cancelled' => BadgeTone.danger,
      _ => BadgeTone.neutral,
    };

enum SBtnKind { cobalt, navy, secondary, ghost, dangerGhost }

/// `.btn` (radius 10, 13.5px / 650).
class SBtn extends StatelessWidget {
  const SBtn(this.label, {super.key, this.onTap, this.kind = SBtnKind.cobalt, this.icon, this.height, this.radius = 10, this.size = 13.5, this.block = false, this.shadow = false});
  final String label;
  final VoidCallback? onTap;
  final SBtnKind kind;
  final Widget? icon;
  final double? height;
  final double radius, size;
  final bool block, shadow;
  @override
  Widget build(BuildContext context) {
    final (bg, fg, bd) = switch (kind) {
      SBtnKind.cobalt => (SC.cobalt, Colors.white, Colors.transparent),
      SBtnKind.navy => (SC.ink, Colors.white, Colors.transparent),
      SBtnKind.secondary => (SC.surface, SC.ink, SC.borderStrong),
      SBtnKind.ghost => (Colors.transparent, SC.ink2, SC.border),
      SBtnKind.dangerGhost => (Colors.transparent, SC.dangerText, Colors.transparent),
    };
    final disabled = onTap == null;
    final child = Row(mainAxisSize: block ? MainAxisSize.max : MainAxisSize.min, mainAxisAlignment: MainAxisAlignment.center, children: [
      if (icon != null) ...[icon!, const SizedBox(width: 6)],
      Flexible(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: ts(size, w: FontWeight.w600, color: fg, h: 1.3))),
    ]);
    return Opacity(
      opacity: disabled ? 0.48 : 1,
      child: Material(
        color: bg,
        borderRadius: BorderRadius.circular(radius),
        child: InkWell(
          borderRadius: BorderRadius.circular(radius),
          onTap: onTap,
          child: Container(
            height: height, padding: EdgeInsets.symmetric(horizontal: 14, vertical: height == null ? 9 : 0),
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(radius), border: Border.all(color: bd), boxShadow: shadow ? const [BoxShadow(color: Color(0x471A4FD8), blurRadius: 20, offset: Offset(0, 8))] : null),
            child: Center(widthFactor: block ? null : 1, child: child),
          ),
        ),
      ),
    );
  }
}

/// `.section-title`
class SSecTitle extends StatelessWidget {
  const SSecTitle(this.text, {super.key, this.sub});
  final String text;
  final String? sub;
  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(text, style: ts(15, w: FontWeight.w700, ls: -0.15, h: 1.35)),
        if (sub != null) Text(sub!, style: ts(12, color: SC.muted, h: 1.4)),
      ]);
}

/// `.sr-dash-hero`: cobalt gradient header band (dashboard / profile).
class SHero extends StatelessWidget {
  const SHero({super.key, required this.child, this.bottom = 46, this.top = 16});
  final Widget child;
  final double bottom, top;
  @override
  Widget build(BuildContext context) {
    final pad = MediaQuery.of(context).padding.top;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light.copyWith(statusBarColor: Colors.transparent),
      child: Container(
        padding: EdgeInsets.fromLTRB(16, top + pad, 16, bottom),
        decoration: const BoxDecoration(
          gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF1B44C2), Color(0xFF1A4FD8), Color(0xFF2563EB)], stops: [0, 0.6, 1]),
          borderRadius: BorderRadius.vertical(bottom: Radius.circular(24)),
        ),
        child: child,
      ),
    );
  }
}

/// `.hero-logout-btn`
class HeroLogout extends StatelessWidget {
  const HeroLogout({super.key, required this.onTap});
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          width: 32, height: 32,
          decoration: BoxDecoration(shape: BoxShape.circle, color: const Color(0x1FFFFFFF), border: Border.all(color: const Color(0x3DFFFFFF))),
          child: const Center(child: Svg(Ic.logout, size: 16, color: Colors.white)),
        ),
      );
}

/// Bottom navigation (`.bottom-nav`): 4 items, the second is the round "add" action.
class SBottomNav extends StatelessWidget {
  const SBottomNav({super.key, required this.index, required this.onTap});
  final int index;
  final ValueChanged<int> onTap;

  static const _items = [
    (label: 'আজ', icon: Ic.home),
    (label: 'অর্ডার', icon: Ic.plus),
    (label: 'হিস্ট্রি', icon: Ic.doc),
    (label: 'আমি', icon: Ic.user),
  ];

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).padding.bottom;
    return Container(
      height: 66 + bottom,
      padding: EdgeInsets.fromLTRB(6, 4, 6, 4 + bottom),
      decoration: const BoxDecoration(color: SC.surface, border: Border(top: BorderSide(color: SC.border))),
      child: Row(children: [
        for (var i = 0; i < _items.length; i++)
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => onTap(i),
              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                _icon(i),
                const SizedBox(height: 2),
                Text(_items[i].label, style: ts(11, w: index == i ? FontWeight.w700 : FontWeight.w600, color: index == i ? SC.cobalt : SC.muted, h: 1.3)),
              ]),
            ),
          ),
      ]),
    );
  }

  Widget _icon(int i) {
    final active = index == i;
    final center = i == 1;
    if (center) {
      return Container(
        width: 34, height: 34,
        decoration: BoxDecoration(shape: BoxShape.circle, color: active ? SC.cobalt : SC.tabBg, boxShadow: active ? const [BoxShadow(color: Color(0x521A4FD8), blurRadius: 12, offset: Offset(0, 4))] : null),
        child: Center(child: Svg(_items[i].icon, size: 20, color: active ? Colors.white : SC.ink)),
      );
    }
    return Container(
      width: 42, height: 30,
      decoration: BoxDecoration(color: active ? SC.cobaltSoft : Colors.transparent, borderRadius: BorderRadius.circular(10)),
      child: Center(child: Svg(_items[i].icon, size: 20, color: active ? SC.cobalt : SC.muted)),
    );
  }
}

/// `.date-nav-bar.date-nav-rich`: < date + sub-line > in a card.
class SDateNav extends StatelessWidget {
  const SDateNav({super.key, required this.date, required this.sub, required this.onChange, this.today});
  final String date;
  final Widget sub;
  final ValueChanged<String> onChange;
  final String? today;
  @override
  Widget build(BuildContext context) {
    final t = today ?? todayYmd();
    final isToday = date.compareTo(t) >= 0;
    return SCard(
      radius: 14,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      child: Row(children: [
        _round(Ic.chevLeft, () => onChange(addDays(date, -1)), true),
        Expanded(
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () async {
              final d = await showDatePicker(context: context, initialDate: DateTime.parse(date), firstDate: DateTime(2024), lastDate: DateTime.parse(t));
              if (d != null) onChange(ymd(d));
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Column(children: [
                Text('${date == t ? 'আজ, ' : ''}${dateBn(date)}', style: ts(13.5, w: FontWeight.w700, tabular: true)),
                DefaultTextStyle(style: ts(11.5, w: FontWeight.w600, color: SC.muted, tabular: true), textAlign: TextAlign.center, child: sub),
              ]),
            ),
          ),
        ),
        _round(Ic.chevRight2, isToday ? null : () => onChange(addDays(date, 1)), !isToday),
      ]),
    );
  }

  Widget _round(String icon, VoidCallback? onTap, bool enabled) => GestureDetector(
        onTap: onTap,
        child: Opacity(
          opacity: enabled ? 1 : 0.4,
          child: Container(
            width: 34, height: 34,
            decoration: BoxDecoration(shape: BoxShape.circle, color: SC.surface, border: Border.all(color: SC.border)),
            child: Center(child: Svg(icon, size: 18, color: SC.ink2, stroke: 2.4)),
          ),
        ),
      );
}

/// `.day-status` banner.
class SDayStatus extends StatelessWidget {
  const SDayStatus(this.text, {super.key, this.done = false});
  final Widget text;
  final bool done;
  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(color: done ? SC.okBg : SC.warnBg, borderRadius: BorderRadius.circular(12), border: Border.all(color: done ? SC.okBorder : SC.warnBorder)),
        child: DefaultTextStyle(style: ts(12.5, color: done ? SC.ok : SC.warnText, h: 1.45), child: text),
      );
}

/// `.empty-state` card.
class SEmpty extends StatelessWidget {
  const SEmpty(this.text, {super.key});
  final String text;
  @override
  Widget build(BuildContext context) => SCard(padding: const EdgeInsets.fromLTRB(16, 30, 16, 30), child: SizedBox(width: double.infinity, child: Text(text, textAlign: TextAlign.center, style: ts(14, color: SC.muted))));
}

/// Page header used by history / profile style pages (`.sr-plain-head`).
class SPlainHead extends StatelessWidget {
  const SPlainHead(this.title, {super.key, this.sub, this.trailing});
  final String title;
  final String? sub;
  final Widget? trailing;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(2, 2, 2, 0),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: ts(22, w: FontWeight.w800, ls: -0.44, h: 1.25)),
              if (sub != null) Text(sub!, style: ts(12.5, color: SC.muted, h: 1.4)),
            ]),
          ),
          if (trailing != null) trailing!,
        ]),
      );
}

/// Header for pushed sub-pages: white bar, round back button, title/subtitle (`.modal-head`).
class SSubHead extends StatelessWidget {
  const SSubHead({super.key, required this.title, this.sub, this.trailing, this.onBack});
  final String title;
  final String? sub;
  final Widget? trailing;
  final VoidCallback? onBack;
  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.of(context).padding.top;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark.copyWith(statusBarColor: Colors.transparent),
      child: Container(
        padding: EdgeInsets.fromLTRB(14, 12 + top, 14, 12),
        decoration: const BoxDecoration(color: SC.surface, border: Border(bottom: BorderSide(color: SC.border))),
        child: Row(children: [
          GestureDetector(
            onTap: onBack ?? () => Navigator.maybePop(context),
            child: Container(
              width: 34, height: 34,
              decoration: BoxDecoration(shape: BoxShape.circle, color: SC.surface, border: Border.all(color: SC.border)),
              child: const Center(child: Svg(Ic.chevLeft, size: 18, color: SC.ink2, stroke: 2.2)),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: ts(16, w: FontWeight.w800, h: 1.3)),
              if (sub != null) Text(sub!, maxLines: 1, overflow: TextOverflow.ellipsis, style: ts(12, color: SC.muted, h: 1.4, tabular: true)),
            ]),
          ),
          if (trailing != null) trailing!,
        ]),
      ),
    );
  }
}

/// Scaffold body that puts a page in the 430px frame with the SR/DSR background.
class SPage extends StatelessWidget {
  const SPage({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => Scaffold(backgroundColor: SC.outer, body: Frame(child: ColoredBox(color: SC.bg, child: child)));
}
