import '../../core/geo.dart';
import '../routes/route_models.dart';

enum TurnSide { left, right }

class Turn {
  const Turn({
    required this.alongM,
    required this.angleDeg,
    required this.lat,
    required this.lon,
  });

  /// Metros desde el inicio de la ruta hasta el giro.
  final double alongM;

  /// Cambio de rumbo con signo: positivo = derecha, negativo = izquierda.
  final double angleDeg;
  final double lat;
  final double lon;

  TurnSide get side => angleDeg >= 0 ? TurnSide.right : TurnSide.left;

  /// Frase para la guía por voz, p. ej. "gira a la derecha".
  String get phrase {
    final lado = side == TurnSide.right ? 'derecha' : 'izquierda';
    final a = angleDeg.abs();
    if (a >= 130) return 'giro muy cerrado a la $lado';
    if (a >= 75) return 'gira a la $lado';
    return 'gira ligeramente a la $lado';
  }
}

class _Sample {
  const _Sample(this.along, this.lat, this.lon);
  final double along;
  final double lat;
  final double lon;
}

/// Deduce los giros a partir de la geometría del track (no hay motor de rutas).
///
/// Remuestrea la ruta cada [sampleM] metros y compara el rumbo de los
/// [windowM] metros anteriores con el de los siguientes. Las curvas largas y
/// suaves no cuentan: solo cambios de dirección de al menos [minAngleDeg]
/// concentrados en pocos metros.
List<Turn> detectTurns(
  List<TrackPoint> points,
  List<double> cumulativeM, {
  double sampleM = 10,
  double windowM = 30,
  double minAngleDeg = 35,
}) {
  if (points.length < 3) return const [];

  final samples = _resample(points, cumulativeM, sampleM);
  final k = (windowM / sampleM).round();
  if (samples.length < 2 * k + 1) return const [];

  final angles = List<double>.filled(samples.length, 0);
  for (var i = k; i < samples.length - k; i++) {
    final inB = bearing(
        samples[i - k].lat, samples[i - k].lon, samples[i].lat, samples[i].lon);
    final outB = bearing(
        samples[i].lat, samples[i].lon, samples[i + k].lat, samples[i + k].lon);
    angles[i] = bearingDelta(inB, outB);
  }

  // Agrupa muestras consecutivas por encima del umbral y se queda con la
  // de mayor ángulo de cada grupo: un solo aviso por giro.
  final turns = <Turn>[];
  var i = k;
  while (i < samples.length - k) {
    if (angles[i].abs() < minAngleDeg) {
      i++;
      continue;
    }
    var best = i;
    var j = i;
    while (j < samples.length - k && angles[j].abs() >= minAngleDeg) {
      if (angles[j].abs() > angles[best].abs()) best = j;
      j++;
    }
    turns.add(Turn(
      alongM: samples[best].along,
      angleDeg: angles[best],
      lat: samples[best].lat,
      lon: samples[best].lon,
    ));
    i = j;
  }
  return turns;
}

List<_Sample> _resample(
  List<TrackPoint> points,
  List<double> cum,
  double stepM,
) {
  final out = <_Sample>[
    _Sample(0, points.first.lat, points.first.lon),
  ];
  final total = cum.last;
  var seg = 0;
  for (var d = stepM; d < total; d += stepM) {
    while (seg < points.length - 2 && cum[seg + 1] < d) {
      seg++;
    }
    final segLen = cum[seg + 1] - cum[seg];
    final t = segLen == 0 ? 0.0 : ((d - cum[seg]) / segLen).clamp(0.0, 1.0);
    out.add(_Sample(
      d,
      points[seg].lat + t * (points[seg + 1].lat - points[seg].lat),
      points[seg].lon + t * (points[seg + 1].lon - points[seg].lon),
    ));
  }
  out.add(_Sample(total, points.last.lat, points.last.lon));
  return out;
}
