import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';

import '../../core/executables.dart';
import '../settings/alert_sound.dart';
import '../settings/app_settings.dart';

abstract class AlertPlayer {
  Future<void> sound(AlertSound sound);
  Future<void> vibrate();
}

/// Lanza el sonido y la vibración del aviso de desvío según los ajustes.
/// La usan la navegación y el botón "Probar" de Ajustes, para que probar sea
/// exactamente lo mismo que ocurre de verdad.
void playAlarm(AppSettings settings, AlertPlayer player) {
  if (settings.alertSoundEnabled) unawaited(player.sound(settings.alertSound));
  if (settings.alertVibrationEnabled) unawaited(player.vibrate());
}

/// Android e iOS.
class SoundAlertPlayer implements AlertPlayer {
  AudioPlayer? _player;
  String? _loadedAsset;

  @override
  Future<void> sound(AlertSound sound) async {
    try {
      final player = _player ??= AudioPlayer();
      if (_loadedAsset != sound.asset) {
        await player.setAsset(sound.asset);
        _loadedAsset = sound.asset;
      }
      await player.seek(Duration.zero);
      await player.play();
    } catch (e) {
      debugPrint('Sonido de alerta no disponible: $e');
    }
  }

  @override
  Future<void> vibrate() async {
    try {
      await HapticFeedback.vibrate();
    } catch (e) {
      debugPrint('Vibración no disponible: $e');
    }
  }
}

/// Linux de escritorio: just_audio no tiene soporte, así que se reproduce el
/// WAV con las herramientas del sistema (PipeWire, PulseAudio o ALSA).
class CommandLineAlertPlayer implements AlertPlayer {
  final Map<AlertSound, File> _files = {};
  String? _player;
  bool _searched = false;

  @override
  Future<void> sound(AlertSound sound) async {
    try {
      if (!_searched) {
        _searched = true;
        _player = findExecutable(['pw-play', 'paplay', 'aplay']);
      }
      final exe = _player;
      if (exe == null) {
        debugPrint('Sin reproductor de audio (pw-play, paplay o aplay).');
        return;
      }
      var file = _files[sound];
      if (file == null || !file.existsSync()) {
        final data = await rootBundle.load(sound.asset);
        final dir = await Directory.systemTemp.createTemp('gpx_app_sounds_');
        file = File('${dir.path}/${sound.id}.wav');
        await file.writeAsBytes(
          data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        );
        _files[sound] = file;
      }
      final p = await Process.start(exe, [file.path]);
      p.stdout.drain<void>();
      p.stderr.drain<void>();
    } catch (e) {
      debugPrint('Sonido de alerta no disponible: $e');
    }
  }

  @override
  Future<void> vibrate() async {
    debugPrint('[vibración] (el escritorio no vibra)');
  }
}

final alertPlayerProvider = Provider<AlertPlayer>((ref) {
  return defaultTargetPlatform == TargetPlatform.linux
      ? CommandLineAlertPlayer()
      : SoundAlertPlayer();
});
