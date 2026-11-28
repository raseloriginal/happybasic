import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../core/api.dart';
import '../core/format.dart';
import '../core/geo_filter.dart';
import '../core/offline.dart';
import '../core/realtime.dart';
import '../core/tracker.dart';
import '../ui/base_map.dart';
import '../ui/common.dart';
import '../ui/dkit.dart';
import '../ui/hkit.dart';
import '../ui/me_layer.dart';
import '../ui/pwa_kit.dart';
import 'ready_sale_page.dart';
import 'stop_page.dart';

Map<String, dynamic> _m(Object? v) => Map<String, dynamic>.from((v ?? {}) as Map);

String statusBn(String s) => switch (s) {
      'Delivered' => 'ডেলিভারি হয়েছে',
      'Due' => 'বাকি',
      'Partial' => 'আংশিক',
      'Cancelled' => 'বাতিল',
      'Pending' => 'বাকি আছে',
      _ => s,
    };

/// What the shop should pay for the pieces that will be delivered (ordered, capped by van stock, minus cancelled ones).
double stopBill(Map<String, dynamic> s) {
  var t = 0.0;
  for (final c in (s['companies'] as List? ?? [])) {
    final co = _m(c);
    if (co['ready_sale'] == true || co['cancelled'] == true) continue;
    for (final i in (co['items'] as List? ?? [])) {
      final it = _m(i);
      final ordered = int0(it['ordered_qty']), stock = int0(it['stock']);
      t += (ordered < stock ? ordered : stock) * num0(it['sr_rate']);
    }
  }
  return t;
}

/// Cash taken at a finished stop (bill part + old due collected).
double stopCash(Map s) => s['status'] == 'Pending' ? 0 : num0(s['paid_amount']) + num0(s['old_due_collected']);

int stopItems(Map s) {
  var n = 0;
  for (final c in (s['companies'] as List? ?? [])) {
    if (_m(c)['ready_sale'] == true) continue;
    n += ((_m(c)['items'] as List?) ?? const []).length;
  }
  return n;
}

String stopMemo(Map s) {
  for (final c in (s['companies'] as List? ?? [])) {
    final co = _m(c);
    if (co['ready_sale'] != true && '${co['order_code'] ?? ''}'.isNotEmpty) return '${co['order_code']}';
  }
  return '';
}

/// Opens one shop's delivery (DMD) for the loaded `/dsr/delivery` payload [d]; true when something was saved.
Future<bool?> openStop(BuildContext context, Map<String, dynamic> s, Map<String, dynamic> d) {
  final trip = d['trip'] == null ? null : _m(d['trip']);
  return Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => StopPage(
        stop: s,
        reasons: ((d['cancelReasons'] as List?) ?? const []).map((e) => '$e').toList(),
        editable: trip != null && trip['editable'] == true,
        damageProducts: ((d['damageProducts'] as List?) ?? const []).map(_m).toList(),
      )));
}

/// Stop marker / list number: ✓ delivered, ! short or due, ✕ cancelled, else the route number.
({String text, Color bg, Color fg}) stopDot(Map s, int number) => switch ('${s['status']}') {
      'Delivered' => (text: '✓', bg: HC.blue, fg: Colors.white),
      'Due' || 'Partial' => (text: '!', bg: HC.red, fg: Colors.white),
      'Cancelled' => (text: '×', bg: HC.chip, fg: HC.muted),
      _ => (text: bn(number), bg: HC.ink, fg: Colors.white),
    };

/// DM2 — today's shops: sky header (done / cash), route map with numbered pins, the route list.
class DeliveryPage extends StatefulWidget {
  const DeliveryPage({super.key, this.active = true});
  /// The tab is on screen: live GPS runs only then.
  final bool active;
  @override
  State<DeliveryPage> createState() => _DeliveryPageState();
}

class _DeliveryPageState extends State<DeliveryPage> {
  final _map = MapController();
  String? _date; // null = the open trip
  double? _lat, _lng;
  bool _follow = false; // the map opens on the whole route; the my-location button follows me
  Map<String, dynamic>? _data;
  Object? _error;
  bool _loading = true;
  bool _stale = false;
  StreamSubscription? _sync, _live;

