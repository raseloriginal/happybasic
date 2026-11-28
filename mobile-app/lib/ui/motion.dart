import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';

/// The design's easing: cubic-bezier(.2,.8,.2,1) — quick start, long soft landing.
const kEase = Cubic(.2, .8, .2, 1);

/// Content rising into place (design `hpIn`: 14px up, .985 scale, fade, .55s), with an optional delay.
class Appear extends StatefulWidget {
  const Appear({super.key, required this.child, this.delay = Duration.zero, this.offset = 14, this.duration = const Duration(milliseconds: 550)});
  final Widget child;
  final Duration delay;
  final double offset;
  final Duration duration;

  /// Wraps each child with a growing delay (design: +50ms per block, capped).
  static List<Widget> stagger(List<Widget> children, {int stepMs = 50, int maxMs = 400}) => [
        for (var i = 0; i < children.length; i++) Appear(delay: Duration(milliseconds: math.min(i * stepMs, maxMs)), child: children[i]),
      ];

  @override
  State<Appear> createState() => _AppearState();
}

class _AppearState extends State<Appear> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: widget.duration);
  late final Animation<double> _t = CurvedAnimation(parent: _c, curve: kEase);

  @override
  void initState() {
    super.initState();
    if (widget.delay == Duration.zero) {
      _c.forward();
    } else {
      Future.delayed(widget.delay, () {
        if (mounted) _c.forward();
      });
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) return widget.child;
    return AnimatedBuilder(
      animation: _t,
      child: widget.child,
      builder: (_, child) {
        final v = _t.value;
        return Opacity(
          opacity: _c.value.clamp(0.0, 1.0),
          child: Transform.translate(offset: Offset(0, (1 - v) * widget.offset), child: Transform.scale(scale: .985 + .015 * v, child: child)),
        );
      },
    );
  }
}

/// Scales down a little while pressed (design `:active{transform:scale(.97)}`).
class Pressable extends StatefulWidget {
  const Pressable({super.key, required this.child, this.enabled = true, this.scale = .97});
  final Widget child;
  final bool enabled;
  final double scale;
  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _down = false;
  void _set(bool v) {
    if (widget.enabled && v != _down) setState(() => _down = v);
  }

  @override
  Widget build(BuildContext context) => Listener(
        onPointerDown: (_) => _set(true),
        onPointerUp: (_) => _set(false),
        onPointerCancel: (_) => _set(false),
        child: AnimatedScale(
          scale: _down ? widget.scale : 1,
          duration: Duration(milliseconds: _down ? 90 : 220),
          curve: _down ? Curves.easeOut : kEase,
          child: widget.child,
        ),
      );
}

/// Grey placeholder block with a soft light sweep (skeleton loading).
class Skeleton extends StatelessWidget {
  const Skeleton({super.key, this.width, this.height = 14, this.radius = 8, this.dark = false});
  final double? width;
  final double height;
  final double radius;
  final bool dark;
  @override
  Widget build(BuildContext context) => Container(
        width: width, height: height,
        decoration: BoxDecoration(color: dark ? const Color(0x2EFFFFFF) : const Color(0xFFE6EAF2), borderRadius: BorderRadius.circular(radius)),
      );
}

/// Runs one shimmer sweep across every [Skeleton] below it.
class Shimmer extends StatefulWidget {
  const Shimmer({super.key, required this.child});
  final Widget child;
  @override
  State<Shimmer> createState() => _ShimmerState();
}

class _ShimmerState extends State<Shimmer> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1300))..repeat();
  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _c,
        child: widget.child,
        builder: (_, child) => ShaderMask(
          blendMode: BlendMode.srcATop,
          shaderCallback: (r) {
            final x = -1.5 + 3.5 * _c.value;
            return LinearGradient(
              begin: Alignment(x - 1, -.3), end: Alignment(x + 1, .3),
              colors: const [Color(0x00FFFFFF), Color(0x80FFFFFF), Color(0x00FFFFFF)],
              stops: const [.35, .5, .65],
            ).createShader(r);
          },
          child: child,
        ),
      );
}

/// The loading skeleton of a page: a sky header with title lines and a lifted card, then list cards.
class PageSkeleton extends StatelessWidget {
  const PageSkeleton({super.key, this.sky = true});
  final bool sky;
  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.of(context).padding.top;
    Widget card(double h) => Container(
          height: h, margin: const EdgeInsets.only(bottom: 12), padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(22), border: Border.all(color: const Color(0xFFE6EAF2))),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Skeleton(width: 42, height: 42, radius: 14),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Skeleton(width: 140, height: 14),
              const SizedBox(height: 8),
              Skeleton(width: math.max(60, h * 1.2), height: 11),
            ])),
            const Skeleton(width: 54, height: 14),
          ]),
        );
    return Shimmer(
      child: ListView(
        physics: const NeverScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(18, (sky ? top : 0) + 14, 18, 24),
        children: [
          if (sky) ...[
            Row(children: const [
              Skeleton(width: 44, height: 44, radius: 22, dark: true),
              SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Skeleton(width: 120, height: 11, dark: true),
                SizedBox(height: 8),
                Skeleton(width: 170, height: 18, dark: true),
              ])),
            ]),
            const SizedBox(height: 22),
            const Skeleton(width: 190, height: 34, radius: 10, dark: true),
            const SizedBox(height: 22),
          ],
          card(86), card(70), card(70), card(70), card(70),
        ],
      ),
    );
  }
}

