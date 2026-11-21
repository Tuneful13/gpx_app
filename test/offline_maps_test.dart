import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gpx_app/features/map/offline_maps.dart';
import 'package:gpx_app/features/map/region_catalog.dart';

/// Cabecera de un PMTiles v3 seguida de [size] bytes de relleno.
Uint8List _pmtiles(int size, [int fill = 0]) =>
    Uint8List.fromList([...'PMTiles'.codeUnits, 3, ...List.filled(size - 8, fill)]);

/// Servidor HTTP local que imita GitHub: redirige `/r/...` y admite Range.
class _Server {
  late HttpServer server;
  final files = <String, Uint8List>{};
  final requests = <(String path, String? range)>[];
  bool rangeSupport = true;

  String url(String path) => 'http://127.0.0.1:${server.port}$path';

  Future<void> start() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((req) async {
      final path = req.uri.path;
      final range = req.headers.value(HttpHeaders.rangeHeader);
      requests.add((path, range));
      final res = req.response;
      if (path.startsWith('/r/')) {
        res.statusCode = HttpStatus.found;
        res.headers.set(HttpHeaders.locationHeader, path.substring(2));
        await res.close();
        return;
      }
      final body = files[path];
      if (body == null) {
        res.statusCode = HttpStatus.notFound;
        await res.close();
        return;
      }
      if (range != null && rangeSupport) {
        final from = int.parse(RegExp(r'bytes=(\d+)-').firstMatch(range)!.group(1)!);
        res.statusCode = HttpStatus.partialContent;
        res.add(body.sublist(from));
      } else {
        res.add(body);
      }
      await res.close();
    });
  }

  Future<void> stop() => server.close(force: true);
}

