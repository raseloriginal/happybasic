import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../core/tracker.dart';
import 'common.dart';

/// "Location tracking is on" strip for SR / DSR, with a fix button when it is off.
/// Some phones stop background apps to save battery — the button asks Android to exempt this app.
class TrackerBanner extends StatefulWidget {
  const TrackerBanner({super.key, required this.role});
  final String role;
  @override
  State<TrackerBanner> createState() => _TrackerBannerState();
}

class _TrackerBannerState extends State<TrackerBanner> {
  bool _batteryOk = true;

  @override
  void initState() {
    super.initState();
    Permission.ignoreBatteryOptimizations.isGranted.then((v) {
      if (mounted) setState(() => _batteryOk = v);
    });
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Tracker.instance,
      builder: (context, _) {
        final t = Tracker.instance;
        final ok = t.running && t.problem == null;
        if (ok && _batteryOk) return const SizedBox.shrink(); // all good: stay out of the way
        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(color: ok ? const Color(0xFFEAF0FF) : const Color(0xFFFDECEA), borderRadius: BorderRadius.circular(14),
              boxShadow: const [BoxShadow(color: Color(0x1A0A1640), blurRadius: 12, offset: Offset(0, 4))]),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(ok ? Icons.my_location : Icons.location_off, size: 20, color: ok ? kBlue : kDanger),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  ok ? 'লোকেশন ট্র্যাকিং চালু — পার্টনার আপনার অবস্থান দেখতে পাচ্ছেন।' : (t.problem ?? 'লোকেশন ট্র্যাকিং বন্ধ আছে।'),
                  style: TextStyle(fontSize: 13, color: ok ? kInk : kDanger),
                ),
              ),
              if (!ok) TextButton(onPressed: () => Tracker.instance.start(widget.role), child: const Text('চালু করুন')),
            ]),
            if (ok && !_batteryOk)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(0, 32)),
                  onPressed: () async {
                    final r = await Permission.ignoreBatteryOptimizations.request();
                    if (mounted) setState(() => _batteryOk = r.isGranted);
                  },
                  icon: const Icon(Icons.battery_alert, size: 16),
                  label: const Text('স্ক্রিন বন্ধ থাকলেও ট্র্যাকিং চালু রাখুন', style: TextStyle(fontSize: 12.5)),
                ),
              ),
          ]),
        );
      },
    );
  }
}
