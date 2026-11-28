import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/format.dart';
import 'motion.dart';
import 'pwa_kit.dart';

/// "Happy অ্যাপ ডিজাইন" tokens (the design canvas shared by the retailer, SR and delivery-man apps).
class HC {
  static const sky = Color(0xFF1A3FD6);
  static const onSky = Color(0xFFC9D6FF);
  static const onDark = Color(0xFFB8C3E6);
  static const lilac = Color(0xFFA9C4FF);
  static const ink = Color(0xFF0A1640);
  static const ink2 = Color(0xFF475273);
  static const muted = Color(0xFF5B6785);
  static const faint = Color(0xFF9AA4BE);
  static const blue = Color(0xFF1F4FE0);
  static const blueDeep = Color(0xFF1638A8);
  static const soft = Color(0xFFEAF0FF);
  static const bg = Color(0xFFF4F6FB);
  static const line = Color(0xFFE6EAF2);
  static const line2 = Color(0xFFD5DCEB);
  static const chip = Color(0xFFEEF0F5);
  static const red = Color(0xFFD92D20);
  static const redSoft = Color(0xFFFDECEA);
  static const redOnDark = Color(0xFFFF8A80);
  static const outer = Color(0xFFE3E8F2);

  static const lift = [BoxShadow(color: Color(0x240A1640), blurRadius: 40, offset: Offset(0, 18))];
  static const liftSm = [BoxShadow(color: Color(0x260A1640), blurRadius: 16, offset: Offset(0, 6))];
}

const kFont = 'HindSiliguri';

/// Text style in the design font. Digits stay tabular so amounts line up.
TextStyle hs(double size, {FontWeight w = FontWeight.w400, Color color = HC.ink, double h = 1.35, double? ls, bool num = false}) => TextStyle(
      fontFamily: kFont, fontFamilyFallback: const ['Inter'], fontSize: size, fontWeight: w, color: color, height: h, letterSpacing: ls,
      fontFeatures: num ? const [FontFeature.tabularFigures()] : null,
    );

const w5 = FontWeight.w500, w6 = FontWeight.w600, w7 = FontWeight.w700, w8 = FontWeight.w800;

