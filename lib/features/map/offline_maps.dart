import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import 'map_style.dart';
import 'region_catalog.dart';

/// Mapas offline por zonas, guardados en la carpeta privada de la app:
/// - `maps/regions/ID/base.pmtiles`: mapa base
/// - `maps/regions/ID/curvas.pmtiles`: curvas de nivel (opcional)
/// - `maps/regions/ID/info.json`: nombre y versión del catálogo
const _baseFile = 'base.pmtiles';
const _contoursFile = 'curvas.pmtiles';
const _infoFile = 'info.json';

class InstalledRegion {
  const InstalledRegion({
    required this.id,
    required this.name,
    required this.version,
    required this.basePath,
    this.contoursPath,
    required this.bytes,
  });

  final String id;
  final String name;

  /// Versión (Release) del catálogo de la que se descargó.
  final String version;
  final String basePath;
  final String? contoursPath;

  /// Espacio que ocupa en el móvil.
  final int bytes;
}

class OfflineMaps {
  const OfflineMaps({this.regions = const {}, this.glyphsDir, this.revision = 0});

  final Map<String, InstalledRegion> regions;

  /// Carpeta con las fuentes de las etiquetas, copiadas desde los assets.
  final String? glyphsDir;

  /// Cambia cada vez que cambian los archivos (para recargar el mapa).
  final int revision;

  int get totalBytes => regions.values.fold(0, (a, r) => a + r.bytes);

  List<MapRegionFiles> get styleRegions => [
        for (final r in regions.values)
          MapRegionFiles(id: r.id, basePath: r.basePath, contoursPath: r.contoursPath),
      ];
}

/// Estado de una descarga en curso o fallida.
class RegionDownload {
  const RegionDownload({required this.received, required this.total, this.error});

  final int received;
  final int total;

  /// Mensaje si ha fallado (la descarga se puede reintentar y continúa).
  final String? error;

  double get fraction => total == 0 ? 0 : (received / total).clamp(0, 1);
}

/// Carpeta donde se guardan los mapas. Se sustituye en tests.
final mapsDirProvider = FutureProvider<Directory>((ref) async {
  final base = await getApplicationSupportDirectory();
  return Directory('${base.path}/maps').create(recursive: true);
});

/// Comprueba que [file] empieza como un PMTiles v3 ("PMTiles" + versión 3).
Future<bool> isPmtilesV3(File file) async {
  final raf = await file.open();
  try {
    final head = await raf.read(8);
    return head.length == 8 &&
        String.fromCharCodes(head.sublist(0, 7)) == 'PMTiles' &&
        head[7] == 3;
  } finally {
    await raf.close();
  }
}

class OfflineMapsController extends AsyncNotifier<OfflineMaps> {
  final _cancels = <String, DownloadCancel>{};
  int _revision = 0;

  @override
  Future<OfflineMaps> build() async {
    final dir = await ref.watch(mapsDirProvider.future);
    return _scan(dir, await _ensureGlyphs(dir));
  }

  Directory _regionsDir(Directory maps) => Directory('${maps.path}/regions');

  Future<OfflineMaps> _scan(Directory maps, String? glyphsDir) async {
    final regions = <String, InstalledRegion>{};
    final root = _regionsDir(maps);
    if (await root.exists()) {
      await for (final d in root.list()) {
        if (d is! Directory) continue;
        final r = await _readRegion(d);
        if (r != null) regions[r.id] = r;
      }
    }
    final sorted = Map.fromEntries(
      regions.entries.toList()..sort((a, b) => a.value.name.compareTo(b.value.name)),
    );
    return OfflineMaps(regions: sorted, glyphsDir: glyphsDir, revision: _revision++);
  }

  Future<InstalledRegion?> _readRegion(Directory d) async {
    final info = File('${d.path}/$_infoFile');
    final base = File('${d.path}/$_baseFile');
    if (!await info.exists() || !await base.exists()) return null;
    try {
      final j = jsonDecode(await info.readAsString()) as Map<String, dynamic>;
      final contours = File('${d.path}/$_contoursFile');
      final hasContours = await contours.exists();
      return InstalledRegion(
        id: j['id'] as String,
        name: j['nombre'] as String,
        version: j['version'] as String,
        basePath: base.path,
        contoursPath: hasContours ? contours.path : null,
        bytes: await base.length() + (hasContours ? await contours.length() : 0),
      );
    } catch (_) {
      return null;
    }
  }

  /// MapLibre lee las fuentes del disco, no de los assets: se copian una vez.
  Future<String?> _ensureGlyphs(Directory dir) async {
    try {
      final out = Directory('${dir.path}/glyphs/$glyphFont');
      await out.create(recursive: true);
      for (final range in glyphRanges) {
        final f = File('${out.path}/$range.pbf');
        if (await f.exists()) continue;
        final data = await rootBundle.load('assets/glyphs/$glyphFont/$range.pbf');
        await f.writeAsBytes(data.buffer.asUint8List(), flush: true);
      }
      return '${dir.path}/glyphs';
    } catch (_) {
      return null; // Sin fuentes el mapa se ve igual, solo que sin etiquetas.
    }
  }

