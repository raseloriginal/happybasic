import 'package:flutter/material.dart';

import '../core/tracker.dart';
import '../ui/common.dart';
import '../ui/pwa_kit.dart';
import '../ui/skit.dart';
import '../ui/update.dart';
import 'order_page.dart';
import 'sr_history.dart';
import 'sr_pages.dart';

/// SR panel shell — same 4 tabs as the PWA bottom nav: আজ · অর্ডার (round +) · হিস্ট্রি · আমি.
class SrHome extends StatefulWidget {
  const SrHome({super.key});
  @override
  State<SrHome> createState() => _SrHomeState();
}

class _SrHomeState extends State<SrHome> {
  int _tab = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      UpdateChecker.check(context);
      if (!Tracker.instance.running) Tracker.instance.start('sr');
    });
  }

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.of(context).padding.top;
    return Scaffold(
      backgroundColor: SC.outer,
      body: Frame(
        child: ColoredBox(
          color: SC.bg,
          child: Column(children: [
            Expanded(
              child: Stack(children: [
                IndexedStack(index: _tab, children: [
                  SrDashboardPage(onNewOrder: () => setState(() => _tab = 1), onHistory: () => setState(() => _tab = 2)),
                  Padding(padding: EdgeInsets.only(top: top), child: const OrderPage()),
                  const SrHistoryPage(),
                  const SrProfilePage(),
                ]),
                Positioned(top: top + 6, left: 0, right: 0, child: const Center(child: SyncChip())),
              ]),
            ),
            SBottomNav(index: _tab, onTap: (i) => setState(() => _tab = i)),
          ]),
        ),
      ),
    );
  }
}