Map<String, dynamic> _catalogJson(_Server s, String version, {int? baseBytesOverride}) => {
      'formato': 1,
      'version': version,
      'zonas': [
        {
          'id': 'navarra',
          'nombre': 'Navarra',
          'caja': [-2.5, 41.9, -0.7, 43.3],
          'base': {
            'url': s.url('/r/navarra-base.pmtiles'),
            'bytes': baseBytesOverride ?? s.files['/navarra-base.pmtiles']!.length,
          },
          'curvas': {
            'url': s.url('/r/navarra-curvas.pmtiles'),
            'bytes': s.files['/navarra-curvas.pmtiles']!.length,
          },
        },
      ],
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;
  late _Server srv;
  late ProviderContainer container;

  setUp(() async {
    // flutter_test bloquea por defecto las peticiones HTTP reales; aquí van a
    // un servidor local del propio test.
    HttpOverrides.global = null;
    tmp = await Directory.systemTemp.createTemp('maps_test');
    srv = _Server()
      ..files['/navarra-base.pmtiles'] = _pmtiles(5000, 1)
      ..files['/navarra-curvas.pmtiles'] = _pmtiles(3000, 2);
    await srv.start();
    srv.files['/catalogo.json'] = utf8.encode(jsonEncode(_catalogJson(srv, 'v1')));
    container = ProviderContainer(overrides: [
      mapsDirProvider.overrideWith((ref) async => tmp),
      catalogUrlProvider.overrideWithValue(srv.url('/r/catalogo.json')),
    ]);
  });

  tearDown(() async {
    container.dispose();
    await srv.stop();
    await tmp.delete(recursive: true);
  });

  OfflineMapsController maps() => container.read(offlineMapsProvider.notifier);
  OfflineMaps state() => container.read(offlineMapsProvider).requireValue;

  group('catálogo', () {
    test('se descarga (siguiendo la redirección) y se interpreta', () async {
      final c = await container.read(regionCatalogProvider.future);
      expect(c.version, 'v1');
      expect(c.regions.single.name, 'Navarra');
      expect(c.regions.single.base.bytes, 5000);
      expect(c.regions.single.bounds, [-2.5, 41.9, -0.7, 43.3]);
    });

    test('un formato desconocido se rechaza', () {
      expect(() => RegionCatalog.fromJson({'formato': 2, 'version': 'x', 'zonas': []}),
          throwsFormatException);
      expect(() => RegionCatalog.fromJson({'formato': 1, 'zonas': 'no'}), throwsFormatException);
    });
  });

  group('zonas descargadas', () {
    test('al empezar no hay zonas, pero sí fuentes copiadas', () async {
      final m = await container.read(offlineMapsProvider.future);
      expect(m.regions, isEmpty);
      expect(m.glyphsDir, '${tmp.path}/glyphs');
      expect(File('${tmp.path}/glyphs/noto/0-255.pbf').existsSync(), isTrue);
    });

    test('descargar con curvas instala la zona completa', () async {
      await container.read(offlineMapsProvider.future);
      final region = (await container.read(regionCatalogProvider.future)).regions.single;
      await maps().download(region, 'v1', withContours: true);

      final r = state().regions['navarra']!;
      expect(r.name, 'Navarra');
      expect(r.version, 'v1');
      expect(r.bytes, 8000);
      expect(File(r.basePath).readAsBytesSync(), srv.files['/navarra-base.pmtiles']);
      expect(File(r.contoursPath!).readAsBytesSync(), srv.files['/navarra-curvas.pmtiles']);
      expect(container.read(regionDownloadsProvider), isEmpty);
      expect(state().styleRegions.single.contoursPath, r.contoursPath);
    });

    test('sin curvas, y luego añadir solo las curvas', () async {
      await container.read(offlineMapsProvider.future);
      final region = (await container.read(regionCatalogProvider.future)).regions.single;
      await maps().download(region, 'v1', withContours: false);
      expect(state().regions['navarra']!.contoursPath, isNull);

      srv.requests.clear();
      await maps().download(region, 'v1', withContours: true);
      expect(state().regions['navarra']!.contoursPath, isNotNull);
      // No vuelve a bajar el mapa base.
      expect(srv.requests.map((r) => r.$1), isNot(contains('/navarra-base.pmtiles')));
    });

    test('una descarga cortada continúa donde se quedó', () async {
      await container.read(offlineMapsProvider.future);
      final region = (await container.read(regionCatalogProvider.future)).regions.single;
      // Simula un intento anterior que se quedó a 2000 bytes.
      final dir = Directory('${tmp.path}/regions/navarra')..createSync(recursive: true);
      File('${dir.path}/base.pmtiles.new.part')
          .writeAsBytesSync(srv.files['/navarra-base.pmtiles']!.sublist(0, 2000));

      await maps().download(region, 'v1', withContours: false);
      expect(srv.requests, contains(('/navarra-base.pmtiles', 'bytes=2000-')));
      expect(File(state().regions['navarra']!.basePath).readAsBytesSync(),
          srv.files['/navarra-base.pmtiles']);
    });

    test('si el servidor no admite continuar, empieza de cero y sale bien', () async {
      srv.rangeSupport = false;
      await container.read(offlineMapsProvider.future);
      final region = (await container.read(regionCatalogProvider.future)).regions.single;
      final dir = Directory('${tmp.path}/regions/navarra')..createSync(recursive: true);
      File('${dir.path}/base.pmtiles.new.part').writeAsBytesSync(List.filled(2000, 9));

      await maps().download(region, 'v1', withContours: false);
      expect(File(state().regions['navarra']!.basePath).readAsBytesSync(),
          srv.files['/navarra-base.pmtiles']);
    });

    test('un tamaño que no cuadra es un error y no instala nada', () async {
      await container.read(offlineMapsProvider.future);
      final bad = RegionCatalog.fromJson(_catalogJson(srv, 'v1', baseBytesOverride: 9999));
      await maps().download(bad.regions.single, 'v1', withContours: false);

      expect(state().regions, isEmpty);
      final d = container.read(regionDownloadsProvider)['navarra']!;
      expect(d.error, contains('incompleta'));
    });

    test('actualizar a una versión nueva sustituye los archivos', () async {
      await container.read(offlineMapsProvider.future);
      final region = (await container.read(regionCatalogProvider.future)).regions.single;
      await maps().download(region, 'v1', withContours: true);
      final rev = state().revision;

      srv.files['/navarra-base.pmtiles'] = _pmtiles(6000, 7);
      final v2 = RegionCatalog.fromJson(_catalogJson(srv, 'v2')).regions.single;
      await maps().download(v2, 'v2', withContours: true);

      final r = state().regions['navarra']!;
      expect(r.version, 'v2');
      expect(File(r.basePath).readAsBytesSync(), srv.files['/navarra-base.pmtiles']);
      expect(state().revision, greaterThan(rev), reason: 'el mapa debe recargarse');
    });

    test('borrar quita la zona y sus archivos', () async {
      await container.read(offlineMapsProvider.future);
      final region = (await container.read(regionCatalogProvider.future)).regions.single;
      await maps().download(region, 'v1', withContours: true);
      await maps().delete('navarra');
      expect(state().regions, isEmpty);
      expect(Directory('${tmp.path}/regions/navarra').existsSync(), isFalse);
    });
  });

  test('isPmtilesV3 reconoce la cabecera', () async {
    final ok = File('${tmp.path}/a.pmtiles')..writeAsBytesSync(_pmtiles(100));
    final bad = File('${tmp.path}/b.pmtiles')..writeAsBytesSync(List.filled(100, 7));
    expect(await isPmtilesV3(ok), isTrue);
    expect(await isPmtilesV3(bad), isFalse);
  });
}