/// The blue sky behind the top of a screen: radial highlight, dot grid, curved bottom edge.
class SkyPainter extends CustomPainter {
  const SkyPainter();
  @override
  void paint(Canvas canvas, Size size) {
    final clip = Path()..addOval(Rect.fromCenter(center: Offset(size.width / 2, 0), width: size.width * 2.4, height: size.height * 2));
    canvas.save();
    canvas.clipPath(clip);
    final rect = Offset.zero & size;
    canvas.drawRect(rect, Paint()..color = HC.sky);
    final c = Offset(size.width * .85, -size.height * .1);
    final r = math.sqrt(math.pow(c.dx, 2) + math.pow(size.height - c.dy, 2)) * .55;
    canvas.drawRect(rect, Paint()..shader = RadialGradient(colors: const [Color(0xA68CB4FF), Color(0x008CB4FF)]).createShader(Rect.fromCircle(center: c, radius: r)));
    final dot = Paint()..color = const Color(0x17FFFFFF);
    for (double y = 8; y < size.height; y += 16) {
      for (double x = 8; x < size.width; x += 16) {
        canvas.drawCircle(Offset(x, y), 1.2, dot);
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Puts the sky ([height] px below the status bar) behind [child]; the sky scrolls with the content.
/// Use as the first child of a page list that has 18px side padding.
class SkyBox extends StatelessWidget {
  const SkyBox({super.key, required this.height, required this.child, this.side = 18});
  final double height;
  final double side;
  final Widget child;
  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.of(context).padding.top;
    final c = child;
    // Blocks rise in one after another (design hpIn).
    final body = c is Column
        ? Column(mainAxisAlignment: c.mainAxisAlignment, mainAxisSize: c.mainAxisSize, crossAxisAlignment: c.crossAxisAlignment, children: Appear.stagger(c.children))
        : Appear(child: c);
    return Stack(clipBehavior: Clip.none, children: [
      Positioned(left: -side, right: -side, top: -(top + 14), height: height + top, child: const CustomPaint(painter: SkyPainter())),
      body,
    ]);
  }
}

/// White status-bar icons over the sky.
class SkyStatusBar extends StatelessWidget {
  const SkyStatusBar({super.key, required this.child, this.light = true});
  final Widget child;
  final bool light;
  @override
  Widget build(BuildContext context) => AnnotatedRegion<SystemUiOverlayStyle>(
        value: (light ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark).copyWith(
          statusBarColor: Colors.transparent, systemNavigationBarColor: Colors.white, systemNavigationBarIconBrightness: Brightness.dark),
        child: child,
      );
}

/// Round see-through button on the sky (back, bell, logout…).
class GlassBtn extends StatelessWidget {
  const GlassBtn({super.key, required this.icon, required this.onTap, this.label, this.size = 44, this.radius, this.badge, this.dot = false});
  final String icon;
  final VoidCallback? onTap;
  final String? label;
  final double size;
  final double? radius;
  final String? badge;
  final bool dot;
  @override
  Widget build(BuildContext context) => Semantics(
        button: true, label: label,
        child: GestureDetector(
          onTap: onTap == null ? null : () {
            HapticFeedback.selectionClick();
            onTap!();
          },
          child: Container(
            width: size, height: size,
            decoration: BoxDecoration(
              color: const Color(0x24FFFFFF), border: Border.all(color: const Color(0x38FFFFFF)),
              borderRadius: BorderRadius.circular(radius ?? size / 2),
            ),
            child: Stack(clipBehavior: Clip.none, alignment: Alignment.center, children: [
              Svg(icon, size: 20, color: Colors.white, stroke: 1.8),
              if (badge != null)
                Positioned(top: 6, right: 6, child: Container(
                  constraints: const BoxConstraints(minWidth: 16), height: 16, padding: const EdgeInsets.symmetric(horizontal: 3),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8)),
                  alignment: Alignment.center,
                  child: Text(badge!, style: hs(10, w: w8, color: HC.blue, h: 1)),
                )),
              if (dot)
                Positioned(top: 9, right: 10, child: Container(width: 9, height: 9, decoration: BoxDecoration(color: HC.lilac, shape: BoxShape.circle, border: Border.all(color: HC.blue, width: 2)))),
            ]),
          ),
        ),
      );
}

/// Header row on the sky: leading (avatar / back) + kicker + title + trailing.
class SkyHead extends StatelessWidget {
  const SkyHead({super.key, this.leading, this.kicker, required this.title, this.trailing, this.titleSize = 18, this.kickerBelow = false});
  final Widget? leading;
  final String? kicker;
  final String title;
  final Widget? trailing;
  final double titleSize;
  final bool kickerBelow;
  @override
  Widget build(BuildContext context) {
    final k = kicker == null ? null : Text(kicker!, maxLines: 1, overflow: TextOverflow.ellipsis, style: hs(12, color: HC.onSky, h: 1.25));
    final t = Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: hs(titleSize, w: w7, color: Colors.white, h: 1.25));
    return Row(children: [
      if (leading != null) ...[leading!, const SizedBox(width: 12)],
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: kickerBelow ? [t, ?k] : [?k, t])),
      if (trailing != null) ...[const SizedBox(width: 10), trailing!],
    ]);
  }
}

/// Back button for pushed screens on the sky.
class SkyBack extends StatelessWidget {
  const SkyBack({super.key, this.onTap});
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => GlassBtn(icon: Ic.back, label: 'ফিরে যান', onTap: onTap ?? () => Navigator.of(context).maybePop());
}

