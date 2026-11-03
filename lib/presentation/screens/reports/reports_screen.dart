import '../../widgets/app_date_picker.dart';
import '../../widgets/page_loading.dart';
import 'package:expencify/presentation/theme/app_icons.dart';
import 'weekly_recap_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import '../../../application/blocs/account/account_bloc.dart';
import '../../../application/blocs/account/account_event.dart';
import '../../../application/blocs/account/account_state.dart';
import '../../../application/services/reports/insight_period.dart';
import '../../../domain/repositories/transaction_repository.dart';
import 'category_detail_screen.dart';

class ReportsScreen extends StatefulWidget {
  final DateTime Function()? now;
  const ReportsScreen({super.key, this.now});
  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  String _share(double fraction) => fraction > 0 && fraction < .001
      ? '<0.1%'
      : '${(fraction * 100).toStringAsFixed(1)}%';

  final _money = NumberFormat.currency(
    locale: 'en_IN',
    symbol: '₹',
    decimalDigits: 2,
  );
  InsightPeriod _period = InsightPeriod.thisMonth;
  DateTimeRange? _custom;
  InsightWindow? _window;
  List<MapEntry<String, double>> _entries = [];
  double? _previous;
  int? _accountId;
  String _accountName = 'All accounts';
  Object? _dataScope;
  bool _hasData = false;
  bool _loading = true, _comparisonFailed = false;
  String? _error;
  int _request = 0;
  static const _colors = [
    Color(0xFF7C3AED),
    Color(0xFF0284C7),
    Color(0xFFDB2777),
    Color(0xFFB45309),
    Color(0xFF047857),
    Color(0xFF64748B),
  ];
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final request = ++_request;
    final state = context.read<AccountBloc>().state;
    final id = state is AccountLoaded ? state.selectedAccountId : null;
    final name = state is AccountLoaded
        ? state.selectedAccount?.name ?? 'All accounts'
        : 'All accounts';
    final window = InsightWindow.build(
      _period,
      widget.now?.call() ?? DateTime.now(),
      customFrom: _custom?.start,
      customTo: _custom?.end,
    );
    final repo = context.read<TransactionRepository>();
    final scope = (id, _period, _custom?.start, _custom?.end);
    setState(() {
      _loading = true;
      _hasData = _dataScope == scope;
      _error = null;
      _accountId = id;
      _accountName = name;
      _window = window;
    });
    var comparisonFailed = false;
    try {
      final results = await Future.wait<Map<String, double>?>([
        repo.getCategoryTotals(
          type: 'expense',
          from: window.from,
          to: window.to,
          accountId: id,
        ),
        if (window.hasComparison)
          repo
              .getCategoryTotals(
                type: 'expense',
                from: window.previousFrom,
                to: window.previousTo,
                accountId: id,
              )
              .then<Map<String, double>?>((v) => v)
              .catchError((Object _) {
                comparisonFailed = true;
                return null;
              }),
      ]);
      if (!mounted || request != _request) return;
      setState(() {
        _entries = insightEntries(results.first!);
        _previous = results.length > 1 && results[1] != null
            ? insightTotal(insightEntries(results[1]!))
            : null;
        _comparisonFailed = comparisonFailed;
        _dataScope = scope;
        _hasData = true;
        _loading = false;
      });
    } catch (_) {
      if (!mounted || request != _request) return;
      setState(() {
        _loading = false;
        _error = 'Could not load Insights.';
      });
    }
  }

  Future<void> _choosePeriod() async {
    final selected = await showModalBottomSheet<InsightPeriod>(
      context: context,
      showDragHandle: true,
      useSafeArea: true,
      builder: (ctx) => SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: InsightPeriod.values
              .map(
                (p) => ListTile(
                  title: Text(p.label),
                  trailing: p == _period ? const Icon(AppIcons.check) : null,
                  onTap: () => Navigator.pop(ctx, p),
                ),
              )
              .toList(),
        ),
      ),
    );
    if (!mounted || selected == null) return;
    if (selected == InsightPeriod.custom) {
      final now = widget.now?.call() ?? DateTime.now();
      final range = await showAppDateRangePicker(
        context: context,
        firstDate: DateTime(2000),
        lastDate: now,
        initialDateRange: _custom,
      );
      if (!mounted || range == null) return;
      setState(() {
        _period = selected;
        _custom = range;
      });
    } else {
      setState(() {
        _period = selected;
        _custom = null;
      });
    }
    await _load();
  }

  Future<void> _chooseAccount() async {
    final state = context.read<AccountBloc>().state;
    if (state is! AccountLoaded) return;
    final selected = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      useSafeArea: true,
      builder: (ctx) => SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: const Text('All accounts'),
              trailing: state.selectedAccountId == null
                  ? const Icon(AppIcons.check)
                  : null,
              onTap: () => Navigator.pop(ctx, -1),
            ),
            ...state.accounts.map(
              (a) => ListTile(
                title: Text(a.name),
                subtitle: Text(a.bankName),
                trailing: state.selectedAccountId == a.id
                    ? const Icon(AppIcons.check)
                    : null,
                onTap: () => Navigator.pop(ctx, a.id),
              ),
            ),
          ],
        ),
      ),
    );
    if (!mounted || selected == null) return;
    context.read<AccountBloc>().add(
      SelectAccount(selected == -1 ? null : selected),
    );
  }

  Future<void> _openCategory(String name) async {
    final window = _window!;
    final accountId = _accountId;
    final accountName = _accountName;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CategoryDetailScreen(
          category: name,
          type: 'expense',
          accountId: accountId,
          accountLabel: accountName,
          from: window.from,
          to: window.to,
        ),
      ),
    );
    if (mounted) _load();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return BlocListener<AccountBloc, AccountState>(
      listener: (_, state) {
        if (state is AccountLoaded) _load();
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Insights'),
          actions: [
            IconButton(
              tooltip: 'Weekly recap',
              icon: const Icon(AppIcons.dateRange),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const WeeklyRecapScreen()),
              ),
            ),
            IconButton(
              tooltip: 'Refresh Insights',
              onPressed: _loading ? null : _load,
              icon: const Icon(AppIcons.refresh),
            ),
          ],
        ),
        body: LoadingFeedback(
          loading: _loading && _hasData,
          error: _hasData ? _error : null,
          onRetry: _load,
          child: RefreshIndicator(
            onRefresh: _load,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
              children: [
                LayoutBuilder(
                  builder: (context, c) {
                    final stack =
                        c.maxWidth < 340 ||
                        MediaQuery.textScalerOf(context).scale(1) > 1.3;
                    final account = OutlinedButton.icon(
                      onPressed: _chooseAccount,
                      icon: const Icon(AppIcons.accounts, size: 18),
                      label: Text(
                        _accountName,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    );
                    final period = OutlinedButton.icon(
                      onPressed: _choosePeriod,
                      icon: const Icon(AppIcons.calendar, size: 18),
                      label: Text(_period.label),
                    );
                    return stack
                        ? Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              account,
                              const SizedBox(height: 8),
                              period,
                            ],
                          )
                        : Row(
                            children: [
                              Expanded(child: account),
                              const SizedBox(width: 12),
                              Expanded(child: period),
                            ],
                          );
                  },
                ),
                const SizedBox(height: 20),
                if (_loading && !_hasData)
                  const Padding(
                    padding: EdgeInsets.zero,
                    child: SizedBox(
                      height: 420,
                      child: PageLoading(
                        summary: true,
                        label: 'Loading report',
                      ),
                    ),
                  )
                else if (_error != null && !_hasData)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 48),
                    child: Column(
                      children: [
                        const Icon(Icons.cloud_off_outlined, size: 40),
                        const SizedBox(height: 16),
                        Text(_error!),
                        const SizedBox(height: 12),
                        FilledButton(
                          onPressed: _load,
                          child: const Text('Try again'),
                        ),
                      ],
                    ),
                  )
                else ...[
                  _summary(theme),
                  const SizedBox(height: 24),
                  if (_entries.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 40),
                      child: Text(
                        'No expenses recorded in this period.',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyLarge,
                      ),
                    )
                  else ...[
                    _distribution(theme),
                    const SizedBox(height: 24),
                    Text(
                      '${_entries.length} ${_entries.length == 1 ? 'category' : 'categories'}',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 12),
                    ..._entries.asMap().entries.map(
                      (e) => _category(
                        e.value,
                        _colors[e.key < 5 ? e.key : 5],
                        theme,
                      ),
                    ),
                  ],
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _summary(ThemeData theme) {
    final total = insightTotal(_entries);
    String? comparison;
    if (_window!.hasComparison) {
      final label = insightRangeLabel(
        _window!.previousFrom,
        _window!.previousTo,
      );
      if (_comparisonFailed) {
        comparison = 'Comparison unavailable';
      } else if (_previous == 0) {
        comparison = 'No expenses recorded in $label';
      } else if (_previous != null) {
        final delta = ((total - _previous!) * 100).round() / 100;
        comparison = delta == 0
            ? 'Same recorded spending as $label'
            : '${_money.format(delta.abs())} ${delta > 0 ? 'more' : 'less'} than $label';
      }
    }
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer.withValues(alpha: .3),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Total spent', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          Text(
            _money.format(total),
            style: theme.textTheme.headlineLarge?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            insightRangeLabel(_window!.from, _window!.to),
            style: theme.textTheme.bodyMedium,
          ),
          if (comparison != null) ...[
            const SizedBox(height: 12),
            Text(
              comparison,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          if (_comparisonFailed)
            TextButton(onPressed: _load, child: const Text('Retry comparison')),
        ],
      ),
    );
  }

  Widget _distribution(ThemeData theme) {
    final slices = insightSlices(_entries);
    final total = insightTotal(_entries);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Spending by category',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 16),
        Semantics(
          label: slices
              .map((e) => '${e.key}: ${_money.format(e.value)}')
              .join(', '),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: SizedBox(
              height: 24,
              width: double.infinity,
              child: CustomPaint(
                painter: _DistributionPainter(
                  slices.map((e) => e.value / total).toList(),
                  _colors,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 14),
        LayoutBuilder(
          builder: (context, c) => Wrap(
            spacing: 14,
            runSpacing: 10,
            children: slices
                .asMap()
                .entries
                .map(
                  (e) => ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: c.maxWidth),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: _colors[e.key],
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            '${e.value.key} · ${_share(e.value.value / total)}',
                            style: theme.textTheme.bodySmall,
                          ),
                        ),
                      ],
                    ),
                  ),
                )
                .toList(),
          ),
        ),
      ],
    );
  }

  Widget _category(MapEntry<String, double> e, Color color, ThemeData theme) {
    final percent = e.value / insightTotal(_entries);
    final text = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          e.key,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '${_share(percent)} of recorded spending',
          style: theme.textTheme.bodySmall,
        ),
      ],
    );
    final amount = Text(
      _money.format(e.value),
      style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
    );
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 0,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => _openCategory(e.key),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (MediaQuery.textScalerOf(context).scale(1) > 1.3) ...[
                text,
                const SizedBox(height: 10),
                amount,
              ] else
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: text),
                    const SizedBox(width: 12),
                    Flexible(child: amount),
                    const SizedBox(width: 6),
                    const Icon(AppIcons.chevron, size: 18),
                  ],
                ),
              const SizedBox(height: 14),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: percent,
                  minHeight: 5,
                  color: color,
                  backgroundColor: color.withValues(alpha: .1),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DistributionPainter extends CustomPainter {
  final List<double> fractions;
  final List<Color> colors;
  _DistributionPainter(this.fractions, this.colors);
  @override
  void paint(Canvas canvas, Size size) {
    var left = 0.0;
    for (var i = 0; i < fractions.length; i++) {
      final right = i == fractions.length - 1
          ? size.width
          : left + size.width * fractions[i];
      canvas.drawRect(
        Rect.fromLTRB(left, 0, right, size.height),
        Paint()..color = colors[i],
      );
      left = right;
    }
  }

  @override
  bool shouldRepaint(covariant _DistributionPainter old) =>
      !_same(old.fractions, fractions);
  bool _same(List<double> a, List<double> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
