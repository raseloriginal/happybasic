import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../core/api.dart';
import '../core/session.dart';
import '../ui/common.dart';
import '../ui/hkit.dart';
import '../ui/motion.dart';
import '../ui/pwa_kit.dart';

/// Login (design "লগইন · সব অ্যাপ"): greeting on the sky, one card with phone + password, one button.
class LoginPage extends StatefulWidget {
  const LoginPage({super.key});
  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _phone = TextEditingController();
  final _pass = TextEditingController();
  final _passFocus = FocusNode();
  bool _busy = false;
  bool _show = false;
  String? _error;
  int _taps = 0;

  static final _phoneOk = RegExp(r'^01[3-9]\d{8}$');

  @override
  void dispose() {
    _phone.dispose();
    _pass.dispose();
    _passFocus.dispose();
    super.dispose();
  }

  bool get _okPhone => _phoneOk.hasMatch(_phone.text);
  bool get _okPass => _pass.text.length >= 4;

  Future<void> _submit() async {
    if (!_okPhone || !_okPass || _busy) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await context.read<AuthState>().login(_phone.text.trim(), _pass.text);
    } on ApiException catch (e) {
      if (mounted) {
        HapticFeedback.heavyImpact();
        setState(() => _error = e.message);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Tap the logo 7 times: set the server address (for testing / a new domain).
  Future<void> _serverSheet() async {
    final c = TextEditingController(text: ApiClient.base);
    final ok = await showHSheet<bool>(
      context,
      builder: (d) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('সার্ভার ঠিকানা', style: hs(18, w: w7)),
        const SizedBox(height: 12),
        TextField(controller: c, keyboardType: TextInputType.url, decoration: const InputDecoration(hintText: 'https://example.com')),
        const SizedBox(height: 14),
        Row(children: [
          Expanded(child: HBtn('বাতিল', kind: HBtnKind.line, onTap: () => Navigator.pop(d, false))),
          const SizedBox(width: 10),
          Expanded(child: HBtn('সংরক্ষণ', onTap: () => Navigator.pop(d, true))),
        ]),
      ]),
    );
    if (ok == true) {
      await ApiClient.setBase(c.text);
      if (mounted) toast(context, 'সার্ভার: ${ApiClient.base}');
    }
  }

