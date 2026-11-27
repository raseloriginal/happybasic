import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../core/api.dart';
import '../core/format.dart';
import '../core/tracker.dart';
import '../ui/common.dart';
import '../ui/dkit.dart';
import '../ui/pwa_kit.dart';

Map<String, dynamic> _m(Object? v) => Map<String, dynamic>.from((v ?? {}) as Map);

/// Arrival attendance: scan the partner's godown QR; the phone's location is checked against the godown.
class AttendancePage extends StatefulWidget {
  const AttendancePage({super.key, this.scan = false});
  /// Open straight into the QR scanner and close after a successful check-in.
  final bool scan;
  @override
  State<AttendancePage> createState() => _AttendancePageState();
}

class _AttendancePageState extends State<AttendancePage> {
  final MobileScannerController _cam = MobileScannerController(formats: const [BarcodeFormat.qrCode]);
  final GlobalKey<AsyncBodyState> _body = GlobalKey();
  late bool _scanning = widget.scan;
  bool _handling = false;
  String? _date;

  @override
  void dispose() {
    _cam.dispose();
    super.dispose();
  }

  /// The QR holds a link like https://host/dsr/attendance?t=TOKEN, or the bare token.
  String? _tokenOf(String raw) {
    final uri = Uri.tryParse(raw);
    final t = uri?.queryParameters['t'] ?? raw.trim();
    return RegExp(r'^[a-f0-9]{16,64}$').hasMatch(t) ? t : null;
  }

  Future<void> _onScan(BarcodeCapture cap) async {
    if (_handling) return;
    final raw = cap.barcodes.map((b) => b.rawValue).whereType<String>().firstOrNull;
    if (raw == null) return;
    final token = _tokenOf(raw);
    if (token == null) return;
    _handling = true;
    setState(() => _scanning = false);
    final r = await busy(context, () async {
      final pos = await Tracker.currentOnce();
      return ApiClient.send('POST', '/dsr/attendance', opId: ApiClient.newOpId(), body: {
        'token': token,
        'lat': pos?.latitude,
        'lng': pos?.longitude,
        'accuracy': pos?.accuracy,
      });
    });
    _handling = false;
    if (r != null && mounted) {
      toast(context, (r['message'] ?? 'হাজিরা সম্পন্ন।').toString());
      if (widget.scan) {
        Navigator.pop(context, true);
        return;
      }
      _body.currentState?.reload();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_scanning) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: Stack(children: [
          MobileScanner(controller: _cam, onDetect: _onScan),
          Center(child: Container(width: 250, height: 250, decoration: BoxDecoration(border: Border.all(color: Colors.white, width: 3), borderRadius: BorderRadius.circular(20)))),
          Positioned(
            left: 0, right: 0, bottom: 40,
            child: Column(children: [
              Text('গোডাউনের QR কোড ফ্রেমে ধরুন', style: ts(15, w: FontWeight.w700, color: Colors.white)),
              const SizedBox(height: 14),
              SizedBox(width: 140, child: DBtn('বন্ধ করুন', kind: DBtnKind.secondary, height: 44, block: true, onTap: () => widget.scan ? Navigator.pop(context) : setState(() => _scanning = false))),
            ]),
          ),
        ]),
      );
    }
    return DPage(
      title: 'হাজিরা',
      child: AsyncBody(
        key: _body,
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 20),
        load: () => loadCached('dsr_attendance_${_date ?? 'today'}', () => ApiClient.get('/dsr/attendance', query: {'date': _date})),
        builder: (context, d, reload) {
          final today = d['today'] == null ? null : _m(d['today']);
          final days = (d['days'] as List).map(_m).toList();
          final selected = d['selectedDate']?.toString() ?? todayYmd();
          final isToday = d['is_today'] != false;
          final late = today != null && int0(today['late_min']) > 0;
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            DDateNav(date: selected, onChange: (v) => setState(() => _date = v == todayYmd() ? null : v)),
            const SizedBox(height: 14),
            DCard(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                if (today != null) ...[
                  DBadge('${isToday ? 'আজকের' : '${dateBn(selected)}-এর'} হাজিরা সম্পন্ন', tone: late ? DTone.warning : DTone.success),
                  const SizedBox(height: 6),
                  Text(timeBn(today['checked_in_at']?.toString()), style: ts(24, w: FontWeight.w700, tabular: true)),
                  const SizedBox(height: 6),
                  Text(late ? '${bn(today['late_min'])} মিনিট দেরি' : 'সময়মতো', style: ts(12, color: DC.muted)),
                ] else ...[
                  DBadge(isToday ? 'আজ এখনো হাজিরা হয়নি' : 'এই দিনে হাজিরা নেই'),
                  if (isToday) ...[
                    const SizedBox(height: 6),
                    Text('গোডাউনের QR স্ক্যান করুন', style: ts(24, w: FontWeight.w700)),
                    const SizedBox(height: 6),
                    Text('গোডাউনে পৌঁছে ফোনের লোকেশন চালু রেখে স্ক্যান করুন।', style: ts(12, color: DC.muted)),
                  ],
                ],
              ]),
            ),
            if (today == null && isToday) ...[
              const SizedBox(height: 14),
              DCard(
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  DBtn('QR স্ক্যান করুন', block: true, height: 44, onTap: () => setState(() => _scanning = true)),
                ]),
              ),
            ],
            const SizedBox(height: 14),
            DCard(
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                const DSecTitle('এই মাসের হাজিরা'),
                const SizedBox(height: 8),
                for (final x in days.reversed) _Day(x),
              ]),
            ),
          ]);
        },
      ),
    );
  }
}

class _Day extends StatelessWidget {
  const _Day(this.x);
  final Map<String, dynamic> x;
  @override
  Widget build(BuildContext context) {
    final st = '${x['status']}';
    final lateMin = int0(x['late_min']);
    final label = switch (st) {
      'present' => x['time'] != null ? '${timeBn(x['time'].toString())}${lateMin > 0 ? ' · দেরি ${bn(lateMin)} মি.' : ''}' : 'উপস্থিত',
      'half' => 'হাফ ডে',
      'holiday' => 'ছুটি',
      'pending' => 'আজ বাকি',
      _ => 'অনুপস্থিত',
    };
    final bg = st == 'present' ? (lateMin > 0 ? const Color(0xFFFFF4D6) : const Color(0xFFE7F6EC)) : (st == 'half' ? const Color(0xFFFFF4D6) : const Color(0xFFF4F5F7));
    return Opacity(
      opacity: st == 'present' || st == 'half' ? 1 : 0.6,
      child: Container(
        margin: const EdgeInsets.only(bottom: 6), padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(8)),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(dateBn('${x['date'] ?? ''}'.isNotEmpty ? '${x['date']}' : null).replaceAll('—', bn(x['day'])), style: ts(13, tabular: true)),
          const SizedBox(width: 8),
          Flexible(child: Text(label, textAlign: TextAlign.right, style: ts(13, tabular: true))),
        ]),
      ),
    );
  }
}
