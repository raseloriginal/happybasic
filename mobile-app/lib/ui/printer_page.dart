import 'package:flutter/material.dart';
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';

import '../core/printer.dart';
import 'common.dart';

class PrinterPage extends StatefulWidget {
  const PrinterPage({super.key});
  @override
  State<PrinterPage> createState() => _PrinterPageState();
}

class _PrinterPageState extends State<PrinterPage> {
  List<BluetoothInfo> _list = [];
  bool _loading = true;
  int _mm = PrinterService.paperMm;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final l = await PrinterService.pairedPrinters();
    if (mounted) {
      setState(() {
        _list = l;
        _loading = false;
      });
    }
  }

  Future<void> _test() async {
    final err = await PrinterService.print([
      ReceiptLine('হ্যাপি বাংলাদেশ', style: ReceiptStyle.title, center: true),
      ReceiptLine('টেস্ট প্রিন্ট ✓', center: true),
      ReceiptLine.rule(),
      ReceiptLine('পণ্য', right: '৳১,২৩৪'),
    ]);
    if (mounted) toast(context, err ?? 'প্রিন্ট হয়েছে।', error: err != null);
  }

  @override
  Widget build(BuildContext context) {
    final saved = PrinterService.savedMac;
    return Scaffold(
      appBar: AppBar(title: const Text('ব্লুটুথ প্রিন্টার')),
      body: ListView(padding: const EdgeInsets.all(14), children: [
        const Text('আগে ফোনের ব্লুটুথ সেটিংস থেকে প্রিন্টারটি পেয়ার করুন, তারপর এখানে বাছুন।', style: TextStyle(color: kMuted)),
        const SectionTitle('কাগজের মাপ'),
        SegmentedButton<int>(
          segments: const [ButtonSegment(value: 58, label: Text('৫৮ মিমি')), ButtonSegment(value: 80, label: Text('৮০ মিমি'))],
          selected: {_mm},
          onSelectionChanged: (s) async {
            setState(() => _mm = s.first);
            await PrinterService.setPaper(s.first);
          },
        ),
        SectionTitle('পেয়ার করা প্রিন্টার', trailing: IconButton(onPressed: _load, icon: const Icon(Icons.refresh))),
        if (_loading) const Center(child: Padding(padding: EdgeInsets.all(20), child: CircularProgressIndicator())),
        if (!_loading && _list.isEmpty) const Text('কোনো পেয়ার করা ডিভাইস পাওয়া যায়নি।'),
        for (final p in _list)
          Card(
            child: ListTile(
              leading: const Icon(Icons.print),
              title: Text(p.name),
              subtitle: Text(p.macAdress),
              trailing: saved == p.macAdress ? const Icon(Icons.check_circle, color: kOk) : null,
              onTap: () async {
                final ok = await busy(context, () => PrinterService.connect(p.macAdress));
                if (ok == true) {
                  await PrinterService.remember(p);
                  if (mounted) {
                    setState(() {});
                    toast(context, '${p.name} সংযুক্ত হয়েছে।');
                  }
                } else if (mounted) {
                  toast(context, 'সংযোগ হয়নি। প্রিন্টার চালু আছে কিনা দেখুন।', error: true);
                }
              },
            ),
          ),
        const SizedBox(height: 16),
        OutlinedButton.icon(onPressed: saved == null ? null : _test, icon: const Icon(Icons.receipt_long), label: const Text('টেস্ট প্রিন্ট')),
      ]),
    );
  }
}
