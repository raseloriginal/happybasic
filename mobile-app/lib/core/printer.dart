import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:permission_handler/permission_handler.dart';
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';

import 'store.dart';

enum ReceiptStyle { normal, bold, title, small, rule }

class ReceiptLine {
  ReceiptLine(this.left, {this.right, this.style = ReceiptStyle.normal, this.center = false});
  final String left;
  final String? right;
  final ReceiptStyle style;
  final bool center;
  factory ReceiptLine.rule() => ReceiptLine('', style: ReceiptStyle.rule);
}

/// Bluetooth thermal printer (58 mm / 80 mm). Bengali is not in any ESC/POS code page, so the receipt is drawn
/// as a picture (the phone's own Bengali font) and printed as a raster image — it always looks right.
class PrinterService {
  static const _kMac = 'printer_mac';
  static const _kName = 'printer_name';
  static const _kWidth = 'printer_mm';

  static String? get savedMac => LocalStore.getString(_kMac);
  static String? get savedName => LocalStore.getString(_kName);
  static int get paperMm => int.tryParse(LocalStore.getString(_kWidth) ?? '') ?? 58;

  static Future<void> setPaper(int mm) => LocalStore.setString(_kWidth, '$mm');

  static Future<bool> _permissions() async {
    final r = await [Permission.bluetoothConnect, Permission.bluetoothScan].request();
    return r.values.every((s) => s.isGranted || s.isLimited);
  }

  static Future<List<BluetoothInfo>> pairedPrinters() async {
    if (!await _permissions()) return [];
    return PrintBluetoothThermal.pairedBluetooths;
  }

  static Future<bool> connect(String mac) async {
    if (!await _permissions()) return false;
    if (await PrintBluetoothThermal.connectionStatus) {
      await PrintBluetoothThermal.disconnect;
    }
    return PrintBluetoothThermal.connect(macPrinterAddress: mac);
  }

  static Future<void> remember(BluetoothInfo p) async {
    await LocalStore.setString(_kMac, p.macAdress);
    await LocalStore.setString(_kName, p.name);
  }

  /// Prints [lines]; connects to the remembered printer if needed. Returns an error text, or null on success.
  static Future<String?> print(List<ReceiptLine> lines) async {
    final mac = savedMac;
    if (mac == null) return 'আগে প্রোফাইল → ব্লুটুথ প্রিন্টার থেকে প্রিন্টার বাছুন।';
    if (!await _permissions()) return 'ব্লুটুথের অনুমতি দিন।';
    if (!await PrintBluetoothThermal.bluetoothEnabled) return 'ফোনের ব্লুটুথ চালু করুন।';
    if (!await PrintBluetoothThermal.connectionStatus) {
      if (!await PrintBluetoothThermal.connect(macPrinterAddress: mac)) {
        return 'প্রিন্টারের সাথে সংযোগ হয়নি। প্রিন্টার চালু ও কাছে আছে কিনা দেখুন।';
      }
    }
    final width = paperMm == 80 ? 576 : 384;
    final png = await _render(lines, width);
    final decoded = img.decodeImage(png);
    if (decoded == null) return 'রসিদ তৈরি করা যায়নি।';

    final profile = await CapabilityProfile.load();
    final gen = Generator(paperMm == 80 ? PaperSize.mm80 : PaperSize.mm58, profile);
    final bytes = <int>[
      ...gen.imageRaster(decoded, align: PosAlign.center),
      ...gen.feed(3),
      ...gen.cut(),
    ];
    final ok = await PrintBluetoothThermal.writeBytes(bytes);
    return ok ? null : 'প্রিন্ট পাঠানো যায়নি। আবার চেষ্টা করুন।';
  }

  static Future<Uint8List> _render(List<ReceiptLine> lines, int width) async {
    const pad = 8.0;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final w = width.toDouble();
    double y = pad;

    TextPainter tp(String t, double size, FontWeight weight, {TextAlign align = TextAlign.left, double? maxW}) {
      final p = TextPainter(
        text: TextSpan(text: t, style: TextStyle(color: Colors.black, fontSize: size, fontWeight: weight, height: 1.25)),
        textDirection: TextDirection.ltr,
        textAlign: align,
      )..layout(maxWidth: maxW ?? (w - pad * 2));
      return p;
    }

    final draws = <void Function()>[];
    for (final l in lines) {
      if (l.style == ReceiptStyle.rule) {
        final yy = y + 6;
        draws.add(() => canvas.drawLine(Offset(pad, yy), Offset(w - pad, yy), Paint()..color = Colors.black..strokeWidth = 1.5));
        y += 14;
        continue;
      }
      final size = switch (l.style) { ReceiptStyle.title => 30.0, ReceiptStyle.small => 18.0, _ => 22.0 };
      final weight = (l.style == ReceiptStyle.bold || l.style == ReceiptStyle.title) ? FontWeight.w800 : FontWeight.w500;
      if (l.right != null) {
        final r = tp(l.right!, size, weight, maxW: w * 0.4);
        final lt = tp(l.left, size, weight, maxW: w - pad * 2 - r.width - 8);
        final yy = y;
        draws.add(() {
          lt.paint(canvas, Offset(pad, yy));
          r.paint(canvas, Offset(w - pad - r.width, yy));
        });
        y += (lt.height > r.height ? lt.height : r.height) + 3;
      } else {
        final t = tp(l.left, size, weight, align: l.center ? TextAlign.center : TextAlign.left);
        final yy = y;
        draws.add(() => t.paint(canvas, Offset(l.center ? (w - t.width) / 2 : pad, yy)));
        y += t.height + 3;
      }
    }
    y += pad;

    canvas.drawRect(Rect.fromLTWH(0, 0, w, y), Paint()..color = Colors.white);
    for (final d in draws) {
      d();
    }
    final picture = recorder.endRecording();
    final image = await picture.toImage(width, y.ceil());
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    return data!.buffer.asUint8List();
  }
}
