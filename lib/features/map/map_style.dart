import 'package:flutter/painting.dart';

/// Construye el estilo de MapLibre (JSON como `Map`) y los datos GeoJSON que
/// la app dibuja encima (ruta, puntos, tu posición). Funciones puras: no
/// dependen del mapa nativo y se prueban en tests.

const routeSource = 'route';
const walkedSource = 'walked';
const pointsSource = 'points';
const highlightSource = 'highlight';
const userSource = 'user';
const userArrowImage = 'user-arrow';

/// La flecha se dibuja a 96 px; esto la deja en ~35 px. Ajustar en el móvil.
const userArrowSize = 0.4;

/// Fuente de las etiquetas (Noto Sans Regular). El nombre debe coincidir con
/// la carpeta de `assets/glyphs/`; sin espacios para que la ruta `file://`
/// no necesite codificación.
const glyphFont = 'noto';
const _font = [glyphFont];

/// Rangos de caracteres incluidos (latín, puntuación y el símbolo ▲).
const glyphRanges = ['0-255', '256-511', '8192-8447', '9472-9727'];

String colorHex(Color c) {
  String h(double v) => (v * 255).round().clamp(0, 255).toRadixString(16).padLeft(2, '0');
  return '#${h(c.r)}${h(c.g)}${h(c.b)}';
}

Map<String, dynamic> emptyGeoJson() =>
    {'type': 'FeatureCollection', 'features': <dynamic>[]};

/// Archivos de una zona instalada (rutas absolutas en el móvil).
class MapRegionFiles {
  const MapRegionFiles({required this.id, required this.basePath, this.contoursPath});
  final String id;
  final String basePath;
  final String? contoursPath;
}

/// Estilo con todas las zonas de [regions] combinadas. Sin ninguna zona se
/// usa el mapa online de OpenStreetMap (solo con conexión).
/// Con [satellite] se usan ortofotos online (ver [satelliteSources]) y se
/// ignoran las zonas descargadas.
/// [glyphsDir]: carpeta con las fuentes de las etiquetas (sin barra final).
Map<String, dynamic> buildMapStyle({
  List<MapRegionFiles> regions = const [],
  String? glyphsDir,
  required Color routeColor,
  required Color highlightColor,
  bool satellite = false,
}) {
  final vector = regions.isNotEmpty && !satellite;
  final sources = <String, dynamic>{};
  final layers = <Map<String, dynamic>>[];

  if (vector) {
    for (final r in regions) {
      sources[baseSourceId(r.id)] = {
        'type': 'vector',
        'url': 'pmtiles://file://${r.basePath}',
        'attribution': '© OpenMapTiles © OpenStreetMap contributors',
      };
      if (r.contoursPath != null) {
        sources[contoursSourceId(r.id)] = {
          'type': 'vector',
          'url': 'pmtiles://file://${r.contoursPath}',
          'attribution': '© Copernicus DEM GLO-30',
        };
      }
    }
    final withContours = [for (final r in regions) if (r.contoursPath != null) r.id];
    final base = _baseLayers();
    layers.add(base.first); // fondo, una sola vez
    // Cada tipo de capa se dibuja para todas las zonas antes de pasar al
    // siguiente: así en las fronteras el orden (relieve < caminos <
    // etiquetas) es el mismo que con un solo mapa.
    for (final t in base.skip(1)) {
      if (t['id'] == 'boundary') {
        // Curvas encima del relieve y debajo de caminos y etiquetas.
        for (final c in _contourLayers()) {
          for (final id in withContours) {
            layers.add(_forRegion(c, id, contoursSourceId(id)));
          }
        }
      }
      for (final r in regions) {
        layers.add(_forRegion(t, r.id, baseSourceId(r.id)));
      }
    }
  } else if (satellite) {
    sources.addAll(satelliteSources());
    for (final id in satelliteSources().keys) {
      layers.add({'id': id, 'type': 'raster', 'source': id});
    }
  } else {
    sources['osm'] = {
      'type': 'raster',
      'tiles': ['https://tile.openstreetmap.org/{z}/{x}/{y}.png'],
      'tileSize': 256,
      'maxzoom': 19,
      'attribution': '© OpenStreetMap contributors',
    };
    layers.add({'id': 'osm', 'type': 'raster', 'source': 'osm'});
  }

  for (final id in [routeSource, walkedSource, pointsSource, highlightSource, userSource]) {
    sources[id] = {'type': 'geojson', 'data': emptyGeoJson()};
  }
  layers.addAll(_overlayLayers(colorHex(routeColor), colorHex(highlightColor)));

  return {
    'version': 8,
    if (vector && glyphsDir != null) 'glyphs': 'file://$glyphsDir/{fontstack}/{range}.pbf',
    'sources': sources,
    'layers': layers,
  };
}

