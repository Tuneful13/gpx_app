import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../elevation/elevation_chart.dart';
import '../map/map_view.dart';
import '../navigation/navigation_page.dart';
import '../settings/settings_page.dart';
import 'route_providers.dart';
import 'stats_panel.dart';

class ViewerPage extends ConsumerStatefulWidget {
  const ViewerPage({super.key});

  @override
  ConsumerState<ViewerPage> createState() => _ViewerPageState();
}

class _ViewerPageState extends ConsumerState<ViewerPage> {
  int? _selectedIndex;

  Future<void> _startRoute(LoadedRoute loaded) async {
    final choice = await showModalBottomSheet<_StartChoice>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => const _StartSheet(),
    );
    if (choice == null || !mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => NavigationPage(
          loaded: loaded,
          simulate: choice.simulate,
          simSpeedMps: choice.speedMps,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(viewerProvider);
    final controller = ref.read(viewerProvider.notifier);

    ref.listen(viewerProvider, (prev, next) {
      if (next.error != null && next.error != prev?.error) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(next.error!)));
        controller.clearError();
      }
      if (next.loaded != prev?.loaded) _selectedIndex = null;
    });

    final loaded = state.loaded;

    return Scaffold(
      appBar: AppBar(
        title: Text(loaded?.route.name ?? 'GPX App'),
        actions: [
          IconButton(
            tooltip: 'Abrir GPX',
            icon: const Icon(Icons.folder_open),
            onPressed: state.loading ? null : controller.pickGpx,
          ),
          IconButton(
            tooltip: 'Ajustes',
            icon: const Icon(Icons.settings),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const SettingsPage()),
            ),
          ),
        ],
      ),
      // Botón grande a todo el ancho, abajo y bien a la vista.
      bottomNavigationBar: (loaded != null && loaded.route.points.length >= 2)
          ? SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: SizedBox(
                  height: 56,
                  width: double.infinity,
                  child: FilledButton.icon(
                    key: const ValueKey('start-route'),
                    onPressed: () => _startRoute(loaded),
                    icon: const Icon(Icons.navigation, size: 28),
                    label: const Text(
                      'Iniciar ruta',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
              ),
            )
          : null,
      body: loaded == null
          ? _EmptyState(loading: state.loading, onOpen: controller.pickGpx)
          : Column(
              children: [
                Expanded(
                  flex: 3,
                  child: MapView(
                    route: loaded.route,
                    highlight: _selectedIndex == null
                        ? null
                        : LatLng(
                            loaded.route.points[_selectedIndex!].lat,
                            loaded.route.points[_selectedIndex!].lon,
                          ),
                  ),
                ),
                StatsPanel(stats: loaded.stats),
                SizedBox(
                  height: 170,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(8, 8, 16, 8),
                    child: ElevationChart(
                      points: loaded.route.points,
                      cumulativeM: loaded.stats.cumulativeM,
                      onSelect: (i) {
                        if (i != _selectedIndex) setState(() => _selectedIndex = i);
                      },
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

class _StartChoice {
  const _StartChoice({required this.simulate, required this.speedMps});
  final bool simulate;
  final double speedMps;
}

class _StartSheet extends StatefulWidget {
  const _StartSheet();

  @override
  State<_StartSheet> createState() => _StartSheetState();
}

class _StartSheetState extends State<_StartSheet> {
  // En móvil se usa el GPS real por defecto; en escritorio solo tiene sentido simular.
  bool _simulate = defaultTargetPlatform != TargetPlatform.android &&
      defaultTargetPlatform != TargetPlatform.iOS;
  double _speed = 25;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Iniciar ruta', style: theme.textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(
              _simulate
                  ? 'Se recorrerá la ruta de forma simulada, con un desvío a '
                      'mitad de camino para probar el aviso de salida de ruta.'
                  : 'Se usará el GPS del dispositivo. Mantén la app abierta '
                      'o con la notificación de seguimiento activa.',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Simular recorrido (pruebas)'),
              value: _simulate,
              onChanged: (v) => setState(() => _simulate = v),
            ),
            if (_simulate) ...[
              const SizedBox(height: 4),
              SegmentedButton<double>(
                segments: const [
                  ButtonSegment(value: 1.5, label: Text('Paso normal')),
                  ButtonSegment(value: 8, label: Text('Rápido')),
                  ButtonSegment(value: 25, label: Text('Muy rápido')),
                ],
                selected: {_speed},
                onSelectionChanged: (s) => setState(() => _speed = s.first),
              ),
            ],
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () => Navigator.pop(
                  context,
                  _StartChoice(simulate: _simulate, speedMps: _speed),
                ),
                icon: const Icon(Icons.navigation),
                label: const Text('Empezar'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.loading, required this.onOpen});

  final bool loading;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.route, size: 72, color: theme.colorScheme.primary),
            const SizedBox(height: 16),
            Text('Abre un archivo GPX para ver tu ruta',
                style: theme.textTheme.titleMedium,
                textAlign: TextAlign.center),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: loading ? null : onOpen,
              icon: loading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.folder_open),
              label: const Text('Abrir GPX'),
            ),
          ],
        ),
      ),
    );
  }
}