/// Letter (or photo) avatar.
class LetterAvatar extends StatelessWidget {
  const LetterAvatar(this.text, {super.key, this.size = 44, this.radius, this.bg = Colors.white, this.fg = HC.blue, this.fontSize, this.image, this.ring = false, this.border});
  final String text;
  final double size;
  final double? radius;
  final Color bg, fg;
  final double? fontSize;
  final Widget? image;
  final bool ring;
  final Color? border;
  @override
  Widget build(BuildContext context) {
    final letter = text.trim().isEmpty ? '•' : text.trim().characters.first;
    return Container(
      width: size, height: size,
      decoration: BoxDecoration(
        color: bg, borderRadius: BorderRadius.circular(radius ?? size / 2),
        border: border == null ? null : Border.all(color: border!, width: 2),
        boxShadow: ring ? const [BoxShadow(color: Color(0x40FFFFFF), spreadRadius: 4)] : null,
      ),
      clipBehavior: Clip.antiAlias,
      alignment: Alignment.center,
      child: image ?? Text(letter, style: hs(fontSize ?? size * .4, w: w8, color: fg, h: 1)),
    );
  }
}

/// White card. [lift] = floating card over the sky.
class HCard extends StatelessWidget {
  const HCard({super.key, required this.child, this.padding = const EdgeInsets.symmetric(horizontal: 16, vertical: 14), this.lift = false, this.radius, this.onTap, this.color = Colors.white, this.margin, this.border = true});
  final Widget child;
  final EdgeInsets padding;
  final bool lift;
  final double? radius;
  final VoidCallback? onTap;
  final Color color;
  final EdgeInsets? margin;
  final bool border;
  @override
  Widget build(BuildContext context) {
    final r = BorderRadius.circular(radius ?? (lift ? 24 : 22));
    Widget inner = Padding(padding: padding, child: child);
    if (onTap != null) {
      inner = Material(color: Colors.transparent, child: InkWell(borderRadius: r, onTap: () {
        HapticFeedback.selectionClick();
        onTap!();
      }, child: inner));
    }
    final card = Container(
      margin: margin,
      decoration: BoxDecoration(color: color, borderRadius: r, boxShadow: lift ? HC.lift : null, border: lift || !border ? null : Border.all(color: HC.line)),
      clipBehavior: onTap != null ? Clip.antiAlias : Clip.none,
      child: inner,
    );
    return onTap == null ? card : Pressable(scale: .98, child: card);
  }
}

enum HBtnKind { dark, line, blue, white, danger }

/// Big rounded button (54px): dark navy, outlined, blue, white or danger.
class HBtn extends StatelessWidget {
  const HBtn(this.label, {super.key, this.onTap, this.kind = HBtnKind.dark, this.icon, this.height = 54, this.trailingIcon, this.expand = true, this.radius = 16, this.fontSize = 15});
  final String label;
  final VoidCallback? onTap;
  final HBtnKind kind;
  final String? icon;
  final String? trailingIcon;
  final double height;
  final bool expand;
  final double radius;
  final double fontSize;
  @override
  Widget build(BuildContext context) {
    final (bg, fg, border) = switch (kind) {
      HBtnKind.dark => (HC.ink, Colors.white, null),
      HBtnKind.line => (Colors.white, HC.ink, HC.line2),
      HBtnKind.blue => (HC.blue, Colors.white, null),
      HBtnKind.white => (Colors.white, HC.ink, null),
      HBtnKind.danger => (HC.redSoft, HC.red, null),
    };
    final enabled = onTap != null;
    return Semantics(
      button: true, enabled: enabled,
      child: Pressable(enabled: enabled, child: Opacity(
        opacity: enabled ? 1 : .45,
        child: Material(
          color: bg,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius), side: border == null ? BorderSide.none : BorderSide(color: border, width: 1.5)),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: enabled ? () {
              HapticFeedback.lightImpact();
              onTap!();
            } : null,
            child: SizedBox(
              height: height, width: expand ? double.infinity : null,
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: expand ? 10 : 18),
                child: Row(mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min, mainAxisAlignment: MainAxisAlignment.center, children: [
                  if (icon != null) ...[Svg(icon!, size: 18, color: fg, stroke: 2.2), const SizedBox(width: 8)],
                  Flexible(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: hs(fontSize, w: w7, color: fg, h: 1.2))),
                  if (trailingIcon != null) ...[const SizedBox(width: 6), Svg(trailingIcon!, size: 16, color: fg, stroke: 2.2)],
                ]),
              ),
            ),
          ),
        ),
      ),
    ));
  }
}

