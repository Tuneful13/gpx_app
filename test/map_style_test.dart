import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gpx_app/features/map/map_style.dart';

List<String> _layerIds(Map<String, dynamic> style) =>
    [for (final l in style['layers'] as List) (l as Map)['id'] as String];

Map<String, dynamic> _style(List<MapRegionFiles> regions, {String? glyphs}) => buildMapStyle(
      regions: regions,
      glyphsDir: glyphs,
      routeColor: const Color(0xFF2E7D32),
      highlightColor: Colors.purple,
    );

const _navarra = MapRegionFiles(
  id: 'navarra',
  basePath: '/maps/regions/navarra/base.pmtiles',
  contoursPath: '/maps/regions/navarra/curvas.pmtiles',
);
const _rioja = MapRegionFiles(id: 'la-rioja', basePath: '/maps/regions/la-rioja/base.pmtiles');

void main() {
  group('estilo del mapa', () {
    test('sin zonas descargadas usa el mapa online de OpenStreetMap', () {
      final s = _style(const []);
      final sources = s['sources'] as Map;
      expect(sources.containsKey('osm'), isTrue);
      expect(s.containsKey('glyphs'), isFalse);
      expect(_layerIds(s), containsAll(['osm', 'route', 'user-arrow']));
    });

    test('cada zona tiene sus fuentes .pmtiles locales', () {
      final s = _style(const [_navarra, _rioja], glyphs: '/maps/glyphs');
      final sources = s['sources'] as Map;
      expect((sources['omt-navarra'] as Map)['url'],
          'pmtiles://file:///maps/regions/navarra/base.pmtiles');
      expect((sources['curvas-navarra'] as Map)['url'],
          'pmtiles://file:///maps/regions/navarra/curvas.pmtiles');
      expect(sources.containsKey('omt-la-rioja'), isTrue);
      expect(sources.containsKey('curvas-la-rioja'), isFalse, reason: 'La Rioja sin curvas');
      expect(sources.containsKey('osm'), isFalse);
      expect(s['glyphs'], 'file:///maps/glyphs/{fontstack}/{range}.pbf');
    });

    test('los identificadores de capa no se repiten', () {
      final ids = _layerIds(_style(const [_navarra, _rioja]));
      expect(ids.toSet().length, ids.length);
    });

    test('cada tipo de capa va junto para todas las zonas (orden correcto en fronteras)', () {
      final ids = _layerIds(_style(const [_navarra, _rioja]));
      // Todo el relieve de ambas zonas antes que cualquier camino.
      final lastLandcover = [ids.indexOf('landcover-navarra'), ids.indexOf('landcover-la-rioja')]
          .reduce((a, b) => a > b ? a : b);
      final firstPath = [ids.indexOf('path-navarra'), ids.indexOf('path-la-rioja')]
          .reduce((a, b) => a < b ? a : b);
      expect(lastLandcover, lessThan(firstPath));
      // Las etiquetas de pueblos de ambas zonas, después de todas las carreteras.
      expect(ids.indexOf('road-la-rioja'), lessThan(ids.indexOf('place-navarra')));
    });

    test('las curvas van encima del relieve y debajo de caminos y ruta', () {
      final ids = _layerIds(_style(const [_navarra]));
      expect(ids.indexOf('contour-navarra'), greaterThan(ids.indexOf('landcover-navarra')));
      expect(ids.indexOf('contour-navarra'), lessThan(ids.indexOf('path-navarra')));
      expect(ids.indexOf('contour-navarra'), lessThan(ids.indexOf('route')));
      expect(ids, contains('contour-label-navarra'));
    });

    test('el fondo se dibuja una sola vez', () {
      final ids = _layerIds(_style(const [_navarra, _rioja]));
      expect(ids.where((id) => id.startsWith('bg')).length, 1);
    });

    test('la ruta y tu posición se dibujan encima de todo el mapa', () {
      final ids = _layerIds(_style(const [_navarra]));
      expect(ids.indexOf('route'), greaterThan(ids.indexOf('place-navarra')));
      expect(ids.last, 'user-arrow-up');
    });

    test('el estilo se puede serializar a JSON', () {
      expect(jsonEncode(_style(const [_navarra, _rioja], glyphs: '/g')), startsWith('{'));
    });

    test('los colores se pasan en hexadecimal', () {
      expect(colorHex(const Color(0xFF2E7D32)), '#2e7d32');
    });
  });

  group('datos GeoJSON', () {
    test('una línea con menos de dos puntos queda vacía', () {
      expect((lineGeoJson([(43.0, -2.0)])['features'] as List), isEmpty);
    });

    test('las coordenadas van como [lon, lat]', () {
      final g = lineGeoJson([(43.0, -2.0), (43.1, -2.1)]);
      final coords = ((g['features'] as List).first as Map)['geometry']['coordinates'] as List;
      expect(coords.first, [-2.0, 43.0]);
    });

    test('con rumbo la posición lleva heading; sin rumbo no', () {
      Map props(Map<String, dynamic> g) => ((g['features'] as List).first as Map)['properties'] as Map;
      expect(props(userGeoJson(43, -2, 90))['heading'], 90);
      expect(props(userGeoJson(43, -2, null)).containsKey('heading'), isFalse);
      expect((userGeoJson(null, null, null)['features'] as List), isEmpty);
    });

    test('inicio, fin y waypoints se distinguen por "kind"', () {
      final g = pointsGeoJson(start: (43, -2), end: (43.1, -2.1), waypoints: [(43.05, -2.05, 'Fuente')]);
      final kinds = [for (final f in g['features'] as List) (f as Map)['properties']['kind']];
      expect(kinds, ['waypoint', 'start', 'end']);
    });
  });
}
