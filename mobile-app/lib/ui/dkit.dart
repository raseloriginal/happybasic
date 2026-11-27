import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/format.dart';
import 'hkit.dart';
import 'pwa_kit.dart';

/// DSR panel tokens — mapped onto the shared design (hkit) palette.
class DC {
  static const outer = HC.outer;
  static const bg = HC.bg;
  static const surface = Colors.white;
  static const subtle = HC.bg;
  static const border = HC.line;
  static const borderStrong = HC.line2;
  static const ink = HC.ink;
  static const ink2 = HC.ink2;
  static const muted = HC.muted;
  static const accent = HC.ink;
  static const link = HC.blue;
  static const ok = HC.blue;
  static const okBg = HC.soft;
  static const okText = HC.blue;
  static const okBorder = Color(0xFFC9D6FF);
  static const infoBg = HC.soft;
  static const infoText = HC.blue;
  static const infoBorder = Color(0xFFC9D6FF);
  static const warn = Color(0xFFB54708);
  static const warnBg = Color(0xFFFFF6E5);
  static const warnText = Color(0xFFB54708);
  static const warnBorder = Color(0xFFFDE3B5);
  static const danger = HC.red;
  static const dangerBg = HC.redSoft;
  static const dangerText = HC.red;
  static const dangerBorder = Color(0xFFF8C9C4);
  static const track = HC.chip;
}

/// Text in the design font (keeps the old `ts` call shape for DSR pages).
TextStyle dts(double size, {FontWeight w = FontWeight.w400, Color color = HC.ink, double h = 1.35, double? ls, bool tabular = false}) =>
    hs(size, w: w, color: color, h: h, ls: ls, num: tabular);

/// White card, radius 20, hairline border.
class DCard extends StatelessWidget {
  const DCard({super.key, required this.child, this.padding = const EdgeInsets.all(16), this.margin = EdgeInsets.zero, this.onTap});
  final Widget child;
  final EdgeInsets padding, margin;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => HCard(padding: padding, margin: margin, onTap: onTap, radius: 20, child: child);
}

enum DTone { success, info, warning, danger, neutral }

class DBadge extends StatelessWidget {
  const DBadge(this.text, {super.key, this.tone = DTone.neutral});
  final String text;
  final DTone tone;
  @override
  Widget build(BuildContext context) {
    final (bg, fg) = switch (tone) {
      DTone.success || DTone.info => (HC.soft, HC.blue),
      DTone.warning => (DC.warnBg, DC.warnText),
      DTone.danger => (HC.redSoft, HC.red),
      DTone.neutral => (HC.chip, HC.ink2),
    };
    return HChip(text, bg: bg, fg: fg, size: 11.5);
  }
}

enum DBtnKind { primary, secondary, ghost, danger, dangerOutline }

/// Rounded button in the design style (navy primary, outlined secondary, red danger).
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
      DBtnKind.primary => (HC.ink, Colors.white, HC.ink),
      DBtnKind.secondary => (Colors.white, HC.ink, HC.line2),
      DBtnKind.ghost => (Colors.transparent, HC.ink2, HC.line),
      DBtnKind.danger => (HC.red, Colors.white, HC.red),
      DBtnKind.dangerOutline => (HC.redSoft, HC.red, HC.redSoft),
    };
    final r = BorderRadius.circular(small ? 12 : 14);
    return Semantics(
      button: true, enabled: onTap != null,
      child: Opacity(
        opacity: onTap == null ? 0.5 : 1,
        child: Material(
          color: bg, borderRadius: r,
          child: InkWell(
            borderRadius: r,
            onTap: onTap == null ? null : () {
              HapticFeedback.lightImpact();
              onTap!();
            },
            child: Container(
              height: height ?? (small ? 38 : 46), padding: EdgeInsets.symmetric(horizontal: small ? 12 : 16),
              decoration: BoxDecoration(borderRadius: r, border: Border.all(color: bd, width: 1.3)),
              child: Row(mainAxisSize: block ? MainAxisSize.max : MainAxisSize.min, mainAxisAlignment: MainAxisAlignment.center, children: [
                if (icon != null) ...[icon!, const SizedBox(width: 6)],
                Flexible(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: hs(small ? 12.5 : 14, w: w7, color: fg, h: 1.2))),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

class DSecTitle extends StatelessWidget {
  const DSecTitle(this.text, {super.key, this.sub});
  final String text;
  final String? sub;
  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(text, style: hs(16, w: w7)),
        if (sub != null) Text(sub!, style: hs(12, color: HC.muted)),
      ]);
}

/// Date pill: ‹ date › and an "আজ" shortcut.
class DDateNav extends StatelessWidget {
  const DDateNav({super.key, required this.date, required this.onChange, this.subText, this.shadow = true});
  final String date;
  final ValueChanged<String> onChange;
  final String? subText;
  final bool shadow;
  @override
  Widget build(BuildContext context) {
    final today = todayYmd();
    Widget arrow(String t, String label, VoidCallback onTap) => Semantics(
          button: true, label: label,
          child: GestureDetector(
            onTap: onTap, behavior: HitTestBehavior.opaque,
            child: SizedBox(width: 44, height: 44, child: Center(child: Text(t, style: hs(22, w: w6, h: 1)))),
          ),
        );
    return Container(
      height: 52, padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18), border: Border.all(color: HC.line), boxShadow: shadow ? HC.liftSm : null),
      child: Row(children: [
        arrow('‹', 'আগের দিন', () => onChange(addDays(date, -1))),
        Expanded(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () async {
              final d = await showDatePicker(context: context, initialDate: DateTime.parse(date), firstDate: DateTime(2024), lastDate: DateTime.now().add(const Duration(days: 1)));
              if (d != null) onChange(ymd(d));
            },
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Text('${date == today ? 'আজ, ' : ''}${dateBn(date)}', maxLines: 1, overflow: TextOverflow.ellipsis, style: hs(14, w: w7, h: 1.2, num: true)),
              if (subText != null) Text(subText!, maxLines: 1, overflow: TextOverflow.ellipsis, style: hs(11, color: HC.muted, h: 1.2, num: true)),
            ]),
          ),
        ),
        arrow('›', 'পরের দিন', () => onChange(addDays(date, 1))),
        if (date != today)
          GestureDetector(
            onTap: () => onChange(today),
            child: Container(
              height: 40, padding: const EdgeInsets.symmetric(horizontal: 14), alignment: Alignment.center,
              decoration: BoxDecoration(color: HC.ink, borderRadius: BorderRadius.circular(14)),
              child: Text('আজ', style: hs(13, w: w7, color: Colors.white, h: 1.2)),
            ),
          ),
      ]),
    );
  }
}

