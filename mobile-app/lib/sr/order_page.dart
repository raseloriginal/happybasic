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
import '../ui/pwa_kit.dart';
import '../ui/hkit.dart';
import '../ui/me_layer.dart';
import '../ui/tracker_banner.dart';
import 'add_retailer.dart';
import 'order_editor.dart';

Map<String, dynamic> _m(Object? v) => Map<String, dynamic>.from((v ?? {}) as Map);

/// SR2 · দোকান বাছুন: full-screen map, search, numbered shop pins, nearby sheet (nearest first).
class OrderPage extends StatefulWidget {
  const OrderPage({super.key, this.onBack, this.active = true});
  /// The tab is on screen: live GPS runs only then.
  final bool active;
  /// Back to the আজ tab (the design's round back button).
  final VoidCallback? onBack;
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
  bool _follow = true; // the camera glides with me until I drag the map

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
    Tracker.instance.fix.addListener(_onFix);
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
    Tracker.instance.fix.removeListener(_onFix);
    _sync?.cancel();
    _live?.cancel();
    _search.dispose();
    _searchFocus.dispose();
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
    shop['_dist'] = shop['lat'] == null ? null : _distText(_dist(shop));
    setState(() {
      _focusedId = '$retailerId';
      _follow = false;
    });
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
        const Icon(Icons.cloud_off_rounded, size: 56, color: HC.faint),
        gap12,
        Text(_error is ApiException ? (_error as ApiException).message : 'লোড করা যায়নি।', textAlign: TextAlign.center, style: hs(14)),
        gap16,
        Center(child: HBtn('আবার চেষ্টা', kind: HBtnKind.line, expand: false, onTap: _load)),
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
    final top = MediaQuery.of(context).padding.top;
    // Numbers follow the list order (nearest first); shops already ordered get a tick.
    final numbers = <String, int>{};
    var n = 0;
    for (final r in shown) {
      if (_orderFor(orders, r['id']) == null) numbers['${r['id']}'] = ++n;
    }

