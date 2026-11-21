import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tts/flutter_tts.dart';

import '../../core/executables.dart';

/// Una voz instalada en el dispositivo.
class SpeechVoice {
  const SpeechVoice(
    this.name,
    this.locale, {
    String? label,
    this.quality = 0,
    this.network = false,
  }) : label = label ?? name;

  /// Identificador que entiende el motor de voz (lo que se guarda en ajustes).
  final String name;
  final String locale;

  /// Texto para mostrar al usuario.
  final String label;

  /// Calidad según el motor (0 = desconocida, 5 = muy alta).
  final int quality;

  /// true si la voz necesita conexión a internet.
  final bool network;

  @override
  bool operator ==(Object other) =>
      other is SpeechVoice && other.name == name && other.locale == locale;

  @override
  int get hashCode => Object.hash(name, locale);
}

abstract class Speaker {
  /// [rate]: 0,5 = velocidad normal. [voiceName] vacío = voz predeterminada.
  Future<void> speak(
    String text, {
    double rate = 0.5,
    String voiceName = '',
    String voiceLocale = '',
  });

  Future<void> stop();

  /// Voces en español disponibles para elegir (vacío si no se pueden listar).
  Future<List<SpeechVoice>> voices();
}

const _qualityRank = {
  'very high': 5,
  'high': 4,
  'normal': 3,
  'low': 2,
  'very low': 1,
};

String _normLocale(String locale) => locale.replaceAll('_', '-').toLowerCase();

String _regionName(String locale) {
  final l = _normLocale(locale);
  if (l == 'es-es' || l == 'es') return 'España';
  if (l == 'es-us') return 'Latinoamérica';
  if (l == 'es-mx') return 'México';
  if (l == 'es-419') return 'Latinoamérica';
  return locale;
}

/// Interpreta la lista de voces de flutter_tts (Android/iOS): solo español,
/// sin las voces que el motor anuncia pero no tiene descargadas, y ordenadas
/// de mejor a peor (España primero, más calidad, sin internet antes).
List<SpeechVoice> parseTtsVoices(List<dynamic> raw) {
  final out = <SpeechVoice>[];
  for (final v in raw) {
    if (v is! Map) continue;
    final name = v['name']?.toString() ?? '';
    final locale = v['locale']?.toString() ?? '';
    if (name.isEmpty || !_normLocale(locale).startsWith('es')) continue;
    final features = v['features']?.toString() ?? '';
    if (features.contains('notInstalled')) continue;
    final quality = _qualityRank[v['quality']?.toString()] ?? 0;
    final network = v['network_required']?.toString() == '1' ||
        name.contains('network');
    final parts = [
      _regionName(locale),
      if (quality >= 4) 'alta calidad',
      network ? 'requiere internet' : 'sin internet',
    ];
    out.add(SpeechVoice(
      name,
      locale,
      label: '${parts.join(' · ')} ($name)',
      quality: quality,
      network: network,
    ));
  }
  int score(SpeechVoice v) =>
      (_normLocale(v.locale) == 'es-es' ? 100 : 0) +
      v.quality * 10 +
      (v.network ? 0 : 1);
  out.sort((a, b) {
    final c = score(b).compareTo(score(a));
    return c != 0 ? c : a.name.compareTo(b.name);
  });
  return out;
}

/// La voz que se usa si el usuario no ha elegido ninguna: la mejor que
/// funcione sin internet (en ruta a menudo no hay cobertura).
SpeechVoice? bestVoice(List<SpeechVoice> voices) {
  for (final v in voices) {
    if (!v.network) return v;
  }
  return voices.isEmpty ? null : voices.first;
}

/// Voz del sistema (Android, iOS...). Cualquier fallo se ignora: la guía por
/// voz nunca debe tumbar la navegación.
class TtsSpeaker implements Speaker {
  final FlutterTts _tts = FlutterTts();
  bool _ready = false;
  double? _rate;
  String _voice = '';
  SpeechVoice? _auto;

  Future<void> _init() async {
    await _tts.setLanguage('es-ES');
    _auto = bestVoice(await voices());
    debugPrint('[voz] automática: ${_auto?.name ?? 'la del sistema'}');
    _ready = true;
  }

  @override
  Future<void> speak(
    String text, {
    double rate = 0.5,
    String voiceName = '',
    String voiceLocale = '',
  }) async {
    try {
      if (!_ready) await _init();
      if (_rate != rate) {
        await _tts.setSpeechRate(rate);
        _rate = rate;
      }
      final voiceKey = '$voiceName|$voiceLocale';
      if (_voice != voiceKey) {
        if (voiceName.isNotEmpty) {
          await _tts.setVoice({'name': voiceName, 'locale': voiceLocale});
        } else if (_auto != null) {
          await _tts.setVoice({'name': _auto!.name, 'locale': _auto!.locale});
        } else {
          await _tts.setLanguage('es-ES'); // vuelve a la voz por defecto
        }
        _voice = voiceKey;
      }
      await _tts.speak(text);
    } catch (e) {
      debugPrint('TTS no disponible: $e');
    }
  }