  @override
  void initState() {
    super.initState();
    _load();
    _sync = OfflineQueue.instance.onSynced.listen((_) => _load(silent: true));
    _live = Realtime.instance.events.listen((_) => _load(silent: true));
    Tracker.instance.fix.addListener(_onFix);
    Tracker.currentOnce().then((p) {
      if (p != null && mounted) {
        setState(() {
          _lat = p.latitude;
          _lng = p.longitude;
        });
      }
    });
  }

  @override
  void dispose() {
    Tracker.instance.fix.removeListener(_onFix);
    _sync?.cancel();
    _live?.cancel();
    super.dispose();
  }

  /// Distances follow me; rebuilt only after a few metres (the dot itself is animated by [MeLayer]).
  void _onFix() {
    final f = Tracker.instance.fix.value;
    if (f == null || !mounted) return;
    if (_lat != null && GeoFilter.metres(_lat!, _lng!, f.lat, f.lng) < 4) return;
    setState(() {
      _lat = f.lat;
      _lng = f.lng;
    });
  }

  void _followMe() {
    if (_lat == null) {
      toast(context, Tracker.instance.problem ?? 'লোকেশন পাওয়া যায়নি।', error: true);
      return;
    }
    try {
      _map.move(LatLng(_lat!, _lng!), 17);
    } catch (_) {/* map not ready */}
    setState(() => _follow = true);
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) setState(() => _loading = _data == null);
    try {
      final l = await loadCached('dsr_delivery_${_date ?? 'open'}', () => ApiClient.get('/dsr/delivery', query: {'date': _date}));
      if (!mounted) return;
      setState(() {
        _data = l.data;
        _stale = l.stale;
        _error = null;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  Set<String> get _pendingStops => OfflineQueue.instance.ops.where((o) => o.path.startsWith('/dsr/stops/')).map((o) => o.path.split('/')[3]).toSet();

  double? _dist(Map s) {
    if (_lat == null) return null;
    final lat = num0(s['lat']), lng = num0(s['lng']);
    if (lat == 0 && lng == 0) return null;
    const k = 0.017453292519943295;
    final a = 0.5 - cos((lat - _lat!) * k) / 2 + cos(_lat! * k) * cos(lat * k) * (1 - cos((lng - _lng!) * k)) / 2;
    return 12742000 * asin(sqrt(a));
  }

  void _fitAll(List<Map<String, dynamic>> stops) {
    final pts = [for (final s in stops) if (num0(s['lat']) != 0) LatLng(num0(s['lat']), num0(s['lng']))];
    if (_lat != null) pts.add(LatLng(_lat!, _lng!));
    if (pts.isEmpty) return;
    try {
      if (pts.length == 1) {
        _map.move(pts.first, 17);
      } else {
        _map.fitCamera(CameraFit.bounds(bounds: LatLngBounds.fromPoints(pts), padding: const EdgeInsets.all(36), maxZoom: 18));
      }
    } catch (_) {/* map not ready */}
  }

  Future<void> _open(Map<String, dynamic> s) async {
    final v = await openStop(context, s, _data!);
    if (v == true) _load(silent: true);
  }

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.of(context).padding.top;
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_data == null) {
      return ListView(padding: const EdgeInsets.all(20), children: [
        const SizedBox(height: 80),
        const Icon(Icons.cloud_off_rounded, size: 56, color: HC.faint),
        gap12,
        Text(_error is ApiException ? (_error as ApiException).message : 'লোড করা যায়নি।', textAlign: TextAlign.center, style: hs(14)),
        gap16,
        Center(child: HBtn('আবার চেষ্টা', kind: HBtnKind.line, expand: false, onTap: _load)),
      ]);
    }
    final d = _data!;
    final trip = d['trip'] == null ? null : _m(d['trip']);
    final date = d['selectedDate'].toString();
    final stops = ((d['orders'] as List?) ?? const []).map(_m).toList();
    final vanStock = ((d['vanStock'] as List?) ?? const []).map(_m).toList();
    final editable = trip != null && trip['editable'] == true;
    final done = stops.where((s) => s['status'] != 'Pending').length;
    final pending = stops.length - done;
    final cash = stops.fold<double>(0, (a, s) => a + stopCash(s));
    final bill = stops.fold<double>(0, (a, s) => a + (s['status'] == 'Pending' ? stopBill(s) : num0(s['paid_amount']) + num0(s['due_amount'])));

    String? banner;
    var returned = false;
    if (trip == null) {
      banner = 'এই তারিখে কোনো ডিসপ্যাচ করা ট্রিপ নেই — অন্য তারিখ বাছুন।';
    } else if (!editable) {
      banner = trip['status_key'] == 'settled' ? 'এই ট্রিপটি সেটেল হয়ে গেছে — শুধু দেখার জন্য।' : 'সেটেলমেন্টের জন্য জমা দেওয়া হয়েছে — পার্টনার যাচাই করছেন। এখন পরিবর্তন করা যাবে না।';
    } else if (trip['settlement_status'] == 'returned') {
      banner = 'পার্টনার ফেরত পাঠিয়েছেন${'${trip['review_note'] ?? ''}'.isNotEmpty ? ': ${trip['review_note']}' : ''}। সংশোধন করে পুনরায় জমা দিন।';
      returned = true;
    }

    return ListenableBuilder(
      listenable: OfflineQueue.instance,
      builder: (context, _) {
        final pend = _pendingStops;
        return RefreshIndicator(
          edgeOffset: top,
          onRefresh: () => _load(silent: true),
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.fromLTRB(18, top + 14, 18, 24),
            children: [
              SkyBox(
                height: 200,
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  SkyHead(
                    kicker: trip == null ? 'ট্রিপ নেই' : 'ট্রিপ ${bn('${trip['code']}')}',
                    title: 'আজকের দোকান',
                    trailing: GlassBtn(
                      icon: Ic.plus, label: 'রেডি সেল',
                      onTap: editable ? () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ReadySalePage(vanStock: vanStock))).then((v) => v == true ? _load(silent: true) : null) : () => toast(context, 'খোলা ট্রিপ ছাড়া রেডি সেল করা যাবে না।', error: true),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text('${bn(done)}/${bn(stops.length)} · নগদ ${tk(cash)}', style: hs(13, color: HC.onSky, num: true)),
                  const SizedBox(height: 12),
                  SkyDateBar(date: date, onChange: (v) {
                    setState(() => _date = v == todayYmd() ? null : v);
                    _load();
                  }),
                ]),
              ),
              if (banner != null) Padding(padding: const EdgeInsets.only(top: 12), child: DBanner(banner, returned: returned, muted: trip == null)),
              if (_stale) const Padding(padding: EdgeInsets.only(top: 8), child: OfflineBanner()),
              gap12,
              if (stops.any((s) => num0(s['lat']) != 0) || _lat != null)
                Container(
                  height: 230,
                  decoration: BoxDecoration(borderRadius: BorderRadius.circular(24), boxShadow: HC.liftSm),
                  clipBehavior: Clip.antiAlias,
                  child: Stack(children: [
                    Positioned.fill(child: _buildMap(stops)),
                    Positioned(
                      right: 10, top: 10,
                      child: Semantics(button: true, label: 'সব দোকান দেখুন', child: GestureDetector(
                        onTap: () {
                          setState(() => _follow = false);
                          _fitAll(stops);
                        },
                        child: Container(
                          width: 40, height: 40,
                          decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle, boxShadow: HC.liftSm),
                          child: const Center(child: Svg('<circle cx="12" cy="12" r="3"/><path d="M12 2v3M12 19v3M2 12h3M19 12h3"/>', size: 18, color: HC.ink)),
                        ),
                      )),
                    ),
                    Positioned(
                      right: 10, top: 58,
                      child: Semantics(button: true, label: 'আমার অবস্থানে আনুন', child: GestureDetector(
                        onTap: _followMe,
                        child: Container(
                          width: 40, height: 40,
                          decoration: BoxDecoration(color: _follow ? HC.blue : Colors.white, shape: BoxShape.circle, boxShadow: HC.liftSm),
                          child: Icon(Icons.my_location_rounded, size: 18, color: _follow ? Colors.white : HC.ink),
                        ),
                      )),
                    ),
                    const Positioned(left: 0, right: 0, bottom: 4, child: MapCredit()),
                  ]),
                ),
              gap16,
              HSec('রুটের দোকান', trailing: '${bn(pending)}টি বাকি · মোট ${tk(bill)}'),
              gap8,
              if (stops.isEmpty)
                HEmpty(trip == null ? 'কোনো ট্রিপ নেই' : 'এই ট্রিপে কোনো অর্ডার নেই', body: 'পার্টনার ট্রিপ দিলে এখানে দোকানগুলো আসবে।')
              else
                HList(children: [
                  for (var i = 0; i < stops.length; i++) _row(stops[i], i + 1, pend.contains('${stops[i]['id']}'), editable),
                ]),
            ],
          ),
        );
      },
    );
  }

  Widget _row(Map<String, dynamic> s, int number, bool queued, bool editable) {
    final st = '${s['status']}';
    final dot = stopDot(s, number);
    final pending = st == 'Pending';
    final note = '${s['cancel_reason'] ?? ''}';
    final dist = _dist(s);
    final sub = !pending && note.isNotEmpty
        ? note
        : [
            if ('${s['address'] ?? ''}'.isNotEmpty) '${s['address']}',
            if (dist != null) (dist < 1000 ? '${bn(dist.round())} মি' : '${bn((dist / 1000).toStringAsFixed(1))} কিমি'),
            tk(pending ? stopBill(s) : stopCash(s)),
          ].join(' · ');
    final (chipText, chipBg, chipFg) = queued
        ? ('সিঙ্ক বাকি', HC.chip, HC.ink2)
        : switch (st) {
            'Delivered' => ('✓ দেওয়া', HC.soft, HC.blue),
            'Partial' => ('আংশিক', HC.redSoft, HC.red),
            'Due' => ('বাকি ${tk(s['due_amount'])}', HC.redSoft, HC.red),
            'Cancelled' => ('বাতিল', HC.chip, HC.muted),
            _ => ('', HC.chip, HC.ink),
          };
    return InkWell(
      onTap: () => _open(s),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 11),
        child: Row(children: [
          NumDot(dot.text, bg: dot.bg, fg: dot.fg, size: 36),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${s['retailer_name']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: hs(14.5, w: w6)),
            Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: hs(12, color: HC.muted, num: true)),
          ])),
          const SizedBox(width: 8),
          if (pending && !queued)
            HBtn('দিন', expand: false, height: 36, radius: 12, fontSize: 13, onTap: editable ? () => _open(s) : null)
          else
            HChip(chipText, bg: chipBg, fg: chipFg, size: 11),
        ]),
      ),
    );
  }

  Widget _buildMap(List<Map<String, dynamic>> stops) {
    final first = stops.firstWhere((s) => num0(s['lat']) != 0, orElse: () => {});
    final center = first.isNotEmpty ? LatLng(num0(first['lat']), num0(first['lng'])) : (_lat != null ? LatLng(_lat!, _lng!) : const LatLng(23.8645, 90.4005));
    return ColoredBox(
      color: const Color(0xFFE9EDF5),
      child: FlutterMap(
        mapController: _map,
        options: MapOptions(
          initialCenter: center, initialZoom: 15, maxZoom: 21,
          interactionOptions: const InteractionOptions(flags: InteractiveFlag.all & ~InteractiveFlag.rotate),
          onMapReady: () => _fitAll(stops),
          onPositionChanged: (_, byUser) {
            if (byUser && _follow) setState(() => _follow = false);
          },
        ),
        children: [
          if (kMapTiles) const BaseMapLayer(),
          if (stops.where((s) => num0(s['lat']) != 0).length > 1)
            PolylineLayer(polylines: [
              Polyline(points: [for (final s in stops) if (num0(s['lat']) != 0) LatLng(num0(s['lat']), num0(s['lng']))], color: const Color(0x991F4FE0), strokeWidth: 3, pattern: StrokePattern.dashed(segments: const [8, 6])),
            ]),
          MarkerLayer(markers: [
            for (var i = 0; i < stops.length; i++)
              if (num0(stops[i]['lat']) != 0)
                Marker(
                  point: LatLng(num0(stops[i]['lat']), num0(stops[i]['lng'])), width: 34, height: 34,
                  child: GestureDetector(
                    onTap: () => _open(stops[i]),
                    child: Builder(builder: (_) {
                      final dot = stopDot(stops[i], i + 1);
                      return Container(
                        decoration: BoxDecoration(color: dot.bg, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 2.5), boxShadow: HC.liftSm),
                        alignment: Alignment.center,
                        child: Text(dot.text, style: hs(13, w: w8, color: dot.fg, h: 1)),
                      );
                    }),
                  ),
                ),
          ]),
          MeLayer(map: _map, active: widget.active, follow: _follow, initial: _lat == null ? null : LatLng(_lat!, _lng!)),
        ],
      ),
    );
  }
}
