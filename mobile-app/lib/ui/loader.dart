import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

const kLoaderAsset = 'assets/images/loader.gif';

/// Frames in one full round of the loader GIF (checked by test/loader_test.dart).
const kLoaderFrames = 150;

/// Decides when the start-up loader may leave: only at the end of a full
/// animation round, and only after the first screen has finished loading.
class AppStart {
  AppStart._();

  /// First loads of the screens being prepared behind the loader.
  static int pending = 0;

  static Completer<void> _opened = Completer<void>();

  /// Completes once the loader is gone. Dialogs wait for this so they don't cover it.
  static Future<void> get opened => _opened.future;
  static bool get isOpen => _opened.isCompleted;

  static bool canOpen() => pending <= 0;

  static void open() {
    if (!_opened.isCompleted) _opened.complete();
  }

  @visibleForTesting
  static void reset() {
    pending = 0;
    _opened = Completer<void>();
  }
}

/// Shows [child] under the full-screen loader until [AppStart] lets it open.
class StartGate extends StatefulWidget {
  const StartGate({super.key, required this.ready, required this.child, this.maxWait = const Duration(seconds: 20)});
  final bool ready;
  final Widget child;

  /// A slow network or a broken frame must never lock the user out of the app.
  final Duration maxWait;

  @override
  State<StartGate> createState() => _StartGateState();
}

class _StartGateState extends State<StartGate> {
  ImageStream? _stream;
  late final ImageStreamListener _listener = ImageStreamListener(_onFrame, onError: (_, __) => _roundDone());
  Timer? _limit;
  int _frames = 0;
  bool _leaving = AppStart.isOpen;
  bool _gone = AppStart.isOpen;

  @override
  void initState() {
    super.initState();
    if (!_gone) _limit = Timer(widget.maxWait, _leave);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_gone || _stream != null) return;
    // Same stream as the Image widget below, so we count exactly the frames on screen.
    _stream = const AssetImage(kLoaderAsset).resolve(createLocalImageConfiguration(context))..addListener(_listener);
  }

  void _onFrame(ImageInfo info, bool synchronous) {
    info.dispose();
    _frames++;
    // The frame after the last one is the first frame again: the round is complete.
    if (_frames > 1 && (_frames - 1) % kLoaderFrames == 0) _roundDone();
  }

  void _roundDone() {
    if (widget.ready && AppStart.canOpen()) _leave();
  }

  void _leave() {
    if (_leaving || !mounted || !widget.ready) return;
    _limit?.cancel();
    // May be called while a frame is being delivered: rebuild after it.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _leaving = true);
    });
    WidgetsBinding.instance.scheduleFrame();
  }

  @override
  void dispose() {
    _limit?.cancel();
    _stream?.removeListener(_listener);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(fit: StackFit.expand, children: [
      widget.child,
      if (!_gone)
        AnimatedOpacity(
          opacity: _leaving ? 0 : 1,
          duration: const Duration(milliseconds: 300),
          onEnd: () {
            _stream?.removeListener(_listener);
            setState(() => _gone = true);
            AppStart.open();
          },
          child: const AbsorbPointer(child: SplashLoader()),
        ),
    ]);
  }
}

/// The loader filling the screen. The square GIF sits in the middle and its own
/// blue gradient is continued behind it, so no edge is visible.
class SplashLoader extends StatelessWidget {
  const SplashLoader({super.key});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      final side = box.biggest.shortestSide;
      return CustomPaint(
        painter: _LoaderBackground(side),
        child: Center(child: Image.asset(kLoaderAsset, width: side, height: side, gaplessPlayback: true, errorBuilder: (_, __, ___) => const SizedBox())),
      );
    });
  }
}

class _LoaderBackground extends CustomPainter {
  _LoaderBackground(this.side);
  final double side;

  @override
  void paint(Canvas canvas, Size size) {
    final square = Rect.fromCenter(center: size.center(Offset.zero), width: side, height: side);
    canvas.drawRect(
      Offset.zero & size,
      Paint()..shader = ui.Gradient.linear(square.topLeft, square.bottomRight, const [Color(0xFF2D6AEF), Color(0xFF1F46C8)]),
    );
  }

  @override
  bool shouldRepaint(_LoaderBackground old) => old.side != side;
}

/// The same loader as a small rounded tile, for waiting inside the app.
class HbLoader extends StatelessWidget {
  const HbLoader({super.key, this.size = 84});
  final double size;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(size * 0.22),
        child: Image.asset(kLoaderAsset, width: size, height: size, gaplessPlayback: true, errorBuilder: (_, __, ___) => const CircularProgressIndicator()),
      ),
    );
  }
}
