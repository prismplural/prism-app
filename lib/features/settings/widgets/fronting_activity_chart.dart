import 'dart:math';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:prism_plurality/domain/models/fronting_analytics.dart';

/// Compact area chart showing daily fronting activity across a date range.
///
/// Renders only when at least 5 days contain session data.
/// Hidden axes, warm gradient fill, first/last date labels only.
class FrontingActivityChart extends StatelessWidget {
  const FrontingActivityChart({super.key, required this.dailyActivity});

  final List<DailyActivity> dailyActivity;

  @override
  Widget build(BuildContext context) {
    final daysWithData =
        dailyActivity.where((d) => d.totalMinutes > 0).toList();
    if (daysWithData.length < 5) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final maxMinutes = dailyActivity
        .map((d) => d.totalMinutes)
        .reduce(max)
        .toDouble();

    if (maxMinutes == 0) return const SizedBox.shrink();

    final spots = dailyActivity
        .asMap()
        .entries
        .map((e) => FlSpot(e.key.toDouble(), e.value.totalMinutes.toDouble()))
        .toList();

    final lineColor = theme.colorScheme.primary;
    final fillColor = theme.colorScheme.primary.withValues(alpha: 0.15);

    final peakIdx = dailyActivity.indexWhere(
        (d) => d.totalMinutes == maxMinutes.toInt());
    final peakHours = (maxMinutes / 60).toStringAsFixed(1);
    final avgMinutes = dailyActivity
            .map((d) => d.totalMinutes)
            .reduce((a, b) => a + b) /
        dailyActivity.length;
    final avgHours = (avgMinutes / 60).toStringAsFixed(1);

    final firstDate = _shortDate(dailyActivity.first.date);
    final lastDate = _shortDate(dailyActivity.last.date);

    final peakDate = peakIdx >= 0
        ? _shortDate(dailyActivity[peakIdx].date)
        : firstDate;

    return Semantics(
      label:
          'Fronting activity over the selected period. '
          'Peak: ${peakHours}h on $peakDate. '
          'Average: ${avgHours}h per day.',
      excludeSemantics: true,
      child: SizedBox(
        height: 80,
        child: LineChart(
          LineChartData(
            gridData: const FlGridData(show: false),
            borderData: FlBorderData(show: false),
            minY: 0,
            maxY: maxMinutes * 1.15,
            titlesData: FlTitlesData(
              show: true,
              leftTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false)),
              rightTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false)),
              topTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false)),
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 16,
                  getTitlesWidget: (value, meta) {
                    final idx = value.toInt();
                    final style = theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    );
                    if (idx == 0) {
                      return SideTitleWidget(
                        axisSide: meta.axisSide,
                        child: Text(firstDate, style: style),
                      );
                    }
                    if (idx == dailyActivity.length - 1) {
                      return SideTitleWidget(
                        axisSide: meta.axisSide,
                        child: Text(lastDate, style: style),
                      );
                    }
                    return const SizedBox.shrink();
                  },
                ),
              ),
            ),
            lineBarsData: [
              LineChartBarData(
                spots: spots,
                isCurved: true,
                curveSmoothness: 0.3,
                color: lineColor,
                barWidth: 1.5,
                dotData: const FlDotData(show: false),
                belowBarData: BarAreaData(
                  show: true,
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [fillColor, Colors.transparent],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _shortDate(DateTime d) => '${d.month}/${d.day}';
}
