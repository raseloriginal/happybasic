import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/api.dart';
import '../core/format.dart';
import '../core/offline.dart';
import '../core/realtime.dart';
import '../core/store.dart';
import 'dkit.dart';
import 'hkit.dart';
import 'loader.dart';
import 'motion.dart';

const kBlue = Color(0xFF1F4FE0);
const kInk = Color(0xFF0A1640);
const kMuted = Color(0xFF5B6785);
const kBg = Color(0xFFF4F6FB);
const kOk = Color(0xFF15803D);
const kWarn = Color(0xFFD97706);
const kDanger = Color(0xFFDC2626);
const kBorder = Color(0xFFE6EAF2);

/// App theme: one design ("Happy অ্যাপ ডিজাইন") for every role — navy ink, blue accent, Hind Siliguri.
ThemeData buildTheme({String? role}) {
  const accent = Color(0xFF1F4FE0);
  const ink = Color(0xFF0A1640);
  const line = Color(0xFFE6EAF2);
  const strong = Color(0xFFD5DCEB);
  final scheme = ColorScheme.fromSeed(seedColor: accent, primary: accent, surface: Colors.white, onSurface: ink);
  OutlineInputBorder ob(Color c, [double w = 1.5]) => OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: c, width: w));
  final base = ThemeData(useMaterial3: true, fontFamily: 'HindSiliguri', fontFamilyFallback: const ['Inter'], colorScheme: scheme);
  return base.copyWith(
    scaffoldBackgroundColor: const Color(0xFFF4F6FB),
    textTheme: base.textTheme.apply(bodyColor: ink, displayColor: ink),
    pageTransitionsTheme: const PageTransitionsTheme(builders: {
      TargetPlatform.android: CupertinoPageTransitionsBuilder(),
      TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
    }),
    appBarTheme: const AppBarTheme(
      backgroundColor: Color(0xFFF4F6FB), foregroundColor: ink, elevation: 0, scrolledUnderElevation: 0, centerTitle: false, toolbarHeight: 56,
      titleTextStyle: TextStyle(fontFamily: 'HindSiliguri', color: ink, fontSize: 18, fontWeight: FontWeight.w700),
    ),
    cardTheme: CardThemeData(
      color: Colors.white, elevation: 0, margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: const BorderSide(color: line)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true, fillColor: Colors.white,
      border: ob(strong), enabledBorder: ob(strong), focusedBorder: ob(accent),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      hintStyle: const TextStyle(color: Color(0xFF9AA4BE)),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: ink, foregroundColor: Colors.white,
        minimumSize: const Size.fromHeight(52), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        textStyle: const TextStyle(fontFamily: 'HindSiliguri', fontSize: 15, fontWeight: FontWeight.w700),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(50), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        side: const BorderSide(color: strong, width: 1.5), foregroundColor: ink,
        textStyle: const TextStyle(fontFamily: 'HindSiliguri', fontSize: 15, fontWeight: FontWeight.w700),
      ),
    ),
    textButtonTheme: TextButtonThemeData(style: TextButton.styleFrom(foregroundColor: accent, textStyle: const TextStyle(fontFamily: 'HindSiliguri', fontWeight: FontWeight.w700))),
    dialogTheme: DialogThemeData(
      backgroundColor: Colors.white, surfaceTintColor: Colors.transparent, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      titleTextStyle: const TextStyle(fontFamily: 'HindSiliguri', color: ink, fontSize: 18, fontWeight: FontWeight.w700),
      contentTextStyle: const TextStyle(fontFamily: 'HindSiliguri', color: Color(0xFF475273), fontSize: 14, height: 1.45),
    ),
    bottomSheetTheme: const BottomSheetThemeData(backgroundColor: Colors.white, surfaceTintColor: Colors.transparent, showDragHandle: false),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: ink, behavior: SnackBarBehavior.floating, insetPadding: const EdgeInsets.fromLTRB(16, 0, 16, 90),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      contentTextStyle: const TextStyle(fontFamily: 'HindSiliguri', color: Colors.white, fontSize: 14, fontWeight: FontWeight.w500),
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(color: accent),
    dividerTheme: const DividerThemeData(color: line, thickness: 1, space: 1),
    datePickerTheme: DatePickerThemeData(backgroundColor: Colors.white, surfaceTintColor: Colors.transparent, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24))),
  );
}

void toast(BuildContext context, String message, {bool error = false}) {
  final m = ScaffoldMessenger.of(context);
  m.hideCurrentSnackBar();
  m.showSnackBar(SnackBar(
    content: Text(message), behavior: SnackBarBehavior.floating, backgroundColor: error ? const Color(0xFFD92D20) : const Color(0xFF0A1640),
    duration: Duration(seconds: error ? 4 : 2),
  ));
}

