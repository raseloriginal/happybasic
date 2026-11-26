import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/format.dart';
import 'pwa_kit.dart';

/// DSR panel design tokens — copied from public/assets/dsr/css/dsr.css.
class DC {
  static const outer = Color(0xFFE9EDF2);
  static const bg = Color(0xFFF7F8FA);
  static const surface = Colors.white;
  static const subtle = Color(0xFFF9FAFB);
  static const border = Color(0xFFE4E7EC);
  static const borderStrong = Color(0xFFD0D5DD);
  static const ink = Color(0xFF0F172A);
  static const ink2 = Color(0xFF475467);
  static const muted = Color(0xFF667085);
  static const accent = Color(0xFF111827);
  static const link = Color(0xFF2563EB);
  static const ok = Color(0xFF12B76A);
  static const okBg = Color(0xFFECFDF3);
  static const okText = Color(0xFF027A48);
  static const okBorder = Color(0xFFABEFC6);
  static const infoBg = Color(0xFFEFF6FF);
  static const infoText = Color(0xFF1D4ED8);
  static const infoBorder = Color(0xFFBFDBFE);
  static const warn = Color(0xFFF79009);
  static const warnBg = Color(0xFFFFFAEB);
  static const warnText = Color(0xFFB54708);
  static const warnBorder = Color(0xFFFEDF89);
  static const danger = Color(0xFFD92D20);
  static const dangerBg = Color(0xFFFEF3F2);
  static const dangerText = Color(0xFFB42318);
  static const dangerBorder = Color(0xFFFECDCA);
  static const track = Color(0xFFEEF2F6);
}

/// `.card`: white, 1px border, radius 12, padding 15.
class DCard extends StatelessWidget {
  const DCard({super.key, required this.child, this.padding = const EdgeInsets.all(15), this.margin = EdgeInsets.zero, this.onTap});
  final Widget child;
  final EdgeInsets padding, margin;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) {
    Widget inner = Padding(padding: padding, child: child);
    if (onTap != null) inner = Material(color: Colors.transparent, child: InkWell(borderRadius: BorderRadius.circular(12), onTap: onTap, child: inner));
    return Container(
      margin: margin,
      decoration: BoxDecoration(color: DC.surface, borderRadius: BorderRadius.circular(12), border: Border.all(color: DC.border)),
      clipBehavior: onTap != null ? Clip.antiAlias : Clip.none,
      child: inner,
    );
  }
}

enum DTone { success, info, warning, danger, neutral }

class DBadge extends StatelessWidget {
  const DBadge(this.text, {super.key, this.tone = DTone.neutral});
  final String text;
  final DTone tone;
  @override
  Widget build(BuildContext context) {
    final (bg, fg, bd) = switch (tone) {
      DTone.success => (DC.okBg, DC.okText, DC.okBorder),
      DTone.info => (DC.infoBg, DC.infoText, DC.infoBorder),
      DTone.warning => (DC.warnBg, DC.warnText, DC.warnBorder),
      DTone.danger => (DC.dangerBg, DC.dangerText, DC.dangerBorder),
      DTone.neutral => (DC.subtle, DC.ink2, DC.border),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(99), border: Border.all(color: bd)),
      child: Text(text, style: ts(11, w: FontWeight.w600, color: fg, h: 1.45)),
    );
  }
}

enum DBtnKind { primary, secondary, ghost, danger, dangerOutline }

/// `.btn` (radius 8, 13px / 600, black primary).
class DBtn extends StatelessWidget {
  const DBtn(this.label, {super.key, this.onTap, this.kind = DBtnKind.primary, this.icon, this.small = false, this.block = false, this.height});
  final String label;
  final VoidCallback? onTap;
  final DBtnKind kind;
  final Widget? icon;
  final bool small, block;
  final double? height;
  @override
  Widget build(BuildContext context) {
    final (bg, fg, bd) = switch (kind) {
      DBtnKind.primary => (DC.accent, Colors.white, DC.accent),
      DBtnKind.secondary => (DC.surface, DC.ink, DC.borderStrong),
      DBtnKind.ghost => (Colors.transparent, DC.ink2, DC.border),
      DBtnKind.danger => (DC.danger, Colors.white, DC.danger),
      DBtnKind.dangerOutline => (DC.dangerBg, DC.dangerText, DC.dangerBorder),
    };
    return Opacity(
      opacity: onTap == null ? 0.55 : 1,
      child: Material(
        color: bg, borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8), onTap: onTap,
          child: Container(
            height: height, padding: EdgeInsets.symmetric(horizontal: small ? 11 : 14, vertical: height != null ? 0 : (small ? 6 : 8)),
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(8), border: Border.all(color: bd)),
            child: Row(mainAxisSize: block ? MainAxisSize.max : MainAxisSize.min, mainAxisAlignment: MainAxisAlignment.center, children: [
              if (icon != null) ...[icon!, const SizedBox(width: 6)],
              Flexible(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: ts(small ? 12.5 : 13, w: FontWeight.w600, color: fg, h: 1.3))),
            ]),
          ),
        ),
      ),
    );
  }
}

