import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:happy_bangladesh/ui/loader.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(AppStart.reset);

  testWidgets('loader GIF has the frame count the gate relies on', (tester) async {
    await tester.runAsync(() async {
      final data = await rootBundle.load(kLoaderAsset);
      final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
      expect(codec.frameCount, kLoaderFrames);
      codec.dispose();
    });
  });

  test('stays closed while the first screen is still loading', () {
    AppStart.pending = 2;
    expect(AppStart.canOpen(), isFalse);
    AppStart.pending = 0;
    expect(AppStart.canOpen(), isTrue);
  });

  testWidgets('a stuck load never locks the user out', (tester) async {
    AppStart.pending = 1;
    await tester.pumpWidget(const MaterialApp(home: StartGate(ready: true, maxWait: Duration(seconds: 3), child: Text('হোম'))));
    expect(find.byType(SplashLoader), findsOneWidget);
    expect(AppStart.isOpen, isFalse);
    await tester.pump(const Duration(seconds: 3));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
    expect(find.byType(SplashLoader), findsNothing);
    expect(AppStart.isOpen, isTrue);
  });
}
