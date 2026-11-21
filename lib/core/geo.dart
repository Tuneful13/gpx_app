import 'dart:math' as math;

const double _earthRadiusM = 6371008.8;

double _rad(double deg) => deg * math.pi / 180;

/// Distancia en metros entre dos coordenadas (fórmula de Haversine).
double haversine(double lat1, double lon1, double lat2, double lon2) {
  final dLat = _rad(lat2 - lat1);
  final dLon = _rad(lon2 - lon1);
  final a = math.pow(math.sin(dLat / 2), 2) +
      math.cos(_rad(lat1)) *
          math.cos(_rad(lat2)) *
          math.pow(math.sin(dLon / 2), 2);
  return 2 * _earthRadiusM * math.asin(math.min(1.0, math.sqrt(a)));
}

/// Rumbo inicial en grados (0-360) de un punto a otro.
double bearing(double lat1, double lon1, double lat2, double lon2) {
  final dLon = _rad(lon2 - lon1);
  final y = math.sin(dLon) * math.cos(_rad(lat2));
  final x = math.cos(_rad(lat1)) * math.sin(_rad(lat2)) -
      math.sin(_rad(lat1)) * math.cos(_rad(lat2)) * math.cos(dLon);
  return (math.atan2(y, x) * 180 / math.pi + 360) % 360;
}

/// Diferencia angular con signo en (-180, 180]. Positivo = giro a la derecha.
double bearingDelta(double from, double to) {
  var d = (to - from) % 360;
  if (d > 180) d -= 360;
  return d;
}
