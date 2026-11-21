import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

import 'location_source.dart';

/// GPS real. En Android arranca un servicio en primer plano (notificación
/// persistente) para seguir recibiendo posiciones con la pantalla apagada;
/// en iOS activa la ubicación en segundo plano.
class GeolocatorLocationSource implements LocationSource {
  @override
  Future<LocationAccess> ensureAccess() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      return LocationAccess.serviceDisabled;
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    return switch (permission) {
      LocationPermission.denied => LocationAccess.denied,
      LocationPermission.deniedForever => LocationAccess.deniedForever,
      _ => LocationAccess.granted,
    };
  }

  @override
  Stream<Fix> fixes() {
    return Geolocator.getPositionStream(locationSettings: _settings()).map(
      (p) => Fix(
        lat: p.latitude,
        lon: p.longitude,
        time: p.timestamp,
        accuracyM: p.accuracy,
        // Heading o velocidad negativos significan "desconocido".
        speedMps: p.speed >= 0 ? p.speed : null,
        headingDeg: (p.heading >= 0 && p.speed > 0.5) ? p.heading : null,
      ),
    );
  }

  LocationSettings _settings() {
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return AndroidSettings(
          accuracy: LocationAccuracy.best,
          distanceFilter: 3,
          intervalDuration: const Duration(seconds: 1),
          foregroundNotificationConfig: const ForegroundNotificationConfig(
            notificationTitle: 'GPX App',
            notificationText: 'Siguiendo la ruta',
            enableWakeLock: true,
            setOngoing: true,
          ),
        );
      case TargetPlatform.iOS:
      case TargetPlatform.macOS:
        return AppleSettings(
          accuracy: LocationAccuracy.best,
          distanceFilter: 3,
          activityType: ActivityType.fitness,
          pauseLocationUpdatesAutomatically: false,
          showBackgroundLocationIndicator: true,
          allowBackgroundLocationUpdates: true,
        );
      default:
        return const LocationSettings(
          accuracy: LocationAccuracy.best,
          distanceFilter: 3,
        );
    }
  }
}