/// Type a count instead of tapping +/− (long counts are faster to type).
Future<int?> askNumber(BuildContext context, String title, int value) async {
  final c = TextEditingController(text: value == 0 ? '' : '$value');
  final r = await showHSheet<int>(
    context,
    builder: (ctx) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(title, style: hs(17, w: w7)),
      const SizedBox(height: 14),
      TextField(
        controller: c, autofocus: true, keyboardType: TextInputType.number, textAlign: TextAlign.center,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly], style: hs(26, w: w8, num: true),
        onSubmitted: (v) => Navigator.pop(ctx, int.tryParse(v) ?? 0),
      ),
      const SizedBox(height: 14),
      Row(children: [
        Expanded(child: HBtn('বাতিল', kind: HBtnKind.line, onTap: () => Navigator.pop(ctx))),
        const SizedBox(width: 10),
        Expanded(child: HBtn('ঠিক আছে', onTap: () => Navigator.pop(ctx, int.tryParse(c.text) ?? 0))),
      ]),
    ]),
  );
  c.dispose();
  return r;
}

Future<bool> confirm(BuildContext context, String title, {String? body, String yes = 'হ্যাঁ', bool danger = false}) async {
  final r = await showHSheet<bool>(
    context,
    builder: (c) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(title, style: hs(18, w: w7)),
      if (body != null) ...[const SizedBox(height: 6), Text(body, style: hs(14, color: HC.muted))],
      const SizedBox(height: 18),
      Row(children: [
        Expanded(child: HBtn('না', kind: HBtnKind.line, onTap: () => Navigator.pop(c, false))),
        const SizedBox(width: 10),
        Expanded(child: HBtn(yes, kind: danger ? HBtnKind.danger : HBtnKind.dark, onTap: () => Navigator.pop(c, true))),
      ]),
    ]),
  );
  return r ?? false;
}

/// Runs [task] with a blocking spinner, shows API errors as a toast. Returns null on failure.
Future<T?> busy<T>(BuildContext context, Future<T> Function() task) async {
  showDialog(context: context, barrierDismissible: false, builder: (_) => const HbLoader());
  try {
    return await task();
  } on ApiException catch (e) {
    if (context.mounted) toast(context, e.message, error: true);
    return null;
  } catch (_) {
    // Anything unexpected (bad data, plugin error): never leave the user with a stuck spinner or a crash.
    if (context.mounted) toast(context, 'কিছু একটা সমস্যা হয়েছে। আবার চেষ্টা করুন।', error: true);
    return null;
  } finally {
    if (context.mounted) Navigator.of(context, rootNavigator: true).pop();
  }
}

class Loaded {
  Loaded(this.data, {this.stale = false});
  final Map<String, dynamic> data;
  final bool stale; // true when shown from the phone's cache (offline)
}

/// Network first, cached copy when offline.
Future<Loaded> loadCached(String key, Future<Map<String, dynamic>> Function() net) async {
  try {
    final d = await net();
    await LocalStore.writeJson('c_$key', d);
    return Loaded(d);
  } on ApiException catch (e) {
    if (!e.network) rethrow;
    final c = await LocalStore.readJson('c_$key');
    if (c is Map) return Loaded(Map<String, dynamic>.from(c), stale: true);
    rethrow;
  }
}

/// Page body that loads data, supports pull-to-refresh, reloads after the offline queue syncs.
class AsyncBody extends StatefulWidget {
  const AsyncBody({super.key, required this.load, required this.builder, this.padding = const EdgeInsets.fromLTRB(14, 12, 14, 24), this.sky = false, this.bottom = 24});
  final Future<Loaded> Function() load;
  final Widget Function(BuildContext, Map<String, dynamic> data, VoidCallback reload) builder;
  final EdgeInsets padding;
  /// Design pages with a sky header: 18px sides, status-bar aware top; the offline note is a glass pill on the sky.
  final bool sky;
  final double bottom;
  @override
  State<AsyncBody> createState() => AsyncBodyState();
}

class AsyncBodyState extends State<AsyncBody> {
  Loaded? _data;
  Object? _error;
  bool _loading = true;
  StreamSubscription? _sync;
  StreamSubscription? _live;

  @override
  void initState() {
    super.initState();
    // The start-up loader stays until this first load has finished (or failed).
    AppStart.pending++;
    _run().whenComplete(() => AppStart.pending--);
    _sync = OfflineQueue.instance.onSynced.listen((_) => _run(silent: true));
    // Live events (new order, delivery done...), app resume and the 1-minute fallback refresh the screen quietly.
    _live = Realtime.instance.events.listen((_) => _run(silent: true));
  }

