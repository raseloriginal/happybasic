import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/api.dart';
import '../core/session.dart';
import '../ui/common.dart';
import '../ui/hkit.dart';
import '../ui/pwa_kit.dart';

/// Login — same look as the PWA panel login (blue hero, white card, 52px inputs, gradient button).
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
      setState(() => _error = 'মোবাইল নম্বর ও পাসওয়ার্ড লিখুন।');
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

  InputDecoration _deco(String hint, {Widget? suffix}) {
    OutlineInputBorder b(Color c) => OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: c, width: 1.5));
    return InputDecoration(
      hintText: hint, hintStyle: hs(15, color: HC.faint),
      filled: true, fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
      enabledBorder: b(HC.line2), focusedBorder: b(HC.blue), border: b(HC.line2),
      suffixIcon: suffix,
    );
  }

  Widget _label(String t) => Padding(padding: const EdgeInsets.only(bottom: 6), child: Text(t, style: hs(13, w: w7, color: HC.ink2)));

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.of(context).padding.top;
    return SkyStatusBar(
      child: Scaffold(
        backgroundColor: HC.outer,
        body: Frame(
          color: HC.outer,
          child: ColoredBox(
            color: HC.bg,
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(18, top + 14, 18, 24 + MediaQuery.of(context).viewInsets.bottom),
              child: SkyBox(
                height: 300,
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  const SizedBox(height: 40),
                  Center(
                    child: GestureDetector(
                      onTap: () {
                        if (++_taps >= 7) {
                          _taps = 0;
                          _serverDialog();
                        }
                      },
                      child: Container(
                        width: 72, height: 72,
                        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 20, offset: Offset(0, 6))]),
                        clipBehavior: Clip.antiAlias,
                        child: Image.asset('assets/images/logo.jpg', fit: BoxFit.cover, errorBuilder: (_, __, ___) => const SizedBox()),
                      ),
                    ),
                  ),
                  gap12,
                  Text('Happy Bangladesh', textAlign: TextAlign.center, style: hs(24, w: w7, color: Colors.white)),
                  Text('SR · ডেলিভারি · দোকান', textAlign: TextAlign.center, style: hs(14, color: HC.onSky)),
                  const SizedBox(height: 30),
                  HCard(
                    lift: true, padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
                    child: AutofillGroup(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                        Text('সাইন ইন করুন', style: hs(20, w: w7)),
                        Padding(padding: const EdgeInsets.only(top: 2, bottom: 20), child: Text('আপনার মোবাইল নম্বর দিয়ে প্রবেশ করুন', style: hs(14, color: HC.muted))),
                        _label('মোবাইল নম্বর'),
                        TextField(
                          controller: _phone, keyboardType: TextInputType.phone, textInputAction: TextInputAction.next,
                          autofillHints: const [AutofillHints.telephoneNumber, AutofillHints.username],
                          style: hs(16), decoration: _deco('01XXXXXXXXX'),
                        ),
                        gap16,
                        _label('পাসওয়ার্ড'),
                        TextField(
                          controller: _pass, obscureText: !_show, onSubmitted: (_) => _submit(),
                          autofillHints: const [AutofillHints.password],
                          style: hs(16),
                          decoration: _deco('আপনার পাসওয়ার্ড', suffix: TextButton(
                            onPressed: () => setState(() => _show = !_show),
                            child: Text(_show ? 'লুকান' : 'দেখুন', style: hs(15, w: w7, color: HC.blue)),
                          )),
                        ),
                        const SizedBox(height: 18),
                        if (_error != null)
                          Container(
                            margin: const EdgeInsets.only(bottom: 14),
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                            decoration: BoxDecoration(color: HC.redSoft, borderRadius: BorderRadius.circular(12)),
                            child: Text(_error!, style: hs(14, color: HC.red)),
                          ),
                        HBtn(_busy ? 'সাইন ইন হচ্ছে…' : 'সাইন ইন করুন', onTap: _busy ? null : _submit, fontSize: 16),
                      ]),
                    ),
                  ),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
