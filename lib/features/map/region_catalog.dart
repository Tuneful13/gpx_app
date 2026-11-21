import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Catálogo de zonas descargables, publicado junto a los mapas en las
/// Releases del repositorio de mapas. Siempre se lee el de la última Release.
const defaultCatalogUrl =
    'https://github.com/Tuneful13/mapas-norte-pirineos/releases/latest/download/catalogo.json';

class MapAsset {
  const MapAsset({required this.url, required this.bytes});

  factory MapAsset.fromJson(Map<String, dynamic> j) =>
      MapAsset(url: j['url'] as String, bytes: (j['bytes'] as num).toInt());

  final String url;
  final int bytes;
}

class MapRegion {
  const MapRegion({
    required this.id,
    required this.name,
    required this.bounds,
    required this.base,
    required this.contours,
  });

  factory MapRegion.fromJson(Map<String, dynamic> j) => MapRegion(
        id: j['id'] as String,
        name: j['nombre'] as String,
        bounds: [for (final v in j['caja'] as List) (v as num).toDouble()],
        base: MapAsset.fromJson(j['base'] as Map<String, dynamic>),
        contours: MapAsset.fromJson(j['curvas'] as Map<String, dynamic>),
      );

  final String id;
  final String name;

  /// [oeste, sur, este, norte]
  final List<double> bounds;
  final MapAsset base;
  final MapAsset contours;
}

class RegionCatalog {
  const RegionCatalog({required this.version, required this.regions});

  /// Lanza [FormatException] si el JSON no tiene el formato esperado.
  factory RegionCatalog.fromJson(Map<String, dynamic> j) {
    try {
      if (j['formato'] != 1) {
        throw const FormatException('Versión de catálogo no soportada');
      }
      return RegionCatalog(
        version: j['version'] as String,
        regions: [
          for (final r in j['zonas'] as List) MapRegion.fromJson(r as Map<String, dynamic>),
        ],
      );
    } on FormatException {
      rethrow;
    } catch (e) {
      throw FormatException('Catálogo de mapas no válido: $e');
    }
  }

  final String version;
  final List<MapRegion> regions;
}

/// Petición GET que sigue redirecciones a mano: GitHub redirige las
/// descargas a otro servidor y así la cabecera Range se mantiene.
Future<HttpClientResponse> _get(HttpClient client, Uri uri, {int? fromByte}) async {
  var current = uri;
  for (var i = 0; i < 6; i++) {
    final req = await client.getUrl(current);
    req.followRedirects = false;
    if (fromByte != null && fromByte > 0) {
      req.headers.set(HttpHeaders.rangeHeader, 'bytes=$fromByte-');
    }
    final res = await req.close();
    if (res.isRedirect) {
      final location = res.headers.value(HttpHeaders.locationHeader);
      await res.drain<void>();
      if (location == null) break;
      current = current.resolve(location);
      continue;
    }
    return res;
  }
  throw const HttpException('Demasiadas redirecciones');
}

Future<RegionCatalog> fetchCatalog(String url) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
  try {
    final res = await _get(client, Uri.parse(url));
    if (res.statusCode != 200) {
      await res.drain<void>();
      throw HttpException('El servidor respondió ${res.statusCode}');
    }
    final text = await res.transform(utf8.decoder).join();
    return RegionCatalog.fromJson(jsonDecode(text) as Map<String, dynamic>);
  } finally {
    client.close(force: true);
  }
}

/// Permite cancelar una descarga en curso.
class DownloadCancel {
  HttpClient? _client;
  bool _cancelled = false;
  bool get cancelled => _cancelled;

  void cancel() {
    _cancelled = true;
    _client?.close(force: true);
  }
}

class DownloadCancelled implements Exception {
  @override
  String toString() => 'Descarga cancelada';
}

/// Descarga [url] en [dest]. Usa `dest.part` mientras tanto y, si ya
/// existe de un intento anterior, continúa donde se quedó.
/// [onProgress] recibe los bytes que hay en disco.
Future<void> downloadFile(
  String url,
  File dest, {
  required int expectedBytes,
  void Function(int bytes)? onProgress,
  DownloadCancel? cancel,
}) async {
  final part = File('${dest.path}.part');
  var have = await part.exists() ? await part.length() : 0;
  if (have > expectedBytes) {
    await part.delete();
    have = 0;
  }

  final client = HttpClient()..connectionTimeout = const Duration(seconds: 20);
  cancel?._client = client;
  try {
    if (cancel?.cancelled ?? false) throw DownloadCancelled();
    if (have < expectedBytes) {
      final res = await _get(client, Uri.parse(url), fromByte: have);
      final append = res.statusCode == HttpStatus.partialContent;
      if (!append && res.statusCode != HttpStatus.ok) {
        await res.drain<void>();
        throw HttpException('El servidor respondió ${res.statusCode}');
      }
      if (!append) have = 0; // el servidor no admite continuar: desde cero
      final sink = part.openWrite(mode: append ? FileMode.append : FileMode.write);
      try {
        await for (final chunk in res) {
          sink.add(chunk);
          have += chunk.length;
          onProgress?.call(have);
        }
      } finally {
        await sink.close();
      }
    }
    if (cancel?.cancelled ?? false) throw DownloadCancelled();
    final got = await part.length();
    if (got != expectedBytes) {
      await part.delete();
      throw HttpException('Descarga incompleta ($got de $expectedBytes bytes)');
    }
    await part.rename(dest.path);
  } catch (e) {
    if (cancel?.cancelled ?? false) throw DownloadCancelled();
    rethrow;
  } finally {
    client.close(force: true);
  }
}
