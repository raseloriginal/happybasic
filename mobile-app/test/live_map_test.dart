import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:happy_bangladesh/core/geo_filter.dart';
import 'package:happy_bangladesh/core/tracker.dart';
import 'package:happy_bangladesh/ui/me_layer.dart';
import 'package:latlong2/latlong.dart';

void main() {
  test('filter ignores standing wobble and follows walking', () {
    final f = GeoFilter();
    expect(f.push(lat: 23.8, lng: 90.4, accuracy: 8, speed: 0, timeMs: 0), isNotNull);
    // ~1 m of noise while standing still: the dot does not move.
    for (var i = 1; i <= 10; i++) {
      expect(f.push(lat: 23.8 + (i.isEven ? 0.00001 : -0.00001), lng: 90.4, accuracy: 8, speed: 0, timeMs: i * 1000), isNull);
    }
    // Walking north ~1.4 m/s: the dot moves on nearly every fix and ends close to the real position.
    var moves = 0;
    var last = 23.8;
    for (var i = 1; i <= 30; i++) {
      final p = f.push(lat: 23.8 + i * 0.0000126, lng: 90.4, accuracy: 8, speed: 1.4, timeMs: 10000 + i * 1000);
      if (p != null) {
        moves++;
        last = p.lat;
      }
    }
    expect(moves, greaterThan(20));
    expect(GeoFilter.metres(last, 90.4, 23.8 + 30 * 0.0000126, 90.4), lessThan(10));
  });

  testWidgets('dot glides between fixes and the camera follows', (tester) async {
    final map = MapController();
    Tracker.instance.fix.value = null;
    Widget app(bool follow) => MaterialApp(
          home: FlutterMap(
            mapController: map,
            options: const MapOptions(initialCenter: LatLng(23.8, 90.4), initialZoom: 18),
            children: [MeLayer(map: map, active: true, follow: follow, initial: const LatLng(23.8, 90.4))],
          ),
        );
    LatLng dot() => tester.widget<MarkerLayer>(find.byType(MarkerLayer)).markers.single.point;
    await tester.pumpWidget(app(true));
    Tracker.instance.fix.value = (lat: 23.8001, lng: 90.4, accuracy: 5, heading: 0);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500)); // half of the 1 s glide
    expect(dot().latitude, closeTo(23.80005, 0.00002));
    expect(map.camera.center.latitude, closeTo(dot().latitude, 0.000001));
    await tester.pumpAndSettle();
    expect(dot().latitude, closeTo(23.8001, 0.000001));

    // Following off (the user dragged the map): the dot moves, the camera stays.
    await tester.pumpWidget(app(false));
    final before = map.camera.center.latitude;
    Tracker.instance.fix.value = (lat: 23.8002, lng: 90.4, accuracy: 5, heading: null);
    await tester.pumpAndSettle();
    expect(dot().latitude, closeTo(23.8002, 0.000001));
    expect(map.camera.center.latitude, before);
    await tester.pumpWidget(const SizedBox());
    Tracker.instance.fix.value = null;
  });
}
