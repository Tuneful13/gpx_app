String formatDistance(double meters) {
  if (meters < 1000) return '${meters.round()} m';
  return '${(meters / 1000).toStringAsFixed(2)} km';
}

String formatElevation(double meters) => '${meters.round()} m';

/// Distancia pensada para decirse en voz alta: "80 metros", "1,5 kilómetros".
String spokenDistance(double meters) {
  if (meters < 1000) {
    final step = meters < 50 ? 5 : 10;
    final rounded = ((meters / step).round() * step).clamp(step, 999);
    return '$rounded metros';
  }
  final km = (meters / 1000);
  final text = km.toStringAsFixed(1).replaceAll('.', ',');
  return text == '1,0' ? '1 kilómetro' : '$text kilómetros';
}

String formatSpeedKmh(double metersPerSecond) =>
    '${(metersPerSecond * 3.6).toStringAsFixed(1)} km/h';

/// Cronómetro: "05:32" o "1:05:32".
String formatClock(Duration d) {
  final h = d.inHours;
  final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
  final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  return h == 0 ? '$m:$s' : '$h:$m:$s';
}

String formatDuration(Duration d) {
  final h = d.inHours;
  final m = d.inMinutes.remainder(60);
  if (h == 0) return '$m min';
  return '$h h ${m.toString().padLeft(2, '0')} min';
}