/// Round 40px icon button (sheet close etc.).
class DIconBtn extends StatelessWidget {
  const DIconBtn({super.key, required this.icon, required this.onTap, this.tooltip});
  final String icon;
  final VoidCallback onTap;
  final String? tooltip;
  @override
  Widget build(BuildContext context) => Semantics(
        button: true, label: tooltip ?? 'বন্ধ করুন',
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            width: 40, height: 40, margin: const EdgeInsets.only(left: 8),
            decoration: BoxDecoration(color: Colors.white, shape: BoxShape.circle, border: Border.all(color: HC.line)),
            child: Center(child: Svg(icon, size: 16, color: HC.ink, stroke: 2.2)),
          ),
        ),
      );
}

/// Trip state note (submitted / returned).
class DBanner extends StatelessWidget {
  const DBanner(this.text, {super.key, this.returned = false, this.muted = false});
  final String text;
  final bool returned, muted;
  @override
  Widget build(BuildContext context) {
    final (bg, fg) = returned ? (HC.redSoft, HC.red) : (muted ? (Colors.white, HC.ink2) : (DC.warnBg, DC.warnText));
    return Container(
      width: double.infinity, padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(16), border: muted ? Border.all(color: HC.line) : null),
      child: Text(text, style: hs(13, w: w6, color: fg, h: 1.45)),
    );
  }
}

class DProgress extends StatelessWidget {
  const DProgress(this.pct, {super.key, this.complete = false, this.onSky = false});
  final double pct;
  final bool complete, onSky;
  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: BorderRadius.circular(99),
        child: Container(
          height: 8, color: onSky ? const Color(0x33FFFFFF) : HC.chip, alignment: Alignment.centerLeft,
          child: FractionallySizedBox(widthFactor: (pct / 100).clamp(0, 1), child: Container(color: onSky ? Colors.white : (complete ? HC.blue : HC.ink))),
        ),
      );
}

/// Pushed DSR page: sky header (back, kicker, title) with the body sliding up over its curved edge.
class DPage extends StatelessWidget {
  const DPage({super.key, required this.title, required this.child, this.actions = const [], this.kicker});
  final String title;
  final String? kicker;
  final Widget child;
  final List<Widget> actions;
  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.of(context).padding.top;
    return SkyStatusBar(
      child: Scaffold(
        backgroundColor: HC.outer,
        body: Frame(
          color: HC.outer,
          child: ColoredBox(
            color: HC.bg,
            child: Stack(children: [
              Positioned(left: 0, right: 0, top: 0, height: 112 + top, child: const CustomPaint(painter: SkyPainter())),
              Column(children: [
                Padding(
                  padding: EdgeInsets.fromLTRB(18, top + 12, 18, 14),
                  child: SkyHead(
                    leading: const SkyBack(), kicker: kicker, title: title,
                    trailing: actions.isEmpty ? null : Row(mainAxisSize: MainAxisSize.min, children: actions),
                  ),
                ),
                Expanded(child: child),
              ]),
            ]),
          ),
        ),
      ),
    );
  }
}
