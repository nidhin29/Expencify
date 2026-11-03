import '../../widgets/page_loading.dart';
import 'package:expencify/presentation/theme/app_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import '../../../application/services/reports/insight_period.dart';
import '../../../domain/entities/transaction.dart';
import '../../../domain/repositories/transaction_repository.dart';
import '../transactions/transaction_entry_screen.dart';

class CategoryDetailScreen extends StatefulWidget {
  final String category, type, accountLabel;
  final int? accountId;
  final DateTime? from, to;
  const CategoryDetailScreen({
    super.key,
    required this.category,
    required this.type,
    this.accountId,
    this.accountLabel = 'All accounts',
    this.from,
    this.to,
  });
  @override
  State<CategoryDetailScreen> createState() => _CategoryDetailScreenState();
}

class _CategoryDetailScreenState extends State<CategoryDetailScreen> {
  final _money = NumberFormat.currency(
    locale: 'en_IN',
    symbol: '₹',
    decimalDigits: 2,
  );
  Object? _dataScope;
  bool _hasData = false;
  bool _loading = true;
  String? _error;
  int _request = 0;
  List<TransactionModel> _transactions = [];
  List<MapEntry<String, double>> _merchants = [];
  double _total = 0;
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant CategoryDetailScreen old) {
    super.didUpdateWidget(old);
    if (old.category != widget.category ||
        old.type != widget.type ||
        old.accountId != widget.accountId ||
        old.from != widget.from ||
        old.to != widget.to) {
      _load();
    }
  }

  Future<void> _load() async {
    final request = ++_request;
    final repo = context.read<TransactionRepository>();
    final scope = (
      widget.category,
      widget.type,
      widget.accountId,
      widget.from,
      widget.to,
    );
    setState(() {
      _loading = true;
      _hasData = _dataScope == scope;
      _error = null;
    });
    try {
      final values = await repo.getTransactions(
        category: widget.category,
        leafOnly: true,
        type: widget.type,
        accountId: widget.accountId,
        from: widget.from,
        to: widget.to,
      );
      if (!mounted || request != _request) return;
      final merchants = <String, double>{};
      final labels = <String, String>{};
      for (final t in values) {
        final label = t.merchant.trim().isEmpty
            ? 'Unspecified merchant'
            : t.merchant.trim();
        final key = label.toLowerCase();
        labels.putIfAbsent(key, () => label);
        merchants.update(key, (v) => v + t.amount, ifAbsent: () => t.amount);
      }
      final entries = insightEntries(
        merchants.map((key, value) => MapEntry(labels[key]!, value)),
      );
      final totalCents = values.fold<int>(
        0,
        (sum, t) => sum + (t.amount * 100).round(),
      );
      setState(() {
        _transactions = values;
        _merchants = entries;
        _total = totalCents / 100;
        _dataScope = scope;
        _hasData = true;
        _loading = false;
      });
    } catch (_) {
      if (!mounted || request != _request) return;
      setState(() {
        _loading = false;
        _error = 'Could not load this category.';
      });
    }
  }

  Future<void> _edit(TransactionModel transaction) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => TransactionEntryScreen(existing: transaction),
      ),
    );
    if (mounted) _load();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.category),
        actions: [
          IconButton(
            tooltip: 'Refresh category',
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
          child: ListView.builder(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(20),
            itemCount: (!_hasData && (_loading || _error != null))
                ? 1
                : _transactions.length + 1,
            itemBuilder: (context, i) {
              if (_loading && !_hasData) {
                return const Padding(
                  padding: EdgeInsets.zero,
                  child: SizedBox(
                    height: 420,
                    child: PageLoading(summary: true, label: 'Loading report'),
                  ),
                );
              }
              if (_error != null && !_hasData) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 48),
                  child: Column(
                    children: [
                      const Icon(AppIcons.error, size: 40),
                      const SizedBox(height: 16),
                      Text(_error!),
                      const SizedBox(height: 12),
                      FilledButton(
                        onPressed: _load,
                        child: const Text('Try again'),
                      ),
                    ],
                  ),
                );
              }
              if (i == 0) return _header(theme);
              final t = _transactions[i - 1];
              return Card(
                elevation: 0,
                margin: const EdgeInsets.only(bottom: 10),
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: () => _edit(t),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: _amountRow(
                      t.merchant.isNotEmpty
                          ? t.merchant
                          : t.note.isNotEmpty
                          ? t.note
                          : 'Unspecified merchant',
                      DateFormat('d MMM y').format(t.date),
                      _money.format(t.amount),
                      theme,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _header(ThemeData theme) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Container(
        width: double.infinity,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: theme.colorScheme.primaryContainer.withValues(alpha: .3),
          borderRadius: BorderRadius.circular(24),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.type == 'income' ? 'Total received' : 'Total spent',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              _money.format(_total),
              style: theme.textTheme.headlineLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(insightRangeLabel(widget.from, widget.to)),
            const SizedBox(height: 6),
            Text(widget.accountLabel),
            const SizedBox(height: 8),
            Text(
              '${_transactions.length} ${_transactions.length == 1 ? 'transaction' : 'transactions'}',
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
      const SizedBox(height: 24),
      if (_transactions.isEmpty)
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 40),
          child: Center(child: Text('No transactions in this period.')),
        )
      else ...[
        Text(
          'Top merchants',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 12),
        ..._merchants
            .take(5)
            .map(
              (e) => Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Column(
                  children: [
                    _amountRow(
                      e.key,
                      '${(_total > 0 ? e.value / _total * 100 : 0).toStringAsFixed(1)}% of category',
                      _money.format(e.value),
                      theme,
                    ),
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: _total > 0
                            ? (e.value / _total).clamp(0.0, 1.0)
                            : 0,
                        minHeight: 5,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        const SizedBox(height: 12),
        Text(
          'Transactions',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 12),
      ],
    ],
  );
  Widget _amountRow(
    String name,
    String detail,
    String amount,
    ThemeData theme,
  ) {
    final label = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          name,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 4),
        Text(detail, style: theme.textTheme.bodySmall),
      ],
    );
    final money = Text(
      amount,
      style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
    );
    if (MediaQuery.textScalerOf(context).scale(1) > 1.3) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [label, const SizedBox(height: 8), money],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: label),
        const SizedBox(width: 12),
        Flexible(child: money),
      ],
    );
  }
}