  @override
  void dispose() {
    _sync?.cancel();
    _live?.cancel();
    super.dispose();
  }

  Future<void> _run({bool silent = false}) async {
    if (!silent) setState(() => _loading = _data == null);
    try {
      final d = await widget.load();
      if (!mounted) return;
      setState(() {
        _data = d;
        _error = null;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  void reload() => _run(silent: true);

  /// Was the data shown from the phone's cache (no internet)?
  bool get stale => _data?.stale ?? false;

  @override
  Widget build(BuildContext context) {
    if (_loading) return widget.sky ? const SkySkeleton() : const PageSkeleton(sky: false);
    if (_data == null) {
      return ListView(padding: widget.padding, children: [
        const SizedBox(height: 80),
        const Icon(Icons.cloud_off, size: 56, color: kMuted),
        const SizedBox(height: 12),
        Text(_error is ApiException ? (_error as ApiException).message : 'লোড করা যায়নি।', textAlign: TextAlign.center),
        const SizedBox(height: 16),
        Center(child: OutlinedButton(style: OutlinedButton.styleFrom(minimumSize: const Size(140, 44)), onPressed: _run, child: const Text('আবার চেষ্টা'))),
      ]);
    }
    final top = MediaQuery.of(context).padding.top;
    final pad = widget.sky ? EdgeInsets.fromLTRB(18, top + 14, 18, widget.bottom) : widget.padding;
    final list = RefreshIndicator(
      color: kBlue,
      edgeOffset: widget.sky ? top : 0,
      onRefresh: () => _run(silent: true),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
        padding: pad,
        children: [
          if (_data!.stale && !widget.sky) const OfflineBanner(),
          Appear(child: widget.builder(context, _data!.data, reload)),
        ],
      ),
    );
    if (!widget.sky || !_data!.stale) return list;
    // Offline: a small floating note instead of a banner over the sky header.
    return Stack(children: [
      list,
      Positioned(
        left: 0, right: 0, bottom: 12,
        child: Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(color: const Color(0xF00A1640), borderRadius: BorderRadius.circular(999),
                boxShadow: const [BoxShadow(color: Color(0x330A1640), blurRadius: 16, offset: Offset(0, 6))]),
            child: const Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.wifi_off_rounded, size: 16, color: Color(0xFFA9C4FF)),
              SizedBox(width: 8),
              Text('অফলাইন · সংরক্ষিত তথ্য দেখানো হচ্ছে', style: TextStyle(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w600)),
            ]),
          ),
        ),
      ),
    ]);
  }
}

/// Picture from the server, kept on the phone after the first load (works offline).
class NetImage extends StatelessWidget {
  const NetImage(this.url, {super.key, this.fallback, this.fit = BoxFit.cover});
  final String? url;
  final Widget? fallback;
  final BoxFit fit;
  @override
  Widget build(BuildContext context) {
    final f = fallback ?? const SizedBox.shrink();
    if (url == null) return f;
    return CachedNetworkImage(imageUrl: url!, fit: fit, placeholder: (_, __) => f, errorWidget: (_, __, ___) => f, fadeInDuration: Duration.zero);
  }
}

class OfflineBanner extends StatelessWidget {
  const OfflineBanner({super.key});
  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(color: const Color(0xFFFEF3C7), borderRadius: BorderRadius.circular(10)),
        child: const Row(children: [
          Icon(Icons.wifi_off, size: 18, color: Color(0xFFB45309)),
          SizedBox(width: 8),
          Expanded(child: Text('ইন্টারনেট নেই — সর্বশেষ সংরক্ষিত তথ্য দেখানো হচ্ছে।', style: TextStyle(color: Color(0xFFB45309), fontSize: 13))),
        ]),
      );
}

/// Shows how many writes are waiting to sync (tap to sync now).
class SyncChip extends StatelessWidget {
  const SyncChip({super.key});
  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: OfflineQueue.instance,
      builder: (context, _) {
        final q = OfflineQueue.instance;
        if (q.ops.isEmpty) return const SizedBox.shrink();
        return InkWell(
          onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const PendingPage())),
          child: Container(
            margin: const EdgeInsets.only(right: 8),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(color: q.failed > 0 ? const Color(0xFFFEF2F2) : const Color(0xFFFEF3C7), borderRadius: BorderRadius.circular(20)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              q.flushing
                  ? const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2))
                  : Icon(q.failed > 0 ? Icons.error_outline : Icons.sync, size: 16, color: q.failed > 0 ? kDanger : kWarn),
              const SizedBox(width: 5),
              Text('${bn(q.ops.length)}টি বাকি', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: q.failed > 0 ? kDanger : kWarn)),
            ]),
          ),
        );
      },
    );
  }
}

