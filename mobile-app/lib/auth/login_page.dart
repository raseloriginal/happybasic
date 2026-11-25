import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/api.dart';
import '../core/config.dart';
import '../core/session.dart';
import '../ui/common.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});
  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _phone = TextEditingController();
  final _pass = TextEditingController();
  bool _busy = false;
  bool _show = false;
  String? _error;
  int _taps = 0;

  @override
  void dispose() {
    _phone.dispose();
    _pass.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_phone.text.trim().isEmpty || _pass.text.isEmpty) {
      setState(() => _error = 'ফোন নম্বর ও পাসওয়ার্ড দিন।');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await context.read<AuthState>().login(_phone.text.trim(), _pass.text);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Tap the logo 7 times: set the server address (for testing / a new domain).
  Future<void> _serverDialog() async {
    final c = TextEditingController(text: ApiClient.base);
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('সার্ভার ঠিকানা'),
        content: TextField(controller: c, keyboardType: TextInputType.url, decoration: const InputDecoration(hintText: 'https://example.com')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('বাতিল')),
          FilledButton(style: FilledButton.styleFrom(minimumSize: const Size(90, 42)), onPressed: () => Navigator.pop(d, true), child: const Text('সংরক্ষণ')),
        ],
      ),
    );
    if (ok == true) {
      await ApiClient.setBase(c.text);
      if (mounted) toast(context, 'সার্ভার: ${ApiClient.base}');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(children: [
                GestureDetector(
                  onTap: () {
                    if (++_taps >= 7) {
                      _taps = 0;
                      _serverDialog();
                    }
                  },
                  child: Container(
                    width: 84, height: 84,
                    decoration: BoxDecoration(color: kBlue, borderRadius: BorderRadius.circular(24)),
                    child: const Icon(Icons.storefront, color: Colors.white, size: 44),
                  ),
                ),
                const SizedBox(height: 18),
                const Text(AppConfig.appName, style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                const Text('আপনার ফোন নম্বর ও পাসওয়ার্ড দিয়ে লগইন করুন', textAlign: TextAlign.center, style: TextStyle(color: kMuted)),
                const SizedBox(height: 28),
                TextField(
                  controller: _phone,
                  keyboardType: TextInputType.phone,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(labelText: 'ফোন নম্বর', prefixIcon: Icon(Icons.phone_outlined)),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _pass,
                  obscureText: !_show,
                  onSubmitted: (_) => _submit(),
                  decoration: InputDecoration(
                    labelText: 'পাসওয়ার্ড',
                    prefixIcon: const Icon(Icons.lock_outline),
                    suffixIcon: IconButton(icon: Icon(_show ? Icons.visibility_off : Icons.visibility), onPressed: () => setState(() => _show = !_show)),
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity, padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: const Color(0xFFFEF2F2), borderRadius: BorderRadius.circular(10)),
                    child: Text(_error!, style: const TextStyle(color: kDanger)),
                  ),
                ],
                const SizedBox(height: 22),
                FilledButton(
                  onPressed: _busy ? null : _submit,
                  child: _busy ? const SizedBox(height: 22, width: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white)) : const Text('লগইন'),
                ),
                const SizedBox(height: 18),
                const Text('দোকান মালিক: আপনার দোকানের ফোন নম্বরই পাসওয়ার্ড।', textAlign: TextAlign.center, style: TextStyle(color: kMuted, fontSize: 12.5)),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