/// Segmented switch. [onSky] = glass version over the sky.
class HSeg extends StatelessWidget {
  const HSeg({super.key, required this.items, required this.index, required this.onTap, this.onSky = true, this.badges});
  final List<String> items;
  final int index;
  final ValueChanged<int> onTap;
  final bool onSky;
  final List<int>? badges;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: onSky ? const Color(0x24FFFFFF) : HC.bg,
          border: onSky ? Border.all(color: const Color(0x38FFFFFF)) : null,
          borderRadius: BorderRadius.circular(onSky ? 14 : 16),
        ),
        child: Row(children: [
          for (var i = 0; i < items.length; i++)
            Expanded(
              child: Semantics(
                button: true, selected: i == index,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    HapticFeedback.selectionClick();
                    onTap(i);
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    height: onSky ? 38 : 42,
                    decoration: BoxDecoration(
                      color: i == index ? Colors.white : Colors.transparent, borderRadius: BorderRadius.circular(onSky ? 11 : 13),
                      boxShadow: i == index && !onSky ? const [BoxShadow(color: Color(0x140A1640), blurRadius: 8, offset: Offset(0, 2))] : null,
                    ),
                    alignment: Alignment.center,
                    child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Flexible(child: Text(items[i], maxLines: 1, overflow: TextOverflow.ellipsis, style: hs(13, w: i == index ? w7 : w6,
                          color: i == index ? (onSky ? HC.ink : HC.blue) : (onSky ? HC.onSky : HC.muted)))),
                      if (badges != null && badges![i] > 0) ...[
                        const SizedBox(width: 6),
                        Container(
                          constraints: const BoxConstraints(minWidth: 18), height: 18, padding: const EdgeInsets.symmetric(horizontal: 5),
                          decoration: BoxDecoration(color: i == index ? HC.blue : const Color(0x38FFFFFF), borderRadius: BorderRadius.circular(9)),
                          alignment: Alignment.center,
                          child: Text(bn(badges![i]), style: hs(11, w: w8, color: Colors.white, h: 1)),
                        ),
                      ],
                    ]),
                  ),
                ),
              ),
            ),
        ]),
      );
}

/// Horizontal pills (company tabs etc.), navy when on.
class HPills extends StatelessWidget {
  const HPills({super.key, required this.items, required this.index, required this.onTap});
  final List<String> items;
  final int index;
  final ValueChanged<int> onTap;
  @override
  Widget build(BuildContext context) => SizedBox(
        height: 38,
        child: ListView.separated(
          scrollDirection: Axis.horizontal, clipBehavior: Clip.none,
          itemCount: items.length, separatorBuilder: (_, __) => const SizedBox(width: 8),
          itemBuilder: (_, i) => GestureDetector(
            onTap: () {
              HapticFeedback.selectionClick();
              onTap(i);
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              alignment: Alignment.center,
              decoration: BoxDecoration(color: i == index ? HC.ink : Colors.white, borderRadius: BorderRadius.circular(999), border: i == index ? null : Border.all(color: HC.line)),
              child: Text(items[i], style: hs(13, w: w7, color: i == index ? Colors.white : HC.ink, h: 1.2)),
            ),
          ),
        ),
      );
}

class HNavItem {
  const HNavItem(this.label, this.icon, {this.badge = 0});
  final String label;
  final String icon;
  final int badge;
}

