import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gpx_app/features/navigation/alert_player.dart';
import 'package:gpx_app/features/navigation/location_source.dart';
import 'package:gpx_app/features/navigation/navigation_controller.dart';
import 'package:gpx_app/features/navigation/route_matcher.dart';
import 'package:gpx_app/features/navigation/simulated_source.dart';
import 'package:gpx_app/features/navigation/speaker.dart';
import 'package:gpx_app/features/routes/route_models.dart';
import 'package:gpx_app/features/routes/route_providers.dart';
import 'package:gpx_app/features/routes/route_stats.dart';
import 'package:gpx_app/features/settings/alert_sound.dart';
import 'package:gpx_app/features/settings/app_settings.dart';
import 'package:gpx_app/features/settings/settings_controller.dart';
import 'package:gpx_app/features/settings/settings_store.dart';

import 'helpers/fakes.dart';
import 'helpers/route_builder.dart';

class FakeSource implements LocationSource {
  FakeSource({this.access = LocationAccess.granted});

  final LocationAccess access;
  final _controller = StreamController<Fix>();
  DateTime _t = DateTime(2026, 1, 1, 10);

  @override
  Future<LocationAccess> ensureAccess() async => access;

  @override
  Stream<Fix> fixes() => _controller.stream;

  /// Emite una posición a (norte, este) metros del origen, 1 s después de la anterior.
  void emit(double north, double east, {double accuracyM = 5}) {
    _t = _t.add(const Duration(seconds: 1));
    _controller.add(Fix(
      lat: baseLat + northM(north),
      lon: baseLon + eastM(east),
      time: _t,
      accuracyM: accuracyM,
      speedMps: 1.4,
    ));
  }
}

LoadedRoute loadedRoute(List<(double, double)> offsets) {
  final r = buildRoute(offsets);
  return LoadedRoute(
    GpxRoute(name: 'Test', points: r.points),
    computeStats(r.points),
  );
}

