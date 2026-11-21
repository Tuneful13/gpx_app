import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../../core/format.dart';
import '../map/map_view.dart';
import '../routes/route_providers.dart';
import 'location_source.dart';
import 'navigation_controller.dart';
import 'simulated_source.dart';

class NavigationPage extends ConsumerStatefulWidget {
  const NavigationPage({
    super.key,
    required this.loaded,
    this.simulate = false,
    this.simSpeedMps = 25,
  });

  final LoadedRoute loaded;

  /// Recorre la ruta simulada en vez de usar el GPS.
  final bool simulate;
  final double simSpeedMps;

  @override
  ConsumerState<NavigationPage> createState() => _NavigationPageState();
}

class _NavigationPageState extends ConsumerState<NavigationPage> {
  final _mapController = MapViewController();
  bool _follow = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  @override
  void dispose() {
    _mapController.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    LocationSource? source;
    if (widget.simulate) {
      source = SimulatedLocationSource(
        points: widget.loaded.route.points,
        cumulativeM: widget.loaded.stats.cumulativeM,
        speedMps: widget.simSpeedMps,
      );
    }
    await ref.read(navigationProvider.notifier).start(
          widget.loaded,
          source: source,
          simulated: widget.simulate,
        );
  }

  /// Centra el mapa en [pos]. Con rumbo conocido lo gira para que tu dirección
  /// de marcha quede hacia arriba, como Maps; sin rumbo conserva el giro actual.
  void _moveTo(LatLng pos, double? headingDeg) {
    // Si el mapa aún no está listo, aplicará esta cámara en cuanto lo esté.
    final zoom = math.max(_mapController.zoom, 16.0);
    if (headingDeg == null) {
      _mapController.move(pos, zoom);
    } else {
      _mapController.moveAndRotate(pos, zoom, headingUpRotation(headingDeg));
    }
  }

  Future<void> _confirmStop() async {
    final stop = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('¿Terminar la ruta?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Seguir'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Terminar'),
          ),
        ],
      ),
    );
    if (stop == true) await _finish();
  }

  Future<void> _finish() async {
    await ref.read(navigationProvider.notifier).stop();
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final nav = ref.watch(navigationProvider);
    final controller = ref.read(navigationProvider.notifier);

    ref.listen(navigationProvider, (prev, next) {
      final pos = next.position;
      if (_follow && pos != null && pos != prev?.position) {
        _moveTo(pos, next.headingDeg);
      }
    });

    if (nav.accessProblem != null) {
      return _AccessProblemView(
        message: nav.accessProblem!,
        issue: nav.accessIssue,
        onRetry: _start,
        onBack: () => Navigator.of(context).pop(),
      );
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmStop();
      },
      child: Scaffold(
        body: Stack(
          children: [
            Positioned.fill(
              child: MapView(
                route: widget.loaded.route,
                controller: _mapController,
                userPosition: nav.position,
                userHeadingDeg: nav.headingDeg,
                progress: nav.joinedRoute ? nav.match : null,
                onUserGesture: () {
                  if (_follow) setState(() => _follow = false);
                },
              ),
            ),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  children: [
                    if (nav.banner != null) _BannerCard(nav: nav),
                    if (nav.simulated)
                      const Padding(
                        padding: EdgeInsets.only(top: 8),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Chip(
                            avatar: Icon(Icons.science, size: 18),
                            label: Text('SIMULACIÓN'),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            if (!_follow && nav.position != null)
              Positioned(
                right: 16,
                bottom: 200,
                child: FloatingActionButton.small(
                  tooltip: 'Centrar en mi posición',
                  onPressed: () {
                    setState(() => _follow = true);
                    _moveTo(nav.position!, nav.headingDeg);
                  },
                  child: const Icon(Icons.my_location),
                ),
              ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: SafeArea(
                child: _BottomPanel(
                  nav: nav,
                  onToggleMute: controller.toggleMute,
                  onStop: nav.arrived ? _finish : _confirmStop,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BannerCard extends StatelessWidget {
  const _BannerCard({required this.nav});

  final NavState nav;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final banner = nav.banner!;
    final (bg, fg, icon) = switch (banner.kind) {
      BannerKind.warning => (
          scheme.errorContainer,
          scheme.onErrorContainer,
          Icons.warning_amber_rounded
        ),
      BannerKind.success => (
          scheme.primaryContainer,
          scheme.onPrimaryContainer,
          Icons.check_circle_outline
        ),
      BannerKind.info => (
          scheme.surface,
          scheme.onSurface,
          Icons.info_outline
        ),
    };

    return Card(
      color: bg,
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: fg),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    banner.text,
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(color: fg, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _BottomPanel extends StatelessWidget {
  const _BottomPanel({
    required this.nav,
    required this.onToggleMute,
    required this.onStop,
  });

  final NavState nav;
  final VoidCallback onToggleMute;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final speed = nav.speedMps;

    return Card(
      margin: const EdgeInsets.all(12),
      elevation: 6,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _Metric(label: 'Restante', value: formatDistance(nav.remainingM)),
                _Metric(label: 'Recorrido', value: formatDistance(nav.doneM)),
                _Metric(label: 'Tiempo', value: formatClock(nav.elapsed)),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              [
                if (speed != null) formatSpeedKmh(speed),
                if (nav.eta != null) 'Llegada en ${formatDuration(nav.eta!)}',
              ].join('  ·  '),
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                IconButton.filledTonal(
                  tooltip: nav.muted ? 'Activar voz' : 'Silenciar voz',
                  onPressed: onToggleMute,
                  icon: Icon(nav.muted ? Icons.volume_off : Icons.volume_up),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    style: nav.arrived
                        ? null
                        : FilledButton.styleFrom(
                            backgroundColor: theme.colorScheme.error,
                            foregroundColor: theme.colorScheme.onError,
                          ),
                    onPressed: onStop,
                    icon: Icon(nav.arrived ? Icons.check : Icons.stop),
                    label: Text(nav.arrived ? 'Finalizar' : 'Terminar ruta'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        Text(label, style: theme.textTheme.labelMedium),
        Text(
          value,
          style: theme.textTheme.headlineSmall
              ?.copyWith(fontWeight: FontWeight.w700),
        ),
      ],
    );
  }
}

class _AccessProblemView extends StatelessWidget {
  const _AccessProblemView({
    required this.message,
    required this.issue,
    required this.onRetry,
    required this.onBack,
  });

  final String message;
  final LocationAccess? issue;
  final VoidCallback onRetry;
  final VoidCallback onBack;

  Future<void> _openSettings() async {
    try {
      if (issue == LocationAccess.serviceDisabled) {
        await Geolocator.openLocationSettings();
      } else {
        await Geolocator.openAppSettings();
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final needsSettings = issue == LocationAccess.deniedForever ||
        issue == LocationAccess.serviceDisabled;
    return Scaffold(
      appBar: AppBar(title: const Text('No se puede iniciar')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.location_off, size: 64),
              const SizedBox(height: 16),
              Text(message, textAlign: TextAlign.center),
              const SizedBox(height: 24),
              if (needsSettings)
                FilledButton.icon(
                  onPressed: _openSettings,
                  icon: const Icon(Icons.settings),
                  label: const Text('Abrir ajustes'),
                ),
              const SizedBox(height: 8),
              OutlinedButton(onPressed: onRetry, child: const Text('Reintentar')),
              TextButton(onPressed: onBack, child: const Text('Volver')),
            ],
          ),
        ),
      ),
    );
  }
}