/// Bottom tab bar: white bar, navy pill behind the active icon.
class HTabBar extends StatelessWidget {
  const HTabBar({super.key, required this.items, required this.index, required this.onTap});
  final List<HNavItem> items;
  final int index;
  final ValueChanged<int> onTap;
  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).padding.bottom;
    return Appear(offset: 70, duration: const Duration(milliseconds: 500), child: Container(
      decoration: const BoxDecoration(color: Colors.white, border: Border(top: BorderSide(color: HC.line))),
      padding: EdgeInsets.fromLTRB(8, 0, 8, bottom),
      child: Row(children: [
        for (var i = 0; i < items.length; i++)
          Expanded(
            child: Semantics(
              button: true, selected: i == index, label: items[i].label,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  if (i != index) HapticFeedback.selectionClick();
                  onTap(i);
                },
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(0, 8, 0, 10),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 220), curve: Curves.easeOut,
                      width: items.length > 4 ? 48 : 56, height: 32,
                      decoration: BoxDecoration(color: i == index ? HC.ink : Colors.transparent, borderRadius: BorderRadius.circular(16)),
                      child: Stack(clipBehavior: Clip.none, alignment: Alignment.center, children: [
                        Svg(items[i].icon, size: 20, color: i == index ? Colors.white : HC.muted, stroke: 1.8),
                        if (items[i].badge > 0)
                          Positioned(top: -2, right: 6, child: Container(
                            constraints: const BoxConstraints(minWidth: 16), height: 16, padding: const EdgeInsets.symmetric(horizontal: 4),
                            decoration: BoxDecoration(color: HC.red, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.white, width: 1.5)),
                            alignment: Alignment.center,
                            child: Text(items[i].badge > 9 ? '৯+' : bn(items[i].badge), style: hs(9, w: w8, color: Colors.white, h: 1)),
                          )),
                      ]),
                    ),
                    const SizedBox(height: 4),
                    Text(items[i].label, maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: hs(items.length > 4 ? 11 : 12, w: i == index ? w7 : w5, color: i == index ? HC.ink : HC.muted, h: 1.2)),
                  ]),
                ),
              ),
            ),
          ),
      ]),
    ));
  }
}

/// One cell of a stat strip.
class HStat {
  const HStat(this.label, this.value, {this.color = HC.ink, this.labelOnTop = true});
  final String label;
  final String value;
  final Color color;
  final bool labelOnTop;
}

enum StripStyle { card, soft, dark, plain }

/// Row of numbers split by thin dividers (ওভার / কমিশন / নিট…).
class HStrip extends StatelessWidget {
  const HStrip(this.cells, {super.key, this.style = StripStyle.card, this.valueSize = 17, this.title});
  final List<HStat> cells;
  final StripStyle style;
  final double valueSize;
  final String? title;
  @override
  Widget build(BuildContext context) {
    final dark = style == StripStyle.dark;
    final divider = dark ? const Color(0x1FFFFFFF) : HC.line;
    final row = IntrinsicHeight(
      child: Row(children: [
        for (var i = 0; i < cells.length; i++)
          Expanded(
            child: Container(
              decoration: BoxDecoration(border: i == 0 ? null : Border(left: BorderSide(color: divider))),
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                if (cells[i].labelOnTop) Text(cells[i].label, maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center, style: hs(11, color: dark ? HC.onDark : HC.muted)),
                FittedBox(fit: BoxFit.scaleDown, child: Text(cells[i].value, style: hs(valueSize, w: w8, color: cells[i].color, num: true, h: 1.3))),
                if (!cells[i].labelOnTop) Text(cells[i].label, maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center, style: hs(12, color: HC.muted)),
              ]),
            ),
          ),
      ]),
    );
    final body = title == null
        ? row
        : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Padding(padding: const EdgeInsets.fromLTRB(14, 0, 14, 8), child: Text(title!, style: hs(12, color: HC.onDark))),
            row,
          ]);
    return switch (style) {
      StripStyle.card => Container(padding: const EdgeInsets.symmetric(vertical: 10), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18), border: Border.all(color: HC.line)), child: body),
      StripStyle.soft => Container(padding: const EdgeInsets.symmetric(vertical: 8), decoration: BoxDecoration(color: HC.bg, borderRadius: BorderRadius.circular(14)), child: body),
      StripStyle.dark => Container(padding: const EdgeInsets.fromLTRB(4, 14, 4, 12), decoration: BoxDecoration(color: HC.ink, borderRadius: BorderRadius.circular(22)), child: body),
      StripStyle.plain => body,
    };
  }
}

