import 'package:flutter_test/flutter_test.dart';
import 'package:gpx_app/features/navigation/speaker.dart';

void main() {
  // Formato real que devuelve flutter_tts en Android.
  final raw = [
    {'name': 'es-es-x-eed-local', 'locale': 'es-ES', 'quality': 'normal', 'network_required': '0', 'features': ''},
    {'name': 'es-es-x-eee-local', 'locale': 'es-ES', 'quality': 'high', 'network_required': '0', 'features': ''},
    {'name': 'es-es-x-eee-network', 'locale': 'es-ES', 'quality': 'very high', 'network_required': '1', 'features': ''},
    {'name': 'es-us-x-esd-local', 'locale': 'es-US', 'quality': 'very high', 'network_required': '0', 'features': ''},
    {'name': 'es-es-x-eef-local', 'locale': 'es-ES', 'quality': 'very high', 'network_required': '0', 'features': 'notInstalled'},
    {'name': 'en-us-x-sfg-local', 'locale': 'en-US', 'quality': 'very high', 'network_required': '0', 'features': ''},
  ];

  test('solo español instalado, ordenado de mejor a peor', () {
    final voices = parseTtsVoices(raw);
    expect(voices.map((v) => v.name), [
      'es-es-x-eee-network',
      'es-es-x-eee-local',
      'es-es-x-eed-local',
      'es-us-x-esd-local',
    ]);
    expect(voices[1].label, 'España · alta calidad · sin internet (es-es-x-eee-local)');
  });

  test('la voz automática es la mejor que funciona sin internet', () {
    expect(bestVoice(parseTtsVoices(raw))!.name, 'es-es-x-eee-local');
  });

  test('sin voces no hay voz automática', () {
    expect(bestVoice(const []), isNull);
  });
}
