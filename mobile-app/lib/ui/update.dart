import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/api.dart';
import 'common.dart';

/// Shown when the server refuses this build (APP_MIN_VERSION_CODE).
class UpdateRequiredPage extends StatelessWidget {
  const UpdateRequiredPage({super.key, required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            const Icon(Icons.system_update, size: 72, color: kBlue),
            const SizedBox(height: 18),
            const Text('অ্যাপ আপডেট দরকার', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
            const SizedBox(height: 10),
            Text(message, textAlign: TextAlign.center, style: const TextStyle(color: kMuted)),
            const SizedBox(height: 26),
            FilledButton(
              onPressed: () => launchUrl(Uri.parse('${ApiClient.base}/app'), mode: LaunchMode.externalApplication),
              child: const Text('নতুন অ্যাপ ডাউনলোড করুন'),
            ),
          ]),
        ),
      ),
    );
  }
}

/// Soft update prompt: asks the server for the newest build once after sign-in.
class UpdateChecker {
  static bool _done = false;

  static Future<void> check(BuildContext context) async {
    if (_done) return;
    _done = true;
    try {
      final r = await ApiClient.get('/app/version', query: {'code': ApiClient.buildNumber});
      if (r['update'] != true || !context.mounted) return;
      final force = r['force'] == true;
      await showDialog<void>(
        context: context,
        barrierDismissible: !force,
        builder: (c) => PopScope(
          canPop: !force,
          child: AlertDialog(
            title: Text('নতুন সংস্করণ ${r['version_name']}'),
            content: Text((r['notes'] ?? 'অ্যাপের নতুন সংস্করণ এসেছে।').toString()),
            actions: [
              if (!force) TextButton(onPressed: () => Navigator.pop(c), child: const Text('পরে')),
              FilledButton(
                style: FilledButton.styleFrom(minimumSize: const Size(110, 42)),
                onPressed: () => launchUrl(Uri.parse((r['url'] ?? '${ApiClient.base}/app').toString()), mode: LaunchMode.externalApplication),
                child: const Text('আপডেট'),
              ),
            ],
          ),
        ),
      );
    } catch (_) {/* offline: skip */}
  }
}
