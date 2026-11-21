import 'package:xml/xml.dart';

import 'route_models.dart';

class GpxFormatException implements Exception {
  GpxFormatException(this.message);
  final String message;
  @override
  String toString() => 'GpxFormatException: $message';
}

/// Parsea un GPX. Usa los `trkpt`; si no hay, cae a los `rtept` (rutas).
GpxRoute parseGpx(String source, {String fallbackName = 'Ruta'}) {
  final XmlDocument doc;
  try {
    // Algunos exportadores añaden BOM o espacios antes de la cabecera XML.
    doc = XmlDocument.parse(source.replaceFirst(RegExp(r'^[﻿\s]+'), ''));
  } on XmlException catch (e) {
    throw GpxFormatException('XML no válido: ${e.message}');
  }

  final root = doc.rootElement;
  if (root.name.local != 'gpx') {
    throw GpxFormatException('El archivo no es un GPX.');
  }

  var points = _readPoints(root.findAllElements('trkpt'));
  if (points.isEmpty) {
    points = _readPoints(root.findAllElements('rtept'));
  }
  if (points.isEmpty) {
    throw GpxFormatException('El GPX no contiene puntos de track ni de ruta.');
  }

  final waypoints = <Waypoint>[];
  for (final w in root.findAllElements('wpt')) {
    final lat = double.tryParse(w.getAttribute('lat') ?? '');
    final lon = double.tryParse(w.getAttribute('lon') ?? '');
    if (lat == null || lon == null) continue;
    waypoints.add(Waypoint(
      lat,
      lon,
      name: _text(w, 'name'),
      ele: double.tryParse(_text(w, 'ele') ?? ''),
    ));
  }

  final name = _text(root.findAllElements('trk').firstOrNull, 'name') ??
      _text(root.findAllElements('rte').firstOrNull, 'name') ??
      _text(root.findElements('metadata').firstOrNull, 'name') ??
      fallbackName;

  return GpxRoute(name: name, points: points, waypoints: waypoints);
}

List<TrackPoint> _readPoints(Iterable<XmlElement> elements) {
  final out = <TrackPoint>[];
  for (final e in elements) {
    final lat = double.tryParse(e.getAttribute('lat') ?? '');
    final lon = double.tryParse(e.getAttribute('lon') ?? '');
    if (lat == null || lon == null) continue;
    out.add(TrackPoint(
      lat,
      lon,
      ele: double.tryParse(_text(e, 'ele') ?? ''),
      time: DateTime.tryParse(_text(e, 'time') ?? ''),
    ));
  }
  return out;
}

String? _text(XmlElement? parent, String child) {
  final t = parent?.findElements(child).firstOrNull?.innerText.trim();
  return (t == null || t.isEmpty) ? null : t;
}