/// `.section-title`
class DSecTitle extends StatelessWidget {
  const DSecTitle(this.text, {super.key, this.sub});
  final String text;
  final String? sub;
  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(text, style: ts(15, w: FontWeight.w600, ls: -0.15, h: 1.35)),
        if (sub != null) Text(sub!, style: ts(12, color: DC.muted, h: 1.4)),
      ]);
}

/// `.topbar`: 54px white bar with the logo, page title, optional actions and sign-out.
class DTopBar extends StatelessWidget {
  const DTopBar({super.key, required this.title, this.actions = const []});
  final String title;
  final List<Widget> actions;
  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.of(context).padding.top;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark.copyWith(statusBarColor: Colors.transparent),
      child: Container(
        height: 54 + top, padding: EdgeInsets.fromLTRB(14, top, 14, 0),
        decoration: const BoxDecoration(color: DC.surface, border: Border(bottom: BorderSide(color: DC.border))),
        child: Row(children: [
          Container(
            width: 28, height: 28,
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(7), border: Border.all(color: DC.border)),
            clipBehavior: Clip.antiAlias,
            child: Image.asset('assets/images/logo.jpg', fit: BoxFit.cover, errorBuilder: (_, __, ___) => const SizedBox()),
          ),
          const SizedBox(width: 10),
          Expanded(child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: ts(16, w: FontWeight.w600, ls: -0.16, h: 1.3))),
          ...actions,
        ]),
      ),
    );
  }
}

/// `.icon-btn` (32px, radius 8)
class DIconBtn extends StatelessWidget {
  const DIconBtn({super.key, required this.icon, required this.onTap, this.tooltip});
  final String icon;
  final VoidCallback onTap;
  final String? tooltip;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(left: 8),
        child: Tooltip(
          message: tooltip ?? '',
          child: GestureDetector(
            onTap: onTap,
            child: Container(
              width: 32, height: 32,
              decoration: BoxDecoration(color: DC.surface, borderRadius: BorderRadius.circular(8), border: Border.all(color: DC.border)),
              child: Center(child: Svg(icon, size: 17, color: DC.ink2)),
            ),
          ),
        ),
      );
}

/// Bottom navigation (5 items, icon + label).
class DBottomNav extends StatelessWidget {
  const DBottomNav({super.key, required this.index, required this.onTap});
  final int index;
  final ValueChanged<int> onTap;

  static const items = [
    (label: 'ড্যাশবোর্ড', icon: '<rect x="3" y="3" width="7" height="9" rx="1.5"/><rect x="14" y="3" width="7" height="5" rx="1.5"/><rect x="14" y="12" width="7" height="9" rx="1.5"/><rect x="3" y="16" width="7" height="5" rx="1.5"/>'),
    (label: 'ডেলিভারি', icon: '<path d="M10 17h4V5H2v12h3"/><path d="M20 17h2v-3.34a4 4 0 0 0-1.17-2.83L19 9h-5"/><circle cx="7.5" cy="17.5" r="2.5"/><circle cx="17.5" cy="17.5" r="2.5"/>'),
    (label: 'ভ্যান স্টক', icon: '<path d="M21 8a2 2 0 0 0-1-1.73l-7-4a2 2 0 0 0-2 0l-7 4A2 2 0 0 0 3 8v8a2 2 0 0 0 1 1.73l7 4a2 2 0 0 0 2 0l7-4A2 2 0 0 0 21 16Z"/><path d="m3.3 7 8.7 5 8.7-5"/><path d="M12 22V12"/>'),
    (label: 'সেটেলমেন্ট', icon: '<rect x="2" y="5" width="20" height="14" rx="2"/><path d="M2 10h20"/><path d="M6 15h4"/>'),
    (label: 'খরচ', icon: '<path d="M4 2v20l2-1 2 1 2-1 2 1 2-1 2 1 2-1 2 1V2l-2 1-2-1-2 1-2-1-2 1-2-1-2 1Z"/><path d="M8 7h8"/><path d="M8 11h8"/><path d="M8 15h5"/>'),
  ];

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).padding.bottom;
    return Container(
      height: 60 + bottom, padding: EdgeInsets.only(bottom: bottom),
      decoration: const BoxDecoration(color: DC.surface, border: Border(top: BorderSide(color: DC.border))),
      child: Row(children: [
        for (var i = 0; i < items.length; i++)
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => onTap(i),
              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                Svg(items[i].icon, size: 19, color: index == i ? DC.accent : DC.muted, stroke: index == i ? 2.25 : 1.8),
                const SizedBox(height: 3),
                Text(items[i].label, maxLines: 1, style: ts(10.5, w: index == i ? FontWeight.w600 : FontWeight.w500, color: index == i ? DC.accent : DC.muted, h: 1.3)),
              ]),
            ),
          ),
      ]),
    );
  }
}

