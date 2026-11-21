import 'dart:async';

import 'package:gpx_app/features/map/map_view.dart';

/// `flutter test` ejecuta esto antes de cada archivo de tests.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  // MapLibre es un mapa nativo y no se puede dibujar en tests de widgets.
  MapView.useNativeMap = false;
  await testMain();
}
