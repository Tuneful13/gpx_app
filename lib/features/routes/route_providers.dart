import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'gpx_parser.dart';
import 'route_models.dart';
import 'route_stats.dart';

class LoadedRoute {
  const LoadedRoute(this.route, this.stats);
  final GpxRoute route;
  final RouteStats stats;
}

class ViewerState {
  const ViewerState({this.loaded, this.loading = false, this.error});

  final LoadedRoute? loaded;
  final bool loading;
  final String? error;
}

class ViewerController extends Notifier<ViewerState> {
  @override
  ViewerState build() => const ViewerState();

  /// Carga una ruta desde el texto de un GPX (también útil para tests).
  void loadFromString(String gpx, {String fallbackName = 'Ruta'}) {
    final route = parseGpx(gpx, fallbackName: fallbackName);
    state = ViewerState(loaded: LoadedRoute(route, computeStats(route.points)));
  }

  Future<void> pickGpx() async {
    state = ViewerState(loaded: state.loaded, loading: true);
    try {
      final file = await FilePicker.pickFile(dialogTitle: 'Abrir archivo GPX');
      if (file == null) {
        state = ViewerState(loaded: state.loaded);
        return;
      }
      if (file.extension?.toLowerCase() != 'gpx') {
        throw GpxFormatException('Elige un archivo con extensión .gpx');
      }
      final text = utf8.decode(await file.readAsBytes(), allowMalformed: true);
      loadFromString(
        text,
        fallbackName: file.name.replaceAll(RegExp(r'\.gpx$', caseSensitive: false), ''),
      );
    } on GpxFormatException catch (e) {
      state = ViewerState(loaded: state.loaded, error: e.message);
    } catch (e) {
      state = ViewerState(
        loaded: state.loaded,
        error: 'No se pudo abrir el archivo: $e',
      );
    }
  }

  void clearError() => state = ViewerState(loaded: state.loaded);
}

final viewerProvider =
    NotifierProvider<ViewerController, ViewerState>(ViewerController.new);
