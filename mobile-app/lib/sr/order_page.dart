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
import '../ui/pwa_kit.dart';
import '../ui/skit.dart';
import '../ui/tracker_banner.dart';
import 'add_retailer.dart';
import 'order_editor.dart';

Map<String, dynamic> _m(Object? v) => Map<String, dynamic>.from((v ?? {}) as Map);

const _grayscale = ColorFilter.matrix(<double>[
  0.2126, 0.7152, 0.0722, 0, 0, //
  0.2126, 0.7152, 0.0722, 0, 0,
  0.2126, 0.7152, 0.0722, 0, 0,
  0, 0, 0, 1, 0,
]);

/// SR "অর্ডার" tab — the PWA's full-screen map: floating search bar, shop pins, bottom dock of shop cards.
class OrderPage extends StatefulWidget {
  const OrderPage({super.key});
  @override
  State<OrderPage> createState() => _OrderPageState();
}

class _OrderPageState extends State<OrderPage> {
  static const _scopeMetres = 50.0;
  final _search = TextEditingController();
  final _searchFocus = FocusNode();
  final _map = MapController();
  double? _lat, _lng;
  String _q = '';
  bool _collapsed = false;
  String? _focusedId;

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
    _searchFocus.addListener(() => setState(() {}));
    Tracker.currentOnce().then((p) {
      if (p != null && mounted) {
        setState(() {
          _lat = p.latitude;
          _lng = p.longitude;
        });
        _moveTo(p.latitude, p.longitude, 18);
      }
    });
  }

  @override
  void dispose() {
    _sync?.cancel();
    _live?.cancel();
    _search.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) setState(() => _loading = _data == null);
    try {
      final l = await loadCached('sr_bootstrap', () => ApiClient.get('/sr/bootstrap'));
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

  void _moveTo(double lat, double lng, double zoom) {
    try {
      _map.move(LatLng(lat, lng), zoom);
    } catch (_) {/* map not laid out yet */}
  }

  double? _dist(Map r) {
    if (_lat == null) return null;
    final lat = num0(r['lat']), lng = num0(r['lng']);
    if (lat == 0 && lng == 0) return null;
    const k = 0.017453292519943295;
    final a = 0.5 - cos((lat - _lat!) * k) / 2 + cos(_lat! * k) * cos(lat * k) * (1 - cos((lng - _lng!) * k)) / 2;
    return 12742000 * asin(sqrt(a)); // metres
  }

  String _distText(double? m) => m == null ? 'দূরত্ব অজানা' : (m < 1000 ? '${bn(m.round())} মি' : '${bn((m / 1000).toStringAsFixed(1))} কিমি');

  /// All shops that match the search (or, without a search, the shops within 50 m) — nearest first.
  List<Map<String, dynamic>> _visible(List retailers) {
    final q = _q.trim().toLowerCase();
    var rows = retailers.map(_m).toList();
    for (final r in rows) {
      r['_d'] = _dist(r);
    }
    if (q.isNotEmpty) {
      rows = rows.where((r) => '${r['name']} ${r['phone']} ${r['address']}'.toLowerCase().contains(q)).toList();
    } else if (_lat != null) {
      rows = rows.where((r) => r['_d'] != null && (r['_d'] as double) <= _scopeMetres).toList();
    }
    if (_lat != null) rows.sort((a, b) => ((a['_d'] as double?) ?? 9e12).compareTo((b['_d'] as double?) ?? 9e12));
    return rows.take(220).toList();
  }

  Map<String, dynamic>? _orderFor(List orders, Object? retailerId) {
    for (final o in orders) {
      if ('${(o as Map)['retailer_id']}' == '$retailerId' && o['status_key'] != 'cancelled') return _m(o);
    }
    for (final o in orders) {
      if ('${(o as Map)['retailer_id']}' == '$retailerId') return _m(o);
    }
    return null;
  }

  List<QueuedOp> get _pendingOrders => OfflineQueue.instance.ops.where((o) => o.method == 'POST' && o.path == '/sr/orders').toList();

  Future<void> _openEditor(List retailers, List products, Object? retailerId, {Map<String, dynamic>? existing}) async {
    Map<String, dynamic>? shop;
    for (final r in retailers) {
      if ('${(r as Map)['id']}' == '$retailerId') shop = _m(r);
    }
    shop ??= {'id': retailerId, 'name': existing?['retailer'] ?? 'দোকান', 'address': existing?['retailer_address'] ?? ''};
    setState(() => _focusedId = '$retailerId');
    if (shop['lat'] != null && num0(shop['lat']) != 0) _moveTo(num0(shop['lat']), num0(shop['lng']), 18);
    final saved = await Navigator.of(context).push<bool>(MaterialPageRoute(
      builder: (_) => OrderEditorPage(shop: shop!, products: products.map(_m).toList(), existing: existing),
    ));
    if (saved == true) _load(silent: true);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_data == null) {
      return ListView(padding: const EdgeInsets.all(20), children: [
        const SizedBox(height: 80),
        const Icon(Icons.cloud_off, size: 56, color: SC.muted),
        const SizedBox(height: 12),
        Text(_error is ApiException ? (_error as ApiException).message : 'লোড করা যায়নি।', textAlign: TextAlign.center, style: ts(14)),
        const SizedBox(height: 16),
        Center(child: SBtn('আবার চেষ্টা', kind: SBtnKind.secondary, onTap: _load)),
      ]);
    }
    final data = _data!;
    final day = _m(data['day']);
    final orders = (day['orders'] as List?) ?? [];
    final completed = day['completed'] == true || data['day_completed'] == true;
    final products = (data['products'] as List?) ?? [];
    final retailers = (data['retailers'] as List?) ?? [];
    final shown = _visible(retailers);
    final searching = _q.trim().isNotEmpty;

    return ListenableBuilder(
      listenable: OfflineQueue.instance,
      builder: (context, _) => Stack(children: [
        Positioned.fill(child: _buildMap(shown, orders)),
        // top bar
        Positioned(
          top: 10, left: 10, right: 10,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Expanded(child: _searchBox()),
              const SizedBox(width: 7),
              _pill('আজ', onTap: () => _openToday(day, orders, retailers, products, completed), kind: SBtnKind.secondary),
              const SizedBox(width: 7),
              _pill('নতুন দোকান', onTap: _addShop, kind: SBtnKind.navy, icon: const Svg(Ic.plus, size: 14, color: Colors.white, stroke: 2.4)),
            ]),
            if (_searchFocus.hasFocus && searching) _suggest(shown, orders, retailers, products),
            const SizedBox(height: 8),
            const TrackerBanner(role: 'sr'),
            if (_stale) const OfflineBanner(),
          ]),
        ),
        // bottom dock
        Positioned(left: 0, right: 0, bottom: 0, child: _dock(shown, orders, retailers, products, completed, searching)),
      ]),
    );
  }

  Widget _pill(String label, {required VoidCallback onTap, required SBtnKind kind, Widget? icon}) => Container(
        decoration: const BoxDecoration(boxShadow: [BoxShadow(color: Color(0x240F172A), blurRadius: 12, offset: Offset(0, 3))]),
        child: SBtn(label, onTap: onTap, kind: kind, icon: icon, height: 38, radius: 99, size: 12),
      );

  Widget _searchBox() => Container(
        height: 38, padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(color: SC.surface, borderRadius: BorderRadius.circular(99), border: Border.all(color: SC.border), boxShadow: const [BoxShadow(color: Color(0x1A0F172A), blurRadius: 12, offset: Offset(0, 3))]),
        child: Row(children: [
          const Svg('<circle cx="11" cy="11" r="8"/><path d="m21 21-4.3-4.3"/>', size: 15, color: SC.muted),
          const SizedBox(width: 6),
          Expanded(
            child: TextField(
              controller: _search, focusNode: _searchFocus, onChanged: (v) => setState(() => _q = v),
              style: ts(12.5, w: FontWeight.w600),
              decoration: InputDecoration(hintText: 'দোকান খুঁজুন (বাংলা / Banglish)…', hintStyle: ts(12.5, w: FontWeight.w600, color: SC.muted), border: InputBorder.none, isDense: true, filled: false, contentPadding: EdgeInsets.zero),
            ),
          ),
          if (_q.isNotEmpty)
            GestureDetector(
              onTap: () => setState(() { _search.clear(); _q = ''; }),
              child: Container(width: 20, height: 20, decoration: const BoxDecoration(color: SC.neutralBg, shape: BoxShape.circle), child: Center(child: Text('×', style: ts(14, color: SC.muted, h: 1)))),
            ),
        ]),
      );

  Widget _suggest(List<Map<String, dynamic>> shown, List orders, List retailers, List products) {
    final rows = shown.take(8).toList();
    return Container(
      margin: const EdgeInsets.only(top: 6), constraints: const BoxConstraints(maxHeight: 370),
      decoration: BoxDecoration(color: SC.surface, borderRadius: BorderRadius.circular(14), border: Border.all(color: SC.border), boxShadow: const [BoxShadow(color: Color(0x2E0F172A), blurRadius: 34, offset: Offset(0, 14))]),
      clipBehavior: Clip.antiAlias,
      child: rows.isEmpty
          ? Padding(padding: const EdgeInsets.all(12), child: Center(child: Text('"${_q.trim()}"-এর সাথে মিলে যাওয়া কোনো দোকান পাওয়া যায়নি।', style: ts(12, color: SC.muted))))
          : ListView(shrinkWrap: true, padding: EdgeInsets.zero, children: [
              for (var i = 0; i < rows.length; i++)
                InkWell(
                  onTap: () {
                    _searchFocus.unfocus();
                    final lat = num0(rows[i]['lat']), lng = num0(rows[i]['lng']);
                    setState(() => _focusedId = '${rows[i]['id']}');
                    if (lat != 0) _moveTo(lat, lng, 18);
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
                    decoration: BoxDecoration(border: i == rows.length - 1 ? null : const Border(bottom: BorderSide(color: SC.border))),
                    child: Row(children: [
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text('${rows[i]['name']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: ts(13, w: FontWeight.w700)),
                          Text('${rows[i]['address'] ?? rows[i]['phone'] ?? ''}', maxLines: 1, overflow: TextOverflow.ellipsis, style: ts(11.5, color: SC.muted)),
                        ]),
                      ),
                      if (rows[i]['_d'] != null) Text(_distText(rows[i]['_d'] as double), style: ts(11.5, color: SC.muted, tabular: true)),
                    ]),
                  ),
                ),
            ]),
    );
  }

  Widget _buildMap(List<Map<String, dynamic>> shown, List orders) {
    final first = shown.firstWhere((r) => num0(r['lat']) != 0, orElse: () => {});
    final center = _lat != null ? LatLng(_lat!, _lng!) : (first.isNotEmpty ? LatLng(num0(first['lat']), num0(first['lng'])) : const LatLng(23.8103, 90.4125));
    return Container(
      color: const Color(0xFFE5E7EB),
      child: FlutterMap(
        mapController: _map,
        options: MapOptions(initialCenter: center, initialZoom: 18, maxZoom: 21, interactionOptions: const InteractionOptions(flags: InteractiveFlag.all & ~InteractiveFlag.rotate)),
        children: [
          if (kMapTiles)
            ColorFiltered(
              colorFilter: _grayscale,
              child: TileLayer(
                urlTemplate: 'https://mt{s}.google.com/vt/lyrs=m&x={x}&y={y}&z={z}',
                subdomains: const ['0', '1', '2', '3'],
                maxNativeZoom: 20, userAgentPackageName: 'bd.happybangladesh.app',
              ),
            ),
          if (_lat != null)
            CircleLayer(circles: [CircleMarker(point: LatLng(_lat!, _lng!), radius: _scopeMetres, useRadiusInMeter: true, color: const Color(0x1A1A4FD8), borderColor: const Color(0x8C1A4FD8), borderStrokeWidth: 1.5)]),
          MarkerLayer(markers: [
            for (final r in shown)
              if (num0(r['lat']) != 0)
                Marker(
                  point: LatLng(num0(r['lat']), num0(r['lng'])), width: 170, height: 48, alignment: Alignment.topCenter,
                  child: GestureDetector(onTap: () => setState(() => _focusedId = '${r['id']}'), child: _pin('${r['name']}', _orderFor(orders, r['id']) != null, '${r['id']}' == _focusedId)),
                ),
            if (_lat != null)
              Marker(
                point: LatLng(_lat!, _lng!), width: 30, height: 30,
                child: Container(decoration: BoxDecoration(color: SC.cobalt, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 3), boxShadow: const [BoxShadow(color: Color(0x3D1A4FD8), spreadRadius: 6)])),
              ),
          ]),
        ],
      ),
    );
  }

  Widget _pin(String name, bool done, bool focused) => Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3), margin: const EdgeInsets.only(bottom: 3),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(7), border: Border.all(color: focused ? SC.cobalt : SC.borderStrong), boxShadow: [BoxShadow(color: focused ? const Color(0x331A4FD8) : const Color(0x290F172A), blurRadius: 10, offset: const Offset(0, 3))]),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Container(width: 7, height: 7, decoration: BoxDecoration(color: done ? SC.ok : SC.cobalt, shape: BoxShape.circle)),
            const SizedBox(width: 5),
            Flexible(child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: ts(11, w: FontWeight.w700, h: 1.3))),
          ]),
        ),
        Container(width: 12, height: 12, decoration: BoxDecoration(color: done ? SC.ok : SC.cobalt, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 2), boxShadow: const [BoxShadow(color: Color(0x590F172A), blurRadius: 6, offset: Offset(0, 2))])),
      ]);

  Widget _dock(List<Map<String, dynamic>> shown, List orders, List retailers, List products, bool completed, bool searching) {
    final pending = shown.where((r) => _orderFor(orders, r['id']) == null).length;
    final bottom = _collapsed ? 4.0 : 10.0;
    return Container(
      padding: EdgeInsets.fromLTRB(10, _collapsed ? 4 : 16, 10, bottom),
      decoration: BoxDecoration(
        color: _collapsed ? SC.surface : null,
        border: _collapsed ? const Border(top: BorderSide(color: SC.border)) : null,
        gradient: _collapsed ? null : const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0x00F3F6FB), Color(0xF0F3F6FB), SC.surface], stops: [0, 0.18, 0.38]),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: EdgeInsets.fromLTRB(4, 0, 4, _collapsed ? 4 : 8),
          child: Row(children: [
            Expanded(
              child: Wrap(spacing: 6, runSpacing: 2, crossAxisAlignment: WrapCrossAlignment.center, children: [
                const SSecTitle('কাছের দোকান'),
                Text(shown.isEmpty ? '' : (searching ? '· ${bn(shown.length)}টি পাওয়া গেছে' : '· ${bn(pending)}টি বাকি'), style: ts(12, w: FontWeight.w600, color: SC.muted, tabular: true)),
                SBadge(searching || _lat == null ? 'সকল এলাকা' : '৫০ মি.', tone: searching ? BadgeTone.cobalt : BadgeTone.info),
              ]),
            ),
            SBtn('সেন্টার', kind: SBtnKind.ghost, size: 11.5, onTap: () {
              if (_lat != null) _moveTo(_lat!, _lng!, 18);
            }),
            const SizedBox(width: 6),
            GestureDetector(
              onTap: () => setState(() => _collapsed = !_collapsed),
              child: Container(
                width: 34, height: 34, decoration: BoxDecoration(shape: BoxShape.circle, color: SC.surface, border: Border.all(color: SC.border)),
                child: Center(child: RotatedBox(quarterTurns: _collapsed ? 2 : 0, child: const Svg('<path d="m6 9 6 6 6-6"/>', size: 16, color: SC.ink2))),
              ),
            ),
          ]),
        ),
        if (!_collapsed)
          SizedBox(
            height: 108,
            child: shown.isEmpty
                ? Padding(padding: const EdgeInsets.all(6), child: Text(searching ? '"${_q.trim()}"-এর সাথে মিলে যাওয়া কোনো দোকান পাওয়া যায়নি।' : 'আপনার ৫০ মিটারের মধ্যে কোনো দোকান পাওয়া যায়নি।', style: ts(12, color: SC.muted)))
                : ListView.separated(
                    scrollDirection: Axis.horizontal, padding: const EdgeInsets.fromLTRB(2, 2, 2, 4), itemCount: shown.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 9),
                    itemBuilder: (_, i) => _shopCard(shown[i], orders, retailers, products, completed),
                  ),
          ),
      ]),
    );
  }

  Widget _shopCard(Map<String, dynamic> r, List orders, List retailers, List products, bool completed) {
    final o = _orderFor(orders, r['id']);
    final st = '${o?['status_key'] ?? ''}'.toLowerCase();
    final (bg, bd) = o == null
        ? (const Color(0xFF2563EB), const Color(0xFF1D4ED8))
        : st == 'cancelled'
            ? (const Color(0xFFD92D20), const Color(0xFFB42318))
            : (st == 'due' || st == 'partial')
                ? (const Color(0xFFD97706), const Color(0xFFB45309))
                : (const Color(0xFF059669), const Color(0xFF047857));
    final focused = '${r['id']}' == _focusedId;
    final badge = o == null ? 'অর্ডার বাকি' : (st == 'pending' ? 'অর্ডার হয়েছে' : statusBnKey(st.isEmpty ? '${o['status']}' : st));
    final sub = '${r['address'] ?? ''}'.isNotEmpty ? '${r['address']}' : ('${r['phone'] ?? ''}'.isNotEmpty ? '${r['phone']}' : 'অবস্থান পিনকৃত');
    final white = const Color(0xE0FFFFFF);
    return GestureDetector(
      onTap: () {
        if (completed) {
          toast(context, 'আজকের অর্ডার সম্পন্ন হয়েছে। পরিবর্তন করতে "আজ" থেকে দিনটি পুনরায় খুলুন।', error: true);
          return;
        }
        if (o != null && o['editable'] != true) {
          toast(context, '${r['name']}-এর অর্ডারটি ইতিমধ্যেই ট্রিপে দেওয়া হয়েছে।', error: true);
          return;
        }
        _openEditor(retailers, products, r['id'], existing: o != null && st != 'cancelled' ? o : null);
      },
      child: Container(
        width: 220, padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: bg, borderRadius: BorderRadius.circular(16), border: Border.all(color: focused ? Colors.white : bd),
          boxShadow: [BoxShadow(color: const Color(0x290F172A), blurRadius: 16, offset: const Offset(0, 6)), if (focused) const BoxShadow(color: SC.ink, spreadRadius: 2.5)],
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(child: Text('${r['name']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: ts(13.5, w: FontWeight.w700, color: Colors.white, h: 1.25))),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(color: const Color(0x38FFFFFF), borderRadius: BorderRadius.circular(99), border: Border.all(color: const Color(0x5CFFFFFF))),
              child: Text(badge, style: ts(10.5, w: FontWeight.w600, color: Colors.white, h: 1.4)),
            ),
          ]),
          const SizedBox(height: 6),
          Text('$sub · ${_distText(r['_d'] as double?)}', maxLines: 1, overflow: TextOverflow.ellipsis, style: ts(11.5, color: white, tabular: true)),
          const Spacer(),
          Container(
            padding: const EdgeInsets.only(top: 6),
            decoration: const BoxDecoration(border: Border(top: BorderSide(color: Color(0x3DFFFFFF)))),
            child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Flexible(child: Text(o != null ? 'আজকের অর্ডার' : 'পূর্বের বকেয়া', maxLines: 1, overflow: TextOverflow.ellipsis, style: ts(12, color: white))),
              const SizedBox(width: 6),
              Text(bnMoney(o != null ? o['sr_total'] : (r['due'] ?? 0), smart: true), style: ts(12, w: FontWeight.w700, color: Colors.white, tabular: true)),
            ]),
          ),
        ]),
      ),
    );
  }

  Future<void> _addShop() async {
    final added = await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => const AddRetailerPage()));
    if (added == true) _load(silent: true);
  }

  Future<void> _complete(bool reopen) async {
    final ok = await confirm(context, reopen ? 'আজকের দিন আবার খুলবেন?' : 'আজকের অর্ডার সম্পন্ন করবেন?',
        body: reopen ? 'খুললে অর্ডার যোগ বা পরিবর্তন করতে পারবেন।' : 'সম্পন্ন করলে অর্ডারগুলো ডেলিভারি ট্রিপের জন্য প্রস্তুত হবে।', yes: reopen ? 'খুলুন' : 'সম্পন্ন করুন');
    if (!ok || !mounted) return;
    final r = await busy(context, () => OfflineQueue.write('POST', reopen ? '/sr/orders/reopen' : '/sr/orders/complete',
        body: {'at': DateTime.now().millisecondsSinceEpoch ~/ 1000}, label: reopen ? 'দিন আবার খোলা' : 'আজকের অর্ডার সম্পন্ন', queueable: !reopen));
    if (r != null && mounted) {
      toast(context, r.queued ? 'ইন্টারনেট এলে সম্পন্ন হবে।' : (r.data['message'] ?? 'হয়েছে।').toString());
      _load(silent: true);
    }
  }

  Future<void> _openToday(Map<String, dynamic> day, List orders, List retailers, List products, bool completed) async {
    final totals = _m(day['totals']);
    final oc = num0(totals['oc']);
    final pend = _pendingOrders;
    final action = await showModalBottomSheet<String>(
      context: context, isScrollControlled: true, backgroundColor: Colors.transparent, useSafeArea: true,
      builder: (ctx) => Align(
        alignment: Alignment.bottomCenter,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: kFrameW, maxHeight: MediaQuery.of(ctx).size.height * 0.88),
          child: Container(
            decoration: const BoxDecoration(color: SC.surface, borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
            clipBehavior: Clip.antiAlias,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Padding(padding: const EdgeInsets.only(top: 9, bottom: 3), child: Container(width: 38, height: 4, decoration: BoxDecoration(color: SC.borderStrong, borderRadius: BorderRadius.circular(99)))),
              Container(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: SC.border))),
                child: Row(children: [
                  Expanded(child: SSecTitle('আজকের অর্ডারসমূহ', sub: '${bn(day['date'] ?? '')} · ${bn(totals['orders'] ?? 0)}টি অর্ডার · ${bnMoney(totals['value'] ?? 0, smart: true)} · O/C ${signedMoney(oc, smart: true)}')),
                  GestureDetector(onTap: () => Navigator.pop(ctx), child: Container(width: 34, height: 34, decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: SC.border)), child: const Center(child: Svg('<path d="M18 6 6 18M6 6l12 12"/>', size: 16, color: SC.ink2, stroke: 2.2)))),
                ]),
              ),
              Flexible(
                child: ListView(shrinkWrap: true, padding: const EdgeInsets.all(16), children: [
                  SDayStatus(done: completed, Text(completed
                      ? (day['locked'] == true ? 'সম্পন্ন — অর্ডারগুলো ডেলিভারি ট্রিপে দেওয়া হয়েছে।' : 'সম্পন্ন — ডেলিভারি ট্রিপের অপেক্ষায়। পরিবর্তনের জন্য পুনরায় খুলুন।')
                      : 'খোলা আছে — দিনের কাজ শেষে "আজকের অর্ডার সম্পন্ন করুন" চাপুন যাতে পার্টনার ট্রিপে দিতে পারেন।')),
                  const SizedBox(height: 10),
                  for (final o in pend)
                    Container(
                      margin: const EdgeInsets.only(bottom: 8), padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                      decoration: BoxDecoration(color: SC.warnBg, borderRadius: BorderRadius.circular(12), border: Border.all(color: SC.warnBorder)),
                      child: Row(children: [
                        const Icon(Icons.schedule, color: SC.warn, size: 20),
                        const SizedBox(width: 10),
                        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(_retailerName(retailers, (o.body as Map)['retailer_id']), style: ts(13, w: FontWeight.w700)),
                          Text('${bn(((o.body as Map)['items'] as List).length)}টি পণ্য · ইন্টারনেট এলে যাবে', style: ts(11.5, color: SC.warnText)),
                        ])),
                      ]),
                    ),
                  if (orders.isEmpty && pend.isEmpty) const SEmpty('আজ এখনো কোনো অর্ডার নেই।'),
                  for (final raw in orders)
                    Builder(builder: (_) {
                      final o = _m(raw);
                      final ocv = num0(o['oc']);
                      final editable = o['editable'] == true && !completed;
                      return Container(
                        margin: const EdgeInsets.only(bottom: 8), padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                        decoration: BoxDecoration(color: SC.surface, borderRadius: BorderRadius.circular(12), border: Border.all(color: SC.border)),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text('${o['retailer']}', style: ts(13.5, w: FontWeight.w700)),
                              Text('${bn(o['code'])} · ${bn((o['items'] as List).length)}টি পণ্য · ${bn(o['time'] ?? '')}${o['trip'] != null && '${o['trip']}'.isNotEmpty ? ' · ${bn(o['trip'])}' : ''}', style: ts(12, color: SC.muted, tabular: true)),
                            ])),
                            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                              Text(bnMoney(o['sr_total'], smart: true), style: ts(13.5, w: FontWeight.w700, tabular: true)),
                              Text('O/C ${signedMoney(ocv, smart: true)}', style: ts(12, w: ocv == 0 ? FontWeight.w400 : FontWeight.w600, color: ocv > 0 ? SC.ok : (ocv < 0 ? SC.dangerText : SC.muted), tabular: true)),
                            ]),
                          ]),
                          const SizedBox(height: 6),
                          if (editable)
                            Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                              SBtn('সম্পাদনা', kind: SBtnKind.secondary, size: 11.5, onTap: () {
                                Navigator.pop(ctx);
                                _openEditor(retailers, products, o['retailer_id'], existing: o);
                              }),
                              const SizedBox(width: 6),
                              SBtn('বাতিল', kind: SBtnKind.dangerGhost, size: 11.5, onTap: () async {
                                if (!await confirm(ctx, 'অর্ডার বাতিল করবেন?', danger: true, yes: 'বাতিল করুন')) return;
                                if (!ctx.mounted) return;
                                final r = await busy(ctx, () => ApiClient.send('DELETE', '/sr/orders/${o['id']}'));
                                if (r != null && ctx.mounted) {
                                  toast(ctx, (r['message'] ?? 'বাতিল হয়েছে।').toString());
                                  Navigator.pop(ctx, 'reload');
                                }
                              }),
                            ])
                          else
                            Align(alignment: Alignment.centerRight, child: SBadge(statusBnKey('${o['status_key'] ?? o['status']}'), tone: o['editable'] == true ? BadgeTone.neutral : BadgeTone.info)),
                        ]),
                      );
                    }),
                ]),
              ),
              if (orders.isNotEmpty || completed)
                Container(
                  padding: EdgeInsets.fromLTRB(14, 12, 14, 14 + MediaQuery.of(ctx).padding.bottom),
                  decoration: const BoxDecoration(border: Border(top: BorderSide(color: SC.border))),
                  child: completed
                      ? SBtn('আজকের দিন পুনরায় খুলুন', kind: SBtnKind.secondary, block: true, onTap: () => Navigator.pop(ctx, 'reopen'))
                      : SBtn('আজকের অর্ডার সম্পন্ন করুন', block: true, onTap: () => Navigator.pop(ctx, 'complete')),
                ),
            ]),
          ),
        ),
      ),
    );
    if (!mounted) return;
    if (action == 'complete') {
      await _complete(false);
    } else if (action == 'reopen') {
      await _complete(true);
    } else if (action == 'reload') {
      _load(silent: true);
    }
  }

  String _retailerName(List retailers, Object? id) {
    for (final r in retailers) {
      if ('${(r as Map)['id']}' == '$id') return r['name'].toString();
    }
    return 'দোকান #$id';
  }
}