/// `.page-date-nav`: pill with ‹ date › and an "আজ" shortcut.
class DDateNav extends StatelessWidget {
  const DDateNav({super.key, required this.date, required this.onChange, this.subText, this.shadow = true});
  final String date;
  final ValueChanged<String> onChange;
  final String? subText;
  final bool shadow;
  @override
  Widget build(BuildContext context) {
    final today = todayYmd();
    Widget arrow(String t, VoidCallback onTap) => GestureDetector(
          onTap: onTap, behavior: HitTestBehavior.opaque,
          child: SizedBox(width: 32, height: 34, child: Center(child: Text(t, style: ts(18, w: FontWeight.w700, h: 1)))),
        );
    return Container(
      height: shadow ? 42 : 40, padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(color: DC.surface, borderRadius: BorderRadius.circular(99), border: Border.all(color: DC.border), boxShadow: const [BoxShadow(color: Color(0x140F172A), blurRadius: 12, offset: Offset(0, 4))]),
      child: Row(children: [
        arrow('‹', () => onChange(addDays(date, -1))),
        Expanded(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () async {
              final d = await showDatePicker(context: context, initialDate: DateTime.parse(date), firstDate: DateTime(2024), lastDate: DateTime.now().add(const Duration(days: 1)));
              if (d != null) onChange(ymd(d));
            },
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              const Svg('<rect x="3" y="4" width="18" height="18" rx="2"/><path d="M16 2v4M8 2v4M3 10h18"/>', size: 14, color: Color(0xFF1D4ED8)),
              const SizedBox(width: 7),
              Flexible(
                child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(dateBn(date), maxLines: 1, overflow: TextOverflow.ellipsis, style: ts(12, w: FontWeight.w800, h: 1.15, tabular: true)),
                  if (subText != null || date == today) Text(subText ?? 'আজ', maxLines: 1, overflow: TextOverflow.ellipsis, style: ts(10, w: FontWeight.w600, color: DC.muted, h: 1.15, tabular: true)),
                ]),
              ),
            ]),
          ),
        ),
        arrow('›', () => onChange(addDays(date, 1))),
        if (date != today)
          GestureDetector(
            onTap: () => onChange(today),
            child: Container(
              height: 34, padding: const EdgeInsets.symmetric(horizontal: 12), alignment: Alignment.center,
              decoration: BoxDecoration(color: const Color(0xFF1D4ED8), borderRadius: BorderRadius.circular(99)),
              child: Text('আজ', style: ts(12, w: FontWeight.w700, color: Colors.white, h: 1.2)),
            ),
          ),
      ]),
    );
  }
}

/// `.trip-state-banner`
class DBanner extends StatelessWidget {
  const DBanner(this.text, {super.key, this.returned = false, this.muted = false});
  final String text;
  final bool returned, muted;
  @override
  Widget build(BuildContext context) {
    final (bg, fg, bd) = returned ? (DC.dangerBg, DC.dangerText, DC.dangerBorder) : (muted ? (const Color(0xF2FFFFFF), DC.ink2, DC.borderStrong) : (DC.warnBg, DC.warnText, DC.warnBorder));
    return Container(
      width: double.infinity, padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(8), border: Border.all(color: bd)),
      child: Text(text, style: ts(12.5, w: FontWeight.w600, color: fg, h: 1.4)),
    );
  }
}

/// `.progress-track` / `.progress-fill`
class DProgress extends StatelessWidget {
  const DProgress(this.pct, {super.key, this.complete = false});
  final double pct;
  final bool complete;
  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: BorderRadius.circular(99),
        child: Container(height: 10, color: DC.track, alignment: Alignment.centerLeft, child: FractionallySizedBox(widthFactor: (pct / 100).clamp(0, 1), child: Container(color: complete ? DC.ok : DC.accent))),
      );
}

/// Page shell for DSR sub-pages that are pushed on top of the tabs: top bar with a back arrow + body on the DSR background.
class DPage extends StatelessWidget {
  const DPage({super.key, required this.title, required this.child, this.actions = const []});
  final String title;
  final Widget child;
  final List<Widget> actions;
  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.of(context).padding.top;
    return Scaffold(
      backgroundColor: DC.outer,
      body: Frame(
        child: ColoredBox(
          color: DC.bg,
          child: Column(children: [
            Container(
              height: 54 + top, padding: EdgeInsets.fromLTRB(8, top, 14, 0),
              decoration: const BoxDecoration(color: DC.surface, border: Border(bottom: BorderSide(color: DC.border))),
              child: Row(children: [
                IconButton(onPressed: () => Navigator.maybePop(context), icon: const Svg('<path d="m15 18-6-6 6-6"/>', size: 22, color: DC.ink, stroke: 2.2)),
                Expanded(child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: ts(16, w: FontWeight.w600, ls: -0.16))),
                ...actions,
              ]),
            ),
            Expanded(child: child),
          ]),
        ),
      ),
    );
  }
}
