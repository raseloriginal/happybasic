import 'package:flutter/material.dart';

import '../core/api.dart';
import '../core/tracker.dart';
import '../ui/common.dart';
import '../ui/hkit.dart';
import '../ui/pwa_kit.dart';

/// "নতুন দোকান যোগ করুন" — register a new shop at the SR's current location
/// (needs internet — the shop gets a real id from the server).
class AddRetailerPage extends StatefulWidget {
  const AddRetailerPage({super.key});
  @override
  State<AddRetailerPage> createState() => _AddRetailerPageState();
}

class _AddRetailerPageState extends State<AddRetailerPage> {
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _address = TextEditingController();
  double? _lat, _lng;
  bool _locating = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _locate();
  }

  Future<void> _locate() async {
    setState(() => _locating = true);
    final p = await Tracker.currentOnce();
    if (!mounted) return;
    setState(() {
      _locating = false;
      _lat = p?.latitude;
      _lng = p?.longitude;
    });
    if (p == null) toast(context, Tracker.instance.problem ?? 'লোকেশন পাওয়া যায়নি।', error: true);
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty || _address.text.trim().isEmpty) {
      setState(() => _error = 'দোকানের নাম ও ঠিকানা দিন।');
      return;
    }
    if (_lat == null) {
      setState(() => _error = 'দোকানের লোকেশন দরকার। লোকেশন চালু করে আবার চেষ্টা করুন।');
      return;
    }
    setState(() => _error = null);
    final r = await busy(context, () => ApiClient.send('POST', '/sr/retailers', opId: ApiClient.newOpId(), body: {
          'name': _name.text.trim(),
          'phone': _phone.text.trim(),
          'address': _address.text.trim(),
          'lat': _lat,
          'lng': _lng,
        }));
    if (r != null && mounted) {
      toast(context, (r['message'] ?? 'দোকান যোগ হয়েছে।').toString());
      Navigator.pop(context, true);
    }
  }

  Widget _field(String label, TextEditingController c, String hint, {bool req = false, TextInputType? type}) => Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text.rich(TextSpan(style: hs(13, w: w6, color: HC.ink2), children: [TextSpan(text: label), if (req) TextSpan(text: ' *', style: hs(13, color: HC.red))])),
          const SizedBox(height: 6),
          TextField(
            controller: c, keyboardType: type, style: hs(15), textInputAction: TextInputAction.next,
            decoration: InputDecoration(
              hintText: hint, hintStyle: hs(15, color: HC.faint), isDense: true, filled: true, fillColor: Colors.white,
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: HC.line)),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: HC.line)),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: HC.blue, width: 1.5)),
            ),
          ),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.of(context).padding.top;
    return SkyStatusBar(
      child: Scaffold(
        backgroundColor: HC.bg,
        body: Column(children: [
          Expanded(
            child: ListView(padding: EdgeInsets.fromLTRB(18, top + 14, 18, 16), children: [
              const SkyBox(height: 120, child: SkyHead(leading: SkyBack(), kicker: 'বর্তমান লোকেশনে পিন হবে', title: 'নতুন দোকান')),
              const SizedBox(height: 22),
              HCard(
                lift: true, radius: 24, padding: const EdgeInsets.fromLTRB(16, 18, 16, 6),
                child: Column(children: [
                  _field('দোকানের নাম', _name, 'যেমন: এনামুল স্টোর', req: true),
                  _field('ঠিকানা / বাজার', _address, 'ঠিকানা লিখুন', req: true),
                  _field('মোবাইল নম্বর (ঐচ্ছিক)', _phone, '01XXXXXXXXX', type: TextInputType.phone),
                ]),
              ),
              gap12,
              HCard(
                radius: 20,
                child: Row(children: [
                  Container(
                    width: 42, height: 42,
                    decoration: BoxDecoration(color: _lat == null ? HC.redSoft : HC.soft, borderRadius: BorderRadius.circular(13)),
                    child: Center(child: _locating
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : Svg('<path d="M20 10c0 6-8 12-8 12s-8-6-8-12a8 8 0 0 1 16 0Z"/><circle cx="12" cy="10" r="3"/>', size: 20, color: _lat == null ? HC.red : HC.blue)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(_locating ? 'লোকেশন খোঁজা হচ্ছে…' : (_lat == null ? 'লোকেশন পাওয়া যায়নি' : 'বর্তমান লোকেশন নেওয়া হয়েছে'), style: hs(14, w: w7)),
                      Text(_lat != null ? '${_lat!.toStringAsFixed(5)}, ${_lng!.toStringAsFixed(5)}' : 'GPS চালু করে আবার চাপুন', style: hs(12, color: HC.muted, num: true)),
                    ]),
                  ),
                  HBtn('আবার', kind: HBtnKind.line, expand: false, height: 40, radius: 12, fontSize: 13, onTap: _locating ? null : _locate),
                ]),
              ),
              const SizedBox(height: 10),
              Text('দোকানের সামনে দাঁড়িয়ে সংরক্ষণ করুন — এই লোকেশনটিই দোকানের ঠিকানা হিসেবে জমা হবে। নতুন দোকান যোগ করতে ইন্টারনেট লাগবে।', style: hs(12.5, color: HC.muted, h: 1.5)),
              if (_error != null)
                Container(
                  margin: const EdgeInsets.only(top: 12), padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(color: HC.redSoft, borderRadius: BorderRadius.circular(14)),
                  child: Text(_error!, style: hs(13, w: w6, color: HC.red)),
                ),
            ]),
          ),
          Container(
            padding: EdgeInsets.fromLTRB(18, 10, 18, 12 + MediaQuery.of(context).padding.bottom),
            color: HC.bg,
            child: Row(children: [
              Expanded(flex: 10, child: HBtn('বাতিল', kind: HBtnKind.line, height: 52, onTap: () => Navigator.pop(context))),
              const SizedBox(width: 10),
              Expanded(flex: 16, child: HBtn('সংরক্ষণ করুন', height: 52, onTap: _save)),
            ]),
          ),
        ]),
      ),
    );
  }
}
