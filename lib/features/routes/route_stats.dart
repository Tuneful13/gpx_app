import '../../core/geo.dart';
import 'route_models.dart';

/// Calcula estadísticas de una ruta.
///
/// El desnivel usa histéresis: solo se contabiliza un cambio cuando la altura
/// se aleja más de [elevationThresholdM] de la última referencia. Así el ruido
/// del GPS/barómetro no infla el desnivel acumulado.
RouteStats computeStats(
  List<TrackPoint> points, {
  double elevationThresholdM = 3,
}) {
  final cumulative = List<double>.filled(points.length, 0);
  var distance = 0.0;
  for (var i = 1; i < points.length; i++) {
    distance += haversine(
      points[i - 1].lat,
      points[i - 1].lon,
      points[i].lat,
      points[i].lon,
    );
    cumulative[i] = distance;
  }

  var gain = 0.0;
  var loss = 0.0;
  double? ref;
  double? minEle;
  double? maxEle;
  for (final p in points) {
    final e = p.ele;
    if (e == null) continue;
    minEle = minEle == null ? e : (e < minEle ? e : minEle);
    maxEle = maxEle == null ? e : (e > maxEle ? e : maxEle);
    if (ref == null) {
      ref = e;
      continue;
    }
    final diff = e - ref;
    if (diff.abs() >= elevationThresholdM) {
      if (diff > 0) {
        gain += diff;
      } else {
        loss -= diff;
      }
      ref = e;
    }
  }

  Duration? duration;
  final first = points.first.time;
  final last = points.last.time;
  if (first != null && last != null && last.isAfter(first)) {
    duration = last.difference(first);
  }

  return RouteStats(
    distanceM: distance,
    elevationGainM: gain,
    elevationLossM: loss,
    minEleM: minEle,
    maxEleM: maxEle,
    cumulativeM: cumulative,
    duration: duration,
  );
}
