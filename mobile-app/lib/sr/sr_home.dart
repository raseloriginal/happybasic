import 'package:flutter/material.dart';

import '../core/tracker.dart';
import '../ui/common.dart';
import '../ui/hkit.dart';
import '../ui/pwa_kit.dart';
import '../ui/update.dart';
import 'order_page.dart';
import 'sr_history.dart';
import 'sr_pages.dart';

const _icHome = '<path d="M4 11l8-6 8 6v8a1 1 0 0 1-1 1H5a1 1 0 0 1-1-1z"/>';
const _icOrder = '<path d="M20 10c0 6-8 12-8 12s-8-6-8-12a8 8 0 0 1 16 0Z"/><path d="M12 7v6M9 10h6"/>';
const _icHistory = '<path d="M8 6h12M8 12h12M8 18h12"/><circle cx="4" cy="6" r="1"/><circle cx="4" cy="12" r="1"/><circle cx="4" cy="18" r="1"/>';
const _icMe = '<circle cx="12" cy="8" r="4"/><path d="M4 20a8 8 0 0 1 16 0"/>';

/// SR app (design SR1–SR7): আজ · অর্ডার · হিস্ট্রি · আমি.
class SrHome extends StatefulWidget {
  const SrHome({super.key});
  @override
  State<SrHome> createState() => _SrHomeState();
}

class _SrHomeState extends State<SrHome> {
  int _tab = 0;
  final _visited = <int>{0};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      UpdateChecker.check(context);
      if (!Tracker.instance.running) Tracker.instance.start('sr');
    });
  }

  void _go(int i) => setState(() {
        _tab = i;
        _visited.add(i);
      });

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.of(context).padding.top;
    // Tabs are built the first time they are opened, then kept alive (map and lists keep their state).
    Widget lazy(int i, Widget Function() b) => _visited.contains(i) ? b() : const SizedBox.shrink();
    return PopScope(
      canPop: _tab == 0,
      onPopInvokedWithResult: (did, _) {
        if (!did) _go(0); // Android back from a tab goes to আজ first
      },
      child: SkyStatusBar(
        light: _tab != 1,
        child: Scaffold(
          backgroundColor: HC.outer,
          body: Frame(
            color: HC.outer,
            child: ColoredBox(
              color: HC.bg,
              child: Stack(children: [
                IndexedStack(index: _tab, children: [
                  SrDashboardPage(onNewOrder: () => _go(1), onHistory: () => _go(2)),
                  lazy(1, () => OrderPage(onBack: () => _go(0))),
                  lazy(2, () => const SrHistoryPage()),
                  lazy(3, () => const SrProfilePage()),
                ]),
                if (_tab != 1) Positioned(top: top + 6, left: 0, right: 0, child: const Center(child: SyncChip())),
              ]),
            ),
          ),
          bottomNavigationBar: Frame(
            shrink: true,
            color: HC.outer,
            child: HTabBar(index: _tab, onTap: _go, items: const [
              HNavItem('আজ', _icHome),
              HNavItem('অর্ডার', _icOrder),
              HNavItem('হিস্ট্রি', _icHistory),
              HNavItem('আমি', _icMe),
            ]),
          ),
        ),
      ),
    );
  }
}
