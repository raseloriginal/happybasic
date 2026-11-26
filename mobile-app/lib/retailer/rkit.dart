import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../ui/pwa_kit.dart';

/// Retailer panel design tokens — copied from public/assets/retailer/css/retailer.css.
class RC {
  static const outer = Color(0xFFE7ECF3);
  static const bg = Color(0xFFF5F7FC);
  static const border = Color(0xFFE2E8F0);
  static const ink = Color(0xFF0F172A);
  static const ink2 = Color(0xFF475569);
  static const muted = Color(0xFF64748B);
  static const blue = Color(0xFF1D5BD8);
  static const blueSoft = Color(0xFFE8F0FE);
  static const blueInk = Color(0xFF1E40AF);
  static const ok = Color(0xFF15803D);
  static const okSoft = Color(0xFFE1F3E6);
  static const muteSoft = Color(0xFFE8ECF2);
  static const danger = Color(0xFFBE123C);
  static const dangerSoft = Color(0xFFFCE7EA);
  static const warn = Color(0xFFB45309);
  static const warnSoft = Color(0xFFFEF3C7);
  static const purple = Color(0xFF7C3FD6);
  static const okStripe = Color(0xFF22A355);

  static const shadow = [
    BoxShadow(color: Color(0x0A0F172A), blurRadius: 2, offset: Offset(0, 1)),
    BoxShadow(color: Color(0x141E40AF), blurRadius: 24, offset: Offset(0, 8)),
  ];
}

/// `.card`: white, radius 22, soft blue shadow.
class RCard extends StatelessWidget {
  const RCard({super.key, required this.child, this.padding = EdgeInsets.zero, this.margin = EdgeInsets.zero, this.onTap, this.shadow, this.radius = 22, this.border, this.color = Colors.white, this.clip = false});
  final Widget child;
  final EdgeInsets padding;
  final EdgeInsets margin;
  final VoidCallback? onTap;
  final List<BoxShadow>? shadow;
  final double radius;
  final Border? border;
  final Color color;
  final bool clip;

  @override
  Widget build(BuildContext context) {
    final deco = BoxDecoration(color: color, borderRadius: BorderRadius.circular(radius), boxShadow: shadow ?? RC.shadow, border: border);
    Widget inner = Padding(padding: padding, child: child);
    if (onTap != null) {
      inner = Material(
        color: Colors.transparent,
        child: InkWell(borderRadius: BorderRadius.circular(radius), onTap: onTap, child: inner),
      );
    }
    return Container(margin: margin, decoration: deco, clipBehavior: clip || onTap != null ? Clip.antiAlias : Clip.none, child: inner);
  }
}

/// `.hero`: blue gradient header with the two soft circles.
class RHero extends StatelessWidget {
  const RHero({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.of(context).padding.top;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light.copyWith(statusBarColor: Colors.transparent),
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(36)),
        child: Container(
          decoration: const BoxDecoration(gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF3B82F6), Color(0xFF1D4FD0)])),
          child: Stack(children: [
            Positioned(right: -70, top: -90, child: _circle(220)),
            Positioned(left: -50, bottom: -70, child: _circle(140)),
            Padding(padding: EdgeInsets.fromLTRB(18, 26 + top, 18, 64), child: child),
          ]),
        ),
      ),
    );
  }

  Widget _circle(double d) => Container(width: d, height: d, decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0x14FFFFFF)));
}