  void _help() => showHSheet<void>(
        context,
        builder: (c) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('লগইন হচ্ছে না?', style: hs(18, w: w7)),
          const SizedBox(height: 10),
          for (final t in const [
            'যে মোবাইল নম্বর পার্টনার বা অফিসে দিয়েছেন, সেটিই লিখুন (০১ দিয়ে শুরু, ১১ সংখ্যা)।',
            'পাসওয়ার্ড ভুলে গেলে আপনার পার্টনারকে বলুন — তিনি নতুন পাসওয়ার্ড দিতে পারবেন।',
            'দোকানদার হলে আপনার SR-কে বলুন, তিনি দোকানের নম্বর ঠিক করে দেবেন।',
            'ইন্টারনেট চালু আছে কিনা দেখে আবার চেষ্টা করুন।',
          ])
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Container(margin: const EdgeInsets.only(top: 8, right: 10), width: 6, height: 6, decoration: const BoxDecoration(color: HC.blue, shape: BoxShape.circle)),
                Expanded(child: Text(t, style: hs(14, color: HC.ink2))),
              ]),
            ),
          const SizedBox(height: 6),
          HBtn('ঠিক আছে', onTap: () => Navigator.pop(c)),
        ]),
      );

  String get _greet {
    final h = DateTime.now().hour;
    return h < 12 ? 'শুভ সকাল' : (h < 17 ? 'শুভ দুপুর' : 'শুভ সন্ধ্যা');
  }

  BoxDecoration _box(bool on) => on
      ? BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: HC.blue, width: 2),
          boxShadow: const [BoxShadow(color: HC.soft, spreadRadius: 4)])
      : BoxDecoration(color: const Color(0xFFF8FAFD), borderRadius: BorderRadius.circular(16), border: Border.all(color: const Color(0xFFDCE1EC), width: 1.5));

  Widget _label(String t) => Padding(padding: const EdgeInsets.only(top: 2), child: Text(t, style: hs(13, w: w6, color: HC.muted)));

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.of(context).padding.top;
    final all = _okPhone && _okPass;
    final field = InputDecoration.collapsed(hintText: '', hintStyle: hs(18, color: HC.faint)).copyWith(filled: false);
    return SkyStatusBar(
      child: Scaffold(
        backgroundColor: HC.outer,
        body: Frame(
          color: HC.outer,
          child: ColoredBox(
            color: HC.bg,
            child: CustomScrollView(slivers: [
              SliverPadding(
                padding: EdgeInsets.fromLTRB(22, top + 12, 22, 0),
                sliver: SliverToBoxAdapter(
                  child: SkyBox(
                    height: 330, side: 22,
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      Row(children: [
                        GestureDetector(
                          onTap: () {
                            if (++_taps >= 7) {
                              _taps = 0;
                              _serverSheet();
                            }
                          },
                          child: Container(
                            width: 36, height: 36, alignment: Alignment.center,
                            decoration: BoxDecoration(color: const Color(0x29FFFFFF), borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0x4DFFFFFF))),
                            child: Image.asset('assets/images/mark_white.png', width: 21, errorBuilder: (_, __, ___) => const SizedBox()),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text('Happy', style: hs(17, w: w7, color: Colors.white)),
                      ]),
                      const SizedBox(height: 20),
                      Text('$_greet 👋', style: hs(30, w: w7, color: Colors.white, h: 1.2)),
                      const SizedBox(height: 18),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 22),
                        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(22),
                            boxShadow: const [BoxShadow(color: Color(0x1F0A1640), blurRadius: 40, offset: Offset(0, 18))]),
                        child: AutofillGroup(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                            Text('লগইন করুন', style: hs(17, w: w7)),
                            const SizedBox(height: 12),
                            _label('মোবাইল নম্বর / আইডি'),
                            const SizedBox(height: 8),
                            AnimatedContainer(
                              duration: const Duration(milliseconds: 220), curve: kEase,
                              height: 60, padding: const EdgeInsets.symmetric(horizontal: 14),
                              decoration: _box(_okPhone),
                              child: Row(children: [
                                Container(
                                  padding: const EdgeInsets.only(right: 10),
                                  decoration: const BoxDecoration(border: Border(right: BorderSide(color: Color(0xFFDCE1EC)))),
                                  child: Row(children: [
                                    Semantics(
                                      label: 'বাংলাদেশ',
                                      child: ClipRRect(
                                        borderRadius: BorderRadius.circular(3),
                                        child: Container(width: 24, height: 16, color: const Color(0xFF006A4E), alignment: const Alignment(-.12, 0),
                                            child: Container(width: 9.2, height: 9.2, decoration: const BoxDecoration(color: Color(0xFFF42A41), shape: BoxShape.circle))),
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Text('+৮৮', style: hs(15, w: w7)),
                                  ]),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: TextField(
                                    controller: _phone, keyboardType: TextInputType.phone, textInputAction: TextInputAction.next, maxLength: 11,
                                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                                    autofillHints: const [AutofillHints.telephoneNumber, AutofillHints.username],
                                    onChanged: (_) => setState(() => _error = null),
                                    onSubmitted: (_) => _passFocus.requestFocus(),
                                    style: hs(19, w: w7, ls: 1, num: true),
                                    decoration: field.copyWith(hintText: '01XXXXXXXXX', counterText: ''),
                                  ),
                                ),
                                AnimatedScale(
                                  scale: _okPhone ? 1 : 0, duration: const Duration(milliseconds: 260), curve: Curves.easeOutBack,
                                  child: Container(
                                    width: 24, height: 24, decoration: const BoxDecoration(color: Color(0xFF12805C), shape: BoxShape.circle),
                                    child: const Icon(Icons.check_rounded, color: Colors.white, size: 16),
                                  ),
                                ),
                              ]),
                            ),
                            const SizedBox(height: 12),
                            _label('পাসওয়ার্ড'),
                            const SizedBox(height: 8),
                            AnimatedContainer(
                              duration: const Duration(milliseconds: 220), curve: kEase,
                              height: 60, padding: const EdgeInsets.only(left: 16, right: 8),
                              decoration: _box(_okPass),
                              child: Row(children: [
                                const Svg('<rect x="5" y="11" width="14" height="10" rx="2"/><path d="M8 11V8a4 4 0 0 1 8 0v3"/>', size: 20, color: HC.muted, stroke: 1.8),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: TextField(
                                    controller: _pass, focusNode: _passFocus, obscureText: !_show, textInputAction: TextInputAction.go,
                                    autofillHints: const [AutofillHints.password],
                                    onChanged: (_) => setState(() => _error = null),
                                    onSubmitted: (_) => _submit(),
                                    style: hs(18, w: w7, ls: 2),
                                    decoration: field.copyWith(hintText: '••••••'),
                                  ),
                                ),
                                Semantics(
                                  button: true, label: 'পাসওয়ার্ড দেখুন',
                                  child: Pressable(
                                    child: GestureDetector(
                                      onTap: () => setState(() => _show = !_show),
                                      child: SizedBox(width: 44, height: 44, child: Center(child: Svg(
                                        _show ? '<path d="M3 3l18 18"/><path d="M10.6 5.1A10 10 0 0 1 12 5c6 0 10 7 10 7a17 17 0 0 1-3.2 3.9M6.6 6.6A17 17 0 0 0 2 12s4 7 10 7a9.7 9.7 0 0 0 5.4-1.6"/>'
                                            : '<path d="M2 12s4-7 10-7 10 7 10 7-4 7-10 7S2 12 2 12z"/><circle cx="12" cy="12" r="3"/>',
                                        size: 20, color: HC.muted, stroke: 1.8))),
                                    ),
                                  ),
                                ),
                              ]),
                            ),
                            AnimatedSize(
                              duration: const Duration(milliseconds: 260), curve: kEase,
                              child: _error == null
                                  ? const SizedBox(width: double.infinity)
                                  : Container(
                                      width: double.infinity,
                                      margin: const EdgeInsets.only(top: 12),
                                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                      decoration: BoxDecoration(color: HC.redSoft, borderRadius: BorderRadius.circular(12)),
                                      child: Text(_error!, style: hs(13.5, w: w6, color: HC.red)),
                                    ),
                            ),
                            const SizedBox(height: 14),
                            Semantics(
                              button: true, enabled: all && !_busy,
                              child: Pressable(
                                enabled: all && !_busy,
                                child: GestureDetector(
                                  onTap: _submit,
                                  child: AnimatedContainer(
                                    duration: const Duration(milliseconds: 220), curve: kEase,
                                    height: 56, alignment: Alignment.center,
                                    decoration: BoxDecoration(
                                      color: all ? HC.sky : const Color(0xFFDCE1EC), borderRadius: BorderRadius.circular(16),
                                      boxShadow: all ? const [BoxShadow(color: Color(0x521A3FD6), blurRadius: 30, offset: Offset(0, 14))] : null,
                                    ),
                                    child: _busy
                                        ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white))
                                        : Row(mainAxisSize: MainAxisSize.min, children: [
                                            Text('লগইন', style: hs(16, w: w7, color: all ? Colors.white : const Color(0xFF8891AA))),
                                            const SizedBox(width: 8),
                                            Svg('<path d="M9 5l7 7-7 7"/>', size: 18, color: all ? Colors.white : const Color(0xFF8891AA), stroke: 1.8),
                                          ]),
                                  ),
                                ),
                              ),
                            ),
                          ]),
                        ),
                      ),
                    ]),
                  ),
                ),
              ),
              SliverFillRemaining(
                hasScrollBody: false,
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(22, 24, 22, 30 + MediaQuery.of(context).padding.bottom),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Text('লগইন হচ্ছে না? ', style: hs(13, color: HC.muted)),
                      GestureDetector(onTap: _help, child: Text('সাহায্য নিন', style: hs(13, w: w7, color: HC.blue))),
                    ]),
                  ),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
