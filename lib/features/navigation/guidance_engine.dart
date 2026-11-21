import '../../core/format.dart';
import '../routes/route_models.dart';
import 'route_matcher.dart';
import 'turn_detector.dart';

class _WaypointOnRoute {
  _WaypointOnRoute(this.name, this.alongM);
  final String name;
  final double alongM;
}

/// Decide qué decir en voz alta según el avance sobre la ruta.
///
/// Cada aviso se da una sola vez. Si el GPS "salta" y te saltas un umbral
/// (por ejemplo la primera lectura ya está a 20 m del giro), se da solo el
/// aviso más cercano en vez de repetir los anteriores.
class GuidanceEngine {
  GuidanceEngine({
    required this.turns,
    required this.totalM,
    required List<Waypoint> waypoints,
    required RouteMatcher matcher,
    this.farAnnounceM = 100,
    this.nearAnnounceM = 25,
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

  final List<Turn> turns;
  final double totalM;
  final double farAnnounceM;
  final double nearAnnounceM;
  final double waypointAnnounceM;
  final double arrivalM;

  final List<_WaypointOnRoute> _waypoints = [];
  final Set<int> _farDone = {};
  final Set<int> _nearDone = {};
  final Set<int> _waypointsDone = {};
  int _lastKm = 0;
  bool _arrived = false;

  bool get arrived => _arrived;

  /// Mensajes nuevos a decir para la posición [alongM] (metros desde el inicio).
  List<String> update(double alongM) {
    final messages = <String>[];

    for (var i = 0; i < turns.length; i++) {
      final remaining = turns[i].alongM - alongM;
      if (remaining < -10 || remaining > farAnnounceM) continue;

      if (remaining <= nearAnnounceM) {
        if (_nearDone.add(i)) {
          _farDone.add(i); // ya no tiene sentido el aviso lejano
          messages.add(_capitalize(turns[i].phrase));
        }
      } else if (_farDone.add(i)) {
        messages.add(
            'En ${spokenDistance(remaining)}, ${turns[i].phrase}');
      }
    }

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
      final left = totalM - alongM;
      if (left > arrivalM) {
        messages.add(
            'Kilómetro $km. Quedan ${spokenDistance(left)}');
      }
    }

    if (!_arrived && totalM - alongM <= arrivalM && alongM > totalM * 0.5) {
      _arrived = true;
      messages.add('Has llegado al final de la ruta');
    }

    return messages;
  }

  static String _capitalize(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
}
