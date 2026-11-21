class TrackPoint {
  const TrackPoint(this.lat, this.lon, {this.ele, this.time});

  final double lat;
  final double lon;
  final double? ele;
  final DateTime? time;
}

class Waypoint {
  const Waypoint(this.lat, this.lon, {this.name, this.ele});

  final double lat;
  final double lon;
  final String? name;
  final double? ele;
}

class GpxRoute {
  const GpxRoute({
    required this.name,
    required this.points,
    this.waypoints = const [],
  });

  final String name;
  final List<TrackPoint> points;
  final List<Waypoint> waypoints;
}

class RouteStats {
  const RouteStats({
    required this.distanceM,
    required this.elevationGainM,
    required this.elevationLossM,
    required this.minEleM,
    required this.maxEleM,
    required this.cumulativeM,
    this.duration,
  });

  final double distanceM;
  final double elevationGainM;
  final double elevationLossM;
  final double? minEleM;
  final double? maxEleM;

  /// Distancia acumulada en metros en cada punto (misma longitud que points).
  final List<double> cumulativeM;

  /// Solo si el GPX trae marcas de tiempo.
  final Duration? duration;
}