class PendingPage extends StatelessWidget {
  const PendingPage({super.key});
  @override
  Widget build(BuildContext context) {
    return DPage(
      title: 'সিঙ্ক বাকি',
      child: ListenableBuilder(
        listenable: OfflineQueue.instance,
        builder: (context, _) {
          final ops = OfflineQueue.instance.ops;
          if (ops.isEmpty) return const Center(child: Text('সব সিঙ্ক হয়ে গেছে ✓'));
          return ListView(padding: const EdgeInsets.all(14), children: [
            FilledButton.icon(
              onPressed: OfflineQueue.instance.flushing ? null : OfflineQueue.instance.flush,
              icon: const Icon(Icons.sync), label: const Text('এখনই সিঙ্ক করুন')),
            const SizedBox(height: 12),
            for (final o in ops)
              Card(
                child: ListTile(
                  title: Text(o.label),
                  subtitle: Text(o.error ?? 'ইন্টারনেট এলে পাঠানো হবে', style: TextStyle(color: o.error != null ? kDanger : kMuted)),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () async {
                      if (await confirm(context, 'এটি মুছে ফেলবেন?', body: 'এই কাজটি সার্ভারে যাবে না।', danger: true, yes: 'মুছুন')) {
                        OfflineQueue.instance.discard(o.id);
                      }
                    },
                  ),
                ),
              ),
          ]);
        },
      ),
    );
  }
}

class Pill extends StatelessWidget {
  const Pill(this.text, {super.key, this.color = kBlue});
  final String text;
  final Color color;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
        child: Text(text, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w700)),
      );
}

class StatTile extends StatelessWidget {
  const StatTile(this.label, this.value, {super.key, this.color = kInk, this.icon});
  final String label;
  final String value;
  final Color color;
  final IconData? icon;
  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              if (icon != null) ...[Icon(icon, size: 16, color: kMuted), const SizedBox(width: 5)],
              Expanded(child: Text(label, style: const TextStyle(color: kMuted, fontSize: 12.5), overflow: TextOverflow.ellipsis)),
            ]),
            const SizedBox(height: 6),
            FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text(value, style: TextStyle(fontSize: 21, fontWeight: FontWeight.w800, color: color))),
          ]),
        ),
      );
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key, this.trailing});
  final String text;
  final Widget? trailing;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(2, 18, 2, 8),
        child: Row(children: [
          Expanded(child: Text(text, style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w800, color: kInk))),
          if (trailing != null) trailing!,
        ]),
      );
}

/// < date > navigator used by history / delivery pages.
class DateBar extends StatelessWidget {
  const DateBar({super.key, required this.date, required this.onChange, this.maxToday = true});
  final String date;
  final ValueChanged<String> onChange;
  final bool maxToday;
  @override
  Widget build(BuildContext context) {
    final isToday = date == todayYmd();
    return Card(
      child: Row(children: [
        IconButton(icon: const Icon(Icons.chevron_left), onPressed: () => onChange(addDays(date, -1))),
        Expanded(
          child: InkWell(
            onTap: () async {
              final d = await showDatePicker(
                context: context, initialDate: DateTime.parse(date), firstDate: DateTime(2024), lastDate: DateTime.now().add(const Duration(days: 1)));
              if (d != null) onChange(ymd(d));
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Column(children: [
                Text(dateBn(date), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                Text(isToday ? 'আজ · ${weekdayBn(date)}' : weekdayBn(date), style: const TextStyle(color: kMuted, fontSize: 12)),
              ]),
            ),
          ),
        ),
        IconButton(icon: const Icon(Icons.chevron_right), onPressed: maxToday && isToday ? null : () => onChange(addDays(date, 1))),
      ]),
    );
  }
}

/// Numeric text field that accepts only digits (and optionally one dot).
class NumField extends StatelessWidget {
  const NumField({super.key, required this.controller, this.label, this.decimal = false, this.onChanged, this.width, this.dense = false});
  final TextEditingController controller;
  final String? label;
  final bool decimal;
  final ValueChanged<String>? onChanged;
  final double? width;
  final bool dense;
  @override
  Widget build(BuildContext context) {
    final f = TextField(
      controller: controller,
      keyboardType: TextInputType.numberWithOptions(decimal: decimal),
      inputFormatters: [FilteringTextInputFormatter.allow(decimal ? RegExp(r'[0-9.]') : RegExp(r'[0-9]'))],
      onChanged: onChanged,
      textAlign: dense ? TextAlign.center : TextAlign.start,
      decoration: InputDecoration(labelText: label, isDense: dense, contentPadding: dense ? const EdgeInsets.symmetric(vertical: 10, horizontal: 6) : null),
    );
    return width == null ? f : SizedBox(width: width, child: f);
  }
}
