import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// Max width of the PWA frame (`--w` / `--mobile-w`). On a phone it is simply the full width.
const double kFrameW = 430;

/// Map tiles come from the network; widget tests switch them off.
bool kMapTiles = true;

/// Centers [child] in the 430px frame on wide screens (tablets), like the PWA's `.shell`.
class Frame extends StatelessWidget {
  const Frame({super.key, required this.child, this.color});
  final Widget child;
  final Color? color;
  @override
  Widget build(BuildContext context) => ColoredBox(
        color: color ?? const Color(0xFFE7ECF3),
        child: Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: kFrameW), child: child)),
      );
}

/// Same SVG icon paths as the PWA (24x24 viewBox, stroke icons).
class Svg extends StatelessWidget {
  const Svg(this.path, {super.key, this.size = 20, this.color = Colors.black, this.stroke = 2, this.fill});
  final String path;
  final double size;
  final Color color;
  final double stroke;
  final Color? fill;

  static String _hex(Color c) => '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';

  @override
  Widget build(BuildContext context) {
    final svg = '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="${fill == null ? 'none' : _hex(fill!)}" '
        'stroke="${_hex(color)}" stroke-width="$stroke" stroke-linecap="round" stroke-linejoin="round">$path</svg>';
    return SvgPicture.string(svg, width: size, height: size);
  }
}

/// The PWA's icon set (paths copied from the panel layouts).
class Ic {
  static const home = '<path d="M3 10.5 12 3l9 7.5V20a1 1 0 0 1-1 1h-5.5v-6.5h-5V21H4a1 1 0 0 1-1-1z"/>';
  static const plus = '<path d="M12 5v14M5 12h14"/>';
  static const doc = '<rect x="5" y="3" width="14" height="18" rx="2"/><path d="M9 8h6M9 12h6M9 16h4"/>';
  static const user = '<circle cx="12" cy="8" r="4"/><path d="M4 20a8 8 0 0 1 16 0"/>';
  static const bell = '<path d="M18 8a6 6 0 0 0-12 0c0 7-3 9-3 9h18s-3-2-3-9M13.7 21a2 2 0 0 1-3.4 0"/>';
  static const back = '<path d="m15 5-7 7 7 7"/>';
  static const chevRight = '<path d="m9 6 6 6-6 6"/>';
  static const chevLeft = '<path d="m15 18-6-6 6-6"/>';
  static const chevRight2 = '<path d="m9 18 6-6-6-6"/>';
  static const logout = '<path d="M9 21H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h4M16 17l5-5-5-5M21 12H9"/>';
  static const print = '<polyline points="6 9 6 2 18 2 18 9"/><path d="M6 18H4a2 2 0 0 1-2-2v-5a2 2 0 0 1 2-2h16a2 2 0 0 1 2 2v5a2 2 0 0 1-2 2h-2"/><rect x="6" y="14" width="12" height="8"/>';
  static const logoMark = '<path d="M6 5v14M18 5v14M6 12h12"/>';
}

/// A widget that is laid out [overlap] px higher than its natural position and takes that much less space,
/// so it sits on top of the widget above it (CSS negative margin-top).
class NegativeTop extends SingleChildRenderObjectWidget {
  const NegativeTop({super.key, required this.overlap, required super.child});
  final double overlap;
  @override
  RenderObject createRenderObject(BuildContext context) => _RenderNegativeTop(overlap);
  @override
  void updateRenderObject(BuildContext context, covariant _RenderNegativeTop r) => r.overlap = overlap;
}

class _RenderNegativeTop extends RenderShiftedBox {
  _RenderNegativeTop(this._overlap) : super(null);
  double _overlap;
  set overlap(double v) {
    if (v != _overlap) {
      _overlap = v;
      markNeedsLayout();
    }
  }

  @override
  void performLayout() {
    final c = child;
    if (c == null) {
      size = constraints.smallest;
      return;
    }
    c.layout(constraints, parentUsesSize: true);
    size = Size(c.size.width, math.max(0, c.size.height - _overlap));
    (c.parentData! as BoxParentData).offset = Offset(0, -_overlap);
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final c = child;
    if (c != null) context.paintChild(c, offset + (c.parentData! as BoxParentData).offset);
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    final c = child;
    if (c == null) return false;
    final off = (c.parentData! as BoxParentData).offset;
    return result.addWithPaintOffset(offset: off, position: position, hitTest: (r, p) => c.hitTest(r, position: p));
  }
}

TextStyle ts(double size, {FontWeight w = FontWeight.w400, Color color = const Color(0xFF0F172A), double h = 1.4, double? ls, bool tabular = false}) =>
    TextStyle(fontSize: size, fontWeight: w, color: color, height: h, letterSpacing: ls, fontFeatures: tabular ? const [FontFeature.tabularFigures()] : null);
