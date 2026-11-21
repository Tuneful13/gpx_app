import 'dart:math' as math;

import 'package:gpx_app/features/routes/route_models.dart';
import 'package:gpx_app/features/routes/route_stats.dart';

const double mPerDegLat = 111195;
const double baseLat = 40.0;
const double baseLon = -3.0;

double northM(double meters) => meters / mPerDegLat;

double eastM(double meters) =>
    meters / (mPerDegLat * math.cos(baseLat * math.pi / 180));

/// Construye una ruta a partir de desplazamientos (norte, este) en metros
/// respecto a un origen fijo.
({List<TrackPoint> points, List<double> cum}) buildRoute(
  List<(double north, double east)> offsets,
) {
  final points = [
    for (final (n, e) in offsets)
      TrackPoint(baseLat + northM(n), baseLon + eastM(e)),
  ];
  return (points: points, cum: computeStats(points).cumulativeM);
}

/// Ruta recta hacia el norte con un punto cada [stepM] metros.
({List<TrackPoint> points, List<double> cum}) straightNorth(
  double lengthM, {
  double stepM = 50,
}) {
  return buildRoute([
    for (var d = 0.0; d < lengthM; d += stepM) (d, 0.0),
    (lengthM, 0.0),
  ]);
}
