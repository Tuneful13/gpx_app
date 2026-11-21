import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gpx_app/features/map/offline_maps.dart';
import 'package:gpx_app/features/map/offline_maps_page.dart';
import 'package:gpx_app/features/map/region_catalog.dart';

MapRegion _region(String id, String name, int base, int curvas) => MapRegion(
      id: id,
      name: name,
      bounds: const [0, 0, 1, 1],
      base: MapAsset(url: 'https://x/$id-base.pmtiles', bytes: base),
      contours: MapAsset(url: 'https://x/$id-curvas.pmtiles', bytes: curvas),
    );

/// Estado fijo de zonas descargadas, sin tocar el disco.
class _FakeMaps extends OfflineMapsController {
  _FakeMaps(this.value);
  final OfflineMaps value;
  final downloaded = <(String, String, bool)>[];

  @override
  Future<OfflineMaps> build() async => value;

  @override
  Future<void> download(MapRegion region, String version, {required bool withContours}) async {
    downloaded.add((region.id, version, withContours));
  }
}

void main() {
  final catalog = RegionCatalog(version: 'v2', regions: [
    _region('cantabria', 'Cantabria', 60000000, 40000000),
    _region('navarra', 'Navarra', 50000000, 30000000),
    _region('andorra', 'Andorra', 5000000, 4000000),
    _region('la-rioja', 'La Rioja', 20000000, 10000000),
  ]);
  final installed = OfflineMaps(regions: {
    'navarra': const InstalledRegion(
        id: 'navarra', name: 'Navarra', version: 'v2', basePath: '/n', bytes: 80000000,
        contoursPath: '/c'),
    'andorra': const InstalledRegion(
        id: 'andorra', name: 'Andorra', version: 'v1', basePath: '/a', bytes: 5000000),
  });

  Future<_FakeMaps> pump(WidgetTester tester, {Map<String, RegionDownload> downloads = const {}}) async {
    final fake = _FakeMaps(installed);
    final container = ProviderContainer(overrides: [
      regionCatalogProvider.overrideWith((ref) async => catalog),
      offlineMapsProvider.overrideWith(() => fake),
    ]);
    addTearDown(container.dispose);
    downloads.forEach(container.read(regionDownloadsProvider.notifier).set);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: OfflineMapsPage()),
    ));
    await tester.pumpAndSettle();
    return fake;
  }

  String subtitleOf(WidgetTester tester, String id) {
    final tile = find.byKey(ValueKey('region-$id'));
    return tester
        .widgetList<Text>(find.descendant(of: tile, matching: find.byType(Text)))
        .map((t) => t.data)
        .join(' | ');
  }

  testWidgets('resume lo descargado y lista las zonas del catálogo', (tester) async {
    await pump(tester);
    expect(find.text('Descargado: 2 zonas · 85 MB'), findsOneWidget);
    for (final name in ['Cantabria', 'Navarra', 'Andorra', 'La Rioja']) {
      expect(find.text(name), findsOneWidget);
    }
  });

  testWidgets('cada zona muestra su estado', (tester) async {
    await pump(tester, downloads: {
      'la-rioja': const RegionDownload(received: 15000000, total: 30000000),
    });
    // Sin descargar: tamaño con curvas.
    expect(subtitleOf(tester, 'cantabria'), contains('100 MB'));
    // Descargada y al día.
    expect(subtitleOf(tester, 'navarra'), contains('Descargado · 80 MB'));
    expect(subtitleOf(tester, 'navarra'), isNot(contains('versión nueva')));
    // Descargada de una versión vieja y sin curvas.
    expect(subtitleOf(tester, 'andorra'), contains('sin curvas'));
    expect(subtitleOf(tester, 'andorra'), contains('hay una versión nueva'));
    // Descargando.
    expect(subtitleOf(tester, 'la-rioja'), contains('15 MB de 30 MB'));
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
  });

  testWidgets('sin curvas de nivel el tamaño ofrecido baja', (tester) async {
    await pump(tester);
    await tester.tap(find.byKey(const ValueKey('with-contours')));
    await tester.pumpAndSettle();
    expect(subtitleOf(tester, 'cantabria'), contains('60 MB'));
  });

  testWidgets('descargar pide confirmación con el tamaño y descarga', (tester) async {
    final fake = await pump(tester);
    await tester.tap(find.descendant(
      of: find.byKey(const ValueKey('region-cantabria')),
      matching: find.byTooltip('Descargar'),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Descargar Cantabria'), findsOneWidget);
    expect(find.textContaining('100 MB, con curvas de nivel'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Descargar'));
    await tester.pumpAndSettle();
    expect(fake.downloaded, [('cantabria', 'v2', true)]);
  });

  test('formatBytes', () {
    expect(formatBytes(408320134), '408 MB');
    expect(formatBytes(3500000), '3,5 MB');
    expect(formatBytes(312000), '312 KB');
  });
}
