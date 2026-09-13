import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../db.dart';
import '../theme.dart';
import '../widgets/common.dart';

class TrendsScreen extends StatefulWidget {
  const TrendsScreen({super.key});
  @override
  State<TrendsScreen> createState() => _TrendsScreenState();
}

class _TrendsScreenState extends State<TrendsScreen> {
  List<DailyLog> _logs = [];
  List<Shot> _shots = [];

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    final l = await AppDb.instance.logs(days: 90);
    final s = await AppDb.instance.shots();
    if (mounted) {
      setState(() {
        _logs = l;
        _shots = s;
      });
    }
  }

  Widget _chart(String emoji, String title, List<FlSpot> spots, Color color,
      {double? minY, String? caption}) {
    final scheme = Theme.of(context).colorScheme;
    if (spots.length < 2) {
      return SoftCard(
        child: Row(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                  shape: BoxShape.circle, color: color.withValues(alpha: .15)),
              alignment: Alignment.center,
              child: const Text('🌱', style: TextStyle(fontSize: 26)),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: Theme.of(context).textTheme.titleMedium),
                  Text('Log a few more days and your trend will sprout here.',
                      style: TextStyle(
                          fontSize: 12, color: scheme.onSurfaceVariant)),
                ],
              ),
            ),
          ],
        ),
      );
    }
    final shotDays =
        _shots.map((s) => DateFormat('yyyy-MM-dd').format(s.takenAt)).toSet();
    return SoftCard(
      padding: const EdgeInsets.fromLTRB(12, 16, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 6),
            child: Row(
              children: [
                Text('$emoji ', style: const TextStyle(fontSize: 18)),
                Text(title, style: Theme.of(context).textTheme.titleMedium),
              ],
            ),
          ),
          if (caption != null)
            Padding(
              padding: const EdgeInsets.only(left: 6, top: 2),
              child: Text(caption,
                  style: TextStyle(
                      fontSize: 12.5, color: scheme.onSurfaceVariant)),
            ),
          const SizedBox(height: 14),
          SizedBox(
            height: 200,
            child: LineChart(
              LineChartData(
                minY: minY,
                lineBarsData: [
                  LineChartBarData(
                    spots: spots,
                    color: color,
                    isCurved: true,
                    curveSmoothness: .3,
                    preventCurveOverShooting: true,
                    barWidth: 3.5,
                    isStrokeCapRound: true,
                    dotData: FlDotData(
                      show: spots.length <= 14,
                      getDotPainter: (_, __, ___, ____) => FlDotCirclePainter(
                          radius: 4,
                          color: Colors.white,
                          strokeWidth: 2.5,
                          strokeColor: color),
                    ),
                    belowBarData: BarAreaData(
                      show: true,
                      gradient: LinearGradient(
                        colors: [
                          color.withValues(alpha: .35),
                          color.withValues(alpha: 0)
                        ],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                      ),
                    ),
                  ),
                ],
                lineTouchData: LineTouchData(
                  touchTooltipData: LineTouchTooltipData(
                    getTooltipColor: (_) => Palette.ink,
                    getTooltipItems: (spots) => [
                      for (final s in spots)
                        LineTooltipItem(
                          s.y.toStringAsFixed(
                              s.y == s.y.roundToDouble() ? 0 : 1),
                          const TextStyle(
                              color: Colors.white, fontWeight: FontWeight.w800),
                        ),
                    ],
                  ),
                ),
                // Vertical lines on shot days so side effects can be read against dose timing.
                extraLinesData: ExtraLinesData(
                  verticalLines: [
                    for (var i = 0; i < _logs.length; i++)
                      if (shotDays.contains(_logs[i].day))
                        VerticalLine(
                          x: i.toDouble(),
                          color: scheme.onSurfaceVariant.withValues(alpha: .35),
                          strokeWidth: 1.5,
                          dashArray: [5, 5],
                        ),
                  ],
                ),
                titlesData: FlTitlesData(
                  topTitles: const AxisTitles(),
                  rightTitles: const AxisTitles(),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 36,
                      getTitlesWidget: (v, _) => Text(
                        v.toStringAsFixed(0),
                        style: TextStyle(
                            fontSize: 11.5, color: scheme.onSurfaceVariant),
                      ),
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 24,
                      interval: (_logs.length / 4).ceilToDouble().clamp(1, 30),
                      getTitlesWidget: (v, _) {
                        final i = v.toInt();
                        if (i < 0 || i >= _logs.length) return const SizedBox();
                        return Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            DateFormat('M/d')
                                .format(DateTime.parse(_logs[i].day)),
                            style: TextStyle(
                                fontSize: 11.5, color: scheme.onSurfaceVariant),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                gridData: FlGridData(
                  drawVerticalLine: false,
                  getDrawingHorizontalLine: (_) => FlLine(
                      color: scheme.outlineVariant.withValues(alpha: .35),
                      strokeWidth: 1),
                ),
                borderData: FlBorderData(show: false),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final weight = <FlSpot>[];
    final se = <FlSpot>[];
    for (var i = 0; i < _logs.length; i++) {
      if (_logs[i].weightKg != null) {
        weight.add(FlSpot(i.toDouble(), _logs[i].weightKg!));
      }
      se.add(FlSpot(i.toDouble(), _logs[i].sideEffectTotal.toDouble()));
    }
    final delta = weight.length >= 2 ? weight.last.y - weight.first.y : null;
    final avgSe = _logs.isEmpty
        ? null
        : _logs.fold<int>(0, (a, l) => a + l.sideEffectTotal) / _logs.length;

    return RefreshIndicator(
      onRefresh: load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
        children: [
          Text('Your journey',
              style: Theme.of(context).textTheme.headlineSmall),
          Text(
              'Last ${_logs.length} check-in${_logs.length == 1 ? '' : 's'} at a glance',
              style: TextStyle(
                  color: scheme.onSurfaceVariant, fontWeight: FontWeight.w600)),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _Stat(
                  emoji: '⚖️',
                  color: Palette.lavender,
                  value: delta == null
                      ? '—'
                      : '${delta > 0 ? '+' : ''}${delta.toStringAsFixed(1)}',
                  label: 'kg change',
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _Stat(
                  emoji: '😌',
                  color: Palette.peach,
                  value: avgSe == null ? '—' : avgSe.toStringAsFixed(1),
                  label: 'avg side effects',
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _Stat(
                  emoji: '✅',
                  color: Palette.mint,
                  value: '${_logs.length}',
                  label: 'check-ins',
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          _chart('⚖️', 'Weight (kg)', weight, Palette.lavender),
          const SizedBox(height: 14),
          _chart(
            '🩺',
            'Side-effect score',
            se,
            Palette.coral,
            minY: 0,
            caption: 'Dashed lines mark shot days',
          ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat(
      {required this.emoji,
      required this.color,
      required this.value,
      required this.label});
  final String emoji;
  final Color color;
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SoftCard(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
      color: color.withValues(alpha: .14),
      child: Column(
        children: [
          Text(emoji, style: const TextStyle(fontSize: 22)),
          const SizedBox(height: 6),
          Text(value,
              style:
                  const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          Text(label,
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 11.5,
                  color: scheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
