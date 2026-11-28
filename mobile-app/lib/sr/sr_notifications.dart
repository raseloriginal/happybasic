import 'package:flutter/material.dart';

import '../core/api.dart';
import '../core/format.dart';
import '../ui/common.dart';
import '../ui/hkit.dart';
import '../ui/pwa_kit.dart';

Map<String, dynamic> _m(Object? v) => Map<String, dynamic>.from((v ?? {}) as Map);

/// SR · নোটিফিকেশন: what happened to my orders at delivery (taken, taken less, cancelled), last 14 days.
class SrNotificationsPage extends StatefulWidget {
  const SrNotificationsPage({super.key});
  @override
  State<SrNotificationsPage> createState() => _SrNotificationsPageState();
}

class _SrNotificationsPageState extends State<SrNotificationsPage> {
  int _tab = 0;

  @override
  void initState() {
    super.initState();
    ApiClient.send('POST', '/sr/notifications/seen').catchError((_) => <String, dynamic>{});
  }

  @override
  Widget build(BuildContext context) {
    return SkyStatusBar(
      child: Scaffold(
        backgroundColor: HC.bg,
        body: Frame(
          color: HC.outer,
          child: ColoredBox(
            color: HC.bg,
            child: AsyncBody(
              sky: true,
              load: () => loadCached('sr_notif', () => ApiClient.get('/sr/notifications')),
              builder: (context, d, reload) {
                final items = ((d['items'] as List?) ?? const []).map(_m).toList();
                final done = items.where((e) => e['kind'] == 'done').toList();
                final issues = items.where((e) => e['kind'] != 'done').toList();
                final unread = int0(d['unread']);
                final list = _tab == 0 ? issues : done;
                return SkyBox(
                  height: 230,
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    SkyHead(leading: const SkyBack(), kicker: unread > 0 ? '${bn(unread)}টি নতুন' : 'সব দেখা হয়েছে', title: 'নোটিফিকেশন'),
                    gap12,
                    HSeg(
                      items: const ['কম / বাতিল', 'ডেলিভারি হয়েছে'], index: _tab, onTap: (i) => setState(() => _tab = i),
                      badges: [issues.where((e) => e['unread'] == true).length, done.where((e) => e['unread'] == true).length],
                    ),
                    gap12,
                    HCard(
                      lift: true, padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                      child: list.isEmpty
                          ? Padding(
                              padding: const EdgeInsets.symmetric(vertical: 18),
                              child: Text(_tab == 0 ? 'কোনো অর্ডার কম বা বাতিল হয়নি' : 'এখনো কোনো ডেলিভারির খবর নেই', textAlign: TextAlign.center, style: hs(13, color: HC.muted)))
                          : Column(children: [
                              for (var i = 0; i < list.length; i++)
                                Container(
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                  decoration: BoxDecoration(border: i == 0 ? null : const Border(top: BorderSide(color: HC.line))),
                                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                    LetterAvatar('${list[i]['initial'] ?? ''}', size: 40, radius: 13,
                                        bg: list[i]['kind'] == 'cancel' ? HC.redSoft : (list[i]['kind'] == 'short' ? HC.chip : HC.soft),
                                        fg: list[i]['kind'] == 'cancel' ? HC.red : (list[i]['kind'] == 'short' ? HC.ink2 : HC.blue), fontSize: 16),
                                    const SizedBox(width: 12),
                                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                      Text('${list[i]['title']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: hs(14.5, w: w7)),
                                      Text('${list[i]['sub']}', maxLines: 2, overflow: TextOverflow.ellipsis,
                                          style: hs(12.5, color: list[i]['kind'] == 'cancel' ? HC.red : HC.muted)),
                                    ])),
                                    const SizedBox(width: 8),
                                    Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                                      Text(list[i]['group'] == 'আজ' ? '${list[i]['when']}' : '${list[i]['group']}', style: hs(11.5, color: HC.muted, num: true)),
                                      if (list[i]['unread'] == true)
                                        Container(margin: const EdgeInsets.only(top: 6), width: 8, height: 8, decoration: const BoxDecoration(color: HC.blue, shape: BoxShape.circle)),
                                    ]),
                                  ]),
                                ),
                            ]),
                    ),
                  ]),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
