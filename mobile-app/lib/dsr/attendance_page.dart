import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../core/api.dart';
import '../core/format.dart';
import '../core/tracker.dart';
import '../ui/common.dart';

Map<String, dynamic> _m(Object? v) => Map<String, dynamic>.from((v ?? {}) as Map);

/// Arrival attendance: scan the partner's godown QR; the phone's location is checked against the godown.
class AttendancePage extends StatefulWidget {
  const AttendancePage({super.key});
  @override
  State<AttendancePage> createState() => _AttendancePageState();
}

class _AttendancePageState extends State<AttendancePage> {
  final MobileScannerController _cam = MobileScannerController(formats: const [BarcodeFormat.qrCode]);
  final GlobalKey<AsyncBodyState> _body = GlobalKey();
  bool _scanning = false;
  bool _handling = false;

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
      _body.currentState?.reload();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('হাজিরা')),
      body: _scanning
          ? Stack(children: [
              MobileScanner(controller: _cam, onDetect: _onScan),
              Center(child: Container(width: 250, height: 250, decoration: BoxDecoration(border: Border.all(color: Colors.white, width: 3), borderRadius: BorderRadius.circular(20)))),
              Positioned(
                left: 0, right: 0, bottom: 40,
                child: Column(children: [
                  const Text('গোডাউনের QR কোড ফ্রেমে ধরুন', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 14),
                  FilledButton(style: FilledButton.styleFrom(minimumSize: const Size(140, 44)), onPressed: () => setState(() => _scanning = false), child: const Text('বন্ধ করুন')),
                ]),
              ),
            ])
          : AsyncBody(
              key: _body,
              load: () => loadCached('dsr_attendance', () => ApiClient.get('/dsr/attendance')),
              builder: (context, d, reload) {
                final today = d['today'] == null ? null : _m(d['today']);
                final days = (d['days'] as List).map(_m).toList();
                return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(18),
                      child: Column(children: [
                        Icon(today == null ? Icons.qr_code_scanner : Icons.verified, size: 54, color: today == null ? kBlue : kOk),
                        const SizedBox(height: 10),
                        Text(today == null ? 'আজকের হাজিরা বাকি' : 'আজকের হাজিরা সম্পন্ন', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                        if (today != null) Text('${timeBn(today['checked_in_at']?.toString())}${int0(today['late_min']) > 0 ? ' · ${bn(today['late_min'])} মিনিট দেরি' : ''}', style: const TextStyle(color: kMuted)),
                        const SizedBox(height: 14),
                        if (today == null)
                          FilledButton.icon(onPressed: () => setState(() => _scanning = true), icon: const Icon(Icons.qr_code_scanner), label: const Text('QR স্ক্যান করুন')),
                      ]),
                    ),
                  ),
                  SectionTitle('${dateBn(d['selectedDate']?.toString())} মাসের হাজিরা'),
                  for (final x in days.reversed)
                    Card(
                      margin: const EdgeInsets.only(bottom: 6),
                      child: ListTile(
                        dense: true,
                        leading: Text(bn(x['day']), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                        title: Text(switch (x['status']) { 'present' => 'উপস্থিত', 'absent' => 'অনুপস্থিত', 'half' => 'অর্ধদিবস', 'holiday' => 'ছুটি', _ => '${x['status']}' }),
                        subtitle: x['time'] == null ? null : Text('${timeBn(x['time']?.toString())}${int0(x['late_min']) > 0 ? ' · ${bn(x['late_min'])} মিনিট দেরি' : ''}'),
                        trailing: Icon(x['status'] == 'present' ? Icons.check_circle : Icons.cancel, color: x['status'] == 'present' ? kOk : kDanger, size: 20),
                      ),
                    ),
                ]);
              },
            ),
    );
  }
}
