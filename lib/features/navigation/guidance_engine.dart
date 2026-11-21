import '../routes/route_models.dart';
import 'route_matcher.dart';

class _WaypointOnRoute {
  _WaypointOnRoute(this.name, this.alongM);
  final String name;
  final double alongM;
}

/// Decide qué decir en voz alta según el avance sobre la ruta.
///
/// Avisa de los puntos de interés, de cada kilómetro recorrido y de la llegada.
/// Cada aviso se da una sola vez.
class GuidanceEngine {
  GuidanceEngine({
    required this.totalM,
    required List<Waypoint> waypoints,
    required RouteMatcher matcher,
    this.waypointAnnounceM = 40,
    this.arrivalM = 30,
  }) {
    for (final w in waypoints) {
      final m = matcher.match(w.lat, w.lon);
      // Ignora waypoints que no están junto a la ruta.
      if (m.distanceToRouteM <= 50) {
        _waypoints.add(_WaypointOnRoute(w.name ?? 'Punto de interés', m.alongM));
      }
    }
  }

  final double totalM;
  final double waypointAnnounceM;
  final double arrivalM;

  final List<_WaypointOnRoute> _waypoints = [];
  final Set<int> _waypointsDone = {};
  int _lastKm = 0;
  bool _arrived = false;

  bool get arrived => _arrived;

  /// Mensajes nuevos a decir para la posición [alongM] (metros desde el inicio).
  List<String> update(double alongM) {
    final messages = <String>[];

    for (var i = 0; i < _waypoints.length; i++) {
      final remaining = _waypoints[i].alongM - alongM;
      if (remaining >= -10 &&
          remaining <= waypointAnnounceM &&
          _waypointsDone.add(i)) {
        messages.add('Punto de interés: ${_waypoints[i].name}');
      }
    }

    final km = (alongM / 1000).floor();
    if (km > _lastKm && km >= 1) {
      _lastKm = km;
      if (totalM - alongM > arrivalM) messages.add('Kilómetro $km');
    }

    if (!_arrived && totalM - alongM <= arrivalM && alongM > totalM * 0.5) {
      _arrived = true;
      messages.add('Has llegado al final de la ruta');
    }

    return messages;
  }
}