/// `.plain-head` (white sticky header with a shadow), optional back arrow.
class RPlainHead extends StatelessWidget {
  const RPlainHead({super.key, required this.title, this.subtitle, this.onBack});
  final String title;
  final String? subtitle;
  final VoidCallback? onBack;
  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.of(context).padding.top;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark.copyWith(statusBarColor: Colors.transparent),
      child: Container(
        padding: EdgeInsets.fromLTRB(20, 22 + top, 20, 14),
        decoration: const BoxDecoration(color: Colors.white, boxShadow: [BoxShadow(color: Color(0x0F0F172A), blurRadius: 14, offset: Offset(0, 2))]),
        child: Row(children: [
          if (onBack != null) ...[
            InkResponse(onTap: onBack, radius: 24, child: const SizedBox(width: 34, height: 34, child: Center(child: Svg(Ic.back, size: 26, color: RC.ink, stroke: 2.2)))),
            const SizedBox(width: 16),
          ],
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: ts(26, w: FontWeight.w700, h: 1.25)),
              if (subtitle != null) Text(subtitle!, style: ts(14, color: RC.muted, h: 1.4)),
            ]),
          ),
        ]),
      ),
    );
  }
}

/// `.sec-title`: 20px bold with a blue bar.
class RSecTitle extends StatelessWidget {
  const RSecTitle(this.text, {super.key, this.muted = false});
  final String text;
  final bool muted;
  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.fromLTRB(4, muted ? 6 : 0, 4, 14),
        child: Row(children: [
          if (!muted) ...[Container(width: 5, height: 20, decoration: BoxDecoration(color: RC.blue, borderRadius: BorderRadius.circular(3))), const SizedBox(width: 10)],
          Expanded(child: Text(text, style: ts(muted ? 15 : 20, w: FontWeight.w700, color: muted ? RC.ink2 : RC.ink))),
        ]),
      );
}

/// `.empty` card.
class REmpty extends StatelessWidget {
  const REmpty(this.title, {super.key, this.body});
  final String title;
  final String? body;
  @override
  Widget build(BuildContext context) => RCard(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.fromLTRB(20, 28, 20, 28),
        child: SizedBox(
          width: double.infinity,
          child: Column(children: [
            Text(title, style: ts(17, w: FontWeight.w700), textAlign: TextAlign.center),
            if (body != null) Padding(padding: const EdgeInsets.only(top: 4), child: Text(body!, style: ts(14, color: RC.ink2), textAlign: TextAlign.center)),
          ]),
        ),
      );
}

/// `.pill-nav`: floating rounded bar. Items: today (blue when active) / history (purple when active).
class RPillNav extends StatelessWidget {
  const RPillNav({super.key, required this.index, required this.onTap});
  final int index;
  final ValueChanged<int> onTap;
  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).padding.bottom;
    final items = [
      (label: 'আজ', icon: Ic.home, on: RC.blue, iconOff: RC.blue),
      (label: 'হিস্ট্রি', icon: Ic.doc, on: RC.purple, iconOff: RC.purple),
    ];
    return Positioned(
      left: 28, right: 28, bottom: 14 + bottom,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(99),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
          child: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xEBFFFFFF), borderRadius: BorderRadius.circular(99), border: Border.all(color: const Color(0xCCE2E8F0)),
              boxShadow: const [BoxShadow(color: Color(0x2E0F172A), blurRadius: 30, offset: Offset(0, 8))],
            ),
            child: Row(children: [
              for (var i = 0; i < items.length; i++) ...[
                if (i > 0) const SizedBox(width: 6),
                Expanded(
                  child: GestureDetector(
                    onTap: () => onTap(i),
                    behavior: HitTestBehavior.opaque,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 250),
                      height: 50,
                      decoration: BoxDecoration(
                        color: index == i ? items[i].on : Colors.transparent,
                        borderRadius: BorderRadius.circular(99),
                        boxShadow: index == i ? [BoxShadow(color: items[i].on.withValues(alpha: 0.35), blurRadius: 16, offset: const Offset(0, 6))] : null,
                      ),
                      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                        Svg(items[i].icon, size: 22, color: index == i ? Colors.white : items[i].iconOff),
                        const SizedBox(width: 10),
                        Text(items[i].label, style: ts(16, w: FontWeight.w700, color: index == i ? Colors.white : RC.ink2)),
                      ]),
                    ),
                  ),
                ),
              ],
            ]),
          ),
        ),
      ),
    );
  }
}
