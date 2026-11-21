import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../routes/route_models.dart';

/// Índices de [n] elementos reducidos a como mucho [max], conservando
/// siempre el primero y el último. Mantiene la correspondencia con la ruta.
List<int> downsampleIndices(int n, int max) {
  if (n <= max) return List<int>.generate(n, (i) => i);
  final out = <int>[];
  final step = (n - 1) / (max - 1);
  for (var i = 0; i < max; i++) {
    out.add((i * step).round());
  }
  return out;
}

class ElevationChart extends StatelessWidget {
  const ElevationChart({
    super.key,
    required this.points,
    required this.cumulativeM,
    required this.onSelect,
  });

  final List<TrackPoint> points;
  final List<double> cumulativeM;

  /// Se llama con el índice del punto de la ruta tocado, o null al soltar.
  final ValueChanged<int?> onSelect;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final indices = downsampleIndices(points.length, 400)
        .where((i) => points[i].ele != null)
        .toList();

    if (indices.length < 2) {
      return const Center(child: Text('Esta ruta no tiene datos de altitud'));
    }

    final spots = [
      for (final i in indices) FlSpot(cumulativeM[i] / 1000, points[i].ele!),
    ];
    final eles = spots.map((s) => s.y);
    final minY = eles.reduce((a, b) => a < b ? a : b);
    final maxY = eles.reduce((a, b) => a > b ? a : b);
    final pad = ((maxY - minY) * 0.1).clamp(5, double.infinity).toDouble();

    return LineChart(
      LineChartData(
        minY: minY - pad,
        maxY: maxY + pad,
        gridData: const FlGridData(drawVerticalLine: false),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(),
          rightTitles: const AxisTitles(),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 44,
              getTitlesWidget: (v, meta) => SideTitleWidget(
                meta: meta,
                child: Text('${v.round()} m',
                    style: Theme.of(context).textTheme.labelSmall),
              ),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 24,
              getTitlesWidget: (v, meta) => SideTitleWidget(
                meta: meta,
                child: Text('${v.toStringAsFixed(v < 10 ? 1 : 0)} km',
                    style: Theme.of(context).textTheme.labelSmall),
              ),
            ),
          ),
        ),
        lineTouchData: LineTouchData(
          touchCallback: (event, response) {
            final touched = response?.lineBarSpots;
            if (!event.isInterestedForInteractions ||
                touched == null ||
                touched.isEmpty) {
              onSelect(null);
              return;
            }
            onSelect(indices[touched.first.spotIndex]);
          },
          touchTooltipData: LineTouchTooltipData(
            getTooltipItems: (spots) => [
              for (final s in spots)
                LineTooltipItem(
                  '${s.y.round()} m\n${s.x.toStringAsFixed(2)} km',
                  TextStyle(color: scheme.onInverseSurface, fontSize: 12),
                ),
            ],
          ),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: false,
            barWidth: 2.5,
            color: scheme.primary,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(
              show: true,
              color: scheme.primary.withValues(alpha: 0.15),
            ),
          ),
        ],
      ),
    );
  }
}
