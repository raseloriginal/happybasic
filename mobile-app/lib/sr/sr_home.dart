import 'package:flutter/material.dart';

import '../core/tracker.dart';
import '../ui/common.dart';
import '../ui/update.dart';
import 'order_page.dart';
import 'sr_pages.dart';

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
    const titles = ['অর্ডার', 'ড্যাশবোর্ড', 'ইতিহাস', 'আমি'];
    return Scaffold(
      appBar: AppBar(title: Text(titles[_tab]), actions: const [SyncChip()]),
      body: IndexedStack(index: _tab, children: const [OrderPage(), SrDashboardPage(), SrHistoryPage(), SrProfilePage()]),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.add_shopping_cart_outlined), selectedIcon: Icon(Icons.add_shopping_cart), label: 'অর্ডার'),
          NavigationDestination(icon: Icon(Icons.dashboard_outlined), selectedIcon: Icon(Icons.dashboard), label: 'ড্যাশবোর্ড'),
          NavigationDestination(icon: Icon(Icons.history), selectedIcon: Icon(Icons.history), label: 'ইতিহাস'),
          NavigationDestination(icon: Icon(Icons.person_outline), selectedIcon: Icon(Icons.person), label: 'আমি'),
        ],
      ),
    );
  }
}