/// List inside a card with hairline separators.
class HList extends StatelessWidget {
  const HList({super.key, required this.children, this.padding = const EdgeInsets.symmetric(horizontal: 16, vertical: 4), this.lift = false});
  final List<Widget> children;
  final EdgeInsets padding;
  final bool lift;
  @override
  Widget build(BuildContext context) => HCard(
        lift: lift, padding: padding,
        child: Column(children: [
          for (var i = 0; i < children.length; i++)
            Container(decoration: BoxDecoration(border: i == 0 ? null : const Border(top: BorderSide(color: HC.line))), child: children[i]),
        ]),
      );
}

/// Product / item row: letter tile, name, sub line, amount.
class HItemRow extends StatelessWidget {
  const HItemRow({super.key, required this.name, required this.sub, required this.amount, this.tag, this.tagOver = true, this.image, this.soft = false});
  final String name;
  final String sub;
  final String amount;
  final String? tag;
  final bool tagOver;
  final Widget? image;
  final bool soft;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(children: [
          LetterAvatar(name, size: 38, radius: 11, bg: soft ? HC.soft : HC.chip, fg: soft ? HC.blue : HC.ink2, fontSize: 15, image: image),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(name, maxLines: 2, overflow: TextOverflow.ellipsis, style: hs(14, w: w6)),
              Wrap(crossAxisAlignment: WrapCrossAlignment.center, spacing: 4, children: [
                Text(sub, style: hs(12, color: HC.muted, num: true)),
                if (tag != null)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(color: tagOver ? HC.soft : HC.redSoft, borderRadius: BorderRadius.circular(6)),
                    child: Text(tag!, style: hs(10, w: w7, color: tagOver ? HC.blue : HC.red, num: true)),
                  ),
              ]),
            ]),
          ),
          const SizedBox(width: 8),
          Text(amount, style: hs(14, w: w7, num: true)),
        ]),
      );
}

/// Dashed separator line.
class HDashed extends StatelessWidget {
  const HDashed({super.key, this.color = HC.line2});
  final Color color;
  @override
  Widget build(BuildContext context) => SizedBox(
        height: 1.5, width: double.infinity,
        child: CustomPaint(painter: _DashPainter(color)),
      );
}

class _DashPainter extends CustomPainter {
  _DashPainter(this.color);
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()..color = color..strokeWidth = 1.5;
    for (double x = 0; x < size.width; x += 7) {
      canvas.drawLine(Offset(x, 0), Offset(math.min(x + 4, size.width), 0), p);
    }
  }

  @override
  bool shouldRepaint(covariant _DashPainter o) => o.color != color;
}

/// "label ........ value" line.
class HKv extends StatelessWidget {
  const HKv(this.label, this.value, {super.key, this.valueColor = HC.ink, this.big = false, this.bold = true});
  final String label;
  final String value;
  final Color valueColor;
  final bool big;
  final bool bold;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2.5),
        child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
          Expanded(child: Text(label, style: hs(13, color: HC.muted))),
          const SizedBox(width: 10),
          Text(value, style: hs(big ? 20 : 13, w: bold || big ? w7 : w5, color: valueColor, num: true)),
        ]),
      );
}

/// Small rounded chip / badge.
class HChip extends StatelessWidget {
  const HChip(this.text, {super.key, this.bg = HC.soft, this.fg = HC.blue, this.dot = false, this.size = 12});
  final String text;
  final Color bg, fg;
  final bool dot;
  final double size;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (dot) ...[Container(width: 6, height: 6, decoration: BoxDecoration(color: fg, shape: BoxShape.circle)), const SizedBox(width: 5)],
          Flexible(child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, style: hs(size, w: w7, color: fg, h: 1.3, num: true))),
        ]),
      );
}

