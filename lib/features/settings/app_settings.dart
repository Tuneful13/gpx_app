import 'alert_sound.dart';

/// Preferencias del usuario. Inmutable; los valores siempre quedan dentro de
/// sus límites, aunque lo guardado en disco esté corrupto o sea de otra versión.
class AppSettings {
  const AppSettings({
    this.keepScreenOn = true,
    this.offRouteThresholdM = defaultOffRouteThresholdM,
    this.offRouteRepeatSeconds = defaultOffRouteRepeatSeconds,
    this.alertSoundEnabled = true,
    this.alertSound = AlertSound.alarm,
    this.alertVibrationEnabled = true,
    this.voiceEnabled = true,
    this.voiceRate = defaultVoiceRate,
    this.voiceName = '',
    this.voiceLocale = '',
    this.satellite = false,
  });

  // Valores por defecto y límites (los usa también la pantalla de ajustes).
  static const defaultOffRouteThresholdM = 30.0;
  static const minOffRouteThresholdM = 10.0;
  static const maxOffRouteThresholdM = 100.0;

  static const defaultOffRouteRepeatSeconds = 20;
  static const minOffRouteRepeatSeconds = 10;
  static const maxOffRouteRepeatSeconds = 60;

  /// 0,5 es la velocidad normal de la voz del sistema.
  static const defaultVoiceRate = 0.5;
  static const minVoiceRate = 0.25;
  static const maxVoiceRate = 1.0;

  /// Mantener la pantalla encendida mientras navegas.
  final bool keepScreenOn;

  /// Distancia a la ruta a partir de la cual se considera que te has salido.
  final double offRouteThresholdM;

  /// Cada cuántos segundos se repite el aviso mientras sigues fuera.
  final int offRouteRepeatSeconds;

  /// Sonido del aviso de desvío.
  final bool alertSoundEnabled;
  final AlertSound alertSound;

  /// Vibración del aviso de desvío.
  final bool alertVibrationEnabled;

  /// Voz activada al empezar una ruta.
  final bool voiceEnabled;

  /// Velocidad de la voz (0,5 = normal).
  final double voiceRate;

  /// Voz concreta del sistema; vacío = la predeterminada.
  final String voiceName;
  final String voiceLocale;

  /// Mapa en vista satélite (ortofotos online) en vez del mapa normal.
  final bool satellite;

  AppSettings copyWith({
    bool? keepScreenOn,
    double? offRouteThresholdM,
    int? offRouteRepeatSeconds,
    bool? alertSoundEnabled,
    AlertSound? alertSound,
    bool? alertVibrationEnabled,
    bool? voiceEnabled,
    double? voiceRate,
    String? voiceName,
    String? voiceLocale,
    bool? satellite,
  }) {
    return AppSettings(
      keepScreenOn: keepScreenOn ?? this.keepScreenOn,
      offRouteThresholdM: _clamp(
        offRouteThresholdM ?? this.offRouteThresholdM,
        minOffRouteThresholdM,
        maxOffRouteThresholdM,
      ),
      offRouteRepeatSeconds: (offRouteRepeatSeconds ?? this.offRouteRepeatSeconds)
          .clamp(minOffRouteRepeatSeconds, maxOffRouteRepeatSeconds),
      alertSoundEnabled: alertSoundEnabled ?? this.alertSoundEnabled,
      alertSound: alertSound ?? this.alertSound,
      alertVibrationEnabled: alertVibrationEnabled ?? this.alertVibrationEnabled,
      voiceEnabled: voiceEnabled ?? this.voiceEnabled,
      voiceRate: _clamp(
        voiceRate ?? this.voiceRate,
        minVoiceRate,
        maxVoiceRate,
      ),
      voiceName: voiceName ?? this.voiceName,
      voiceLocale: voiceLocale ?? this.voiceLocale,
      satellite: satellite ?? this.satellite,
    );
  }

  Map<String, Object> toMap() => {
        'keepScreenOn': keepScreenOn,
        'offRouteThresholdM': offRouteThresholdM,
        'offRouteRepeatSeconds': offRouteRepeatSeconds,
        'alertSoundEnabled': alertSoundEnabled,
        'alertSound': alertSound.id,
        'alertVibrationEnabled': alertVibrationEnabled,
        'voiceEnabled': voiceEnabled,
        'voiceRate': voiceRate,
        'voiceName': voiceName,
        'voiceLocale': voiceLocale,
        'satellite': satellite,
      };

  /// Lee ajustes guardados. Lo que falte o tenga un tipo inesperado vuelve a
  /// su valor por defecto; lo que se salga de rango se ajusta al límite.
  factory AppSettings.fromMap(Map<String, Object?> map) {
    return const AppSettings().copyWith(
      keepScreenOn: _bool(map['keepScreenOn']),
      offRouteThresholdM: _num(map['offRouteThresholdM']),
      offRouteRepeatSeconds: _num(map['offRouteRepeatSeconds'])?.round(),
      alertSoundEnabled: _bool(map['alertSoundEnabled']),
      alertSound: AlertSound.fromId(map['alertSound']),
      alertVibrationEnabled: _bool(map['alertVibrationEnabled']),
      voiceEnabled: _bool(map['voiceEnabled']),
      voiceRate: _num(map['voiceRate']),
      voiceName: _str(map['voiceName']),
      voiceLocale: _str(map['voiceLocale']),
      satellite: _bool(map['satellite']),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is AppSettings &&
      other.keepScreenOn == keepScreenOn &&
      other.offRouteThresholdM == offRouteThresholdM &&
      other.offRouteRepeatSeconds == offRouteRepeatSeconds &&
      other.alertSoundEnabled == alertSoundEnabled &&
      other.alertSound == alertSound &&
      other.alertVibrationEnabled == alertVibrationEnabled &&
      other.voiceEnabled == voiceEnabled &&
      other.voiceRate == voiceRate &&
      other.voiceName == voiceName &&
      other.voiceLocale == voiceLocale &&
      other.satellite == satellite;

  @override
  int get hashCode => Object.hash(
        keepScreenOn,
        offRouteThresholdM,
        offRouteRepeatSeconds,
        alertSoundEnabled,
        alertSound,
        alertVibrationEnabled,
        voiceEnabled,
        voiceRate,
        voiceName,
        voiceLocale,
        satellite,
      );

  static double _clamp(double v, double min, double max) =>
      v.isNaN ? min : v.clamp(min, max).toDouble();

  static double? _num(Object? v) {
    if (v is num && v.isFinite) return v.toDouble();
    return null;
  }

  static bool? _bool(Object? v) => v is bool ? v : null;

  static String? _str(Object? v) => v is String ? v : null;
}