  bool isDownloading(String id) => _cancels.containsKey(id);

  /// Descarga (o actualiza) la zona [region]. Con [withContours] también las
  /// curvas de nivel; sin ellas, borra las que hubiera. Si la descarga se
  /// corta, al reintentar continúa donde se quedó.
  Future<void> download(MapRegion region, String version, {required bool withContours}) async {
    if (_cancels.containsKey(region.id)) return;
    final maps = await ref.read(mapsDirProvider.future);
    final dir = Directory('${_regionsDir(maps).path}/${region.id}');
    await dir.create(recursive: true);

    final installed = state.asData?.value.regions[region.id];
    final sameVersion = installed?.version == version;
    final jobs = <(MapAsset, File)>[
      if (!sameVersion) (region.base, File('${dir.path}/$_baseFile')),
      if (withContours && (!sameVersion || installed?.contoursPath == null))
        (region.contours, File('${dir.path}/$_contoursFile')),
    ];
    // Al actualizar, los archivos nuevos se descargan aparte y sustituyen a
    // los viejos solo al final: si falla, el mapa anterior sigue funcionando.
    final total = jobs.fold(0, (a, j) => a + j.$1.bytes);
    final cancel = DownloadCancel();
    _cancels[region.id] = cancel;
    final progress = ref.read(regionDownloadsProvider.notifier);
    progress.set(region.id, RegionDownload(received: 0, total: total));

    try {
      var done = 0;
      final ready = <(File, File)>[];
      for (final (asset, dest) in jobs) {
        final tmp = File('${dest.path}.new');
        await downloadFile(
          asset.url,
          tmp,
          expectedBytes: asset.bytes,
          cancel: cancel,
          onProgress: (b) => progress.set(region.id, RegionDownload(received: done + b, total: total)),
        );
        if (!await isPmtilesV3(tmp)) {
          await tmp.delete();
          throw const FormatException('El archivo descargado no es un mapa válido');
        }
        done += asset.bytes;
        ready.add((tmp, dest));
      }
      for (final (tmp, dest) in ready) {
        await tmp.rename(dest.path);
      }
      if (!withContours) {
        final c = File('${dir.path}/$_contoursFile');
        if (await c.exists()) await c.delete();
      }
      await File('${dir.path}/$_infoFile').writeAsString(jsonEncode({
        'id': region.id,
        'nombre': region.name,
        'version': version,
      }));
      progress.remove(region.id);
      await _refresh();
    } on DownloadCancelled {
      progress.remove(region.id);
    } catch (e) {
      progress.set(region.id, RegionDownload(received: 0, total: total, error: _message(e)));
    } finally {
      _cancels.remove(region.id);
    }
  }

  /// Cancela la descarga. Lo ya descargado se conserva para continuar luego.
  void cancel(String id) => _cancels[id]?.cancel();

  /// Borra la zona y cualquier descarga a medias.
  Future<void> delete(String id) async {
    cancel(id);
    final maps = await ref.read(mapsDirProvider.future);
    final dir = Directory('${_regionsDir(maps).path}/$id');
    if (await dir.exists()) await dir.delete(recursive: true);
    ref.read(regionDownloadsProvider.notifier).remove(id);
    await _refresh();
  }

  Future<void> _refresh() async {
    final maps = await ref.read(mapsDirProvider.future);
    state = AsyncData(await _scan(maps, state.asData?.value.glyphsDir));
  }

  static String _message(Object e) => switch (e) {
        SocketException() => 'Sin conexión. Vuelve a intentarlo: seguirá donde se quedó.',
        HttpException(:final message) => message,
        FormatException(:final message) => message,
        FileSystemException() => 'No se pudo guardar el mapa (¿falta espacio?).',
        _ => 'Error: $e',
      };
}

final offlineMapsProvider =
    AsyncNotifierProvider<OfflineMapsController, OfflineMaps>(OfflineMapsController.new);

class RegionDownloads extends Notifier<Map<String, RegionDownload>> {
  @override
  Map<String, RegionDownload> build() => const {};

  void set(String id, RegionDownload d) => state = {...state, id: d};

  void remove(String id) => state = {...state}..remove(id);
}

/// Descargas en curso (o fallidas), por id de zona. Va aparte para que el
/// progreso no fuerce a recalcular el mapa.
final regionDownloadsProvider =
    NotifierProvider<RegionDownloads, Map<String, RegionDownload>>(RegionDownloads.new);

/// URL del catálogo. Se sustituye en tests.
final catalogUrlProvider = Provider<String>((ref) => defaultCatalogUrl);

final regionCatalogProvider = FutureProvider<RegionCatalog>(
  (ref) => fetchCatalog(ref.watch(catalogUrlProvider)),
);
