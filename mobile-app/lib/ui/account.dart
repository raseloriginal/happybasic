import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../core/api.dart';
import '../core/offline.dart';
import '../core/session.dart';
import 'common.dart';
import 'printer_page.dart';

/// Password, photo, printer, sync and sign-out. Shared by SR, DSR and retailers.
class AccountCard extends StatelessWidget {
  const AccountCard({super.key, this.canChangePassword = true, this.canChangePhoto = false, this.onPhotoChanged});
  final bool canChangePassword;
  final bool canChangePhoto;
  final VoidCallback? onPhotoChanged;

  @override
  Widget build(BuildContext context) {
    final auth = context.read<AuthState>();
    return Card(
      child: Column(children: [
        if (canChangePhoto)
          ListTile(
            leading: const Icon(Icons.photo_camera_outlined),
            title: const Text('ছবি পরিবর্তন'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () async {
              final x = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 800, imageQuality: 85);
              if (x == null || !context.mounted) return;
              final r = await busy(context, () => ApiClient.upload('/${auth.role}/profile/photo', 'photo', File(x.path)));
              if (r != null && context.mounted) {
                toast(context, (r['message'] ?? 'ছবি সংরক্ষিত হয়েছে।').toString());
                await auth.refreshProfile();
                onPhotoChanged?.call();
              }
            },
          ),
        if (canChangePassword)
          ListTile(
            leading: const Icon(Icons.lock_outline),
            title: const Text('পাসওয়ার্ড পরিবর্তন'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ChangePasswordPage())),
          ),
        ListTile(
          leading: const Icon(Icons.print_outlined),
          title: const Text('ব্লুটুথ প্রিন্টার'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const PrinterPage())),
        ),
        ListTile(
          leading: const Icon(Icons.sync),
          title: const Text('সিঙ্ক অবস্থা'),
          subtitle: ListenableBuilder(
            listenable: OfflineQueue.instance,
            builder: (_, __) => Text(OfflineQueue.instance.ops.isEmpty ? 'সব সিঙ্ক হয়েছে' : '${OfflineQueue.instance.ops.length}টি বাকি'),
          ),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const PendingPage())),
        ),
        ListTile(
          leading: const Icon(Icons.info_outline),
          title: const Text('অ্যাপ সংস্করণ'),
          subtitle: Text('${ApiClient.versionName} (${ApiClient.buildNumber})'),
        ),
        ListTile(
          leading: const Icon(Icons.logout, color: kDanger),
          title: const Text('লগআউট', style: TextStyle(color: kDanger)),
          onTap: () async {
            final q = OfflineQueue.instance.ops.length;
            if (await confirm(context, 'লগআউট করবেন?',
                body: q > 0 ? 'এখনো $qটি কাজ সিঙ্ক হয়নি। লগআউট করলে সেগুলো মুছে যাবে।' : null, danger: true, yes: 'লগআউট')) {
              await auth.logout();
            }
          },
        ),
      ]),
    );
  }
}

class ChangePasswordPage extends StatefulWidget {
  const ChangePasswordPage({super.key});
  @override
  State<ChangePasswordPage> createState() => _ChangePasswordPageState();
}

class _ChangePasswordPageState extends State<ChangePasswordPage> {
  final _cur = TextEditingController();
  final _new = TextEditingController();
  final _again = TextEditingController();

  Future<void> _save() async {
    final r = await busy(context, () => ApiClient.send('POST', '/auth/password', body: {
          'current_password': _cur.text,
          'password': _new.text,
          'password_confirmation': _again.text,
        }));
    if (r != null && mounted) {
      toast(context, (r['message'] ?? 'পাসওয়ার্ড পরিবর্তন হয়েছে।').toString());
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('পাসওয়ার্ড পরিবর্তন')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        TextField(controller: _cur, obscureText: true, decoration: const InputDecoration(labelText: 'বর্তমান পাসওয়ার্ড')),
        const SizedBox(height: 12),
        TextField(controller: _new, obscureText: true, decoration: const InputDecoration(labelText: 'নতুন পাসওয়ার্ড (কমপক্ষে ৬ অক্ষর)')),
        const SizedBox(height: 12),
        TextField(controller: _again, obscureText: true, decoration: const InputDecoration(labelText: 'নতুন পাসওয়ার্ড আবার')),
        const SizedBox(height: 20),
        FilledButton(onPressed: _save, child: const Text('সংরক্ষণ করুন')),
      ]),
    );
  }
}
