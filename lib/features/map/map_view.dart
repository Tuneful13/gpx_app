import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:math' show Point;

import 'package:latlong2/latlong.dart';
import 'package:maplibre_gl/maplibre_gl.dart' as ml;

import '../navigation/route_matcher.dart';
import '../routes/route_models.dart';
import '../settings/settings_controller.dart';
import 'map_camera.dart';
import 'map_style.dart';
import 'offline_maps.dart';

export 'map_camera.dart' show MapViewController, headingUpRotation;

/// Único widget que conoce la librería de mapa (MapLibre). El resto de la app
/// habla con él a través de [MapViewController] y de sus parámetros.
class MapView extends ConsumerStatefulWidget {
  const MapView({
    super.key,
    required this.route,
    this.highlight,
    this.controller,
    this.userPosition,
    this.userHeadingDeg,
    this.progress,
    this.onUserGesture,
    this.controlsPadding = const EdgeInsets.fromLTRB(12, 0, 0, 40),
  });

  /// El mapa nativo no funciona en los tests de widgets: allí se pone a false
  /// (ver `test/flutter_test_config.dart`) y se dibuja un recuadro en su lugar.
  static bool useNativeMap = true;

  final GpxRoute route;

  /// Punto resaltado (por ejemplo el que se toca en el perfil de elevación).
  final LatLng? highlight;

  final MapViewController? controller;

  /// Posición actual del usuario (navegación).
  final LatLng? userPosition;
  final double? userHeadingDeg;

  /// Avance sobre la ruta: el tramo ya recorrido se pinta en gris.
  final MatchResult? progress;

  /// Se llama cuando el usuario mueve el mapa con el dedo.
  final VoidCallback? onUserGesture;

  /// Distancia desde la esquina inferior izquierda a la que van el botón de
  /// satélite y, encima, la brújula (para no quedar tapados por otros paneles).
  final EdgeInsets controlsPadding;

  @override
  ConsumerState<MapView> createState() => _MapViewState();
}

class _MapViewState extends ConsumerState<MapView> {
  ml.MapLibreMapController? _map;
  bool _styleReady = false;
  MapViewController? _ownCamera;

  MapViewController get _camera =>
      widget.controller ?? (_ownCamera ??= MapViewController());

  @override
  void initState() {
    super.initState();
    _camera.addListener(_applyCamera);
  }