const _ignfUrl = 'https://data.geopf.fr/wmts?SERVICE=WMTS&REQUEST=GetTile&VERSION=1.0.0'
    '&LAYER=ORTHOIMAGERY.ORTHOPHOTOS&STYLE=normal&TILEMATRIXSET=PM'
    '&TILEMATRIX={z}&TILEROW={y}&TILECOL={x}&FORMAT=image/jpeg';
const _ignfAttribution = '© IGN – Géoplateforme';

/// Ortofotos online, en orden de dibujo (la última queda encima):
/// - PNOA (IGN España): buena en España; fuera de España da una imagen de
///   relleno de baja resolución, así que va debajo de todo.
/// - IGN Francia: buena en Francia; en España no devuelve nada (se ve el
///   PNOA) pero en Andorra devuelve blanco, así que se parte en tres zonas
///   que dejan fuera el recuadro de Andorra.
Map<String, Map<String, dynamic>> satelliteSources() {
  Map<String, dynamic> ignf(List<double> bounds) => {
        'type': 'raster',
        'tiles': [_ignfUrl],
        'tileSize': 256,
        'maxzoom': 19,
        'bounds': bounds,
        'attribution': _ignfAttribution,
      };
  return {
    'sat-pnoa': {
      'type': 'raster',
      'tiles': [
        'https://www.ign.es/wmts/pnoa-ma?request=GetTile&service=WMTS&version=1.0.0'
            '&layer=OI.OrthoimageCoverage&style=default&format=image/jpeg'
            '&tilematrixset=GoogleMapsCompatible&tilematrix={z}&tilerow={y}&tilecol={x}',
      ],
      'tileSize': 256,
      'maxzoom': 19,
      'attribution': 'PNOA cedido por © Instituto Geográfico Nacional',
    },
    // Oeste de Andorra, este de Andorra y norte de Andorra.
    'sat-ignf-w': ignf([-5.5, 41.0, 1.40, 51.5]),
    'sat-ignf-e': ignf([1.79, 41.0, 9.9, 51.5]),
    'sat-ignf-n': ignf([1.40, 42.66, 1.79, 51.5]),
  };
}

String baseSourceId(String region) => 'omt-$region';
String contoursSourceId(String region) => 'curvas-$region';

Map<String, dynamic> _forRegion(Map<String, dynamic> template, String region, String source) =>
    {...template, 'id': '${template['id']}-$region', 'source': source};

List<Map<String, dynamic>> _contourLayers() {
  final master = ['==', ['get', 'nivel'], '100'];
  return [
    {
      'id': 'contour',
      'type': 'line',
      'source-layer': 'contour',
      'paint': {
        'line-color': '#b08257',
        'line-width': ['case', master, 1.1, 0.5],
        'line-opacity': ['case', master, 0.9, 0.6],
      },
    },
    {
      'id': 'contour-label',
      'type': 'symbol',
      'source-layer': 'contour',
      'minzoom': 13,
      'filter': master,
      'layout': {
        'symbol-placement': 'line',
        'text-field': ['to-string', ['get', 'ele']],
        'text-font': _font,
        'text-size': 10,
      },
      'paint': {
        'text-color': '#8a5a2b',
        'text-halo-color': '#ffffff',
        'text-halo-width': 1.2,
      },
    },
  ];
}

