import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gpx_app/core/executables.dart';
import 'package:gpx_app/features/navigation/alert_player.dart';
import 'package:gpx_app/features/navigation/speaker.dart';
import 'package:gpx_app/features/settings/alert_sound.dart';
import 'package:gpx_app/features/settings/app_settings.dart';
import 'package:gpx_app/features/settings/settings_controller.dart';
import 'package:gpx_app/features/settings/settings_page.dart';
import 'package:gpx_app/features/settings/settings_store.dart';

import 'helpers/fakes.dart';

void main() {
  group('AppSettings: sonido, vibración y voz', () {
    test('valores por defecto', () {
      const s = AppSettings();
      expect(s.alertSound, AlertSound.alarm);
      expect(s.alertVibrationEnabled, isTrue);
      expect(s.voiceRate, 0.5);
      expect(s.voiceName, '');
      expect(s.voiceLocale, '');
    });

    test('ida y vuelta con los campos nuevos', () {
      final s = const AppSettings().copyWith(
        alertSound: AlertSound.chime,
        alertVibrationEnabled: false,
        voiceRate: 0.8,
        voiceName: 'es-es-x-eed-local',
        voiceLocale: 'es-ES',
      );
      expect(AppSettings.fromMap(s.toMap()), s);
    });

    test('un sonido desconocido o corrupto cae en la alarma', () {
      expect(AppSettings.fromMap({'alertSound': 'sirena-del-futuro'}).alertSound,
          AlertSound.alarm);
      expect(AppSettings.fromMap({'alertSound': 42}).alertSound, AlertSound.alarm);
      expect(AppSettings.fromMap({}).alertSound, AlertSound.alarm);
    });

    test('la velocidad de voz se ajusta a sus límites', () {
      const d = AppSettings();
      expect(d.copyWith(voiceRate: 0.01).voiceRate, AppSettings.minVoiceRate);
      expect(d.copyWith(voiceRate: 9).voiceRate, AppSettings.maxVoiceRate);
      expect(AppSettings.fromMap({'voiceRate': 'rápido'}).voiceRate, 0.5);
    });

    test('nombre de voz con un tipo inesperado vuelve a la predeterminada', () {
      final s = AppSettings.fromMap({'voiceName': 12, 'voiceLocale': true});
      expect(s.voiceName, '');
      expect(s.voiceLocale, '');
    });

    test('cada sonido apunta a un archivo distinto', () {
      expect(AlertSound.values.map((s) => s.asset).toSet().length,
          AlertSound.values.length);
      for (final s in AlertSound.values) {
        expect(AlertSound.fromId(s.id), s);
        expect(File(s.asset).existsSync(), isTrue, reason: s.asset);
      }
    });
  });

  group('voz en Linux (espeak-ng / speech-dispatcher)', () {
    test('velocidad normal = 150 palabras/minuto y respeta los extremos', () {
      expect(espeakWordsPerMinute(0.5), 150);
      expect(espeakWordsPerMinute(1.0), 300);
      expect(espeakWordsPerMinute(0.25), 80); // mínimo de espeak
      expect(espeakWordsPerMinute(5), 450); // máximo de espeak
    });

    test('argumentos de espeak: voz por defecto o la elegida', () {
      expect(espeakArgs('hola', rate: 0.5), ['-v', 'es', '-s', '150', 'hola']);
      expect(
        espeakArgs('hola', rate: 1.0, voiceName: 'spanish-mbrola-4'),
        ['-v', 'spanish-mbrola-4', '-s', '300', 'hola'],
      );
    });

    test('velocidad de speech-dispatcher', () {
      expect(spdSayRate(0.5), 0);
      expect(spdSayRate(1.0), 100);
      expect(spdSayRate(0.25), -50);
      expect(spdSayArgs('hola', rate: 0.5), ['-l', 'es', '-r', '0', 'hola']);
    });

    // Salida real de `espeak-ng --voices=es` en Fedora.
    const espeakOutput = '''
Pty Language       Age/Gender VoiceName          File                 Other Languages
 3  es-es           --/F      spanish-mbrola-3   mb/mb-es3            (es 3)
 4  es-es           --/M      spanish-mbrola-4   mb/mb-es4            (es 4)
 5  es              --/M      Spanish_(Spain)    roa/es
 5  es-419          --/M      Spanish_(Latin_America) roa/es-419           (es-mx 6)(es 6)
 7  es-es           --/M      spanish-mbrola-1   mb/mb-es1            (es 7)
 7  es-es           --/M      spanish-mbrola-2   mb/mb-es2            (es 7)
 7  es-mx           --/M      mexican-mbrola-1   mb/mb-mx1            (es 8)
 7  es-mx           --/M      mexican-mbrola-2   mb/mb-mx2            (es 8)
 7  es-vz           --/M      venezuala-mbrola-1 mb/mb-vz1            (es 8)
''';

    test('usa el identificador de archivo, que es el que acepta espeak -v', () {
      final voices = parseEspeakVoices(espeakOutput);
      expect(voices.map((v) => v.name), ['roa/es-419', 'roa/es']);
      expect(voices.map((v) => v.label),
          ['Spanish (Latin America)', 'Spanish (Spain)']);
      expect(voices.map((v) => v.locale), ['es-419', 'es']);
    });

    test('descarta las voces mbrola (sin el programa mbrola no suenan)', () {
      final voices = parseEspeakVoices(espeakOutput);
      expect(voices.any((v) => v.name.startsWith('mb/')), isFalse);
    });

    test('con mbrola instalado sí se ofrecen', () {
      final voices = parseEspeakVoices(espeakOutput, includeMbrola: true);
      expect(voices, hasLength(9));
      expect(voices.map((v) => v.name), contains('mb/mb-es3'));
    });

    test('cada voz tiene variantes femenina y grave', () {
      final base = parseEspeakVoices(espeakOutput);
      final all = withEspeakVariants(base);
      expect(all, hasLength(base.length * 3));
      final spain =
          all.where((v) => v.name.startsWith('roa/es+') || v.name == 'roa/es');
      expect(spain.map((v) => v.name), ['roa/es', 'roa/es+f3', 'roa/es+m7']);
      expect(spain.map((v) => v.label), [
        'Spanish (Spain)',
        'Spanish (Spain) · femenina',
        'Spanish (Spain) · grave',
      ]);
      // Y los argumentos resultantes son válidos para espeak-ng.
      expect(espeakArgs('hola', rate: 0.5, voiceName: 'roa/es+f3'),
          ['-v', 'roa/es+f3', '-s', '150', 'hola']);
    });

    test('ignora basura y salida vacía', () {
      expect(parseEspeakVoices(''), isEmpty);
      expect(parseEspeakVoices('error: algo falló\nsocket(): no permitido'), isEmpty);
    });

    test('findExecutable recorre el PATH y respeta el orden de preferencia', () {
      final a = Directory.systemTemp.createTempSync('exe_a_');
      final b = Directory.systemTemp.createTempSync('exe_b_');
      addTearDown(() {
        a.deleteSync(recursive: true);
        b.deleteSync(recursive: true);
      });
      File('${a.path}/segundo').writeAsStringSync('');
      File('${b.path}/primero').writeAsStringSync('');
      final path = '${a.path}:${b.path}';

      // "primero" tiene preferencia aunque esté en el último directorio.
      expect(findExecutable(['primero', 'segundo'], pathEnv: path),
          '${b.path}/primero');
      expect(findExecutable(['noexiste', 'segundo'], pathEnv: path),
          '${a.path}/segundo');
      expect(findExecutable(['noexiste'], pathEnv: path), isNull);
      expect(findExecutable(['primero'], pathEnv: ''), isNull);
    });
  });

  group('playAlarm', () {
    test('sonido + vibración por defecto', () {
      final alert = FakeAlert();
      playAlarm(const AppSettings(), alert);
      expect(alert.sounds, [AlertSound.alarm]);
      expect(alert.vibrations, 1);
    });

    test('respeta el sonido elegido', () {
      final alert = FakeAlert();
      playAlarm(const AppSettings().copyWith(alertSound: AlertSound.chime), alert);
      expect(alert.sounds, [AlertSound.chime]);
    });

    test('sin sonido, solo vibra; sin vibración, solo suena', () {
      final a = FakeAlert();
      playAlarm(const AppSettings().copyWith(alertSoundEnabled: false), a);
      expect(a.sounds, isEmpty);
      expect(a.vibrations, 1);

      final b = FakeAlert();
      playAlarm(const AppSettings().copyWith(alertVibrationEnabled: false), b);
      expect(b.sounds, hasLength(1));
      expect(b.vibrations, 0);
    });

    test('con todo desactivado no hace nada', () {
      final alert = FakeAlert();
      playAlarm(
        const AppSettings()
            .copyWith(alertSoundEnabled: false, alertVibrationEnabled: false),
        alert,
      );
      expect(alert.count, 0);
      expect(alert.vibrations, 0);
    });
  });

  group('SettingsPage: pruebas de aviso y voz', () {
    late FakeSpeaker speaker;
    late FakeAlert alert;
    late MemorySettingsStore store;
    late ProviderContainer container;

    Future<void> pumpPage(
      WidgetTester tester, {
      List<SpeechVoice> voices = const [],
      AppSettings initial = const AppSettings(),
    }) async {
      speaker = FakeSpeaker(availableVoices: voices);
      alert = FakeAlert();
      store = MemorySettingsStore(initial.toMap());
      container = ProviderContainer(overrides: [
        speakerProvider.overrideWithValue(speaker),
        alertPlayerProvider.overrideWithValue(alert),
        settingsStoreProvider.overrideWithValue(store),
      ]);
      addTearDown(container.dispose);
      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: SettingsPage()),
      ));
      await tester.pumpAndSettle();
    }

    Future<void> reveal(WidgetTester tester, Finder f) => tester.scrollUntilVisible(
          f,
          200,
          scrollable: find.byType(Scrollable).first,
        );

    testWidgets('"Mantener pantalla encendida" está arriba del todo',
        (tester) async {
      await pumpPage(tester);
      final keepOn = tester.getTopLeft(find.text('Mantener la pantalla encendida')).dy;
      final threshold = tester.getTopLeft(find.text('Umbral de desvío')).dy;
      final sound = tester.getTopLeft(find.text('Sonido')).dy;
      expect(keepOn, lessThan(threshold));
      expect(keepOn, lessThan(sound));
      expect(find.text('Pantalla'), findsOneWidget);
    });

    testWidgets('Probar sonido reproduce el sonido elegido', (tester) async {
      await pumpPage(tester,
          initial: const AppSettings().copyWith(alertSound: AlertSound.beep));
      await reveal(tester, find.byKey(const ValueKey('test-sound')));
      await tester.tap(find.byKey(const ValueKey('test-sound')));
      await tester.pump();
      expect(alert.sounds, [AlertSound.beep]);
      expect(speaker.said, isEmpty);
    });

    testWidgets('elegir un sonido lo guarda y lo reproduce para compararlo',
        (tester) async {
      await pumpPage(tester);
      await reveal(tester, find.text('Campana'));
      await tester.tap(find.text('Campana'));
      await tester.pump();

      expect(container.read(settingsProvider).alertSound, AlertSound.chime);
      expect(AppSettings.fromMap(store.load()).alertSound, AlertSound.chime);
      expect(alert.sounds, [AlertSound.chime]);
    });

    testWidgets('con el sonido desactivado desaparece el selector', (tester) async {
      await pumpPage(tester,
          initial: const AppSettings().copyWith(alertSoundEnabled: false));
      expect(find.byKey(const ValueKey('sound-picker')), findsNothing);
      expect(find.byKey(const ValueKey('test-sound')), findsNothing);
    });

    testWidgets('Probar vibración vibra, sin sonar ni hablar', (tester) async {
      await pumpPage(tester);
      await reveal(tester, find.byKey(const ValueKey('test-vibration')));
      await tester.tap(find.byKey(const ValueKey('test-vibration')));
      await tester.pump();
      expect(alert.vibrations, 1);
      expect(alert.count, 0);
      expect(speaker.said, isEmpty);
    });

    testWidgets('Probar aviso completo: voz + sonido + vibración', (tester) async {
      await pumpPage(tester,
          initial: const AppSettings().copyWith(alertSound: AlertSound.chime));
      await reveal(tester, find.byKey(const ValueKey('test-full')));
      await tester.tap(find.byKey(const ValueKey('test-full')));
      await tester.pump();
      expect(speaker.said, ['Te has salido de la ruta']);
      expect(alert.sounds, [AlertSound.chime]);
      expect(alert.vibrations, 1);
    });

    testWidgets('Probar aviso completo respeta lo que esté desactivado',
        (tester) async {
      await pumpPage(
        tester,
        initial: const AppSettings().copyWith(
          voiceEnabled: false,
          alertSoundEnabled: false,
        ),
      );
      await reveal(tester, find.byKey(const ValueKey('test-full')));
      await tester.tap(find.byKey(const ValueKey('test-full')));
      await tester.pump();
      expect(speaker.said, isEmpty);
      expect(alert.count, 0);
      expect(alert.vibrations, 1);
    });

    testWidgets('Probar voz usa la velocidad y la distancia configuradas',
        (tester) async {
      await pumpPage(
        tester,
        initial: const AppSettings().copyWith(voiceRate: 0.8, offRouteThresholdM: 50),
      );
      await reveal(tester, find.byKey(const ValueKey('test-voice')));
      await tester.tap(find.byKey(const ValueKey('test-voice')));
      await tester.pump();
      expect(speaker.said, ['Sigues fuera de la ruta, a 50 metros']);
      expect(speaker.lastRate, 0.8);
      expect(speaker.lastVoiceName, '');
    });

    testWidgets('Probar voz funciona aunque la voz esté desactivada al empezar',
        (tester) async {
      await pumpPage(tester,
          initial: const AppSettings().copyWith(voiceEnabled: false));
      await reveal(tester, find.byKey(const ValueKey('test-voice')));
      await tester.tap(find.byKey(const ValueKey('test-voice')));
      await tester.pump();
      expect(speaker.said, hasLength(1));
    });

    testWidgets('la velocidad de voz se muestra en porcentaje', (tester) async {
      await pumpPage(tester);
      await reveal(tester, find.text('Velocidad de la voz'));
      expect(find.text('100 %'), findsOneWidget);
    });

    testWidgets('sin voces listables no aparece el selector de voz',
        (tester) async {
      await pumpPage(tester);
      await reveal(tester, find.byKey(const ValueKey('test-voice')));
      expect(find.byKey(const ValueKey('voice-picker')), findsNothing);
    });

    testWidgets('elegir una voz la guarda y se usa al probar', (tester) async {
      await pumpPage(tester, voices: const [
        SpeechVoice('roa/es', 'es', label: 'Spanish (Spain)'),
        SpeechVoice('roa/es+f3', 'es', label: 'Spanish (Spain) · femenina'),
      ]);
      await reveal(tester, find.byKey(const ValueKey('voice-picker')));
      await tester.tap(find.byKey(const ValueKey('voice-picker')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Spanish (Spain) · femenina').last);
      await tester.pumpAndSettle();

      // Se guarda el identificador del motor, no la etiqueta que ve el usuario.
      final s = container.read(settingsProvider);
      expect(s.voiceName, 'roa/es+f3');
      expect(s.voiceLocale, 'es');
      expect(AppSettings.fromMap(store.load()).voiceName, 'roa/es+f3');

      await reveal(tester, find.byKey(const ValueKey('test-voice')));
      await tester.tap(find.byKey(const ValueKey('test-voice')));
      await tester.pump();
      expect(speaker.lastVoiceName, 'roa/es+f3');
      expect(speaker.lastVoiceLocale, 'es');
    });

    testWidgets('una voz guardada que ya no existe se muestra como predeterminada',
        (tester) async {
      await pumpPage(
        tester,
        voices: const [SpeechVoice('roa/es', 'es', label: 'Spanish (Spain)')],
        initial: const AppSettings().copyWith(voiceName: 'voz-desinstalada'),
      );
      await reveal(tester, find.byKey(const ValueKey('voice-picker')));
      expect(find.text('Automática (la mejor disponible)'), findsOneWidget);
    });
  });
}