    return ListenableBuilder(
      listenable: OfflineQueue.instance,
      builder: (context, _) => Stack(children: [
        Positioned.fill(child: _buildMap(shown, orders, numbers)),
        Positioned(
          top: top + 14, left: 18, right: 18,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              if (widget.onBack != null) ...[_roundBtn(icon: Ic.back, label: 'ফিরে যান', onTap: widget.onBack!), const SizedBox(width: 10)],
              Expanded(child: _searchBox()),
              const SizedBox(width: 10),
              _todayBtn(orders.length, completed, () => _openToday(day, orders, retailers, products, completed)),
              const SizedBox(width: 10),
              _roundBtn(icon: Ic.plus, label: 'নতুন দোকান যোগ করুন', onTap: _addShop, dark: true),
            ]),
            if (_searchFocus.hasFocus && searching) _suggest(shown, orders, retailers, products),
            const SizedBox(height: 10),
            const TrackerBanner(role: 'sr'),
            if (_stale)
              Align(child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(color: const Color(0xF00A1640), borderRadius: BorderRadius.circular(999)),
                child: Text('অফলাইন · সংরক্ষিত তালিকা', style: hs(12, w: w6, color: Colors.white)),
              )),
          ]),
        ),
        Positioned(left: 0, right: 0, bottom: 0, child: _sheet(shown, orders, retailers, products, completed, searching, numbers)),
      ]),
    );
  }

  Widget _roundBtn({required String icon, required String label, required VoidCallback onTap, bool dark = false}) => Semantics(
        button: true, label: label,
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            width: 46, height: 46,
            decoration: BoxDecoration(color: dark ? HC.ink : Colors.white, shape: BoxShape.circle,
                boxShadow: [BoxShadow(color: dark ? const Color(0x400A1640) : const Color(0x260A1640), blurRadius: 16, offset: const Offset(0, 6))]),
            alignment: Alignment.center,
            child: Svg(icon, size: 20, color: dark ? Colors.white : HC.ink, stroke: 2.2),
          ),
        ),
      );

  Widget _todayBtn(int count, bool done, VoidCallback onTap) => Semantics(
        button: true, label: 'আজকের অর্ডার',
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            height: 46, padding: const EdgeInsets.symmetric(horizontal: 12), alignment: Alignment.center,
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(23), boxShadow: HC.liftSm),
            child: Text('আজ · ${bn(count)}${done ? ' ✓' : ''}', style: hs(12, w: w7, num: true)),
          ),
        ),
      );

  Widget _searchBox() => Container(
        height: 46, padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(23), boxShadow: HC.liftSm),
        child: Row(children: [
          const Svg('<circle cx="11" cy="11" r="8"/><path d="m21 21-4.3-4.3"/>', size: 16, color: HC.muted),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: _search, focusNode: _searchFocus, onChanged: (v) => setState(() => _q = v),
              textInputAction: TextInputAction.search, style: hs(14),
              decoration: InputDecoration(hintText: 'দোকান খুঁজুন', hintStyle: hs(14, color: HC.muted), border: InputBorder.none, enabledBorder: InputBorder.none, focusedBorder: InputBorder.none, isDense: true, filled: false, contentPadding: EdgeInsets.zero),
            ),
          ),
          if (_q.isNotEmpty)
            GestureDetector(
              onTap: () => setState(() {
                _search.clear();
                _q = '';
              }),
              child: Container(width: 22, height: 22, decoration: const BoxDecoration(color: HC.chip, shape: BoxShape.circle), child: Center(child: Text('×', style: hs(15, color: HC.muted, h: 1)))),
            ),
        ]),
      );

  Widget _suggest(List<Map<String, dynamic>> shown, List orders, List retailers, List products) {
    final rows = shown.take(8).toList();
    return Container(
      margin: const EdgeInsets.only(top: 8), constraints: const BoxConstraints(maxHeight: 360),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), boxShadow: HC.lift),
      clipBehavior: Clip.antiAlias,
      child: rows.isEmpty
          ? Padding(padding: const EdgeInsets.all(14), child: Text('"${_q.trim()}"-এর সাথে মিলে যাওয়া কোনো দোকান পাওয়া যায়নি।', textAlign: TextAlign.center, style: hs(13, color: HC.muted)))
          : ListView(shrinkWrap: true, padding: const EdgeInsets.symmetric(horizontal: 14), children: [
              for (var i = 0; i < rows.length; i++)
                InkWell(
                  onTap: () {
                    _searchFocus.unfocus();
                    final lat = num0(rows[i]['lat']), lng = num0(rows[i]['lng']);
                    setState(() {
                      _focusedId = '${rows[i]['id']}';
                      _follow = false;
                    });
                    if (lat != 0) _moveTo(lat, lng, 18);
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 11),
                    decoration: BoxDecoration(border: i == 0 ? null : const Border(top: BorderSide(color: HC.line))),
                    child: Row(children: [
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('${rows[i]['name']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: hs(14, w: w6)),
                        Text('${rows[i]['address'] ?? rows[i]['phone'] ?? ''}', maxLines: 1, overflow: TextOverflow.ellipsis, style: hs(12, color: HC.muted)),
                      ])),
                      if (rows[i]['_d'] != null) Text(_distText(rows[i]['_d'] as double), style: hs(12, color: HC.muted, num: true)),
                    ]),
                  ),
                ),
            ]),
    );
  }

  Widget _buildMap(List<Map<String, dynamic>> shown, List orders, Map<String, int> numbers) {
    final first = shown.firstWhere((r) => num0(r['lat']) != 0, orElse: () => {});
    final center = _lat != null ? LatLng(_lat!, _lng!) : (first.isNotEmpty ? LatLng(num0(first['lat']), num0(first['lng'])) : const LatLng(23.8103, 90.4125));
    return Container(
      color: const Color(0xFFE9EEF6),
      child: FlutterMap(
        mapController: _map,
        options: MapOptions(
          initialCenter: center, initialZoom: 18, maxZoom: 21,
          interactionOptions: const InteractionOptions(flags: InteractiveFlag.all & ~InteractiveFlag.rotate),
          onPositionChanged: (_, byUser) {
            if (byUser && _follow) setState(() => _follow = false);
          },
        ),
        children: [
          if (kMapTiles) const BaseMapLayer(),
          MarkerLayer(markers: [
            for (final r in shown)
              if (num0(r['lat']) != 0)
                Marker(
                  point: LatLng(num0(r['lat']), num0(r['lng'])), width: 180, height: 54, alignment: Alignment.topCenter,
                  child: GestureDetector(
                    onTap: () => setState(() => _focusedId = '${r['id']}'),
                    child: _pin('${r['name']}', numbers['${r['id']}'], '${r['id']}' == _focusedId),
                  ),
                ),
          ]),
          MeLayer(map: _map, active: widget.active, follow: _follow, scopeMetres: _scopeMetres, initial: _lat == null ? null : LatLng(_lat!, _lng!)),
        ],
      ),
    );
  }

  /// SR2 pin: white pill with a blue number (✓ on navy when ordered); the focused one turns blue.
  Widget _pin(String name, int? number, bool focused) {
    final done = number == null;
    final stem = done ? HC.ink : HC.blue;
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Container(
        padding: const EdgeInsets.fromLTRB(4, 4, 10, 4),
        decoration: BoxDecoration(color: focused ? HC.blue : Colors.white, borderRadius: BorderRadius.circular(999),
            boxShadow: const [BoxShadow(color: Color(0x380A1640), blurRadius: 16, offset: Offset(0, 6))]),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 22, height: 22, alignment: Alignment.center,
            decoration: BoxDecoration(color: focused ? Colors.white : (done ? HC.ink : HC.blue), shape: BoxShape.circle),
            child: Text(done ? '✓' : bn(number), style: hs(11, w: w7, color: focused ? HC.blue : Colors.white, h: 1)),
          ),
          const SizedBox(width: 6),
          Flexible(child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: hs(12, w: w7, color: focused ? Colors.white : HC.ink, h: 1.2))),
        ]),
      ),
      Container(width: 2, height: 10, color: stem),
      Container(width: 10, height: 10, decoration: BoxDecoration(color: stem, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 2))),
    ]);
  }

  /// SR2 bottom sheet: "কাছের দোকান", numbered list nearest first, order / edit button per shop.
  Widget _sheet(List<Map<String, dynamic>> shown, List orders, List retailers, List products, bool completed, bool searching, Map<String, int> numbers) {
    final pending = shown.where((r) => _orderFor(orders, r['id']) == null).length;
    final maxH = MediaQuery.of(context).size.height * .42;
    return Container(
      decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          boxShadow: [BoxShadow(color: Color(0x240A1640), blurRadius: 30, offset: Offset(0, -12))]),
      padding: const EdgeInsets.fromLTRB(18, 10, 18, 4),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => setState(() => _collapsed = !_collapsed),
          onVerticalDragEnd: (d) {
            final v = d.primaryVelocity ?? 0;
            if (v.abs() > 120) setState(() => _collapsed = v > 0);
          },
          child: Column(children: [
            Center(child: Container(width: 40, height: 5, margin: const EdgeInsets.only(bottom: 10), decoration: BoxDecoration(color: HC.line2, borderRadius: BorderRadius.circular(3)))),
            Row(children: [
              Text(searching ? 'খোঁজার ফলাফল' : 'কাছের দোকান', style: hs(17, w: w7)),
              const SizedBox(width: 8),
              Expanded(child: Text(
                shown.isEmpty ? '' : (searching ? '${bn(shown.length)}টি পাওয়া গেছে' : '${bn(pending)}টি বাকি · দূরত্ব অনুযায়ী'),
                maxLines: 1, overflow: TextOverflow.ellipsis, style: hs(12, color: HC.muted, num: true),
              )),
              HChip(searching || _lat == null ? 'সকল এলাকা' : '৫০ মি.', size: 11),
              const SizedBox(width: 6),
              Semantics(
                button: true, label: 'আমার অবস্থানে আনুন',
                child: GestureDetector(
                  onTap: () {
                    if (_lat != null) _moveTo(_lat!, _lng!, 18);
                    setState(() => _follow = true);
                  },
                  child: Container(width: 34, height: 34, decoration: const BoxDecoration(color: HC.bg, shape: BoxShape.circle),
                      child: const Icon(Icons.my_location_rounded, size: 18, color: HC.ink)),
                ),
              ),
            ]),
          ]),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 200), curve: Curves.easeOut,
          child: _collapsed
              ? const SizedBox(width: double.infinity, height: 6)
              : ConstrainedBox(
                  constraints: BoxConstraints(maxHeight: maxH),
                  child: shown.isEmpty
                      ? Padding(padding: const EdgeInsets.symmetric(vertical: 16), child: Text(searching ? '"${_q.trim()}"-এর সাথে মিলে যাওয়া কোনো দোকান পাওয়া যায়নি।' : 'আপনার ৫০ মিটারের মধ্যে কোনো দোকান নেই। খুঁজে নিন বা নতুন দোকান যোগ করুন।', textAlign: TextAlign.center, style: hs(13, color: HC.muted)))
                      : ListView.builder(
                          shrinkWrap: true, padding: const EdgeInsets.only(top: 4, bottom: 6), itemCount: shown.length,
                          itemBuilder: (_, i) => _shopRow(shown[i], i == 0, numbers['${shown[i]['id']}'], orders, retailers, products, completed),
                        ),
                ),
        ),
      ]),
    );
  }

  Widget _shopRow(Map<String, dynamic> r, bool first, int? number, List orders, List retailers, List products, bool completed) {
    final o = _orderFor(orders, r['id']);
    final st = '${o?['status_key'] ?? ''}'.toLowerCase();
    final cancelled = st == 'cancelled';
    final focused = '${r['id']}' == _focusedId;
    final status = o == null
        ? (num0(r['due']) > 0 ? 'যাওয়া বাকি · আগের বাকি ${tk(r['due'])}' : 'যাওয়া বাকি')
        : (st == 'pending' ? 'আজ অর্ডার নেওয়া হয়েছে · ${tk(o['sr_total'])}' : statusBnKey(st.isEmpty ? '${o['status']}' : st));
    final editable = o == null || (o['editable'] == true && !cancelled);
    void open() {
      if (completed) {
        toast(context, 'আজকের অর্ডার সম্পন্ন হয়েছে। পরিবর্তন করতে "আজ" থেকে দিনটি পুনরায় খুলুন।', error: true);
        return;
      }
      if (o != null && o['editable'] != true && !cancelled) {
        toast(context, '${r['name']}-এর অর্ডারটি ইতিমধ্যেই ট্রিপে দেওয়া হয়েছে।', error: true);
        return;
      }
      _openEditor(retailers, products, r['id'], existing: o != null && !cancelled ? o : null);
    }

    return Material(
      color: focused ? HC.soft : Colors.transparent,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () {
          setState(() => _focusedId = '${r['id']}');
          final lat = num0(r['lat']);
          if (lat != 0) _moveTo(lat, num0(r['lng']), 18);
        },
        child: Container(
          constraints: const BoxConstraints(minHeight: 58),
          padding: EdgeInsets.symmetric(horizontal: focused ? 8 : 0, vertical: 8),
          decoration: BoxDecoration(border: first || focused ? null : const Border(top: BorderSide(color: HC.line))),
          child: Row(children: [
            NumDot(number != null ? bn(number) : (cancelled ? '×' : '✓'),
                bg: number != null ? HC.soft : (cancelled ? HC.chip : HC.ink), fg: number != null ? HC.blue : (cancelled ? HC.ink2 : Colors.white)),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${r['name']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: hs(15, w: w6)),
              Text('${_distText(r['_d'] as double?)} · $status', maxLines: 1, overflow: TextOverflow.ellipsis, style: hs(12, color: HC.muted, num: true)),
            ])),
            const SizedBox(width: 8),
            Semantics(
              button: true,
              child: GestureDetector(
                onTap: open,
                child: Container(
                  height: 36, padding: const EdgeInsets.symmetric(horizontal: 14), alignment: Alignment.center,
                  decoration: BoxDecoration(color: o == null ? HC.blue : HC.chip, borderRadius: BorderRadius.circular(12)),
                  child: Text(o == null ? 'অর্ডার' : (editable && !completed ? 'এডিট' : 'দেখুন'), style: hs(13, w: w7, color: o == null ? Colors.white : HC.ink2)),
                ),
              ),
            ),
          ]),
        ),
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
    final action = await showHSheet<String>(context, builder: (ctx) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      Row(children: [
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('আজকের অর্ডার', style: hs(18, w: w8)),
          Text('${bn(totals['orders'] ?? 0)}টি মেমো · ${tk(totals['value'] ?? 0)} · O/C ${sMoney(oc)}', style: hs(12, color: HC.muted, num: true)),
        ])),
        Semantics(button: true, label: 'বন্ধ করুন', child: GestureDetector(
          onTap: () => Navigator.pop(ctx),
          child: Container(width: 40, height: 40, decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: HC.line)),
              child: const Center(child: Svg('<path d="M18 6 6 18M6 6l12 12"/>', size: 16, color: HC.ink, stroke: 2.2))),
        )),
      ]),
      gap12,
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(color: completed ? HC.bg : HC.soft, borderRadius: BorderRadius.circular(14)),
        child: Text(completed
            ? (day['locked'] == true ? 'দিন সম্পন্ন — অর্ডারগুলো ডেলিভারি ট্রিপে দেওয়া হয়েছে।' : 'দিন সম্পন্ন — ডেলিভারি ট্রিপের অপেক্ষায়। পরিবর্তনের জন্য পুনরায় খুলুন।')
            : 'দিন খোলা আছে — কাজ শেষে "আজকের অর্ডার সম্পন্ন করুন" চাপুন, তাহলে পার্টনার ট্রিপে দিতে পারবেন।', style: hs(13)),
      ),
      gap12,
      if (pend.isNotEmpty || orders.isNotEmpty)
        HList(children: [
          for (final o in pend)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Row(children: [
                const NumDot('…', bg: HC.chip, fg: HC.ink2, size: 38),
                const SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(_retailerName(retailers, (o.body as Map)['retailer_id']), style: hs(14, w: w6)),
                  Text('${bn(((o.body as Map)['items'] as List).length)}টি পণ্য · ইন্টারনেট এলে যাবে', style: hs(12, color: HC.muted)),
                ])),
                const HChip('সিঙ্ক বাকি', bg: HC.chip, fg: HC.ink2, size: 11),
              ]),
            ),
          for (final raw in orders)
            Builder(builder: (_) {
              final o = _m(raw);
              final ocv = num0(o['oc']);
              final cancelled = '${o['status_key']}' == 'cancelled';
              final editable = o['editable'] == true && !completed && !cancelled;
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Row(children: [
                    LetterAvatar('${o['retailer']}', size: 38, radius: 12, bg: cancelled ? HC.chip : HC.soft, fg: cancelled ? HC.ink2 : HC.blue, fontSize: 15),
                    const SizedBox(width: 12),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('${o['retailer']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: hs(14, w: w6)),
                      Text('মেমো #${bn(o['code'])} · ${bn((o['items'] as List).length)}টি পণ্য · ${bn(o['time'] ?? '')}', style: hs(12, color: HC.muted, num: true)),
                    ])),
                    Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                      Text(tk(o['sr_total']), style: hs(14, w: w7, num: true)),
                      Text('O/C ${sMoney(ocv)}', style: hs(11, w: w7, color: ocv > 0 ? HC.blue : (ocv < 0 ? HC.red : HC.muted), num: true)),
                    ]),
                  ]),
                  if (editable) ...[
                    const SizedBox(height: 8),
                    Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                      HBtn('সম্পাদনা', kind: HBtnKind.line, expand: false, height: 38, radius: 12, fontSize: 13, onTap: () {
                        Navigator.pop(ctx);
                        _openEditor(retailers, products, o['retailer_id'], existing: o);
                      }),
                      const SizedBox(width: 8),
                      HBtn('বাতিল', kind: HBtnKind.danger, expand: false, height: 38, radius: 12, fontSize: 13, onTap: () async {
                        if (!await confirm(ctx, 'অর্ডার বাতিল করবেন?', body: '${o['retailer']}-এর আজকের অর্ডার মুছে যাবে।', danger: true, yes: 'বাতিল করুন')) return;
                        if (!ctx.mounted) return;
                        final r = await busy(ctx, () => OfflineQueue.write('DELETE', '/sr/orders/${o['id']}', label: '${o['retailer']}-এর অর্ডার বাতিল'));
                        if (r != null && ctx.mounted) {
                          toast(ctx, r.queued ? 'ইন্টারনেট এলে বাতিল হবে।' : (r.data['message'] ?? 'বাতিল হয়েছে।').toString());
                          Navigator.pop(ctx, 'reload');
                        }
                      }),
                    ]),
                  ] else
                    Align(alignment: Alignment.centerRight, child: Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: HChip(statusBnKey('${o['status_key'] ?? o['status']}'), bg: cancelled ? HC.redSoft : HC.chip, fg: cancelled ? HC.red : HC.ink2, size: 11),
                    )),
                ]),
              );
            }),
        ])
      else
        const HEmpty('আজ এখনো কোনো অর্ডার নেই', body: 'ম্যাপ থেকে দোকান বেছে অর্ডার নিন।'),
      if (orders.isNotEmpty || completed) ...[
        gap16,
        completed
            ? HBtn('আজকের দিন পুনরায় খুলুন', kind: HBtnKind.line, onTap: () => Navigator.pop(ctx, 'reopen'))
            : HBtn('আজকের অর্ডার সম্পন্ন করুন', onTap: () => Navigator.pop(ctx, 'complete')),
      ],
    ]));
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
