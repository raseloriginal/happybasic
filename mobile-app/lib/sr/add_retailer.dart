import 'package:flutter/material.dart';

import '../core/api.dart';
import '../core/tracker.dart';
import '../ui/common.dart';

/// Register a new shop at the SR's current location (needs internet — the shop gets a real id from the server).
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
      toast(context, 'দোকানের নাম ও ঠিকানা দিন।', error: true);
      return;
    }
    if (_lat == null) {
      toast(context, 'দোকানের লোকেশন দরকার। লোকেশন চালু করে আবার চেষ্টা করুন।', error: true);
      return;
    }
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('নতুন দোকান')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        TextField(controller: _name, decoration: const InputDecoration(labelText: 'দোকানের নাম *')),
        const SizedBox(height: 12),
        TextField(controller: _phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'মোবাইল নম্বর (ঐচ্ছিক)')),
        const SizedBox(height: 12),
        TextField(controller: _address, decoration: const InputDecoration(labelText: 'ঠিকানা *')),
        const SizedBox(height: 14),
        Card(
          child: ListTile(
            leading: Icon(_lat == null ? Icons.location_off : Icons.my_location, color: _lat == null ? kDanger : kOk),
            title: Text(_locating ? 'লোকেশন খোঁজা হচ্ছে…' : (_lat == null ? 'লোকেশন পাওয়া যায়নি' : 'বর্তমান লোকেশন নেওয়া হয়েছে')),
            subtitle: _lat == null ? null : Text('${_lat!.toStringAsFixed(5)}, ${_lng!.toStringAsFixed(5)}'),
            trailing: IconButton(icon: const Icon(Icons.refresh), onPressed: _locate),
          ),
        ),
        const SizedBox(height: 6),
        const Text('দোকানের সামনে দাঁড়িয়ে সংরক্ষণ করুন — লোকেশনটি দোকানের অবস্থান হিসেবে জমা হবে।', style: TextStyle(color: kMuted, fontSize: 12.5)),
        const SizedBox(height: 20),
        FilledButton(onPressed: _save, child: const Text('দোকান যোগ করুন')),
      ]),
    );
  }
}