/// Mapa base para el esquema OpenMapTiles, pensado para montaña.
List<Map<String, dynamic>> _baseLayers() {
  const notRoad = ['!', ['in', ['get', 'class'], ['literal', ['path', 'track', 'rail', 'transit']]]];
  const halo = {'text-color': '#222222', 'text-halo-color': '#ffffff', 'text-halo-width': 1.5};
  return [
    {'id': 'bg', 'type': 'background', 'paint': {'background-color': '#f2efe9'}},
    {
      'id': 'landcover', 'type': 'fill', 'source': 'omt', 'source-layer': 'landcover',
      'paint': {
        'fill-color': ['match', ['get', 'class'], 'wood', '#add19e', 'grass', '#cdebb0',
          'farmland', '#eef0d5', 'rock', '#e0dcd5', 'wetland', '#d6e9e1', 'sand', '#f5e9c6',
          'ice', '#ffffff', '#dde8cc'],
        'fill-opacity': 0.8,
      },
    },
    {
      'id': 'landuse', 'type': 'fill', 'source': 'omt', 'source-layer': 'landuse',
      'paint': {
        'fill-color': ['match', ['get', 'class'], 'residential', '#e8e2da',
          'industrial', '#ebdbe8', '#e9e5dc'],
        'fill-opacity': 0.7,
      },
    },
    {
      'id': 'park', 'type': 'fill', 'source': 'omt', 'source-layer': 'park',
      'paint': {'fill-color': '#c8facc', 'fill-opacity': 0.35, 'fill-outline-color': '#6aa86a'},
    },
    {'id': 'water', 'type': 'fill', 'source': 'omt', 'source-layer': 'water',
      'paint': {'fill-color': '#aad3df'}},
    {
      'id': 'waterway', 'type': 'line', 'source': 'omt', 'source-layer': 'waterway',
      'paint': {
        'line-color': '#aad3df',
        'line-width': ['interpolate', ['linear'], ['zoom'], 8, 0.5, 14, 2],
      },
    },
    {
      'id': 'building', 'type': 'fill', 'source': 'omt', 'source-layer': 'building',
      'minzoom': 13, 'paint': {'fill-color': '#d9d0c9', 'fill-outline-color': '#bfb3a8'},
    },
    {
      'id': 'boundary', 'type': 'line', 'source': 'omt', 'source-layer': 'boundary',
      'filter': ['<=', ['get', 'admin_level'], 4],
      'paint': {'line-color': '#9e6a9e', 'line-width': 1.2, 'line-dasharray': [3, 2]},
    },
    {
      'id': 'path', 'type': 'line', 'source': 'omt', 'source-layer': 'transportation',
      'filter': ['in', ['get', 'class'], ['literal', ['path', 'track']]], 'minzoom': 11,
      'paint': {
        'line-color': ['match', ['get', 'class'], 'track', '#996600', '#d4402a'],
        'line-width': ['interpolate', ['linear'], ['zoom'], 11, 0.6, 16, 2],
        'line-dasharray': [2, 1.5],
      },
    },
    {
      'id': 'road-casing', 'type': 'line', 'source': 'omt', 'source-layer': 'transportation',
      'filter': notRoad, 'layout': {'line-cap': 'round', 'line-join': 'round'},
      'paint': {
        'line-color': '#b0a69c',
        'line-width': ['interpolate', ['linear'], ['zoom'], 8, 1, 16, 9],
      },
    },
    {
      'id': 'road', 'type': 'line', 'source': 'omt', 'source-layer': 'transportation',
      'filter': notRoad, 'layout': {'line-cap': 'round', 'line-join': 'round'},
      'paint': {
        'line-color': ['match', ['get', 'class'], ['motorway', 'trunk'], '#e892a2',
          'primary', '#fcd6a4', 'secondary', '#f7fabf', '#ffffff'],
        'line-width': ['interpolate', ['linear'], ['zoom'], 8, 0.5, 16, 7],
      },
    },
    {
      'id': 'rail', 'type': 'line', 'source': 'omt', 'source-layer': 'transportation',
      'filter': ['==', ['get', 'class'], 'rail'],
      'paint': {'line-color': '#707070', 'line-width': 1},
    },
    {
      'id': 'road-name', 'type': 'symbol', 'source': 'omt',
      'source-layer': 'transportation_name', 'minzoom': 13,
      'layout': {
        'symbol-placement': 'line', 'text-field': ['get', 'name'],
        'text-font': _font, 'text-size': 11,
      },
      'paint': {'text-color': '#333333', 'text-halo-color': '#ffffff', 'text-halo-width': 1.2},
    },
    {
      'id': 'peak', 'type': 'symbol', 'source': 'omt', 'source-layer': 'mountain_peak',
      'minzoom': 10,
      'layout': {
        'text-field': ['concat', '▲ ', ['get', 'name'], '\n', ['to-string', ['get', 'ele']], ' m'],
        'text-font': _font, 'text-size': 11, 'text-anchor': 'top',
      },
      'paint': {'text-color': '#6b4a2b', 'text-halo-color': '#ffffff', 'text-halo-width': 1.2},
    },
    {
      'id': 'place', 'type': 'symbol', 'source': 'omt', 'source-layer': 'place',
      'layout': {
        'text-field': ['get', 'name'], 'text-font': _font,
        'text-size': ['match', ['get', 'class'], 'city', 16, 'town', 14, 'village', 12, 11],
      },
      'paint': halo,
    },
  ];
}

