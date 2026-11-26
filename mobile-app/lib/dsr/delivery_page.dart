import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../core/api.dart';
import '../core/format.dart';
import '../core/offline.dart';
import '../core/realtime.dart';
import '../core/tracker.dart';
import '../ui/common.dart';
import '../ui/dkit.dart';
import '../ui/pwa_kit.dart';
import 'ready_sale_page.dart';
import 'stop_page.dart';

Map<String, dynamic> _m(Object? v) => Map<String, dynamic>.from((v ?? {}) as Map);

Color statusColor(String s) => switch (s) {
      'Delivered' => DC.okText,
      'Due' => DC.dangerText,
      'Partial' => DC.warnText,
      'Cancelled' => DC.muted,
      _ => DC.infoText,
    };

String statusBn(String s) => switch (s) {
      'Delivered' => 'ডেলিভারি হয়েছে',
      'Due' => 'বাকি',
      'Partial' => 'আংশিক',
      'Cancelled' => 'বাতিল',
      'Pending' => 'বাকি আছে',
      _ => s,
    };

const _grayscale = ColorFilter.matrix(<double>[
  0.2126, 0.7152, 0.0722, 0, 0, //
  0.2126, 0.7152, 0.0722, 0, 0,
  0.2126, 0.7152, 0.0722, 0, 0,
  0, 0, 0, 1, 0,
]);

/// DSR "ডেলিভারি" tab — the PWA's full-screen delivery map: floating date nav + রেডি সেল, shop pins,
/// bottom dock of status-coloured order cards. Tapping a card opens that shop's delivery.
class DeliveryPage extends StatefulWidget {
  const DeliveryPage({super.key});
  @override
  State<DeliveryPage> createState() => _DeliveryPageState();
}

