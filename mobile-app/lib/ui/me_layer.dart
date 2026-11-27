import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../core/geo_filter.dart';
import '../core/tracker.dart';
import 'hkit.dart';

/// The user's own dot on a map, moving like Google Maps: it glides from one GPS fix to the next instead of
/// jumping, shows the direction of travel, and (while [follow] is true) the camera glides with it.
/// While [active] (the map is on screen) the GPS runs at one fix per second.
class MeLayer extends StatefulWidget {
  const MeLayer({super.key, required this.map, required this.active, required this.follow, this.initial, this.scopeMetres});
  final MapController map;
  final bool active, follow;
  /// Shown until the live stream delivers its first fix.
  final LatLng? initial;
  /// Radius of the "shops near me" circle that travels with the dot.
  final double? scopeMetres;
  @override
  State<MeLayer> createState() => _MeLayerState();
}

class _MeLayerState extends State<MeLayer> with SingleTickerProviderStateMixin {
  late final AnimationController _anim;
  LatLng? _from, _to;
  double? _heading;
  int _lastMs = 0;
  bool _holding = false;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(vsync: this, value: 1)..addListener(_followNow);
    final f = Tracker.instance.fix.value;
    _from = _to = f == null ? widget.initial : LatLng(f.lat, f.lng);
    Tracker.instance.fix.addListener(_onFix);
    _hold(widget.active);
  }

  @override
  void didUpdateWidget(MeLayer old) {
    super.didUpdateWidget(old);
    _hold(widget.active);
    if (_to == null && widget.initial != null) _from = _to = widget.initial;
    if (widget.follow && !old.follow) WidgetsBinding.instance.addPostFrameCallback((_) => _followNow());
  }

  void _hold(bool on) {
    if (on == _holding) return;
    _holding = on;
    Future.microtask(() => Tracker.instance.setLive(on)); // not during a build: the tracker has listeners
  }

  @override
  void dispose() {
    Tracker.instance.fix.removeListener(_onFix);
    _hold(false);
    _anim.dispose();
    super.dispose();
  }

  LatLng? get _shown {
    final a = _from, b = _to;
    if (a == null || b == null) return b;
    final t = _anim.value;
    return LatLng(a.latitude + (b.latitude - a.latitude) * t, a.longitude + (b.longitude - a.longitude) * t);
  }

  void _onFix() {
    final f = Tracker.instance.fix.value;
    if (f == null || !mounted) return;
    final next = LatLng(f.lat, f.lng);
    final now = DateTime.now().millisecondsSinceEpoch;
    // The glide lasts as long as the time between fixes, so the dot never stops and starts.
    final gap = _lastMs == 0 ? 1000 : (now - _lastMs).clamp(400, 1600);
    _lastMs = now;
    final cur = _shown;
    _heading = f.heading;
    // No glide for a first fix or a huge jump (the app was asleep).
    final jump = cur == null || GeoFilter.metres(cur.latitude, cur.longitude, next.latitude, next.longitude) > 500;
    _from = jump ? next : cur;
    _to = next;
    if (widget.active && !jump) {
      _anim.duration = Duration(milliseconds: gap);
      _anim.forward(from: 0);
    } else {
      _anim.value = 1;
      _followNow();
    }
    setState(() {});
  }

  void _followNow() {
    final p = _shown;
    if (!mounted || !widget.follow || !widget.active || p == null) return;
    try {
      widget.map.move(p, widget.map.camera.zoom);
    } catch (_) {/* map not laid out yet */}
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _anim,
        builder: (_, _) {
          final p = _shown;
          if (p == null) return const SizedBox.shrink();
          return Stack(children: [
            if (widget.scopeMetres != null)
              CircleLayer(circles: [CircleMarker(point: p, radius: widget.scopeMetres!, useRadiusInMeter: true, color: const Color(0x1A1F4FE0), borderColor: const Color(0x8C1F4FE0), borderStrokeWidth: 1.5)]),
            MarkerLayer(markers: [Marker(point: p, width: 64, height: 64, child: IgnorePointer(child: _dot()))]),
          ]);
        },
      );

  Widget _dot() => Stack(alignment: Alignment.center, children: [
        if (_heading != null)
          TweenAnimationBuilder<double>(
            tween: _AngleTween(_heading! * math.pi / 180),
            duration: const Duration(milliseconds: 400),
            builder: (_, angle, _) => Transform.rotate(angle: angle, child: const CustomPaint(size: Size(64, 64), painter: _BeamPainter())),
          ),
        Container(width: 22, height: 22, decoration: BoxDecoration(color: HC.blue, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 3), boxShadow: const [BoxShadow(color: Color(0x401F4FE0), blurRadius: 6, spreadRadius: 4)])),
      ]);
}

/// Turns the short way round (350° → 10° is 20°, not 340°).
class _AngleTween extends Tween<double> {
  _AngleTween(double end) : super(begin: end, end: end);
  @override
  double lerp(double t) {
    var d = (end! - begin!) % (2 * math.pi);
    if (d > math.pi) d -= 2 * math.pi;
    return begin! + d * t;
  }
}

/// The light cone in front of the dot, pointing up (north) before rotation.
class _BeamPainter extends CustomPainter {
  const _BeamPainter();
  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width / 2;
    final path = ui.Path()
      ..moveTo(c.dx, c.dy)
      ..arcTo(Rect.fromCircle(center: c, radius: r), -math.pi / 2 - 0.55, 1.1, false)
      ..close();
    canvas.drawPath(path, Paint()..shader = ui.Gradient.radial(c, r, const [Color(0x991F4FE0), Color(0x001F4FE0)]));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
