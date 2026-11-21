enum OffRouteEvent {
  /// Sin cambios.
  none,

  /// Acabas de salirte de la ruta.
  left,

  /// Sigues fuera y toca repetir el aviso.
  stillOff,

  /// Has vuelto a la ruta.
  returned,
}

/// Decide cuándo avisar de que te has salido de la ruta.
///
/// - Exige varias lecturas seguidas fuera del umbral (evita falsos avisos por
///   un salto puntual del GPS).
/// - Usa histéresis al volver: hay que acercarse más que el umbral para dar
///   por terminado el desvío (evita avisos intermitentes en el límite).
/// - Repite el aviso cada [repeatEvery] mientras sigues fuera.
class OffRouteMonitor {
  OffRouteMonitor({
    this.thresholdM = 30,
    this.consecutiveFixes = 3,
    this.repeatEvery = const Duration(seconds: 20),
    this.returnFactor = 0.7,
  });

  final double thresholdM;
  final int consecutiveFixes;
  final Duration repeatEvery;
  final double returnFactor;

  bool _off = false;
  int _count = 0;
  DateTime? _lastAlert;

  bool get isOff => _off;

  OffRouteEvent update(double distanceToRouteM, DateTime now) {
    if (!_off) {
      _count = distanceToRouteM > thresholdM ? _count + 1 : 0;
      if (_count >= consecutiveFixes) {
        _off = true;
        _lastAlert = now;
        return OffRouteEvent.left;
      }
      return OffRouteEvent.none;
    }

    if (distanceToRouteM <= thresholdM * returnFactor) {
      _off = false;
      _count = 0;
      _lastAlert = null;
      return OffRouteEvent.returned;
    }
    if (now.difference(_lastAlert!) >= repeatEvery) {
      _lastAlert = now;
      return OffRouteEvent.stillOff;
    }
    return OffRouteEvent.none;
  }

  void reset() {
    _off = false;
    _count = 0;
    _lastAlert = null;
  }
}