class _DeliveryPageState extends State<DeliveryPage> {
  final _map = MapController();
  String? _date; // null = the open trip
  double? _lat, _lng;
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
    Tracker.currentOnce().then((p) {
      if (p != null && mounted) setState(() {
        _lat = p.latitude;
        _lng = p.longitude;
      });
    });
  }

  @override
  void dispose() {
    _sync?.cancel();
    _live?.cancel();
    super.dispose();
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

  String _distText(double? m) => m == null ? 'দূরত্ব অজানা' : (m < 1000 ? '${bn(m.round())} মি' : '${bn((m / 1000).toStringAsFixed(1))} কিমি');

  /// What the shop should pay for the pieces that will be delivered (ordered, capped by van stock, minus cancelled ones).
  double _shouldPay(Map<String, dynamic> s) {
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

  void _fitAll(List<Map<String, dynamic>> stops) {
    final pts = [for (final s in stops) if (num0(s['lat']) != 0) LatLng(num0(s['lat']), num0(s['lng']))];
    if (_lat != null) pts.add(LatLng(_lat!, _lng!));
    if (pts.isEmpty) return;
    try {
      if (pts.length == 1) {
        _map.move(pts.first, 17);
      } else {
        _map.fitCamera(CameraFit.bounds(bounds: LatLngBounds.fromPoints(pts), padding: const EdgeInsets.fromLTRB(28, 68, 28, 190), maxZoom: 18));
      }
    } catch (_) {/* map not ready */}
  }

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.of(context).padding.top;
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_data == null) {
      return ListView(padding: const EdgeInsets.all(20), children: [
        const SizedBox(height: 80),
        const Icon(Icons.cloud_off, size: 56, color: DC.muted),
        const SizedBox(height: 12),
        Text(_error is ApiException ? (_error as ApiException).message : 'লোড করা যায়নি।', textAlign: TextAlign.center, style: ts(14)),
        const SizedBox(height: 16),
        Center(child: DBtn('আবার চেষ্টা', kind: DBtnKind.secondary, onTap: _load)),
      ]);
    }
    final d = _data!;
    final trip = d['trip'] == null ? null : _m(d['trip']);
    final date = d['selectedDate'].toString();
    final stops = (d['orders'] as List).map(_m).toList();
    final vanStock = (d['vanStock'] as List).map(_m).toList();
    final reasons = (d['cancelReasons'] as List).map((e) => '$e').toList();
    final damageProducts = (d['damageProducts'] as List).map(_m).toList();
    final editable = trip != null && trip['editable'] == true;
    for (final s in stops) {
      s['_d'] = _dist(s);
    }
    stops.sort((a, b) {
      int rank(Map s) => s['status'] == 'Pending' ? 0 : 1;
      final r = rank(a).compareTo(rank(b));
      if (r != 0) return r;
      return ((a['_d'] as double?) ?? 9e12).compareTo((b['_d'] as double?) ?? 9e12);
    });
    final pending = stops.where((s) => s['status'] == 'Pending').length;

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
        return Stack(children: [
          Positioned.fill(child: _buildMap(stops)),
          Positioned(
            top: top + 10, left: 10, right: 10,
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                Expanded(
                  child: DDateNav(date: date, subText: trip != null ? bn('${trip['code']}') : 'ট্রিপ নেই', onChange: (v) {
                    setState(() => _date = v == todayYmd() ? null : v);
                    _load();
                  }),
                ),
                const SizedBox(width: 8),
                Container(
                  decoration: const BoxDecoration(boxShadow: [BoxShadow(color: Color(0x240F172A), blurRadius: 12, offset: Offset(0, 4))]),
                  child: DBtn('রেডি সেল', small: true, height: 38, icon: const Svg(Ic.plus, size: 14, color: Colors.white, stroke: 2.2),
                      onTap: editable ? () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ReadySalePage(vanStock: vanStock))).then((v) => v == true ? _load(silent: true) : null) : null),
                ),
              ]),
              if (banner != null) Padding(padding: const EdgeInsets.only(top: 8), child: DBanner(banner, returned: returned, muted: trip == null)),
              if (_stale) const Padding(padding: EdgeInsets.only(top: 8), child: OfflineBanner()),
            ]),
          ),
          Positioned(
            right: 12, bottom: 184,
            child: GestureDetector(
              onTap: () => _fitAll(stops),
              child: Container(
                width: 40, height: 40,
                decoration: BoxDecoration(color: DC.surface, shape: BoxShape.circle, border: Border.all(color: DC.border), boxShadow: const [BoxShadow(color: Color(0x240F172A), blurRadius: 14, offset: Offset(0, 4))]),
                child: const Center(child: Svg('<circle cx="12" cy="12" r="3"/><path d="M12 2v3M12 19v3M2 12h3M19 12h3"/><circle cx="12" cy="12" r="7" stroke-dasharray="2 2"/>', size: 18, color: DC.ink)),
              ),
            ),
          ),
          Positioned(
            left: 0, right: 0, bottom: 0,
            child: Container(
              padding: const EdgeInsets.fromLTRB(10, 18, 10, 10),
              decoration: const BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0x00F7F8FA), Color(0xF0F7F8FA), DC.surface], stops: [0, 0.18, 0.38])),
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
                  child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                    Row(children: [Text('কাছাকাছি অর্ডার', style: ts(13, w: FontWeight.w700)), const SizedBox(width: 6), DBadge(bn(stops.length))]),
                    Flexible(child: Text(trip == null ? '${dateBn(date)}-এ কোনো ট্রিপ নেই' : '${bn(stops.length)}টি স্টপের মধ্যে ${bn(pending)}টি বাকি', maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.right, style: ts(12, color: DC.muted, tabular: true))),
                  ]),
                ),
                SizedBox(
                  height: 108,
                  child: stops.isEmpty
                      ? Padding(padding: const EdgeInsets.all(6), child: Text(trip == null ? 'এই তারিখে কোনো ডিসপ্যাচ করা ট্রিপ নেই।' : 'এই ট্রিপে কোনো অর্ডার নেই।', style: ts(12, color: DC.muted)))
                      : ListView.separated(
                          scrollDirection: Axis.horizontal, padding: const EdgeInsets.fromLTRB(2, 2, 2, 4), itemCount: stops.length,
                          separatorBuilder: (_, __) => const SizedBox(width: 9),
                          itemBuilder: (_, i) => _card(stops[i], pend.contains('${stops[i]['id']}'), reasons, damageProducts, editable),
                        ),
                ),
              ]),
            ),
          ),
        ]);
      },
    );
  }

  Widget _buildMap(List<Map<String, dynamic>> stops) {
    final first = stops.firstWhere((s) => num0(s['lat']) != 0, orElse: () => {});
    final center = _lat != null ? LatLng(_lat!, _lng!) : (first.isNotEmpty ? LatLng(num0(first['lat']), num0(first['lng'])) : const LatLng(23.8645, 90.4005));
    return Container(
      color: const Color(0xFFE5E7EB),
      child: FlutterMap(
        mapController: _map,
        options: MapOptions(
          initialCenter: center, initialZoom: 16, maxZoom: 21,
          interactionOptions: const InteractionOptions(flags: InteractiveFlag.all & ~InteractiveFlag.rotate),
          onMapReady: () => _fitAll(stops),
        ),
        children: [
          if (kMapTiles)
            ColorFiltered(
              colorFilter: _grayscale,
              child: TileLayer(urlTemplate: 'https://mt{s}.google.com/vt/lyrs=m&x={x}&y={y}&z={z}', subdomains: const ['0', '1', '2', '3'], maxNativeZoom: 20, userAgentPackageName: 'bd.happybangladesh.app'),
            ),
          MarkerLayer(markers: [
            for (final s in stops)
              if (num0(s['lat']) != 0)
                Marker(
                  point: LatLng(num0(s['lat']), num0(s['lng'])), width: 170, height: 48, alignment: Alignment.topCenter,
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3), margin: const EdgeInsets.only(bottom: 3),
                      decoration: BoxDecoration(color: DC.surface, borderRadius: BorderRadius.circular(7), border: Border.all(color: DC.borderStrong), boxShadow: const [BoxShadow(color: Color(0x240F172A), blurRadius: 10, offset: Offset(0, 3))]),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Container(width: 7, height: 7, decoration: BoxDecoration(shape: BoxShape.circle, color: switch ('${s['status']}') { 'Delivered' => DC.ok, 'Due' || 'Partial' => DC.warn, 'Cancelled' => DC.danger, _ => const Color(0xFF2563EB) })),
                        const SizedBox(width: 5),
                        Flexible(child: Text('${s['retailer_name']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: ts(11, w: FontWeight.w600, h: 1.3))),
                      ]),
                    ),
                    Container(width: 11, height: 11, decoration: BoxDecoration(color: DC.accent, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 2), boxShadow: const [BoxShadow(color: Color(0x400F172A), blurRadius: 6, offset: Offset(0, 2))])),
                  ]),
                ),
            if (_lat != null)
              Marker(
                point: LatLng(_lat!, _lng!), width: 28, height: 28,
                child: Container(decoration: BoxDecoration(color: const Color(0xFF2563EB), shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 2.5), boxShadow: const [BoxShadow(color: Color(0x402563EB), spreadRadius: 3)])),
              ),
          ]),
        ],
      ),
    );
  }

  Widget _card(Map<String, dynamic> s, bool queued, List<String> reasons, List<Map<String, dynamic>> damageProducts, bool editable) {
    final st = '${s['status']}';
    final (bg, bd) = switch (st) {
      'Delivered' => (const Color(0xFF059669), const Color(0xFF047857)),
      'Due' || 'Partial' => (const Color(0xFFD97706), const Color(0xFFB45309)),
      'Cancelled' => (const Color(0xFFD92D20), const Color(0xFFB42318)),
      _ => (const Color(0xFF2563EB), const Color(0xFF1D4ED8)),
    };
    final pending = st == 'Pending';
    final paid = num0(s['paid_amount']) + num0(s['old_due_collected']);
    final sub = '${s['address'] ?? ''}'.isNotEmpty ? '${s['address']}' : ('${s['phone'] ?? ''}'.isNotEmpty ? '${s['phone']}' : 'অবস্থান পিনকৃত');
    const white = Color(0xE0FFFFFF);
    return GestureDetector(
      onTap: () => Navigator.of(context)
          .push<bool>(MaterialPageRoute(builder: (_) => StopPage(stop: s, reasons: reasons, editable: editable, damageProducts: damageProducts)))
          .then((v) => v == true ? _load(silent: true) : null),
      child: Container(
        width: 220, padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 10),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12), border: Border.all(color: bd), boxShadow: const [BoxShadow(color: Color(0x290F172A), blurRadius: 16, offset: Offset(0, 6))]),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(child: Text('${s['retailer_name']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: ts(13.5, w: FontWeight.w700, color: Colors.white, h: 1.25))),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(color: const Color(0x38FFFFFF), borderRadius: BorderRadius.circular(99), border: Border.all(color: const Color(0x5CFFFFFF))),
              child: Text(queued ? 'সিঙ্ক বাকি' : statusBn(st), style: ts(10.5, w: FontWeight.w600, color: Colors.white, h: 1.4)),
            ),
          ]),
          const SizedBox(height: 6),
          Text('$sub · ${_distText(s['_d'] as double?)}', maxLines: 1, overflow: TextOverflow.ellipsis, style: ts(11.5, color: white, tabular: true)),
          const Spacer(),
          Container(
            padding: const EdgeInsets.only(top: 6),
            decoration: const BoxDecoration(border: Border(top: BorderSide(color: Color(0x3DFFFFFF)))),
            child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Text(pending ? 'পরিশোধযোগ্য' : 'পরিশোধ / বকেয়া', style: ts(12, color: white)),
              Flexible(child: Text(pending ? bnMoney(_shouldPay(s), smart: true) : '${bnMoney(paid, smart: true)} / ${bnMoney(s['due_amount'] ?? 0, smart: true)}', maxLines: 1, overflow: TextOverflow.ellipsis, style: ts(12, w: FontWeight.w700, color: Colors.white, tabular: true))),
            ]),
          ),
        ]),
      ),
    );
  }
}
