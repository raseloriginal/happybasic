import 'package:flutter/material.dart';

import '../core/api.dart';
import '../core/tracker.dart';
import '../ui/common.dart';
import '../ui/pwa_kit.dart';
import '../ui/skit.dart';

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
        padding: const EdgeInsets.only(bottom: 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text.rich(TextSpan(style: ts(12.5, w: FontWeight.w600, color: SC.ink2), children: [TextSpan(text: label), if (req) TextSpan(text: ' *', style: ts(12.5, color: SC.danger))])),
          const SizedBox(height: 5),
          TextField(
            controller: c, keyboardType: type, style: ts(13.5),
            decoration: InputDecoration(
              hintText: hint, hintStyle: ts(13.5, color: SC.muted), isDense: true, filled: true, fillColor: SC.surface,
              contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 11),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: SC.borderStrong)),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: SC.borderStrong)),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: SC.cobalt)),
            ),
          ),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    return SPage(
      child: Column(children: [
        const SSubHead(title: 'নতুন দোকান যোগ করুন', sub: 'নতুন দোকান নিবন্ধন করুন ও বর্তমান অবস্থান পিন করুন'),
        Expanded(
          child: ListView(padding: const EdgeInsets.all(16), children: [
            _field('দোকানের নাম', _name, 'যেমন: এনামুল স্টোর', req: true),
            _field('ঠিকানা / অবস্থান', _address, 'ঠিকানা লিখুন', req: true),
            _field('মোবাইল নম্বর (ঐচ্ছিক)', _phone, '01XXXXXXXXX', type: TextInputType.phone),
            SCard(
              radius: 12, padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(children: [
                Icon(_lat == null ? Icons.location_off : Icons.my_location, color: _lat == null ? SC.danger : SC.ok, size: 22),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(_locating ? 'লোকেশন খোঁজা হচ্ছে…' : (_lat == null ? 'লোকেশন পাওয়া যায়নি' : 'বর্তমান লোকেশন নেওয়া হয়েছে'), style: ts(13, w: FontWeight.w700)),
                    if (_lat != null) Text('${_lat!.toStringAsFixed(5)}, ${_lng!.toStringAsFixed(5)}', style: ts(11.5, color: SC.muted, tabular: true)),
                  ]),
                ),
                SBtn('আবার', kind: SBtnKind.ghost, size: 11.5, onTap: _locate),
              ]),
            ),
            const SizedBox(height: 8),
            Text('দোকানের সামনে দাঁড়িয়ে সংরক্ষণ করুন — লোকেশনটি দোকানের অবস্থান হিসেবে জমা হবে।', style: ts(12, color: SC.muted, h: 1.45)),
            if (_error != null)
              Container(
                margin: const EdgeInsets.only(top: 12), padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
                decoration: BoxDecoration(color: SC.dangerBg, borderRadius: BorderRadius.circular(10), border: Border.all(color: SC.dangerBorder)),
                child: Text(_error!, style: ts(12, color: SC.dangerText)),
              ),
          ]),
        ),
        Container(
          padding: EdgeInsets.fromLTRB(16, 12, 16, 12 + MediaQuery.of(context).padding.bottom),
          decoration: const BoxDecoration(color: SC.surface, border: Border(top: BorderSide(color: SC.border))),
          child: Row(children: [
            Expanded(child: SBtn('বাতিল', kind: SBtnKind.secondary, height: 44, onTap: () => Navigator.pop(context))),
            const SizedBox(width: 10),
            Expanded(flex: 2, child: SBtn('সংরক্ষণ করুন', height: 44, onTap: _save)),
          ]),
        ),
      ]),
    );
  }
}
