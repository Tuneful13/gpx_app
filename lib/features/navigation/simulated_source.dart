import 'dart:math' as math;

import '../../core/geo.dart';
import '../routes/route_models.dart';
import 'location_source.dart';

const double _mPerDeg = 111195;

/// Recorre la ruta como si alguien caminase por ella, para probar la
/// navegación sin salir a la calle. Incluye un desvío lateral a mitad de
/// camino (entre el 40 % y el 52 % de la ruta) para probar el aviso de
/// "te has salido de la ruta".
class SimulatedLocationSource implements LocationSource {
  SimulatedLocationSource({
    required this.points,
    required this.cumulativeM,
    this.speedMps = 25,
    this.tick = const Duration(seconds: 1),
    this.withDetour = true,
    this.detourWidthM = 90,
  }) : assert(points.length >= 2);

  final List<TrackPoint> points;
  final List<double> cumulativeM;

  /// Metros que avanza por segundo. 1,5 = paso normal; más = más rápido.
  final double speedMps;

  /// Tiempo real entre lecturas.
  final Duration tick;

  final bool withDetour;
  final double detourWidthM;

  static const double _detourStart = 0.40;
  static const double _detourEnd = 0.52;

  double get totalM => cumulativeM.last;

  @override
  Future<LocationAccess> ensureAccess() async => LocationAccess.granted;

  /// Posición simulada tras recorrer [alongM] metros.
  Fix positionAt(double alongM, DateTime time) {
    final d = alongM.clamp(0.0, totalM);
    var seg = 0;
    while (seg < points.length - 2 && cumulativeM[seg + 1] < d) {
      seg++;
    }
    final a = points[seg];
    final b = points[seg + 1];
    final segLen = cumulativeM[seg + 1] - cumulativeM[seg];
    final t = segLen == 0 ? 0.0 : ((d - cumulativeM[seg]) / segLen);
    var lat = a.lat + t * (b.lat - a.lat);
    var lon = a.lon + t * (b.lon - a.lon);
    final heading = bearing(a.lat, a.lon, b.lat, b.lon);

    if (withDetour && totalM > 0) {
      final frac = d / totalM;
      if (frac > _detourStart && frac < _detourEnd) {
        final bump =
            math.sin(math.pi * (frac - _detourStart) / (_detourEnd - _detourStart));
        final offsetM = detourWidthM * bump;
        final perp = (heading + 90) * math.pi / 180;
        lat += offsetM * math.cos(perp) / _mPerDeg;
        lon += offsetM * math.sin(perp) / (_mPerDeg * math.cos(lat * math.pi / 180));
      }
    }

    return Fix(
      lat: lat,
      lon: lon,
      time: time,
      accuracyM: 5,
      speedMps: speedMps,
      headingDeg: heading,
    );
  }

  @override
  Stream<Fix> fixes() async* {
    var along = 0.0;
    while (true) {
      yield positionAt(along, DateTime.now());
      if (along >= totalM) return;
      await Future<void>.delayed(tick);
      along = math.min(totalM, along + speedMps);
    }
  }
}