/// Empty / info card.
class HEmpty extends StatelessWidget {
  const HEmpty(this.title, {super.key, this.body, this.icon});
  final String title;
  final String? body;
  final String? icon;
  @override
  Widget build(BuildContext context) => HCard(
        padding: const EdgeInsets.fromLTRB(20, 26, 20, 26),
        child: SizedBox(
          width: double.infinity,
          child: Column(children: [
            if (icon != null) ...[Svg(icon!, size: 30, color: HC.faint, stroke: 1.6), const SizedBox(height: 8)],
            Text(title, textAlign: TextAlign.center, style: hs(16, w: w7)),
            if (body != null) Padding(padding: const EdgeInsets.only(top: 4), child: Text(body!, textAlign: TextAlign.center, style: hs(13, color: HC.muted))),
          ]),
        ),
      );
}

/// Section title row: bold left, muted right.
class HSec extends StatelessWidget {
  const HSec(this.title, {super.key, this.trailing, this.size = 16});
  final String title;
  final String? trailing;
  final double size;
  @override
  Widget build(BuildContext context) => Row(children: [
        Expanded(child: Text(title, style: hs(size, w: w7))),
        if (trailing != null) Text(trailing!, style: hs(12, color: HC.muted, num: true)),
      ]);
}

/// Date bar on the sky: ‹  label / sub  ›. Tapping the label opens a date picker.
class SkyDateBar extends StatelessWidget {
  const SkyDateBar({super.key, required this.date, required this.onChange, this.sub, this.today});
  final String date; // Y-m-d
  final ValueChanged<String> onChange;
  final String? sub;
  final String? today;
  @override
  Widget build(BuildContext context) {
    final t = today ?? todayYmd();
    final d = DateTime.tryParse(date) ?? DateTime.now();
    String ymd(DateTime x) => '${x.year}-${x.month.toString().padLeft(2, '0')}-${x.day.toString().padLeft(2, '0')}';
    final isToday = date == t;
    final canNext = date.compareTo(t) < 0;
    Widget arrow(String glyph, String label, bool on, VoidCallback tap) => Semantics(
          button: true, label: label, enabled: on,
          child: GestureDetector(
            onTap: on ? () {
              HapticFeedback.selectionClick();
              tap();
            } : null,
            child: Opacity(
              opacity: on ? 1 : .4,
              child: Container(
                width: 44, height: 44,
                decoration: BoxDecoration(color: const Color(0x24FFFFFF), border: Border.all(color: const Color(0x38FFFFFF)), borderRadius: BorderRadius.circular(14)),
                alignment: Alignment.center,
                child: Text(glyph, style: hs(22, color: Colors.white, h: 1)),
              ),
            ),
          ),
        );
    return Row(children: [
      arrow('‹', 'আগের দিন', true, () => onChange(ymd(d.subtract(const Duration(days: 1))))),
      const SizedBox(width: 10),
      Expanded(
        child: GestureDetector(
          onTap: () async {
            final p = await showDatePicker(context: context, initialDate: d, firstDate: DateTime(2024), lastDate: DateTime.tryParse(t) ?? DateTime.now());
            if (p != null) onChange(ymd(p));
          },
          child: Column(children: [
            Text('${isToday ? 'আজ, ' : ''}${dateBn(date)}', maxLines: 1, overflow: TextOverflow.ellipsis, style: hs(17, w: w7, color: Colors.white)),
            if (sub != null) Text(sub!, maxLines: 1, overflow: TextOverflow.ellipsis, style: hs(12, color: HC.onSky)),
          ]),
        ),
      ),
      const SizedBox(width: 10),
      arrow('›', 'পরের দিন', canNext, () => onChange(ymd(d.add(const Duration(days: 1))))),
    ]);
  }
}

