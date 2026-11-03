import 'dart:math' as math;
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../domain/repositories/transaction_repository.dart';
import 'page_loading.dart';

/// Owns chart reads so changing its range never reloads the dashboard.
class HomeSpendingChart extends StatefulWidget {
  final TransactionRepository repository;
  final int? accountId;
  final int refreshToken;
  final String initialPeriod;
  final ValueChanged<String>? onPeriodChanged;
  final DateTime Function()? clock;
  const HomeSpendingChart({
    super.key,
    required this.repository,
    this.accountId,
    this.refreshToken = 0,
    this.initialPeriod = '7 Days',
    this.onPeriodChanged,
    this.clock,
  });

  @override
  State<HomeSpendingChart> createState() => _HomeSpendingChartState();
}

class _HomeSpendingChartState extends State<HomeSpendingChart> {
  late String _period = widget.initialPeriod;
  Map<String, double>? _data;
  DateTime _asOf = DateTime.now();
  bool _loading = true;
  String? _error;
  int _request = 0;
  final _money = NumberFormat.currency(
    locale: 'en_IN',
    symbol: '₹',
    decimalDigits: 2,
  );
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant HomeSpendingChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.accountId != widget.accountId ||
        oldWidget.repository != widget.repository) {
      _load(clear: true);
    } else if (oldWidget.refreshToken != widget.refreshToken) {
      _load();
    }
  }

  Future<void> _load({bool clear = false}) async {
    final request = ++_request;
    final period = _period;
    final now = (widget.clock ?? DateTime.now)();
    final today = DateTime(now.year, now.month, now.day);
    final from = period == 'This Year'
        ? DateTime(now.year)
        : today.subtract(Duration(days: period == '7 Days' ? 6 : 29));
    setState(() {
      if (clear) _data = null;
      if (_data == null) _asOf = now;
      _loading = true;
      _error = null;
    });
    try {
      // Daily totals preserve the account filter in every range, including Year.
      final daily = await widget.repository.getDailyTotals(
        type: 'expense',
        from: from,
        to: now,
        accountId: widget.accountId,
      );
      final data = <String, double>{};
      for (final entry in daily.entries) {
        final key = period == 'This Year'
            ? entry.key.substring(0, 7)
            : entry.key;
        data.update(key, (v) => v + entry.value, ifAbsent: () => entry.value);
      }
      if (!mounted || request != _request) return;
      setState(() {
        _data = data;
        _asOf = now;
        _loading = false;
      });
    } catch (_) {
      if (!mounted || request != _request) return;
      setState(() {
        _loading = false;
        _error = _data == null
            ? 'Could not load spending.'
            : 'Could not refresh spending.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final chartHeight =
        220.0 +
        (MediaQuery.textScalerOf(context).scale(12) / 12 - 1).clamp(0, 2) * 40;
    final total = _data?.values.fold(0.0, (a, b) => a + b) ?? 0;
    final today = DateTime(_asOf.year, _asOf.month, _asOf.day);
    final days = _period == 'This Year'
        ? today.difference(DateTime(today.year)).inDays + 1
        : _period == '7 Days'
        ? 7
        : 30;
    final subtitle = _period == 'This Year'
        ? 'Year to date · ${_asOf.year}'
        : '${DateFormat('d MMM').format(today.subtract(Duration(days: days - 1)))} – ${DateFormat('d MMM').format(today)}';
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Spending overview', style: theme.textTheme.titleMedium),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: SegmentedButton<String>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: '7 Days', label: Text('7D')),
                ButtonSegment(value: '30 Days', label: Text('30D')),
                ButtonSegment(value: 'This Year', label: Text('Year')),
              ],
              selected: {_period},
              onSelectionChanged: (values) {
                final value = values.single;
                if (value == _period) return;
                _period = value;
                widget.onPeriodChanged?.call(value);
                _load(clear: true);
              },
              style: const ButtonStyle(
                minimumSize: WidgetStatePropertyAll(Size(48, 48)),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: cs.surface,
              border: Border.all(color: cs.outlineVariant),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ...[
                  Text(
                    subtitle,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _data == null ? '—' : _money.format(total),
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    _data == null
                        ? ' '
                        : '${_money.format(total / days)} daily average',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
                if (_error != null) ...[
                  Text(_error!, style: TextStyle(color: cs.error)),
                  TextButton(onPressed: _load, child: const Text('Retry')),
                ],
                SizedBox(
                  height: 3,
                  child: _loading && _data != null
                      ? const LinearProgressIndicator()
                      : null,
                ),
                if (_data == null && _loading)
                  SizedBox(
                    height: chartHeight,
                    child: const PageLoading(label: 'Loading spending'),
                  )
                else if (_data != null && total == 0)
                  SizedBox(
                    height: chartHeight,
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.bar_chart_rounded,
                            size: 36,
                            color: cs.primary,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'No spending in this period',
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodyLarge,
                          ),
                        ],
                      ),
                    ),
                  )
                else if (_data != null)
                  _chart(context),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _chart(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final yearly = _period == 'This Year';
    final today = DateTime(_asOf.year, _asOf.month, _asOf.day);
    final count = yearly
        ? _asOf.month
        : _period == '7 Days'
        ? 7
        : 30;
    final dates = List.generate(
      count,
      (i) => yearly
          ? DateTime(today.year, i + 1)
          : today.subtract(Duration(days: count - 1 - i)),
    );
    final values = dates
        .map(
          (d) =>
              _data![DateFormat(yearly ? 'yyyy-MM' : 'yyyy-MM-dd').format(d)] ??
              0.0,
        )
        .toList();
    final highest = values.reduce((a, b) => a > b ? a : b);
    final roughStep = highest / 3;
    final magnitude = math
        .pow(10, (math.log(roughStep) / math.ln10).floor())
        .toDouble();
    final ratio = roughStep / magnitude;
    final interval =
        (ratio <= 1
            ? 1
            : ratio <= 2
            ? 2
            : ratio <= 5
            ? 5
            : 10) *
        magnitude;
    final maxY = (highest * 1.15 / interval).ceil() * interval;
    final scale = MediaQuery.textScalerOf(context).scale(12) / 12;
    return Semantics(
      label:
          'Spending by ${yearly ? 'month' : 'day'}. Highest spending ${_money.format(highest)} on ${DateFormat(yearly ? 'MMMM yyyy' : 'd MMMM yyyy').format(dates[values.indexOf(highest)])}. Tap a bar for its amount.',
      child: SizedBox(
        height: 220 + (scale - 1).clamp(0, 2) * 40,
        child: LayoutBuilder(
          builder: (context, constraints) => BarChart(
            BarChartData(
              minY: 0,
              maxY: maxY,
              gridData: FlGridData(
                horizontalInterval: interval,
                drawVerticalLine: false,
                getDrawingHorizontalLine: (_) => FlLine(
                  color: cs.outlineVariant.withValues(alpha: .5),
                  strokeWidth: 1,
                ),
              ),
              borderData: FlBorderData(show: false),
              barTouchData: BarTouchData(
                touchTooltipData: BarTouchTooltipData(
                  fitInsideHorizontally: true,
                  fitInsideVertically: true,
                  getTooltipColor: (_) => cs.inverseSurface,
                  getTooltipItem: (group, _, rod, _) => BarTooltipItem(
                    '${DateFormat(yearly ? 'MMMM yyyy' : 'EEE, d MMM').format(dates[group.x])}\n${_money.format(rod.toY)}',
                    TextStyle(
                      color: cs.onInverseSurface,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              titlesData: FlTitlesData(
                topTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
                rightTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 52 * scale.clamp(1, 1.5),
                    getTitlesWidget: (value, meta) => Text(
                      NumberFormat.compactCurrency(
                        locale: 'en_IN',
                        symbol: '₹',
                        decimalDigits: 0,
                      ).format(value),
                      style: TextStyle(
                        color: cs.onSurfaceVariant,
                        fontSize: 11,
                      ),
                    ),
                  ),
                ),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 32 * scale,
                    getTitlesWidget: (value, meta) {
                      final i = value.toInt();
                      if (i < 0 || i >= count) return const SizedBox.shrink();
                      final step = yearly
                          ? (constraints.maxWidth < 340 ? 3 : 2)
                          : count == 30
                          ? 7
                          : scale > 1.5
                          ? 2
                          : 1;
                      if (i % step != 0 && !(count == 30 && i == count - 1)) {
                        return const SizedBox.shrink();
                      }
                      if (count == 30 && i == 28) {
                        return const SizedBox.shrink();
                      }
                      return Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          DateFormat(
                            yearly
                                ? 'MMM'
                                : count == 30
                                ? 'd/M'
                                : 'E',
                          ).format(dates[i]),
                          style: TextStyle(
                            color: cs.onSurfaceVariant,
                            fontSize: 11,
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
              barGroups: List.generate(
                count,
                (i) => BarChartGroupData(
                  x: i,
                  barRods: [
                    BarChartRodData(
                      toY: values[i],
                      color: cs.primary,
                      width: ((constraints.maxWidth - 70) / count * .55).clamp(
                        2,
                        20,
                      ),
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(4),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