void main() {
  late FakeSpeaker speaker;
  late FakeAlert alert;
  late ProviderContainer container;

  setUp(() {
    speaker = FakeSpeaker();
    alert = FakeAlert();
    container = ProviderContainer(overrides: [
      speakerProvider.overrideWithValue(speaker),
      alertPlayerProvider.overrideWithValue(alert),
    ]);
    addTearDown(container.dispose);
  });

  NavState nav() => container.read(navigationProvider);
  NavigationController ctrl() => container.read(navigationProvider.notifier);

  // Ruta en L: 400 m al norte y 400 m al este (800 m en total, un giro a la derecha).
  final lRoute = loadedRoute([(0, 0), (400, 0), (400, 400)]);

  test('recorrido completo: llegar a la ruta, giro, desvío, vuelta y llegada',
      () async {
    final src = FakeSource();
    await ctrl().start(lRoute, source: src);

    expect(nav().active, isTrue);
    expect(speaker.said.single, 'Ruta iniciada. Distancia total 800 metros');

    // Lejos de la ruta: te guía hacia ella, sin alarma de desvío.
    for (var i = 0; i < 5; i++) {
      src.emit(0, 2000);
    }
    await pumpEventQueue();
    expect(nav().joinedRoute, isFalse);
    expect(nav().banner!.text, startsWith('Acércate a la ruta'));
    expect(alert.count, 0);

    // Llegas a la ruta.
    src.emit(10, 0);
    await pumpEventQueue();
    expect(nav().joinedRoute, isTrue);
    expect(speaker.said, contains('Estás en la ruta'));
    expect(nav().remainingM, closeTo(790, 2));

    // A 90 m del giro.
    src.emit(310, 0);
    await pumpEventQueue();
    expect(speaker.said.last, 'En 90 metros, gira a la derecha');
    expect(nav().nextTurn, isNotNull);
    expect(nav().nextTurnInM, closeTo(90, 8));

    // Te sales 70 m a un lado: a la tercera lectura salta el aviso.
    src.emit(350, 70);
    src.emit(352, 70);
    await pumpEventQueue();
    expect(nav().offRoute, isFalse);
    expect(alert.count, 0);
    src.emit(354, 70);
    await pumpEventQueue();
    expect(nav().offRoute, isTrue);
    expect(alert.count, 1);
    expect(speaker.said.last, 'Te has salido de la ruta');
    expect(nav().banner!.kind, BannerKind.warning);

    // Vuelves.
    src.emit(360, 0);
    await pumpEventQueue();
    expect(nav().offRoute, isFalse);
    expect(speaker.said.last, 'Has vuelto a la ruta');

    // El giro.
    src.emit(392, 0);
    await pumpEventQueue();
    expect(speaker.said.last, 'Gira a la derecha');

    // Llegada.
    src.emit(400, 200);
    src.emit(400, 395);
    await pumpEventQueue();
    expect(nav().arrived, isTrue);
    expect(speaker.said.last, 'Has llegado al final de la ruta');
    expect(nav().remainingM, lessThan(30));
  });

  test('una lectura con poca precisión no dispara el desvío', () async {
    final src = FakeSource();
    await ctrl().start(lRoute, source: src);
    src.emit(10, 0);
    for (var i = 0; i < 4; i++) {
      src.emit(100, 80, accuracyM: 120);
    }
    await pumpEventQueue();
    expect(nav().offRoute, isFalse);
    expect(alert.count, 0);
  });

  test('sin permiso no arranca y explica el motivo', () async {
    await ctrl().start(lRoute, source: FakeSource(access: LocationAccess.denied));
    expect(nav().active, isFalse);
    expect(nav().accessProblem, contains('permiso'));
    expect(nav().accessIssue, LocationAccess.denied);
  });

  test('GPS desactivado y permiso denegado para siempre dan mensajes distintos',
      () async {
    await ctrl().start(lRoute,
        source: FakeSource(access: LocationAccess.serviceDisabled));
    final off = nav().accessProblem;
    await ctrl().start(lRoute,
        source: FakeSource(access: LocationAccess.deniedForever));
    expect(nav().accessProblem, isNot(off));
    expect(nav().accessIssue, LocationAccess.deniedForever);
  });

  test('silenciar corta la voz pero la navegación sigue', () async {
    final src = FakeSource();
    await ctrl().start(lRoute, source: src);
    ctrl().toggleMute();
    expect(nav().muted, isTrue);
    expect(speaker.stops, 1);

    final before = speaker.said.length;
    src.emit(10, 0);
    src.emit(310, 0);
    await pumpEventQueue();
    expect(speaker.said.length, before);
    expect(nav().joinedRoute, isTrue);
    expect(nav().banner!.text, contains('gira a la derecha'));
  });

  test('terminar la ruta reinicia el estado y para la voz', () async {
    final src = FakeSource();
    await ctrl().start(lRoute, source: src);
    src.emit(10, 0);
    await pumpEventQueue();
    await ctrl().stop();
    expect(nav().active, isFalse);
    expect(nav().position, isNull);
    expect(speaker.stops, 1);
  });

  test('una ruta de un solo punto no se puede navegar', () async {
    final one = loadedRoute([(0, 0)]);
    await ctrl().start(one, source: FakeSource());
    expect(nav().active, isFalse);
    expect(nav().accessProblem, contains('2 puntos'));
  });

  group('ajustes de usuario aplicados a la navegación', () {
    ProviderContainer containerWith(AppSettings s) {
      final c = ProviderContainer(overrides: [
        speakerProvider.overrideWithValue(speaker),
        alertPlayerProvider.overrideWithValue(alert),
        settingsStoreProvider.overrideWithValue(MemorySettingsStore(s.toMap())),
      ]);
      addTearDown(c.dispose);
      return c;
    }

    test('con umbral de 100 m, estar a 70 m de la ruta no es un desvío', () async {
      final c = containerWith(const AppSettings().copyWith(offRouteThresholdM: 100));
      final src = FakeSource();
      await c.read(navigationProvider.notifier).start(lRoute, source: src);
      src.emit(10, 0);
      for (var i = 0; i < 5; i++) {
        src.emit(350, 70);
      }
      await pumpEventQueue();
      expect(c.read(navigationProvider).offRoute, isFalse);
      expect(alert.count, 0);
    });

    test('con umbral de 30 m (por defecto), a 70 m sí es un desvío', () async {
      final c = containerWith(const AppSettings());
      final src = FakeSource();
      await c.read(navigationProvider.notifier).start(lRoute, source: src);
      src.emit(10, 0);
      for (var i = 0; i < 3; i++) {
        src.emit(350, 70);
      }
      await pumpEventQueue();
      expect(c.read(navigationProvider).offRoute, isTrue);
    });

    test('con umbral de 10 m, 20 m de separación ya es un desvío', () async {
      final c = containerWith(const AppSettings().copyWith(offRouteThresholdM: 10));
      final src = FakeSource();
      await c.read(navigationProvider.notifier).start(lRoute, source: src);
      src.emit(10, 0);
      for (var i = 0; i < 3; i++) {
        src.emit(350, 20);
      }
      await pumpEventQueue();
      expect(c.read(navigationProvider).offRoute, isTrue);
    });

    test('el intervalo de repetición del aviso se respeta', () async {
      final c = containerWith(
        const AppSettings().copyWith(offRouteRepeatSeconds: 10),
      );
      final src = FakeSource();
      await c.read(navigationProvider.notifier).start(lRoute, source: src);
      src.emit(10, 0);
      for (var i = 0; i < 3; i++) {
        src.emit(350, 70);
      }
      await pumpEventQueue();
      expect(alert.count, 1);
      // Con 10 s entre avisos (las lecturas llegan cada 1 s): 9 s más = aún no.
      for (var i = 0; i < 9; i++) {
        src.emit(350, 70);
      }
      await pumpEventQueue();
      expect(alert.count, 1);
      src.emit(350, 70);
      await pumpEventQueue();
      expect(alert.count, 2);
    });

    test('con voz desactivada al empezar no habla, pero la ruta funciona',
        () async {
      final c = containerWith(const AppSettings().copyWith(voiceEnabled: false));
      final src = FakeSource();
      await c.read(navigationProvider.notifier).start(lRoute, source: src);
      expect(c.read(navigationProvider).muted, isTrue);
      src.emit(10, 0);
      src.emit(310, 0);
      await pumpEventQueue();
      expect(speaker.said, isEmpty);
      expect(c.read(navigationProvider).joinedRoute, isTrue);
    });

    test('sin sonido de alerta: no suena la alarma pero sí avisa por voz', () async {
      final c = containerWith(const AppSettings().copyWith(alertSoundEnabled: false));
      final src = FakeSource();
      await c.read(navigationProvider.notifier).start(lRoute, source: src);
      src.emit(10, 0);
      for (var i = 0; i < 3; i++) {
        src.emit(350, 70);
      }
      await pumpEventQueue();
      expect(c.read(navigationProvider).offRoute, isTrue);
      expect(alert.count, 0);
      expect(speaker.said.last, 'Te has salido de la ruta');
    });

    test('el aviso previo de giro usa la distancia configurada', () async {
      final c = containerWith(const AppSettings().copyWith(turnAnnounceM: 50));
      final src = FakeSource();
      await c.read(navigationProvider.notifier).start(lRoute, source: src);
      src.emit(10, 0);
      src.emit(310, 0); // a 90 m del giro: con 50 m de aviso todavía no.
      await pumpEventQueue();
      expect(speaker.said.where((m) => m.startsWith('En ')), isEmpty);
      src.emit(360, 0); // a 40 m
      await pumpEventQueue();
      expect(speaker.said.last, startsWith('En 40 metros'));
    });

    test('la sensibilidad de giros decide qué giros se avisan', () async {
      // Giro de unos 50 grados a la derecha: pasa el filtro de 25° pero no el de 60°.
      final soft = loadedRoute([(0, 0), (400, 0), (400 + 200, 238)]);

      Future<List<String>> runWith(double minAngle) async {
        speaker.said.clear();
        final c = containerWith(
          const AppSettings().copyWith(turnMinAngleDeg: minAngle),
        );
        final src = FakeSource();
        await c.read(navigationProvider.notifier).start(soft, source: src);
        src.emit(10, 0);
        src.emit(380, 0);
        await pumpEventQueue();
        return speaker.said
            .where((m) => m.toLowerCase().contains('gira'))
            .toList();
      }

      expect(await runWith(25), isNotEmpty);
      expect(await runWith(60), isEmpty);
    });

    Future<ProviderContainer> goOffRoute(AppSettings s) async {
      final c = containerWith(s);
      final src = FakeSource();
      await c.read(navigationProvider.notifier).start(lRoute, source: src);
      src.emit(10, 0);
      for (var i = 0; i < 3; i++) {
        src.emit(350, 70);
      }
      await pumpEventQueue();
      expect(c.read(navigationProvider).offRoute, isTrue);
      return c;
    }

    test('al desviarte suena el sonido elegido y vibra', () async {
      await goOffRoute(const AppSettings().copyWith(alertSound: AlertSound.chime));
      expect(alert.sounds, [AlertSound.chime]);
      expect(alert.vibrations, 1);
    });

    test('sin vibración: suena pero no vibra', () async {
      await goOffRoute(const AppSettings().copyWith(alertVibrationEnabled: false));
      expect(alert.count, 1);
      expect(alert.vibrations, 0);
    });

    test('sin sonido ni vibración: solo voz y aviso en pantalla', () async {
      final c = await goOffRoute(const AppSettings()
          .copyWith(alertSoundEnabled: false, alertVibrationEnabled: false));
      expect(alert.count, 0);
      expect(alert.vibrations, 0);
      expect(speaker.said.last, 'Te has salido de la ruta');
      expect(c.read(navigationProvider).banner!.kind, BannerKind.warning);
    });

    test('la voz usa la velocidad y la voz elegidas en ajustes', () async {
      await goOffRoute(const AppSettings().copyWith(
        voiceRate: 0.9,
        voiceName: 'spanish-mbrola-4',
        voiceLocale: 'es-es',
      ));
      expect(speaker.lastRate, 0.9);
      expect(speaker.lastVoiceName, 'spanish-mbrola-4');
      expect(speaker.lastVoiceLocale, 'es-es');
    });

    test('cambiar ajustes con la ruta en marcha no la afecta', () async {
      final c = containerWith(const AppSettings());
      final src = FakeSource();
      await c.read(navigationProvider.notifier).start(lRoute, source: src);
      c.read(settingsProvider.notifier).update(
            (s) => s.copyWith(offRouteThresholdM: 100),
          );
      src.emit(10, 0);
      for (var i = 0; i < 3; i++) {
        src.emit(350, 70);
      }
      await pumpEventQueue();
      expect(c.read(navigationProvider).offRoute, isTrue);
    });
  });

  group('SimulatedLocationSource', () {
    final r = buildRoute([(0, 0), (1000, 0), (1000, 1000)]);

    test('sin desvío sigue la ruta y termina en el final', () async {
      final sim = SimulatedLocationSource(
        points: r.points,
        cumulativeM: r.cum,
        speedMps: 200,
        tick: Duration.zero,
        withDetour: false,
      );
      final matcher = RouteMatcher(r.points, r.cum);
      final fixes = await sim.fixes().toList();
      expect(fixes.length, greaterThan(5));
      for (final f in fixes) {
        expect(matcher.match(f.lat, f.lon).distanceToRouteM, lessThan(1));
      }
      final last = matcher.match(fixes.last.lat, fixes.last.lon);
      expect(last.alongM, closeTo(r.cum.last, 1));
    });

    test('con desvío se aleja ~90 m a mitad de ruta y vuelve a la ruta', () {
      // Ruta recta: en una en L el desvío podría quedar cerca de otro tramo.
      final r = straightNorth(2000);
      final sim = SimulatedLocationSource(
        points: r.points,
        cumulativeM: r.cum,
        tick: Duration.zero,
      );
      final matcher = RouteMatcher(r.points, r.cum);
      double dist(double frac) {
        final f = sim.positionAt(r.cum.last * frac, DateTime(2026));
        return matcher.match(f.lat, f.lon).distanceToRouteM;
      }

      expect(dist(0.1), lessThan(1));
      expect(dist(0.46), closeTo(90, 3));
      expect(dist(0.8), lessThan(1));
    });
  });
}