  @override
  void didUpdateWidget(MapView old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      (old.controller ?? _ownCamera)?.removeListener(_applyCamera);
      _camera.addListener(_applyCamera);
    }
    if (!_styleReady) return;
    if (!identical(old.route, widget.route)) {
      _pushRoute();
      _fitRoute();
    }
    if (old.progress != widget.progress ||
        !identical(old.route, widget.route)) {
      _pushWalked();
    }
    if (old.highlight != widget.highlight) _pushHighlight();
    if (old.userPosition != widget.userPosition ||
        old.userHeadingDeg != widget.userHeadingDeg) {
      _pushUser();
    }
  }

  @override
  void dispose() {
    _camera.removeListener(_applyCamera);
    _ownCamera?.dispose();
    super.dispose();
  }

  // --- Cámara ---

  void _applyCamera() {
    final map = _map;
    final c = _camera.center;
    if (map == null || !_styleReady || c == null) return;
    map.animateCamera(
      ml.CameraUpdate.newCameraPosition(
        ml.CameraPosition(
          target: ml.LatLng(c.latitude, c.longitude),
          zoom: _camera.zoom,
          bearing: _camera.bearing,
        ),
      ),
      duration: const Duration(milliseconds: 400),
    );
  }

  void _onCameraIdle() {
    final p = _map?.cameraPosition;
    if (p == null) return;
    _camera.syncFromMap(
      LatLng(p.target.latitude, p.target.longitude),
      p.zoom,
      p.bearing,
    );
  }

  void _fitRoute() {
    final map = _map;
    final pts = widget.route.points;
    if (map == null || pts.isEmpty) return;
    var s = pts.first.lat, n = s, w = pts.first.lon, e = w;
    for (final p in pts) {
      s = math.min(s, p.lat);
      n = math.max(n, p.lat);
      w = math.min(w, p.lon);
      e = math.max(e, p.lon);
    }
    map.moveCamera(
      ml.CameraUpdate.newLatLngBounds(
        ml.LatLngBounds(southwest: ml.LatLng(s, w), northeast: ml.LatLng(n, e)),
        left: 40,
        top: 40,
        right: 40,
        bottom: 40,
      ),
    );
  }

  // --- Datos dibujados encima ---

  Future<void> _set(String source, Map<String, dynamic> data) async {
    if (!mounted || !_styleReady) return;
    try {
      await _map?.setGeoJsonSource(source, data);
    } catch (e) {
      debugPrint('No se pudo actualizar $source: $e');
    }
  }

  void _pushRoute() {
    final r = widget.route;
    _set(routeSource, lineGeoJson([for (final p in r.points) (p.lat, p.lon)]));
    if (r.points.isEmpty) return;
    _set(
      pointsSource,
      pointsGeoJson(
        start: (r.points.first.lat, r.points.first.lon),
        end: (r.points.last.lat, r.points.last.lon),
        waypoints: [for (final w in r.waypoints) (w.lat, w.lon, w.name)],
      ),
    );
  }

  void _pushWalked() {
    final m = widget.progress;
    final pts = widget.route.points;
    if (m == null || pts.isEmpty) {
      _set(walkedSource, emptyGeoJson());
      return;
    }
    final end = math.min(m.segment + 1, pts.length);
    _set(
      walkedSource,
      lineGeoJson([
        for (final p in pts.sublist(0, end)) (p.lat, p.lon),
        (m.lat, m.lon),
      ]),
    );
  }

  void _pushHighlight() => _set(
    highlightSource,
    singlePointGeoJson(widget.highlight?.latitude, widget.highlight?.longitude),
  );

  void _pushUser() => _set(
    userSource,
    userGeoJson(
      widget.userPosition?.latitude,
      widget.userPosition?.longitude,
      widget.userHeadingDeg,
    ),
  );

  Future<void> _onStyleLoaded() async {
    final map = _map;
    if (map == null || !mounted) return;
    try {
      await map.addImage(userArrowImage, await _arrowPng());
    } catch (e) {
      debugPrint('No se pudo crear la flecha de posición: $e');
    }
    _styleReady = true;
    _pushRoute();
    _pushWalked();
    _pushHighlight();
    _pushUser();
    if (_camera.center != null) {
      _applyCamera();
    } else {
      _fitRoute();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!MapView.useNativeMap) {
      return const ColoredBox(
        key: ValueKey('map-placeholder'),
        color: Color(0xFFE0E0E0),
      );
    }
    final maps = ref.watch(offlineMapsProvider);
    return maps.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, _) => _buildMap(const OfflineMaps()),
      data: _buildMap,
    );
  }

  Widget _buildMap(OfflineMaps maps) {
    final scheme = Theme.of(context).colorScheme;
    final satellite = ref.watch(settingsProvider.select((s) => s.satellite));
    final style = jsonEncode(
      buildMapStyle(
        regions: maps.styleRegions,
        glyphsDir: maps.glyphsDir,
        routeColor: scheme.primary,
        highlightColor: scheme.tertiary,
        satellite: satellite,
      ),
    );
    final first = widget.route.points.isEmpty
        ? null
        : widget.route.points.first;
    final pad = widget.controlsPadding;

    return Stack(
      children: [
        Positioned.fill(
          child: Listener(
            onPointerMove: (_) => widget.onUserGesture?.call(),
            child: ml.MapLibreMap(
              // Al descargar, actualizar o borrar una zona, o al cambiar a satélite,
              // se recrea el mapa (la cámara se conserva).
              key: ValueKey('${maps.revision}-$satellite'),
              styleString: style,
              initialCameraPosition: ml.CameraPosition(
                target: ml.LatLng(first?.lat ?? 43.0, first?.lon ?? -2.0),
                zoom: 12,
              ),
              trackCameraPosition: true,
              rotateGesturesEnabled: true,
              tiltGesturesEnabled: false,
              compassEnabled: true,
              compassViewPosition: ml.CompassViewPosition.bottomLeft,
              compassViewMargins: Point(pad.left, pad.bottom + 52),
              onMapCreated: (c) {
                _map = c;
                _styleReady = false;
              },
              onStyleLoadedCallback: _onStyleLoaded,
              onCameraIdle: _onCameraIdle,
            ),
          ),
        ),
        Positioned(
          left: pad.left,
          bottom: pad.bottom,
          child: FloatingActionButton.small(
            key: const ValueKey('map-layer-toggle'),
            heroTag: null,
            tooltip: satellite ? 'Ver mapa' : 'Ver satélite',
            onPressed: () => ref
                .read(settingsProvider.notifier)
                .update((s) => s.copyWith(satellite: !s.satellite)),
            child: Icon(satellite ? Icons.map_outlined : Icons.satellite_alt),
          ),
        ),
      ],
    );
  }
}

/// Flecha azul de "tu posición", dibujada con el icono de Material.
Future<Uint8List> _arrowPng() async {
  const size = 96.0;
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  final icon = Icons.navigation;
  final painter = TextPainter(
    textDirection: TextDirection.ltr,
    text: TextSpan(
      text: String.fromCharCode(icon.codePoint),
      style: TextStyle(
        fontSize: size * 0.8,
        fontFamily: icon.fontFamily,
        package: icon.fontPackage,
        color: const Color(0xFF1976D2),
        shadows: const [Shadow(color: Colors.white, blurRadius: 6)],
      ),
    ),
  )..layout();
  painter.paint(
    canvas,
    Offset((size - painter.width) / 2, (size - painter.height) / 2),
  );
  final image = await recorder.endRecording().toImage(
    size.toInt(),
    size.toInt(),
  );
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  return bytes!.buffer.asUint8List();
}
