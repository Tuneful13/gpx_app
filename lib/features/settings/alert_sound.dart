/// Sonidos disponibles para el aviso de salida de ruta.
enum AlertSound {
  alarm('alarm', 'Alarma', 'assets/sounds/off_route.wav'),
  beep('beep', 'Pitido', 'assets/sounds/beep.wav'),
  chime('chime', 'Campana', 'assets/sounds/chime.wav');

  const AlertSound(this.id, this.label, this.asset);

  /// Identificador estable que se guarda en disco.
  final String id;
  final String label;
  final String asset;

  /// Un id desconocido (otra versión de la app, dato corrupto) cae en [alarm].
  static AlertSound fromId(Object? id) =>
      values.firstWhere((s) => s.id == id, orElse: () => alarm);
}