/// Bottom sheet in the design (radius 30, handle, safe area, keyboard aware). It follows the finger:
/// pull down to close, push up to open it to full height, and it slides in and out softly.
Future<T?> showHSheet<T>(BuildContext context, {required WidgetBuilder builder, bool scroll = true}) => showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      enableDrag: false,
      backgroundColor: Colors.white,
      barrierColor: const Color(0x730A1640),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(30))),
      clipBehavior: Clip.antiAlias,
      sheetAnimationStyle: const AnimationStyle(duration: Duration(milliseconds: 420), reverseDuration: Duration(milliseconds: 260), curve: kEase, reverseCurve: Curves.easeInCubic),
      builder: (c) => SheetFrame(scroll: scroll, builder: (c, _) => builder(c)),
    );

/// Round "−" / "+" stepper on a soft panel (SR3b / DMD).
class HStepper extends StatelessWidget {
  const HStepper({super.key, required this.value, required this.onChanged, this.min = 0, this.max, this.onTapValue});
  final int value;
  final ValueChanged<int> onChanged;
  final int min;
  final int? max;
  final VoidCallback? onTapValue;
  @override
  Widget build(BuildContext context) {
    Widget btn(String t, bool plus, bool on) => Semantics(
          button: true, label: plus ? 'বাড়ান' : 'কমান', enabled: on,
          child: GestureDetector(
            onTap: on ? () {
              HapticFeedback.selectionClick();
              onChanged(value + (plus ? 1 : -1));
            } : null,
            child: Opacity(
              opacity: on ? 1 : .4,
              child: Container(
                width: 44, height: 44,
                decoration: BoxDecoration(color: plus ? HC.ink : Colors.white, borderRadius: BorderRadius.circular(14),
                    boxShadow: plus ? null : const [BoxShadow(color: Color(0x140A1640), blurRadius: 6, offset: Offset(0, 2))]),
                alignment: Alignment.center,
                child: Text(t, style: hs(22, color: plus ? Colors.white : HC.ink, h: 1)),
              ),
            ),
          ),
        );
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(color: HC.bg, borderRadius: BorderRadius.circular(18)),
      child: Row(children: [
        btn('−', false, value > min),
        Expanded(child: GestureDetector(onTap: onTapValue, child: Text(bn(value), textAlign: TextAlign.center, style: hs(26, w: w8, num: true, h: 1.2)))),
        btn('+', true, max == null || value < max!),
      ]),
    );
  }
}

/// Soft numbered / ticked circle (stop numbers, shop numbers).
class NumDot extends StatelessWidget {
  const NumDot(this.text, {super.key, this.bg = HC.soft, this.fg = HC.blue, this.size = 30});
  final String text;
  final Color bg, fg;
  final double size;
  @override
  Widget build(BuildContext context) => Container(
        width: size, height: size, alignment: Alignment.center,
        decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
        child: Text(text, style: hs(13, w: w7, color: fg, h: 1)),
      );
}

/// A page with the design background, the given children in a scroll view (pull to refresh optional).
class HScroll extends StatelessWidget {
  const HScroll({super.key, required this.children, this.onRefresh, this.bottom = 24, this.controller});
  final List<Widget> children;
  final Future<void> Function()? onRefresh;
  final double bottom;
  final ScrollController? controller;
  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.of(context).padding.top;
    final list = ListView(
      controller: controller,
      physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
      padding: EdgeInsets.fromLTRB(18, top + 14, 18, bottom),
      children: Appear.stagger(children),
    );
    return onRefresh == null ? list : RefreshIndicator(color: HC.blue, edgeOffset: top, onRefresh: onRefresh!, child: list);
  }
}

/// Gap helper used between stacked blocks (12px like the design).
const gap12 = SizedBox(height: 12);
const gap8 = SizedBox(height: 8);
const gap16 = SizedBox(height: 16);

/// Signed money: +৳১২ / −৳১২ (৳০ without a sign).
String sMoney(Object? v) {
  final n = num0(v);
  if (n.abs() < .005) return '৳০';
  return '${n > 0 ? '+' : '−'}৳${numTrim(n.abs())}';
}

/// Money without decimals when whole: ৳১,২০০.
String tk(Object? v) => '৳${numTrim(num0(v))}';
