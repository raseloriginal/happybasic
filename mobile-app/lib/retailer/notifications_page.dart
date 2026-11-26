import 'dart:async';

import 'package:flutter/material.dart';

import '../core/api.dart';
import '../core/format.dart';
import '../ui/common.dart';
import '../ui/pwa_kit.dart';
import 'rkit.dart';

Map<String, dynamic> _m(Object? v) => Map<String, dynamic>.from((v ?? {}) as Map);

/// /retailer/notifications — grouped by day, unread rows highlighted with a blue dot.
class NotificationsPage extends StatefulWidget {
  const NotificationsPage({super.key});
  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage> {
  Timer? _seen;

  @override
  void initState() {
    super.initState();
    // The PWA marks everything as read 1.5 s after the page is shown.
    _seen = Timer(const Duration(milliseconds: 1500), () => ApiClient.send('POST', '/retailer/notifications/seen').catchError((_) => <String, dynamic>{}));
  }

  @override
  void dispose() {
    _seen?.cancel();
    super.dispose();
  }

  static const _tints = [
    (Color(0xFFFFE4CC), Color(0xFFC2570C), Color(0xFFF08C1A)), // orange
    (Color(0xFFDBE7FF), Color(0xFF1D4FD0), Color(0xFF2563EB)), // blue
    (Color(0xFFECE4D6), Color(0xFF7A5A37), Color(0xFF7A5A37)), // brown
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: RC.outer,
      body: Frame(
        child: Container(
          color: RC.bg,
          child: AsyncBody(
            padding: EdgeInsets.zero,
            load: () => loadCached('ret_notif', () => ApiClient.get('/retailer/notifications')),
            builder: (context, d, reload) {
              final events = (d['events'] as List).map(_m).toList();
              final unread = int0(d['unread']);
              final out = <Widget>[];
              String? group;
              for (final e in events) {
                if (e['group'] != group) {
                  group = '${e['group']}';
                  out.add(RSecTitle(group, muted: true));
                }
                out.add(_Row(e));
              }
              return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                RPlainHead(title: 'নোটিফিকেশন', subtitle: unread > 0 ? '${bn(unread)}টি নতুন' : 'সব দেখা হয়েছে', onBack: () => Navigator.pop(context)),
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 14, 14, 40),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    if (events.isEmpty) const REmpty('এখনো কোনো নোটিফিকেশন নেই'),
                    ...out,
                  ]),
                ),
              ]);
            },
          ),
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row(this.e);
  final Map<String, dynamic> e;

  @override
  Widget build(BuildContext context) {
    final kind = '${e['kind']}';
    final unread = e['unread'] == true;
    Widget lead;
    Widget body;
    if (kind == 'order') {
      final company = '${e['company'] ?? ''}';
      final t = _NotificationsPageState._tints[company.hashCode.abs() % 3];
      lead = SizedBox(
        width: 54, height: 62,
        child: Stack(clipBehavior: Clip.none, alignment: Alignment.topCenter, children: [
          Container(
            width: 54, height: 54,
            decoration: BoxDecoration(shape: BoxShape.circle, color: t.$1, border: Border.all(color: t.$3, width: 3)),
            child: Center(child: Text('${e['initial'] ?? ''}', style: ts(22, w: FontWeight.w700, color: t.$2, h: 1))),
          ),
          Positioned(
            bottom: 0,
            child: Container(
              constraints: const BoxConstraints(maxWidth: 70), padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
              decoration: BoxDecoration(color: t.$3, borderRadius: BorderRadius.circular(99)),
              child: Text(company.length > 7 ? company.substring(0, 7) : company, maxLines: 1, overflow: TextOverflow.ellipsis, style: ts(11, w: FontWeight.w700, color: Colors.white, h: 1.3)),
            ),
          ),
        ]),
      );
      body = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('${e['title']}', style: ts(15, w: FontWeight.w700, h: 1.35)),
        Text('${e['sub'] ?? ''}', style: ts(15, h: 1.4)),
        Text('${e['when']}', style: ts(14, color: RC.muted, h: 1.4)),
      ]);
    } else {
      final arrived = kind == 'arrived';
      lead = Container(
        width: 48, height: 48,
        decoration: BoxDecoration(color: arrived ? RC.okSoft : RC.blueSoft, borderRadius: BorderRadius.circular(16)),
        child: Center(child: Text(arrived ? '✓' : '🚚', style: ts(22, color: RC.ink, h: 1))),
      );
      body = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('${e['title']}', style: ts(15, w: FontWeight.w700, h: 1.35)),
        Text('${e['when']}', style: ts(14, color: RC.muted, h: 1.4)),
      ]);
    }
    return RCard(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      child: DecoratedBox(
        decoration: const BoxDecoration(),
        child: Container(
          decoration: unread ? const BoxDecoration(gradient: LinearGradient(colors: [Color(0xFFF3F7FF), Colors.white], stops: [0, 0.6])) : null,
          child: Row(children: [
            lead,
            const SizedBox(width: 14),
            Expanded(child: body),
            if (unread) Container(width: 12, height: 12, decoration: const BoxDecoration(color: RC.blue, shape: BoxShape.circle)),
          ]),
        ),
      ),
    );
  }
}
