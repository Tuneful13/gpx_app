import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'geolocator_source.dart';

/// Una lectura de posición.
class Fix {
  const Fix({
    required this.lat,
    required this.lon,
    required this.time,
    this.accuracyM,
    this.speedMps,
    this.headingDeg,
  });

  final double lat;
  final double lon;
  final DateTime time;
  final double? accuracyM;
  final double? speedMps;
  final double? headingDeg;
}

enum LocationAccess { granted, denied, deniedForever, serviceDisabled }

/// De dónde salen las posiciones: GPS real o simulación.
abstract class LocationSource {
  Future<LocationAccess> ensureAccess();
  Stream<Fix> fixes();
}

final locationSourceProvider =
    Provider<LocationSource>((ref) => GeolocatorLocationSource());
