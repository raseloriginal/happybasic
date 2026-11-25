import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/api.dart';
import '../core/format.dart';
import '../core/session.dart';
import '../core/tracker.dart';
import '../ui/account.dart';
import '../ui/common.dart';
import '../ui/tracker_banner.dart';
import '../ui/update.dart';
import 'attendance_page.dart';
import 'delivery_page.dart';
import 'expense_page.dart';
import 'settlement_page.dart';
import 'van_stock_page.dart';

Map<String, dynamic> _m(Object? v) => Map<String, dynamic>.from((v ?? {}) as Map);

class DsrHome extends StatefulWidget {
  const DsrHome({super.key});
  @override
  State<DsrHome> createState() => _DsrHomeState();
}

class _DsrHomeState extends State<DsrHome> {
  int _tab = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      UpdateChecker.check(context);
      if (!Tracker.instance.running) Tracker.instance.start('dsr');
    });
  }

  @override
  Widget build(BuildContext context) {
    const titles = ['হোম', 'ডেলিভারি', 'ভ্যান স্টক', 'খরচ', 'সেটেলমেন্ট'];
    return Scaffold(
      appBar: AppBar(
        title: Text(titles[_tab]),
        actions: [
          const SyncChip(),
          IconButton(
            icon: const Icon(Icons.person_outline),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const _DsrAccountPage())),
          ),
        ],
      ),
      body: IndexedStack(index: _tab, children: const [_DsrDashboard(), DeliveryPage(), VanStockPage(), ExpensePage(), SettlementPage()]),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'হোম'),
          NavigationDestination(icon: Icon(Icons.local_shipping_outlined), selectedIcon: Icon(Icons.local_shipping), label: 'ডেলিভারি'),
          NavigationDestination(icon: Icon(Icons.inventory_2_outlined), selectedIcon: Icon(Icons.inventory_2), label: 'ভ্যান'),
          NavigationDestination(icon: Icon(Icons.payments_outlined), selectedIcon: Icon(Icons.payments), label: 'খরচ'),
          NavigationDestination(icon: Icon(Icons.fact_check_outlined), selectedIcon: Icon(Icons.fact_check), label: 'সেটেলমেন্ট'),
        ],
      ),
    );
  }
}

class _DsrAccountPage extends StatelessWidget {
  const _DsrAccountPage();
  @override
  Widget build(BuildContext context) {
    final p = context.watch<AuthState>().profile;
    final photo = ApiClient.asset(p['photo']);
    return Scaffold(
      appBar: AppBar(title: const Text('আমি')),
      body: ListView(padding: const EdgeInsets.all(14), children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(children: [
              CircleAvatar(radius: 32, backgroundImage: photo == null ? null : CachedNetworkImageProvider(photo), child: photo == null ? const Icon(Icons.person, size: 30) : null),
              const SizedBox(width: 14),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${p['name']}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                Text('${p['code'] ?? ''} · ${p['phone']}', style: const TextStyle(color: kMuted)),
                Text('${p['partner'] ?? ''}', style: const TextStyle(color: kMuted, fontSize: 12.5)),
              ])),
            ]),
          ),
        ),
        const SizedBox(height: 12),
        const AccountCard(),
      ]),
    );
  }
}

