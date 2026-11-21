import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gpx_app/features/map/map_view.dart';
import 'package:gpx_app/features/navigation/alert_player.dart';
import 'package:gpx_app/features/navigation/location_source.dart';
import 'package:gpx_app/features/navigation/navigation_page.dart';
import 'package:gpx_app/features/navigation/speaker.dart';
import 'package:gpx_app/features/routes/route_models.dart';
import 'package:gpx_app/features/routes/route_providers.dart';
import 'package:gpx_app/features/routes/route_stats.dart';
import 'package:gpx_app/main.dart';
import 'package:latlong2/latlong.dart';

import 'helpers/fakes.dart';
import 'helpers/route_builder.dart';

class HeadingSource implements LocationSource {
  final _controller = StreamController<Fix>();
  DateTime _t = DateTime(2026, 1, 1, 10);

  @override
  Future<LocationAccess> ensureAccess() async => LocationAccess.granted;

  @override
  Stream<Fix> fixes() => _controller.stream;

  void emit(double north, double east, {double? headingDeg}) {
    _t = _t.add(const Duration(seconds: 1));
    _controller.add(Fix(
      lat: baseLat + northM(north),
      lon: baseLon + eastM(east),
      time: _t,
      accuracyM: 5,
      headingDeg: headingDeg,
    ));
  }
}

LoadedRoute _route() {
  final r = buildRoute([(0, 0), (400, 0), (400, 400)]);
  return LoadedRoute(
    GpxRoute(name: 'Test', points: r.points),
    computeStats(r.points),
  );
}

void main() {
  group('orientación del mapa y la flecha', () {
    test('el mapa gira -rumbo para dejar tu dirección hacia arriba', () {
      expect(headingUpRotation(0), 0);
      expect(headingUpRotation(90), -90);
      expect(headingUpRotation(270), 90);
      expect(headingUpRotation(180), 180);
      expect(headingUpRotation(350), 10);
      expect(headingUpRotation(10), -10);
    });

    // En MapLibre el "bearing" es el rumbo que queda arriba de la pantalla:
    // para llevar tu dirección hacia arriba, bearing = tu rumbo.
    test('signo correcto: orientado a tu rumbo, ese rumbo queda ARRIBA', () {
      for (final h in <double>[0, 45, 90, 180, 270, 359]) {
        final c = MapViewController()
          ..moveAndRotate(const LatLng(baseLat, baseLon), 16, headingUpRotation(h));
        expect(c.bearing, closeTo(h, 1e-9), reason: 'rumbo $h');
      }
    });

    test('lo que informa el mapa nativo vuelve como la misma rotación', () {
      final c = MapViewController()
        ..syncFromMap(const LatLng(baseLat, baseLon), 15, 90);
      expect(c.rotation, closeTo(headingUpRotation(90), 1e-9));
      expect(c.zoom, 15);
    });

    test('mover sin rumbo conserva la orientación', () {
      final c = MapViewController()
        ..moveAndRotate(const LatLng(baseLat, baseLon), 16, -90)
        ..move(const LatLng(baseLat + 0.001, baseLon), 17);
      expect(c.rotation, -90);
      expect(c.zoom, 17);
    });
  });

  group('NavigationPage con el mapa orientado a tu dirección', () {
    late HeadingSource src;
    late ProviderContainer container;

    Future<MapViewController> pumpNav(WidgetTester tester) async {
      src = HeadingSource();
      container = ProviderContainer(overrides: [
        locationSourceProvider.overrideWithValue(src),
        speakerProvider.overrideWithValue(FakeSpeaker()),
        alertPlayerProvider.overrideWithValue(FakeAlert()),
      ]);
      addTearDown(container.dispose);
      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: MaterialApp(home: NavigationPage(loaded: _route())),
      ));
      await tester.pump();
      await tester.pump();
      return tester.widget<MapView>(find.byType(MapView)).controller!;
    }

    testWidgets('al moverte hacia el este el mapa gira para llevarlo arriba',
        (tester) async {
      final map = await pumpNav(tester);
      expect(map.rotation, 0);

      src.emit(10, 0, headingDeg: 90);
      await tester.pump();
      expect(map.rotation, closeTo(-90, 1e-6));
      expect(map.bearing, closeTo(90, 1e-6));

      src.emit(20, 0, headingDeg: 270);
      await tester.pump();
      expect(map.rotation, closeTo(90, 1e-6));
    });

    testWidgets('sin rumbo en una lectura, el mapa conserva su orientación',
        (tester) async {
      final map = await pumpNav(tester);
      src.emit(10, 0, headingDeg: 90);
      await tester.pump();
      src.emit(20, 0); // parado: el GPS no da rumbo
      await tester.pump();
      expect(map.rotation, closeTo(-90, 1e-6));
    });

    testWidgets('la cámara sigue tu posición', (tester) async {
      final map = await pumpNav(tester);
      src.emit(100, 0, headingDeg: 0);
      await tester.pump();
      expect(map.center!.latitude, closeTo(baseLat + northM(100), 1e-5));
      expect(map.center!.longitude, closeTo(baseLon, 1e-5));
      expect(map.zoom, greaterThanOrEqualTo(16));
    });
  });

  group('botón Iniciar ruta', () {
    Future<ProviderContainer> pumpApp(WidgetTester tester, {bool load = true}) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(container: container, child: const GpxApp()),
      );
      if (load) {
        container
            .read(viewerProvider.notifier)
            .loadFromString(File('samples/ejemplo.gpx').readAsStringSync());
        await tester.pump();
      }
      return container;
    }

    testWidgets('es grande, a todo el ancho y abajo; ya no es un botón flotante',
        (tester) async {
      await pumpApp(tester);

      final button = find.byKey(const ValueKey('start-route'));
      expect(button, findsOneWidget);
      expect(find.text('Iniciar ruta'), findsOneWidget);
      expect(find.byType(FloatingActionButton), findsNothing);

      final screen = tester.getSize(find.byType(MaterialApp));
      final size = tester.getSize(button);
      expect(size.width, greaterThan(screen.width * 0.85));
      expect(size.height, greaterThanOrEqualTo(56));
      expect(tester.getBottomLeft(button).dy, greaterThan(screen.height * 0.85));
    });

    testWidgets('no aparece si no hay ninguna ruta cargada', (tester) async {
      await pumpApp(tester, load: false);
      expect(find.byKey(const ValueKey('start-route')), findsNothing);
    });

    testWidgets('al pulsarlo se abre la hoja para elegir GPS o simulación',
        (tester) async {
      await pumpApp(tester);
      await tester.tap(find.byKey(const ValueKey('start-route')));
      await tester.pumpAndSettle();
      expect(find.text('Simular recorrido (pruebas)'), findsOneWidget);
      expect(find.text('Empezar'), findsOneWidget);
    });
  });
}
