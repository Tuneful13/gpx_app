import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:gpx_app/features/settings/app_settings.dart';
import 'package:gpx_app/features/settings/settings_controller.dart';
import 'package:gpx_app/features/settings/settings_page.dart';
import 'package:gpx_app/features/settings/settings_store.dart';
import 'package:gpx_app/main.dart';

void main() {
  group('AppSettings', () {
    test('valores por defecto', () {
      const s = AppSettings();
      expect(s.offRouteThresholdM, 30);
      expect(s.offRouteRepeatSeconds, 20);
      expect(s.voiceEnabled, isTrue);
      expect(s.alertSoundEnabled, isTrue);
      expect(s.keepScreenOn, isTrue);
    });

    test('copyWith ajusta los valores a sus límites', () {
      final low = const AppSettings().copyWith(
        offRouteThresholdM: 1,
        offRouteRepeatSeconds: 1,
      );
      expect(low.offRouteThresholdM, AppSettings.minOffRouteThresholdM);
      expect(low.offRouteRepeatSeconds, AppSettings.minOffRouteRepeatSeconds);

      final high = const AppSettings().copyWith(
        offRouteThresholdM: 9999,
        offRouteRepeatSeconds: 9999,
      );
      expect(high.offRouteThresholdM, AppSettings.maxOffRouteThresholdM);
      expect(high.offRouteRepeatSeconds, AppSettings.maxOffRouteRepeatSeconds);
    });

    test('ida y vuelta por toMap/fromMap', () {
      final s = const AppSettings().copyWith(
        offRouteThresholdM: 55,
        offRouteRepeatSeconds: 40,
        voiceEnabled: false,
        alertSoundEnabled: false,
        keepScreenOn: false,
        satellite: true,
      );
      expect(AppSettings.fromMap(s.toMap()), s);
    });

    test('datos guardados corruptos vuelven a los valores por defecto', () {
      final s = AppSettings.fromMap({
        'offRouteThresholdM': 'mucho',
        'offRouteRepeatSeconds': null,
        'voiceEnabled': 'sí',
        'alertSoundEnabled': 1,
      });
      expect(s, const AppSettings());
    });

    test('datos de rango imposible se ajustan al límite, no se descartan', () {
      final s = AppSettings.fromMap({
        'offRouteThresholdM': 5000,
        'offRouteRepeatSeconds': -3,
      });
      expect(s.offRouteThresholdM, AppSettings.maxOffRouteThresholdM);
      expect(s.offRouteRepeatSeconds, AppSettings.minOffRouteRepeatSeconds);
    });

    test('claves desconocidas se ignoran (otra versión de la app)', () {
      final s = AppSettings.fromMap({'ajusteFuturo': 7, 'voiceEnabled': false});
      expect(s.voiceEnabled, isFalse);
      expect(s.offRouteThresholdM, 30);
    });
  });

  group('SettingsController', () {
    test('guarda los cambios y otra sesión los recupera', () {
      final store = MemorySettingsStore();
      final c1 = ProviderContainer(
        overrides: [settingsStoreProvider.overrideWithValue(store)],
      );
      addTearDown(c1.dispose);

      c1.read(settingsProvider.notifier).update(
            (s) => s.copyWith(offRouteThresholdM: 60, voiceEnabled: false),
          );
      expect(c1.read(settingsProvider).offRouteThresholdM, 60);

      // "Reiniciar la app": nuevo contenedor sobre el mismo almacenamiento.
      final c2 = ProviderContainer(
        overrides: [settingsStoreProvider.overrideWithValue(store)],
      );
      addTearDown(c2.dispose);
      expect(c2.read(settingsProvider).offRouteThresholdM, 60);
      expect(c2.read(settingsProvider).voiceEnabled, isFalse);
    });

    test('restablecer vuelve a los valores de fábrica y también se guarda', () {
      final store = MemorySettingsStore();
      final c = ProviderContainer(
        overrides: [settingsStoreProvider.overrideWithValue(store)],
      );
      addTearDown(c.dispose);
      final ctrl = c.read(settingsProvider.notifier);

      ctrl.update((s) => s.copyWith(offRouteThresholdM: 80));
      ctrl.reset();

      expect(c.read(settingsProvider), const AppSettings());
      expect(AppSettings.fromMap(store.load()), const AppSettings());
    });
  });

  group('HiveSettingsStore (disco real)', () {
    test('los ajustes sobreviven a cerrar y reabrir la caja', () async {
      final dir = Directory.systemTemp.createTempSync('gpx_app_hive_test_');
      addTearDown(() async {
        await Hive.close();
        dir.deleteSync(recursive: true);
      });
      Hive.init(dir.path);

      var box = await Hive.openBox<dynamic>('settings');
      final first = ProviderContainer(overrides: [
        settingsStoreProvider.overrideWithValue(HiveSettingsStore(box)),
      ]);
      first.read(settingsProvider.notifier).update(
            (s) => s.copyWith(
              offRouteThresholdM: 65,
              voiceEnabled: false,
            ),
          );
      first.dispose();
      await box.close(); // como al cerrar la app

      box = await Hive.openBox<dynamic>('settings');
      final second = ProviderContainer(overrides: [
        settingsStoreProvider.overrideWithValue(HiveSettingsStore(box)),
      ]);
      addTearDown(second.dispose);

      final s = second.read(settingsProvider);
      expect(s.offRouteThresholdM, 65);
      expect(s.voiceEnabled, isFalse);
      expect(s.offRouteRepeatSeconds, 20); // lo no tocado sigue por defecto
    });
  });

  group('SettingsPage', () {
    Future<(ProviderContainer, MemorySettingsStore)> pumpPage(
      WidgetTester tester,
    ) async {
      final store = MemorySettingsStore();
      final container = ProviderContainer(
        overrides: [settingsStoreProvider.overrideWithValue(store)],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: SettingsPage()),
        ),
      );
      return (container, store);
    }

    testWidgets('muestra el umbral de desvío con su valor actual', (tester) async {
      await pumpPage(tester);
      expect(find.text('Umbral de desvío'), findsOneWidget);
      expect(find.text('30 m'), findsOneWidget);
    });

    testWidgets('arrastrar el deslizador cambia el umbral y lo guarda',
        (tester) async {
      final (container, store) = await pumpPage(tester);

      await tester.drag(find.byType(Slider).first, const Offset(200, 0));
      await tester.pump();

      final threshold = container.read(settingsProvider).offRouteThresholdM;
      expect(threshold, greaterThan(30));
      expect(AppSettings.fromMap(store.load()).offRouteThresholdM, threshold);
      expect(find.text('${threshold.round()} m'), findsWidgets);
    });

    testWidgets('el interruptor de voz se guarda', (tester) async {
      final (container, store) = await pumpPage(tester);

      await tester.scrollUntilVisible(
        find.text('Voz activada al empezar'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Voz activada al empezar'));
      await tester.pump();

      expect(container.read(settingsProvider).voiceEnabled, isFalse);
      expect(AppSettings.fromMap(store.load()).voiceEnabled, isFalse);
    });

    testWidgets('restablecer pide confirmación y vuelve a los valores de fábrica',
        (tester) async {
      final (container, _) = await pumpPage(tester);
      container
          .read(settingsProvider.notifier)
          .update((s) => s.copyWith(offRouteThresholdM: 80));
      await tester.pump();
      expect(find.text('80 m'), findsOneWidget);

      await tester.tap(find.byTooltip('Restablecer valores'));
      await tester.pumpAndSettle();
      // Cancelar no cambia nada.
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
      expect(container.read(settingsProvider).offRouteThresholdM, 80);

      await tester.tap(find.byTooltip('Restablecer valores'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Restablecer'));
      await tester.pumpAndSettle();
      expect(container.read(settingsProvider), const AppSettings());
      expect(find.text('30 m'), findsOneWidget);
    });

    testWidgets('se abre desde el icono de ajustes de la pantalla principal',
        (tester) async {
      await tester.pumpWidget(const ProviderScope(child: GpxApp()));
      await tester.tap(find.byTooltip('Ajustes'));
      await tester.pumpAndSettle();
      expect(find.text('Umbral de desvío'), findsOneWidget);
    });
  });
}
