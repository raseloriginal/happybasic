import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/api.dart';
import '../core/session.dart';
import '../retailer/rkit.dart';
import '../ui/common.dart';
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
    OutlineInputBorder b(Color c, double w) => OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: c, width: w));
    return InputDecoration(
      hintText: hint,
      hintStyle: ts(15, color: const Color(0xFF94A3B8)),
      filled: true, fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
      constraints: const BoxConstraints(minHeight: 52, maxHeight: 52),
      enabledBorder: b(RC.border, 1.5),
      focusedBorder: b(RC.blue, 1.5),
      border: b(RC.border, 1.5),
      suffixIcon: suffix,
    );
  }

  Widget _label(String t) => Padding(padding: const EdgeInsets.only(bottom: 6), child: Text(t, style: ts(14, w: FontWeight.w700, color: RC.ink2)));

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.of(context).padding.top;
    return Scaffold(
      backgroundColor: RC.outer,
      body: Frame(
        child: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFF2F6BE0), Color(0xFF1D4FD0), RC.bg, RC.bg], stops: [0, 0.0001, 0.0001, 1]),
          ),
          child: LayoutBuilder(builder: (context, c) {
            return Stack(children: [
              // gradient strip: 270px tall, then page background
              Positioned(
                left: 0, right: 0, top: 0, height: 270 + top,
                child: Container(decoration: const BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFF2F6BE0), Color(0xFF1D4FD0)]))),
              ),
              Positioned(right: -80, top: -90, child: Container(width: 240, height: 240, decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0x14FFFFFF)))),
              Positioned.fill(
                child: SingleChildScrollView(
                  padding: EdgeInsets.only(bottom: 24 + MediaQuery.of(context).viewInsets.bottom),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Padding(
                      padding: EdgeInsets.fromLTRB(20, 56 + top, 20, 30),
                      child: Column(children: [
                        GestureDetector(
                          onTap: () {
                            if (++_taps >= 7) {
                              _taps = 0;
                              _serverDialog();
                            }
                          },
                          child: Container(
                            width: 72, height: 72, margin: const EdgeInsets.only(bottom: 12),
                            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 20, offset: Offset(0, 6))]),
                            clipBehavior: Clip.antiAlias,
                            child: Image.asset('assets/images/logo.jpg', fit: BoxFit.cover, errorBuilder: (_, __, ___) => const SizedBox()),
                          ),
                        ),
                        Text('Happy Bangladesh', style: ts(26, w: FontWeight.w700, color: Colors.white, h: 1.25)),
                        Text('SR · DSR · দোকান', style: ts(16, color: const Color(0xD9FFFFFF), h: 1.5)),
                      ]),
                    ),
                    Container(
                      margin: const EdgeInsets.symmetric(horizontal: 16),
                      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 26),
                      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(26), boxShadow: const [BoxShadow(color: Color(0x261E40AF), blurRadius: 34, offset: Offset(0, 10))]),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                        Text('সাইন ইন করুন', style: ts(22, w: FontWeight.w700, h: 1.3)),
                        Padding(padding: const EdgeInsets.only(top: 2, bottom: 20), child: Text('আপনার মোবাইল নম্বর দিয়ে প্রবেশ করুন', style: ts(16, color: RC.muted, h: 1.5))),
                        _label('মোবাইল নম্বর'),
                        TextField(
                          controller: _phone,
                          keyboardType: TextInputType.phone,
                          textInputAction: TextInputAction.next,
                          style: ts(16, color: RC.ink),
                          decoration: _deco('01XXXXXXXXX'),
                        ),
                        const SizedBox(height: 16),
                        _label('পাসওয়ার্ড'),
                        TextField(
                          controller: _pass,
                          obscureText: !_show,
                          onSubmitted: (_) => _submit(),
                          style: ts(16, color: RC.ink),
                          decoration: _deco('আপনার পাসওয়ার্ড',
                              suffix: TextButton(
                                onPressed: () => setState(() => _show = !_show),
                                style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 14), minimumSize: const Size(60, 40), foregroundColor: RC.blue),
                                child: Text(_show ? 'লুকান' : 'দেখুন', style: ts(16, w: FontWeight.w700, color: RC.blue)),
                              )),
                        ),
                        const SizedBox(height: 18),
                        if (_error != null)
                          Container(
                            margin: const EdgeInsets.only(bottom: 14),
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                            decoration: BoxDecoration(color: const Color(0xFFFEF2F2), borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFFFECACA))),
                            child: Text(_error!, style: ts(14, color: const Color(0xFFB91C1C), h: 1.5)),
                          ),
                        GestureDetector(
                          onTap: _busy ? null : _submit,
                          child: Container(
                            height: 56,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(18),
                              gradient: const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFF2F6BE0), Color(0xFF1D4FD0)]),
                              boxShadow: const [BoxShadow(color: Color(0x4D1D5BD8), blurRadius: 20, offset: Offset(0, 8))],
                            ),
                            child: Center(child: Text(_busy ? 'সাইন ইন হচ্ছে…' : 'সাইন ইন করুন', style: ts(18, w: FontWeight.w700, color: Colors.white))),
                          ),
                        ),
                      ]),
                    ),
                  ]),
                ),
              ),
            ]);
          }),
        ),
      ),
    );
  }
}
