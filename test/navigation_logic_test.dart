import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:gpx_app/core/format.dart';
import 'package:gpx_app/features/navigation/guidance_engine.dart';
import 'package:gpx_app/features/navigation/off_route_monitor.dart';
import 'package:gpx_app/features/navigation/route_matcher.dart';
import 'package:gpx_app/features/navigation/turn_detector.dart';
import 'package:gpx_app/features/routes/route_models.dart';

import 'helpers/route_builder.dart';

void main() {
  group('RouteMatcher', () {
    test('proyecta sobre el segmento: distancia lateral y avance', () {
      final r = straightNorth(1000);
      final m = RouteMatcher(r.points, r.cum);
      final res = m.match(baseLat + northM(500), baseLon + eastM(10));
      expect(res.distanceToRouteM, closeTo(10, 0.5));
      expect(res.alongM, closeTo(500, 1));
    });

    test('antes del inicio y después del final se queda en los extremos', () {
      final r = straightNorth(1000);
      final m = RouteMatcher(r.points, r.cum);
      expect(m.match(baseLat - northM(40), baseLon).alongM, 0);
      final end = m.match(baseLat + northM(1100), baseLon);
      expect(end.alongM, closeTo(m.totalM, 1e-6));
      expect(end.distanceToRouteM, closeTo(100, 1));
    });

    test('en una ruta de ida y vuelta no salta al tramo de ida', () {
      // Ida 0->500 m al norte y vuelta por el mismo camino.
      final r = buildRoute([
        for (var d = 0.0; d <= 500; d += 50) (d, 0.0),
        for (var d = 450.0; d >= 0; d -= 50) (d, 0.0),
      ]);
      final m = RouteMatcher(r.points, r.cum);
      // Vamos por la vuelta, hacia el sur, a 250 m de latitud (avance ~750).
      final lastSeg = r.points.length - 1 - 5 - 1; // tramo a ~700 m de avance
      final res = m.match(baseLat + northM(250), baseLon, lastSegment: lastSeg);
      expect(res.alongM, closeTo(750, 1));
    });

    test('si nada cerca en la ventana, busca en toda la ruta', () {
      final r = straightNorth(3000);
      final m = RouteMatcher(r.points, r.cum);
      // Último segmento conocido cerca del inicio; ahora estamos en los 2 km.
      final res = m.match(baseLat + northM(2000), baseLon, lastSegment: 0);
      expect(res.alongM, closeTo(2000, 1));
      expect(res.distanceToRouteM, lessThan(1));
    });
  });

  group('OffRouteMonitor', () {
    final t0 = DateTime(2026, 1, 1, 10);

    test('un salto aislado del GPS no dispara el aviso', () {
      final mon = OffRouteMonitor();
      expect(mon.update(10, t0), OffRouteEvent.none);
      expect(mon.update(80, t0), OffRouteEvent.none);
      expect(mon.update(12, t0), OffRouteEvent.none);
      expect(mon.update(90, t0), OffRouteEvent.none);
      expect(mon.isOff, isFalse);
    });

    test('3 lecturas seguidas fuera avisan una vez', () {
      final mon = OffRouteMonitor();
      expect(mon.update(50, t0), OffRouteEvent.none);
      expect(mon.update(55, t0), OffRouteEvent.none);
      expect(mon.update(60, t0), OffRouteEvent.left);
      expect(mon.isOff, isTrue);
      expect(mon.update(70, t0.add(const Duration(seconds: 5))),
          OffRouteEvent.none);
    });

    test('repite el aviso cada 20 s mientras sigues fuera', () {
      final mon = OffRouteMonitor();
      for (var i = 0; i < 3; i++) {
        mon.update(60, t0);
      }
      expect(mon.update(60, t0.add(const Duration(seconds: 19))),
          OffRouteEvent.none);
      expect(mon.update(60, t0.add(const Duration(seconds: 20))),
          OffRouteEvent.stillOff);
      expect(mon.update(60, t0.add(const Duration(seconds: 30))),
          OffRouteEvent.none);
    });

    test('histéresis: a 25 m (bajo el umbral de 30) aún cuenta como fuera', () {
      final mon = OffRouteMonitor();
      for (var i = 0; i < 3; i++) {
        mon.update(60, t0);
      }
      expect(mon.update(25, t0.add(const Duration(seconds: 1))),
          OffRouteEvent.none);
      expect(mon.isOff, isTrue);
      expect(mon.update(15, t0.add(const Duration(seconds: 2))),
          OffRouteEvent.returned);
      expect(mon.isOff, isFalse);
    });
  });

  group('detectTurns', () {
    test('ruta recta: sin giros', () {
      final r = straightNorth(1000);
      expect(detectTurns(r.points, r.cum), isEmpty);
    });

    test('en L hacia la derecha: un solo giro a ~300 m', () {
      final r = buildRoute([(0, 0), (300, 0), (300, 300)]);
      final turns = detectTurns(r.points, r.cum);
      expect(turns.length, 1);
      expect(turns.single.side, TurnSide.right);
      expect(turns.single.alongM, closeTo(300, 15));
      expect(turns.single.angleDeg, closeTo(90, 12));
      expect(turns.single.phrase, 'gira a la derecha');
    });

    test('giro a la izquierda tiene ángulo negativo', () {
      final r = buildRoute([(0, 0), (300, 0), (300, -300)]);
      final turns = detectTurns(r.points, r.cum);
      expect(turns.single.side, TurnSide.left);
      expect(turns.single.angleDeg, lessThan(0));
      expect(turns.single.phrase, 'gira a la izquierda');
    });

    test('una curva larga y suave no cuenta como giro', () {
      // Arco de 90 grados con radio de 300 m, muestreado cada ~5 grados.
      final offsets = <(double, double)>[];
      for (var deg = 0; deg <= 90; deg += 5) {
        final a = deg * math.pi / 180;
        offsets.add((300 * math.sin(a), 300 * (1 - math.cos(a))));
      }
      final r = buildRoute(offsets);
      expect(detectTurns(r.points, r.cum), isEmpty);
    });

    test('el ruido lateral de unos metros no genera giros', () {
      final r = buildRoute([
        for (var d = 0.0; d <= 600; d += 10) (d, (d ~/ 10).isEven ? 2.0 : -2.0),
      ]);
      expect(detectTurns(r.points, r.cum), isEmpty);
    });

    test('un giro en horquilla se describe como muy cerrado', () {
      final r = buildRoute([(0, 0), (300, 0), (0, 12)]);
      final turns = detectTurns(r.points, r.cum);
      expect(turns.length, 1);
      expect(turns.single.angleDeg.abs(), greaterThan(130));
      expect(turns.single.phrase, contains('muy cerrado'));
    });
  });

  group('GuidanceEngine', () {
    GuidanceEngine engineFor(
      ({List<TrackPoint> points, List<double> cum}) r, {
      List<Waypoint> waypoints = const [],
    }) {
      final matcher = RouteMatcher(r.points, r.cum);
      return GuidanceEngine(
        turns: detectTurns(r.points, r.cum),
        totalM: r.cum.last,
        waypoints: waypoints,
        matcher: matcher,
      );
    }

    test('avisa a 100 m y al llegar al giro, cada uno una sola vez', () {
      final g = engineFor(buildRoute([(0, 0), (300, 0), (300, 300)]));
      expect(g.update(0), isEmpty);
      expect(g.update(150), isEmpty);
      final far = g.update(210);
      expect(far.single, startsWith('En 90 metros'));
      expect(far.single, contains('gira a la derecha'));
      expect(g.update(215), isEmpty);
      expect(g.update(280), ['Gira a la derecha']);
      expect(g.update(285), isEmpty);
    });

    test('si el GPS salta el umbral lejano, solo da el aviso cercano', () {
      final g = engineFor(buildRoute([(0, 0), (300, 0), (300, 300)]));
      expect(g.update(150), isEmpty);
      expect(g.update(290), ['Gira a la derecha']);
    });

    test('anuncia kilómetros y la llegada una sola vez', () {
      final g = engineFor(straightNorth(2500));
      expect(g.update(500), isEmpty);
      expect(g.update(1010), ['Kilómetro 1. Quedan 1,5 kilómetros']);
      expect(g.update(1500), isEmpty);
      expect(g.update(2010), ['Kilómetro 2. Quedan 490 metros']);
      expect(g.arrived, isFalse);
      expect(g.update(2480), ['Has llegado al final de la ruta']);
      expect(g.arrived, isTrue);
      expect(g.update(2495), isEmpty);
    });

    test('anuncia un waypoint cercano a la ruta y ignora los lejanos', () {
      final g = engineFor(
        straightNorth(1000),
        waypoints: [
          Waypoint(baseLat + northM(400), baseLon + eastM(5), name: 'Fuente'),
          Waypoint(baseLat + northM(600), baseLon + eastM(500), name: 'Lejano'),
        ],
      );
      expect(g.update(300), isEmpty);
      expect(g.update(370), ['Punto de interés: Fuente']);
      expect(g.update(590), isEmpty);
    });
  });

  group('spokenDistance', () {
    test('metros y kilómetros', () {
      expect(spokenDistance(80), '80 metros');
      expect(spokenDistance(94), '90 metros');
      expect(spokenDistance(3), '5 metros');
      expect(spokenDistance(1000), '1 kilómetro');
      expect(spokenDistance(1530), '1,5 kilómetros');
    });
  });
}