  @override
  Future<void> stop() async {
    try {
      await _tts.stop();
    } catch (_) {}
  }

  @override
  Future<List<SpeechVoice>> voices() async {
    try {
      final raw = await _tts.getVoices;
      if (raw is! List) return const [];
      final out = parseTtsVoices(raw);
      debugPrint('[voz] disponibles: ${out.map((v) => v.label).join(' | ')}');
      return out;
    } catch (e) {
      debugPrint('No se pudieron listar las voces: $e');
      return const [];
    }
  }
}

// --- Linux de escritorio: flutter_tts no tiene soporte, se usa espeak-ng ---

/// Palabras por minuto de espeak-ng para una velocidad [rate] (0,5 = 150).
int espeakWordsPerMinute(double rate) =>
    (150 * rate / 0.5).round().clamp(80, 450);

List<String> espeakArgs(String text, {required double rate, String voiceName = ''}) => [
      '-v',
      voiceName.isNotEmpty ? voiceName : 'es',
      '-s',
      espeakWordsPerMinute(rate).toString(),
      text,
    ];

/// Velocidad de speech-dispatcher (-100..100) para una velocidad [rate].
int spdSayRate(double rate) => ((rate - 0.5) * 200).round().clamp(-100, 100);

List<String> spdSayArgs(String text, {required double rate}) =>
    ['-l', 'es', '-r', spdSayRate(rate).toString(), text];

/// Interpreta la salida de `espeak-ng --voices=es`.
///
/// El identificador que acepta `-v` es la columna del archivo (`roa/es`); el
/// "nombre" de la lista (`Spanish_(Spain)`) no funciona. Las voces `mbrola`
/// (`mb/...`) no suenan si no está instalado el programa `mbrola`, así que se
/// descartan salvo que [includeMbrola] sea true.
List<SpeechVoice> parseEspeakVoices(String output, {bool includeMbrola = false}) {
  final out = <SpeechVoice>[];
  for (final line in output.split('\n')) {
    final cols = line.trim().split(RegExp(r'\s+'));
    // Cabecera: "Pty Language Age/Gender VoiceName File Other Languages".
    if (cols.length < 5 || int.tryParse(cols.first) == null) continue;
    final file = cols[4];
    if (file.startsWith('mb/') && !includeMbrola) continue;
    final label = cols[3].replaceAll('_', ' ');
    out.add(SpeechVoice(file, cols[1], label: label));
  }
  out.sort((a, b) => a.label.compareTo(b.label));
  return out;
}

/// Cada voz base más sus variantes de timbre (espeak-ng las admite con `+`).
List<SpeechVoice> withEspeakVariants(List<SpeechVoice> bases) => [
      for (final v in bases) ...[
        v,
        SpeechVoice('${v.name}+f3', v.locale, label: '${v.label} · femenina'),
        SpeechVoice('${v.name}+m7', v.locale, label: '${v.label} · grave'),
      ],
    ];

class CommandLineSpeaker implements Speaker {
  Process? _current;
  bool _searched = false;
  String? _espeak;
  String? _spd;

  void _find() {
    if (_searched) return;
    _searched = true;
    _espeak = findExecutable(['espeak-ng', 'espeak']);
    _spd = findExecutable(['spd-say']);
  }

  @override
  Future<void> speak(
    String text, {
    double rate = 0.5,
    String voiceName = '',
    String voiceLocale = '',
  }) async {
    _find();
    debugPrint('[voz] $text');
    try {
      if (_espeak != null) {
        await stop(); // los avisos no deben solaparse
        final p = await Process.start(
          _espeak!,
          espeakArgs(text, rate: rate, voiceName: voiceName),
        );
        _current = p;
        p.stdout.drain<void>();
        p.stderr.drain<void>();
      } else if (_spd != null) {
        final p = await Process.start(_spd!, spdSayArgs(text, rate: rate));
        p.stdout.drain<void>();
        p.stderr.drain<void>();
      } else {
        debugPrint('Sin motor de voz: instala espeak-ng para oír los avisos.');
      }
    } catch (e) {
      debugPrint('No se pudo hablar: $e');
    }
  }

  @override
  Future<void> stop() async {
    _current?.kill();
    _current = null;
    if (_espeak == null && _spd != null) {
      try {
        await Process.run(_spd!, ['-C']);
      } catch (_) {}
    }
  }

  @override
  Future<List<SpeechVoice>> voices() async {
    _find();
    if (_espeak == null) return const [];
    try {
      final r = await Process.run(_espeak!, ['--voices=es']);
      final hasMbrola = findExecutable(['mbrola']) != null;
      return withEspeakVariants(
        parseEspeakVoices(r.stdout.toString(), includeMbrola: hasMbrola),
      );
    } catch (_) {
      return const [];
    }
  }
}

final speakerProvider = Provider<Speaker>((ref) {
  return defaultTargetPlatform == TargetPlatform.linux
      ? CommandLineSpeaker()
      : TtsSpeaker();
});

/// Voces que se pueden elegir en Ajustes.
final voicesProvider = FutureProvider<List<SpeechVoice>>(
  (ref) => ref.read(speakerProvider).voices(),
);
