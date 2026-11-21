import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gpx_app/features/routes/route_providers.dart';
import 'package:gpx_app/features/routes/stats_panel.dart';
import 'package:gpx_app/main.dart';

void main() {
  testWidgets('arranca mostrando el estado vacío con botón de abrir GPX',
      (tester) async {
    await tester.pumpWidget(const ProviderScope(child: GpxApp()));

    expect(find.text('Abre un archivo GPX para ver tu ruta'), findsOneWidget);
    expect(find.text('Abrir GPX'), findsOneWidget);
    expect(find.byType(StatsPanel), findsNothing);
  });

  testWidgets('al cargar el GPX de ejemplo muestra nombre y estadísticas',
      (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: const GpxApp()),
    );

    final gpx = File('samples/ejemplo.gpx').readAsStringSync();
    container.read(viewerProvider.notifier).loadFromString(gpx);
    await tester.pump();

    expect(find.text('Ruta circular de ejemplo'), findsOneWidget);
    expect(find.byType(StatsPanel), findsOneWidget);
    expect(find.text('Distancia'), findsOneWidget);
    expect(find.text('Desnivel +'), findsOneWidget);
    expect(find.text('Duración'), findsOneWidget);
    expect(find.text('Abre un archivo GPX para ver tu ruta'), findsNothing);
  });
}