class _DsrDashboard extends StatelessWidget {
  const _DsrDashboard();
  @override
  Widget build(BuildContext context) {
    return AsyncBody(
      load: () => loadCached('dsr_dashboard', () => ApiClient.get('/dsr/dashboard')),
      builder: (context, d, reload) {
        final trip = d['trip'] == null ? null : _m(d['trip']);
        final stats = _m(d['stats']);
        final att = d['attendance'] == null ? null : _m(d['attendance']);
        final settle = d['settlement'] == null ? null : _m(d['settlement']);
        final scanned = att != null && att['checked_in_at'] != null;
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('স্বাগতম, ${_m(d['dsr'])['name']}', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
          Text(dateBn(d['date']?.toString()), style: const TextStyle(color: kMuted)),
          const SizedBox(height: 12),
          const TrackerBanner(role: 'dsr'),
          Card(
            child: ListTile(
              leading: CircleAvatar(backgroundColor: scanned ? const Color(0xFFDCFCE7) : const Color(0xFFFEF3C7), child: Icon(scanned ? Icons.check : Icons.qr_code_scanner, color: scanned ? kOk : kWarn)),
              title: Text(scanned ? 'হাজিরা সম্পন্ন · ${timeBn(att['checked_in_at']?.toString())}' : 'আজকের হাজিরা বাকি', style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text(scanned ? (int0(att['late_min']) > 0 ? '${bn(att['late_min'])} মিনিট দেরি' : 'সময়মতো') : 'গোডাউনের QR স্ক্যান করুন'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AttendancePage())).then((_) => reload()),
            ),
          ),
          const SizedBox(height: 10),
          if (trip == null)
            const Card(child: Padding(padding: EdgeInsets.all(18), child: Text('আজ আপনার কোনো ট্রিপ নেই। পার্টনার ট্রিপ দিলে এখানে দেখা যাবে।', style: TextStyle(color: kMuted))))
          else ...[
            Card(
              child: ListTile(
                leading: const Icon(Icons.route, color: kBlue),
                title: Text('${trip['code']}', style: const TextStyle(fontWeight: FontWeight.w800)),
                subtitle: Text('${dateBn(trip['date']?.toString())}'),
                trailing: Pill(_tripStatus(trip), color: trip['status_key'] == 'settled' ? kOk : kBlue),
              ),
            ),
            if (trip['settlement_status'] == 'returned' && trip['review_note'] != null)
              Container(
                margin: const EdgeInsets.only(top: 10), padding: const EdgeInsets.all(12), width: double.infinity,
                decoration: BoxDecoration(color: const Color(0xFFFEF2F2), borderRadius: BorderRadius.circular(12)),
                child: Text('পার্টনার সেটেলমেন্ট ফেরত পাঠিয়েছেন: ${trip['review_note']}', style: const TextStyle(color: kDanger)),
              ),
            const SectionTitle('আজকের ডেলিভারি'),
            GridView.count(
              crossAxisCount: 2, shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), mainAxisSpacing: 10, crossAxisSpacing: 10, childAspectRatio: 1.9,
              children: [
                StatTile('মোট দোকান', bn(stats['stops']), icon: Icons.storefront),
                StatTile('ডেলিভারি হয়েছে', bn(stats['delivered']), color: kOk, icon: Icons.check_circle_outline),
                StatTile('বাকি আছে', bn(stats['pending']), color: kWarn, icon: Icons.hourglass_empty),
                StatTile('বাতিল', bn(stats['cancelled']), color: kDanger, icon: Icons.cancel_outlined),
                StatTile('ভ্যানে মাল (পিস)', bn(stats['available_pcs']), icon: Icons.inventory_2_outlined),
                StatTile('বাকিতে দেওয়া', bn(stats['due']), color: kDanger, icon: Icons.account_balance_wallet_outlined),
              ],
            ),
            if (settle != null) ...[
              const SectionTitle('আজকের হিসাব'),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(children: [
                    _row('ডেলিভারির বিল', money(settle['total_sales_sr'])),
                    _row('রেডি সেল', money(settle['ready_sale'])),
                    _row('পুরনো বাকি আদায়', money(settle['prior_due_collected'])),
                    _row('ড্যামেজ', '-${money(settle['damaged_amount'])}'),
                    _row('খরচ', '-${money(settle['daily_expenses'])}'),
                    _row('নতুন বাকি', '-${money(settle['retailer_due'])}'),
                    const Divider(),
                    _row('জমা দেওয়ার টাকা', money(settle['net_pay']), bold: true),
                  ]),
                ),
              ),
            ],
          ],
        ]);
      },
    );
  }

  static String _tripStatus(Map<String, dynamic> t) => switch (t['status_key']) {
        'pending' => 'প্রস্তুত হচ্ছে',
        'dispatched' => 'চলছে',
        'in_review' => 'যাচাইয়ে',
        'settled' => 'সেটেলড',
        _ => '${t['status_key']}',
      };

  static Widget _row(String k, String v, {bool bold = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(children: [
          Expanded(child: Text(k, style: TextStyle(fontWeight: bold ? FontWeight.w800 : FontWeight.w500))),
          Text(v, style: TextStyle(fontWeight: bold ? FontWeight.w800 : FontWeight.w600, fontSize: bold ? 17 : 14)),
        ]),
      );
}
