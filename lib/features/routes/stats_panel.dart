import 'package:flutter/material.dart';

import '../../core/format.dart';
import 'route_models.dart';

class StatsPanel extends StatelessWidget {
  const StatsPanel({super.key, required this.stats});

  final RouteStats stats;

  @override
  Widget build(BuildContext context) {
    final items = <(IconData, String, String)>[
      (Icons.straighten, 'Distancia', formatDistance(stats.distanceM)),
      (Icons.trending_up, 'Desnivel +', formatElevation(stats.elevationGainM)),
      (Icons.trending_down, 'Desnivel −', formatElevation(stats.elevationLossM)),
      if (stats.minEleM != null && stats.maxEleM != null) ...[
        (Icons.south, 'Alt. mín.', formatElevation(stats.minEleM!)),
        (Icons.north, 'Alt. máx.', formatElevation(stats.maxEleM!)),
      ],
      if (stats.duration != null)
        (Icons.timer_outlined, 'Duración', formatDuration(stats.duration!)),
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final (icon, label, value) in items)
            _StatChip(icon: icon, label: label, value: value),
        ],
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  const _StatChip({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 20, color: theme.colorScheme.primary),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: theme.textTheme.labelSmall),
              Text(value,
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w600)),
            ],
          ),
        ],
      ),
    );
  }
}