/// Paints the sky behind a skeleton so a loading sky page does not flash white.
class SkySkeleton extends StatelessWidget {
  const SkySkeleton({super.key});
  @override
  Widget build(BuildContext context) => Stack(children: [
        Positioned(
          left: 0, right: 0, top: 0, height: 260 + MediaQuery.of(context).padding.top,
          child: const DecoratedBox(
            decoration: BoxDecoration(
              color: Color(0xFF1A3FD6),
              borderRadius: BorderRadius.vertical(bottom: Radius.elliptical(400, 60)),
            ),
          ),
        ),
        const PageSkeleton(),
      ]);
}

/// The body of a bottom sheet that follows the finger: pull down (also from the top of a scrolled list) to close,
/// push up to open it to full height. Released sheets spring back or slide away softly.
class SheetFrame extends StatefulWidget {
  const SheetFrame({super.key, required this.builder, this.scroll = true, this.padding = const EdgeInsets.fromLTRB(20, 4, 20, 24)});
  final Widget Function(BuildContext context, ScrollController? controller) builder;
  final bool scroll;
  final EdgeInsets padding;
  @override
  State<SheetFrame> createState() => _SheetFrameState();
}

class _SheetFrameState extends State<SheetFrame> with SingleTickerProviderStateMixin {
  final _scroll = ScrollController();
  late final AnimationController _drag = AnimationController.unbounded(vsync: this);
  bool _expanded = false;
  bool _closing = false;

  @override
  void dispose() {
    _scroll.dispose();
    _drag.dispose();
    super.dispose();
  }

  void _move(double dy) {
    _drag.value = math.max(0, _drag.value + dy);
  }

  void _release(double velocity) {
    final h = context.size?.height ?? 400;
    if (_drag.value > math.min(140, h * .28) || velocity > 900) {
      _close(velocity);
      return;
    }
    final sim = SpringSimulation(const SpringDescription(mass: 1, stiffness: 420, damping: 32), _drag.value, 0, velocity);
    _drag.animateWith(sim);
  }

  void _close(double velocity) {
    // velocity is kept for symmetry; the route plays its own soft exit.
    if (_closing) return;
    _closing = true;
    HapticFeedback.selectionClick();
    Navigator.of(context).maybePop();
  }

  bool _onScroll(ScrollNotification n) {
    if (n.depth != 0) return false;
    // Pull down at the top of the list: move the sheet instead.
    if (n is OverscrollNotification && n.overscroll < 0 && n.dragDetails != null) {
      _drag.stop();
      _move(-n.overscroll);
    } else if (n is ScrollUpdateNotification && _drag.value > 0 && n.dragDetails != null && (n.scrollDelta ?? 0) > 0) {
      // Pushing back up while the sheet is pulled down: bring the sheet up first.
      _move(-(n.scrollDelta ?? 0));
      _scroll.jumpTo(0);
    } else if (n is ScrollEndNotification && _drag.value > 0) {
      _release(n.dragDetails?.primaryVelocity ?? 0);
    } else if (n is ScrollUpdateNotification && !_expanded && n.dragDetails != null && (n.scrollDelta ?? 0) > 4) {
      setState(() => _expanded = true);
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final maxH = mq.size.height - mq.padding.top - (_expanded ? 0 : mq.size.height * .1);
    final handle = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onVerticalDragStart: (_) => _drag.stop(),
      onVerticalDragUpdate: (d) {
        if (d.delta.dy < 0 && _drag.value <= 0 && !_expanded && _scroll.hasClients && _scroll.position.maxScrollExtent > 0) {
          setState(() => _expanded = true);
        }
        _move(d.delta.dy);
      },
      onVerticalDragEnd: (d) => _release(d.primaryVelocity ?? 0),
      child: Padding(
        padding: const EdgeInsets.only(top: 10, bottom: 8),
        child: Center(child: Container(width: 44, height: 5, decoration: BoxDecoration(color: const Color(0xFFD5DCEB), borderRadius: BorderRadius.circular(3)))),
      ),
    );
    final body = widget.scroll
        ? Flexible(
            child: NotificationListener<ScrollNotification>(
              onNotification: _onScroll,
              child: SingleChildScrollView(
                controller: _scroll,
                physics: const ClampingScrollPhysics(),
                padding: widget.padding,
                child: widget.builder(context, _scroll),
              ),
            ),
          )
        : Flexible(
            child: GestureDetector(
              onVerticalDragUpdate: (d) => _move(d.delta.dy),
              onVerticalDragEnd: (d) => _release(d.primaryVelocity ?? 0),
              child: widget.builder(context, null),
            ),
          );
    return AnimatedBuilder(
      animation: _drag,
      builder: (_, child) => Transform.translate(offset: Offset(0, _drag.value), child: child),
      child: Padding(
        padding: EdgeInsets.only(bottom: mq.viewInsets.bottom),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 380),
          curve: kEase,
          constraints: BoxConstraints(maxHeight: maxH),
          child: Column(mainAxisSize: MainAxisSize.min, children: [handle, body]),
        ),
      ),
    );
  }
}

/// A tab page that fades and rises a little each time it becomes the visible tab.
class TabFade extends StatefulWidget {
  const TabFade({super.key, required this.active, required this.child});
  final bool active;
  final Widget child;
  @override
  State<TabFade> createState() => _TabFadeState();
}

class _TabFadeState extends State<TabFade> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 320), value: 1);
  late final Animation<double> _t = CurvedAnimation(parent: _c, curve: kEase);

  @override
  void didUpdateWidget(TabFade old) {
    super.didUpdateWidget(old);
    if (widget.active && !old.active) _c.forward(from: 0);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _t,
        child: widget.child,
        builder: (_, child) => Opacity(
          opacity: (.2 + .8 * _c.value).clamp(0.0, 1.0),
          child: Transform.translate(offset: Offset(0, (1 - _t.value) * 10), child: child),
        ),
      );
}
