import 'package:flutter/foundation.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

/// Mantiene la pantalla encendida mientras se navega. Si la plataforma no lo
/// soporta (o en tests) se ignora el error.
Future<void> keepScreenOn(bool on) async {
  try {
    await WakelockPlus.toggle(enable: on);
  } catch (e) {
    debugPrint('No se pudo cambiar el bloqueo de pantalla: $e');
  }
}
