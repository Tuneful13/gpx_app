import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'offline_maps.dart';
import 'region_catalog.dart';

String formatBytes(int bytes) {
  const mb = 1000 * 1000;
  if (bytes >= 10 * mb) return '${(bytes / mb).round()} MB';
  if (bytes >= mb) return '${(bytes / mb).toStringAsFixed(1).replaceAll('.', ',')} MB';
  return '${(bytes / 1000).round()} KB';
}

/// Lista de zonas del catálogo para descargar, actualizar o borrar.
class OfflineMapsPage extends ConsumerStatefulWidget {
  const OfflineMapsPage({super.key});

  @override
  ConsumerState<OfflineMapsPage> createState() => _OfflineMapsPageState();
}

class _OfflineMapsPageState extends ConsumerState<OfflineMapsPage> {
  bool _withContours = true;

  Future<void> _download(MapRegion region, String version) async {
    final installed = ref.read(offlineMapsProvider).asData?.value.regions[region.id];
    final updating = installed != null && installed.version != version;
    final bytes = region.base.bytes + (_withContours ? region.contours.bytes : 0);
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('${updating ? 'Actualizar' : 'Descargar'} ${region.name}'),
        content: Text(
          '${formatBytes(bytes)}${_withContours ? ', con curvas de nivel' : ', sin curvas de nivel'}.\n\n'
          'Mejor con wifi. Si se corta, al reintentar seguirá donde se quedó.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Descargar')),
        ],
      ),
    );
    if (ok != true) return;
    await ref
        .read(offlineMapsProvider.notifier)
        .download(region, version, withContours: _withContours);
  }

  Future<void> _delete(String id, String name) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('¿Borrar $name?'),
        content: const Text('Podrás volver a descargarlo cuando quieras.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Borrar')),
        ],
      ),
    );
    if (ok == true) await ref.read(offlineMapsProvider.notifier).delete(id);
  }

  @override
  Widget build(BuildContext context) {
    final catalog = ref.watch(regionCatalogProvider);
    final installed = ref.watch(offlineMapsProvider).asData?.value ?? const OfflineMaps();
    final downloads = ref.watch(regionDownloadsProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Mapas offline')),
      body: RefreshIndicator(
        onRefresh: () => ref.refresh(regionCatalogProvider.future).then((_) {}, onError: (_) {}),
        child: ListView(
          padding: const EdgeInsets.only(bottom: 24),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
              child: Text(
                installed.regions.isEmpty
                    ? 'Sin mapas descargados: se usa el mapa online de OpenStreetMap, '
                        'que necesita conexión.'
                    : 'Descargado: ${installed.regions.length} '
                        '${installed.regions.length == 1 ? 'zona' : 'zonas'} · '
                        '${formatBytes(installed.totalBytes)}',
                key: const ValueKey('offline-summary'),
                style: theme.textTheme.bodyMedium,
              ),
            ),
            SwitchListTile(
              key: const ValueKey('with-contours'),
              title: const Text('Incluir curvas de nivel'),
              subtitle: const Text('Ocupan bastante en las zonas de montaña.'),
              value: _withContours,
              onChanged: (v) => setState(() => _withContours = v),
            ),
            const Divider(),
            ...catalog.when(
              loading: () => [
                const Padding(
                  padding: EdgeInsets.all(32),
                  child: Center(child: CircularProgressIndicator()),
                ),
              ],
              error: (e, _) => [
                ListTile(
                  key: const ValueKey('catalog-error'),
                  leading: const Icon(Icons.cloud_off),
                  title: const Text('No se pudo cargar la lista de mapas'),
                  subtitle: const Text('Comprueba la conexión.'),
                  trailing: TextButton(
                    onPressed: () => ref.invalidate(regionCatalogProvider),
                    child: const Text('Reintentar'),
                  ),
                ),
                // Sin catálogo, al menos se pueden borrar los ya descargados.
                for (final r in installed.regions.values)
                  ListTile(
                    title: Text(r.name),
                    subtitle: Text('Descargado · ${formatBytes(r.bytes)}'),
                    trailing: IconButton(
                      tooltip: 'Borrar',
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () => _delete(r.id, r.name),
                    ),
                  ),
              ],
              data: (c) => [
                for (final region in c.regions)
                  _RegionTile(
                    region: region,
                    installed: installed.regions[region.id],
                    download: downloads[region.id],
                    catalogVersion: c.version,
                    withContours: _withContours,
                    onDownload: () => _download(region, c.version),
                    onCancel: () => ref.read(offlineMapsProvider.notifier).cancel(region.id),
                    onDelete: () => _delete(region.id, region.name),
                  ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: Text(
                'Mapas: © OpenStreetMap contributors · © OpenMapTiles. '
                'Curvas de nivel: © Copernicus DEM GLO-30.',
                style: theme.textTheme.bodySmall,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RegionTile extends StatelessWidget {
  const _RegionTile({
    required this.region,
    required this.installed,
    required this.download,
    required this.catalogVersion,
    required this.withContours,
    required this.onDownload,
    required this.onCancel,
    required this.onDelete,
  });

  final MapRegion region;
  final InstalledRegion? installed;
  final RegionDownload? download;
  final String catalogVersion;
  final bool withContours;
  final VoidCallback onDownload;
  final VoidCallback onCancel;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final d = download;
    final inst = installed;
    final key = ValueKey('region-${region.id}');

    // Descargando
    if (d != null && d.error == null) {
      return ListTile(
        key: key,
        title: Text(region.name),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 6),
            LinearProgressIndicator(value: d.fraction),
            const SizedBox(height: 4),
            Text('${formatBytes(d.received)} de ${formatBytes(d.total)}'),
          ],
        ),
        trailing: IconButton(
          tooltip: 'Cancelar',
          icon: const Icon(Icons.close),
          onPressed: onCancel,
        ),
      );
    }

    final String status;
    final List<Widget> actions;
    if (d?.error != null) {
      status = d!.error!;
      actions = [
        IconButton(tooltip: 'Reintentar', icon: const Icon(Icons.refresh), onPressed: onDownload),
      ];
    } else if (inst == null) {
      final size = region.base.bytes + (withContours ? region.contours.bytes : 0);
      status = formatBytes(size);
      actions = [
        IconButton(tooltip: 'Descargar', icon: const Icon(Icons.download), onPressed: onDownload),
      ];
    } else {
      final outdated = inst.version != catalogVersion;
      final needsContours = withContours && inst.contoursPath == null;
      status = [
        'Descargado · ${formatBytes(inst.bytes)}',
        if (inst.contoursPath == null) 'sin curvas',
        if (outdated) 'hay una versión nueva',
      ].join(' · ');
      actions = [
        if (outdated || needsContours)
          IconButton(
            tooltip: outdated ? 'Actualizar' : 'Añadir curvas de nivel',
            icon: Icon(outdated ? Icons.system_update_alt : Icons.add),
            onPressed: onDownload,
          ),
        IconButton(tooltip: 'Borrar', icon: const Icon(Icons.delete_outline), onPressed: onDelete),
      ];
    }

    return ListTile(
      key: key,
      leading: Icon(
        inst == null ? Icons.map_outlined : Icons.check_circle,
        color: inst == null ? null : theme.colorScheme.primary,
      ),
      title: Text(region.name),
      subtitle: Text(
        status,
        style: d?.error != null ? TextStyle(color: theme.colorScheme.error) : null,
      ),
      trailing: Row(mainAxisSize: MainAxisSize.min, children: actions),
    );
  }
}
