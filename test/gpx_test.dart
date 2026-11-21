import 'package:flutter_test/flutter_test.dart';
import 'package:gpx_app/features/routes/gpx_parser.dart';
import 'package:gpx_app/features/routes/route_models.dart';
import 'package:gpx_app/features/routes/route_stats.dart';

const _trackGpx = '''<?xml version="1.0" encoding="UTF-8"?>
<gpx version="1.1" creator="test" xmlns="http://www.topografix.com/GPX/1/1">
  <wpt lat="40.001" lon="-3.0"><name>Fuente</name><ele>101</ele></wpt>
  <trk>
    <name>Ruta de prueba</name>
    <trkseg>
      <trkpt lat="40.000" lon="-3.0"><ele>100</ele><time>2026-01-01T10:00:00Z</time></trkpt>
      <trkpt lat="40.001" lon="-3.0"><ele>110</ele><time>2026-01-01T10:10:00Z</time></trkpt>
      <trkpt lat="40.002" lon="-3.0"><ele>105</ele><time>2026-01-01T10:20:00Z</time></trkpt>
    </trkseg>
  </trk>
</gpx>''';

void main() {
  group('parseGpx', () {
    test('lee nombre, puntos y waypoints', () {
      final r = parseGpx(_trackGpx);
      expect(r.name, 'Ruta de prueba');
      expect(r.points.length, 3);
      expect(r.points.first.ele, 100);
      expect(r.points.first.time, DateTime.utc(2026, 1, 1, 10));
      expect(r.waypoints.single.name, 'Fuente');
    });

    test('cae a rtept si no hay trkpt', () {
      const gpx = '''<gpx version="1.1" xmlns="http://www.topografix.com/GPX/1/1">
        <rte><name>R</name>
          <rtept lat="1" lon="1"/><rtept lat="1.001" lon="1"/>
        </rte></gpx>''';
      final r = parseGpx(gpx);
      expect(r.name, 'R');
      expect(r.points.length, 2);
      expect(r.points.first.ele, isNull);
    });

    test('usa el nombre por defecto si no hay ninguno', () {
      const gpx = '''<gpx version="1.1"><trk><trkseg>
        <trkpt lat="1" lon="1"/></trkseg></trk></gpx>''';
      expect(parseGpx(gpx, fallbackName: 'mi_archivo').name, 'mi_archivo');
    });

    test('rechaza XML roto, no-GPX y GPX sin puntos', () {
      expect(() => parseGpx('<gpx><trk>'), throwsA(isA<GpxFormatException>()));
      expect(() => parseGpx('<html/>'), throwsA(isA<GpxFormatException>()));
      expect(() => parseGpx('<gpx version="1.1"/>'),
          throwsA(isA<GpxFormatException>()));
    });

    test('ignora puntos con coordenadas inválidas', () {
      const gpx = '''<gpx version="1.1"><trk><trkseg>
        <trkpt lat="x" lon="1"/><trkpt lat="2" lon="2"/></trkseg></trk></gpx>''';
      expect(parseGpx(gpx).points.length, 1);
    });
  });

  group('computeStats', () {
    test('distancia, desnivel, rango y duración', () {
      final s = computeStats(parseGpx(_trackGpx).points);
      // 0.002 grados de latitud ~ 222.4 m
      expect(s.distanceM, closeTo(222.4, 1));
      expect(s.elevationGainM, 10);
      expect(s.elevationLossM, 5);
      expect(s.minEleM, 100);
      expect(s.maxEleM, 110);
      expect(s.duration, const Duration(minutes: 20));
      expect(s.cumulativeM.first, 0);
      expect(s.cumulativeM.last, closeTo(s.distanceM, 1e-9));
    });

    test('el ruido por debajo del umbral no cuenta como desnivel', () {
      final pts = [
        for (final e in [100.0, 101.0, 100.0, 101.5, 99.5, 100.5])
          TrackPoint(40, -3, ele: e),
      ];
      final s = computeStats(pts, elevationThresholdM: 3);
      expect(s.elevationGainM, 0);
      expect(s.elevationLossM, 0);
    });

    test('sin altitud ni tiempo: valores nulos y desnivel 0', () {
      final s = computeStats(const [TrackPoint(1, 1), TrackPoint(1.001, 1)]);
      expect(s.minEleM, isNull);
      expect(s.maxEleM, isNull);
      expect(s.duration, isNull);
      expect(s.elevationGainM, 0);
    });

    test('un solo punto no rompe', () {
      final s = computeStats(const [TrackPoint(1, 1)]);
      expect(s.distanceM, 0);
      expect(s.cumulativeM, [0]);
    });
  });
}
