import 'dart:math' as math;

import '../routes/route_models.dart';

/// Metros por grado de latitud (aprox. esférica).
const double _mPerDeg = 111195;

class MatchResult {
  const MatchResult({
    required this.segment,
    required this.distanceToRouteM,
    required this.alongM,
    required this.lat,
    required this.lon,
  });

  /// Segmento points[segment] -> points[segment + 1] donde se proyecta.
  final int segment;

  /// Distancia en metros desde la posición hasta la ruta.
  final double distanceToRouteM;

  /// Metros recorridos sobre la ruta hasta el punto proyectado.
  final double alongM;

  /// Punto de la ruta más cercano.
  final double lat;
  final double lon;
}

/// Proyecta posiciones GPS sobre una ruta.
///
/// Busca primero en una ventana alrededor del último segmento conocido, para
/// no saltar a otro tramo cercano (rutas que se cruzan o van y vuelven por el
/// mismo sitio). Si en esa ventana no hay nada cerca, busca en toda la ruta.
class RouteMatcher {
  RouteMatcher(this.points, this.cumulativeM)
      : assert(points.length >= 2, 'La ruta necesita al menos 2 puntos'),
        assert(points.length == cumulativeM.length);

  final List<TrackPoint> points;
  final List<double> cumulativeM;

  double get totalM => cumulativeM.last;

  MatchResult match(
    double lat,
    double lon, {
    int? lastSegment,
    double windowAheadM = 400,
    double windowBackM = 100,
    double globalFallbackM = 50,
  }) {
    if (lastSegment == null) return _search(lat, lon, 0, points.length - 2);

    final last = lastSegment.clamp(0, points.length - 2);
    var lo = last;
    while (lo > 0 && cumulativeM[last] - cumulativeM[lo] < windowBackM) {
      lo--;
    }
    var hi = last;
    while (hi < points.length - 2 &&
        cumulativeM[hi + 1] - cumulativeM[last] < windowAheadM) {
      hi++;
    }

    final windowed = _search(lat, lon, lo, hi);
    if (windowed.distanceToRouteM <= globalFallbackM) return windowed;

    // Nada cerca en la ventana: puede que hayas cortado camino o te hayas ido
    // a otro tramo. Mira toda la ruta y quédate con lo claramente mejor.
    final global = _search(lat, lon, 0, points.length - 2);
    return global.distanceToRouteM < windowed.distanceToRouteM - 10
        ? global
        : windowed;
  }

  MatchResult _search(double lat, double lon, int from, int to) {
    MatchResult? best;
    for (var i = from; i <= to; i++) {
      final r = _project(i, lat, lon);
      if (best == null || r.distanceToRouteM < best.distanceToRouteM) best = r;
    }
    return best!;
  }

  MatchResult _project(int i, double lat, double lon) {
    final a = points[i];
    final b = points[i + 1];
    final cosLat = math.cos(a.lat * math.pi / 180);

    final px = (lon - a.lon) * cosLat * _mPerDeg;
    final py = (lat - a.lat) * _mPerDeg;
    final bx = (b.lon - a.lon) * cosLat * _mPerDeg;
    final by = (b.lat - a.lat) * _mPerDeg;

    final len2 = bx * bx + by * by;
    final t = len2 == 0 ? 0.0 : ((px * bx + py * by) / len2).clamp(0.0, 1.0);
    final dist = math.sqrt(math.pow(px - t * bx, 2) + math.pow(py - t * by, 2));

    return MatchResult(
      segment: i,
      distanceToRouteM: dist,
      alongM: cumulativeM[i] + t * (cumulativeM[i + 1] - cumulativeM[i]),
      lat: a.lat + t * (b.lat - a.lat),
      lon: a.lon + t * (b.lon - a.lon),
    );
  }
}
