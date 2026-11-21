import 'package:gpx_app/features/navigation/alert_player.dart';
import 'package:gpx_app/features/navigation/speaker.dart';
import 'package:gpx_app/features/settings/alert_sound.dart';

class FakeSpeaker implements Speaker {
  FakeSpeaker({this.availableVoices = const []});

  final List<SpeechVoice> availableVoices;
  final said = <String>[];
  int stops = 0;
  double? lastRate;
  String? lastVoiceName;
  String? lastVoiceLocale;

  @override
  Future<void> speak(
    String text, {
    double rate = 0.5,
    String voiceName = '',
    String voiceLocale = '',
  }) async {
    said.add(text);
    lastRate = rate;
    lastVoiceName = voiceName;
    lastVoiceLocale = voiceLocale;
  }

  @override
  Future<void> stop() async => stops++;

  @override
  Future<List<SpeechVoice>> voices() async => availableVoices;
}

class FakeAlert implements AlertPlayer {
  /// Sonidos reproducidos, en orden.
  final sounds = <AlertSound>[];
  int vibrations = 0;

  /// Número de veces que ha sonado la alarma.
  int get count => sounds.length;

  @override
  Future<void> sound(AlertSound sound) async => sounds.add(sound);

  @override
  Future<void> vibrate() async => vibrations++;
}
