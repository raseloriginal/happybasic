import 'dart:math' as math;

/// Same smoothing as the PWA's `geo-filter.js` (a small Kalman filter): GPS wobble while standing still is
/// ignored, real movement is followed. Only used for the on-screen dot, never for the points sent to the server.
class GeoFilter {
  GeoFilter({this.maxAccuracy = 100, this.idleSpeed = 0.6, this.minStep = 2});
  final double maxAccuracy, idleSpeed, minStep;

  double? _lat, _lng;
  double _outLat = 0, _outLng = 0;
  double _variance = 0; // m²
  int _lastMs = 0;
  int _away = 0;

  static double metres(double aLat, double aLng, double bLat, double bLng) {
    const rad = math.pi / 180;
    final s1 = math.sin((bLat - aLat) * rad / 2), s2 = math.sin((bLng - aLng) * rad / 2);
    final h = s1 * s1 + math.cos(aLat * rad) * math.cos(bLat * rad) * s2 * s2;
    return 12742000 * math.asin(math.sqrt(h));
  }

  /// The new dot position, or null when the dot should stay where it is.
  ({double lat, double lng, double accuracy})? push({required double lat, required double lng, required double accuracy, required double speed, required int timeMs}) {
    final acc = math.max(accuracy > 0 ? accuracy : 25.0, 5.0);
    if (_lat == null) {
      _lat = _outLat = lat;
      _lng = _outLng = lng;
      _variance = acc * acc;
      _lastMs = timeMs;
      return (lat: lat, lng: lng, accuracy: acc);
    }
    if (acc > maxAccuracy) return null; // too vague to trust
    final dt = math.max((timeMs - _lastMs) / 1000, 0.0);
    _lastMs = timeMs;
    _away = metres(_lat!, _lng!, lat, lng) > 2 * acc + 12 ? _away + 1 : 0;
    if (_away >= 2) {
      _variance = math.max(_variance, 4 * acc * acc);
      _away = 0;
    }
    final q = math.max(idleSpeed, speed);
    _variance += dt * q * q;
    final k = _variance / (_variance + acc * acc);
    _lat = _lat! + k * (lat - _lat!);
    _lng = _lng! + k * (lng - _lng!);
    _variance *= 1 - k;
    // Dead band: ignore wobble smaller than the filter's own uncertainty (much smaller while walking or driving).
    final band = speed > 0.8 ? 0.5 : math.max(minStep, math.sqrt(_variance) * 0.6);
    if (metres(_outLat, _outLng, _lat!, _lng!) < band) return null;
    _outLat = _lat!;
    _outLng = _lng!;
    return (lat: _outLat, lng: _outLng, accuracy: math.sqrt(_variance));
  }
}