/// Lo que dibuja la app encima del mapa.
List<Map<String, dynamic>> _overlayLayers(String routeColor, String highlightColor) {
  Map<String, dynamic> line(String id, String source, String color, double width) => {
        'id': id,
        'type': 'line',
        'source': source,
        'layout': {'line-cap': 'round', 'line-join': 'round'},
        'paint': {'line-color': color, 'line-width': width},
      };
  return [
    line('route-casing', routeSource, '#ffffff', 9),
    line('route', routeSource, routeColor, 5),
    line('walked-casing', walkedSource, '#ffffff', 9),
    line('walked', walkedSource, '#757575', 5),
    {
      'id': 'points', 'type': 'circle', 'source': pointsSource,
      'paint': {
        'circle-radius': 8,
        'circle-color': ['match', ['get', 'kind'], 'start', '#2e7d32', 'end', '#c62828', '#fb8c00'],
        'circle-stroke-color': '#ffffff',
        'circle-stroke-width': 3,
      },
    },
    {
      'id': 'highlight', 'type': 'circle', 'source': highlightSource,
      'paint': {
        'circle-radius': 8,
        'circle-color': highlightColor,
        'circle-stroke-color': '#ffffff',
        'circle-stroke-width': 3,
      },
    },
    {
      'id': 'user-halo', 'type': 'circle', 'source': userSource,
      'paint': {'circle-radius': 22, 'circle-color': '#1976d2', 'circle-opacity': 0.18},
    },
    // Con rumbo: la flecha apunta a tu dirección real (gira con el mapa).
    {
      'id': 'user-arrow', 'type': 'symbol', 'source': userSource,
      'filter': ['has', 'heading'],
      'layout': {
        'icon-image': userArrowImage,
        'icon-size': userArrowSize,
        'icon-rotate': ['get', 'heading'],
        'icon-rotation-alignment': 'map',
        'icon-allow-overlap': true,
        'icon-ignore-placement': true,
      },
    },
    // Sin rumbo (parado): la flecha mira hacia arriba de la pantalla.
    {
      'id': 'user-arrow-up', 'type': 'symbol', 'source': userSource,
      'filter': ['!', ['has', 'heading']],
      'layout': {
        'icon-image': userArrowImage,
        'icon-size': userArrowSize,
        'icon-rotation-alignment': 'viewport',
        'icon-allow-overlap': true,
        'icon-ignore-placement': true,
      },
    },
  ];
}

// --- Datos GeoJSON (coordenadas [lon, lat]) ---

Map<String, dynamic> lineGeoJson(List<(double lat, double lon)> pts) {
  if (pts.length < 2) return emptyGeoJson();
  return {
    'type': 'FeatureCollection',
    'features': [
      {
        'type': 'Feature',
        'properties': <String, dynamic>{},
        'geometry': {
          'type': 'LineString',
          'coordinates': [for (final p in pts) [p.$2, p.$1]],
        },
      },
    ],
  };
}

Map<String, dynamic> _point(double lat, double lon, Map<String, dynamic> props) => {
      'type': 'Feature',
      'properties': props,
      'geometry': {'type': 'Point', 'coordinates': [lon, lat]},
    };

/// Inicio, fin y waypoints del GPX.
Map<String, dynamic> pointsGeoJson({
  required (double lat, double lon) start,
  required (double lat, double lon) end,
  List<(double lat, double lon, String? name)> waypoints = const [],
}) =>
    {
      'type': 'FeatureCollection',
      'features': [
        for (final w in waypoints) _point(w.$1, w.$2, {'kind': 'waypoint', 'name': w.$3 ?? ''}),
        _point(start.$1, start.$2, {'kind': 'start'}),
        _point(end.$1, end.$2, {'kind': 'end'}),
      ],
    };

Map<String, dynamic> singlePointGeoJson(double? lat, double? lon, [Map<String, dynamic>? props]) {
  if (lat == null || lon == null) return emptyGeoJson();
  return {
    'type': 'FeatureCollection',
    'features': [_point(lat, lon, props ?? <String, dynamic>{})],
  };
}

/// Tu posición; con [headingDeg] la flecha apunta a tu rumbo.
Map<String, dynamic> userGeoJson(double? lat, double? lon, double? headingDeg) =>
    singlePointGeoJson(lat, lon, {'heading': ?headingDeg});
