import 'package:flutter_test/flutter_test.dart';
import 'package:gpx_app/core/geo.dart';

void main() {
  group('haversine', () {
    test('mismo punto = 0', () {
      expect(haversine(40.0, -3.0, 40.0, -3.0), 0);
    });

    test('1 grado de latitud ~ 111.2 km', () {
      expect(haversine(0, 0, 1, 0), closeTo(111195, 100));
    });

    test('Madrid - Barcelona ~ 505 km', () {
      final d = haversine(40.4168, -3.7038, 41.3874, 2.1686);
      expect(d / 1000, closeTo(505, 5));
    });
  });

  group('bearing', () {
    test('norte, este, sur, oeste', () {
      expect(bearing(0, 0, 1, 0), closeTo(0, 0.01));
      expect(bearing(0, 0, 0, 1), closeTo(90, 0.01));
      expect(bearing(0, 0, -1, 0), closeTo(180, 0.01));
      expect(bearing(0, 0, 0, -1), closeTo(270, 0.01));
    });
  });

  group('bearingDelta', () {
    test('cruza el norte correctamente', () {
      expect(bearingDelta(350, 10), closeTo(20, 1e-9)); // derecha
      expect(bearingDelta(10, 350), closeTo(-20, 1e-9)); // izquierda
    });

    test('giro opuesto = 180', () {
      expect(bearingDelta(0, 180).abs(), closeTo(180, 1e-9));
    });
  });
}
