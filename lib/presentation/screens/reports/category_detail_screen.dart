import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import 'package:expencify/domain/entities/transaction.dart';
import 'package:expencify/domain/repositories/transaction_repository.dart';

class CategoryDetailScreen extends StatefulWidget {
  final String category;
  final String type;
  final DateTime? from;
  final DateTime? to;

  const CategoryDetailScreen({
    super.key,
    required this.category,
    required this.type,
    this.from,
    this.to,
  });

  @override
  State<CategoryDetailScreen> createState() => _CategoryDetailScreenState();
}

class _CategoryDetailScreenState extends State<CategoryDetailScreen> {
  bool _loading = true;
  List<TransactionModel> _transactions = [];
  Map<String, double> _merchantBreakdown = {};
  double _total = 0;

  final _rupeeFmt = NumberFormat.currency(
    locale: 'en_IN',
    symbol: '₹',
    decimalDigits: 0,
  );

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final repo = context.read<TransactionRepository>();

    // Fetch all transactions for this category
    final now = DateTime.now();
    final monthStart = DateTime(now.year, now.month, 1);

    final txs = await repo.getTransactions(
      category: widget.category,
      type: widget.type,
      from: widget.from ?? monthStart,
      to: widget.to,
    );

    double total = 0;
    final Map<String, double> merchants = {};
    for (var tx in txs) {
      total += tx.amount;
      final mName = tx.merchant.isNotEmpty ? tx.merchant : 'Other';
      merchants[mName] = (merchants[mName] ?? 0) + tx.amount;
    }

    // Sort merchants by spending
    final sortedMerchants = Map.fromEntries(
      merchants.entries.toList()..sort((a, b) => b.value.compareTo(a.value)),
    );

    setState(() {
      _transactions = txs;
      _merchantBreakdown = sortedMerchants;
      _total = total;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: AppBar(
        title: Text('${widget.category} Insights'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(24),
              children: [
                _buildHeader(theme),
                const SizedBox(height: 32),
                _buildMerchantBreakdown(theme),
                const SizedBox(height: 32),
                _buildTransactionList(theme),
              ],
            ),
    );
  }

  Widget _buildHeader(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            theme.colorScheme.primary,
            theme.colorScheme.primary.withOpacity(0.8),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: theme.colorScheme.primary.withOpacity(0.3),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'TOTAL SPENT THIS MONTH',
            style: TextStyle(
              color: Colors.white.withOpacity(0.7),
              fontSize: 10,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _rupeeFmt.format(_total),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 32,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            widget.from != null && widget.to != null
                ? '${DateFormat('MMM d').format(widget.from!)} - ${DateFormat('MMM d').format(widget.to!)}'
                : widget.from != null
                ? 'Since ${DateFormat('MMM d').format(widget.from!)}'
                : 'This Month',
            style: TextStyle(
              color: Colors.white.withOpacity(0.8),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${_transactions.length} Transactions',
            style: TextStyle(
              color: Colors.white.withOpacity(0.9),
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMerchantBreakdown(ThemeData theme) {
    if (_merchantBreakdown.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Top Merchants',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 16),
        ..._merchantBreakdown.entries.take(5).map((e) {
          final percentage = _total > 0 ? (e.value / _total) : 0.0;
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      e.key,
                      style: const TextStyle(fontWeight: FontWeight.w500),
                    ),
                    Text(
                      _rupeeFmt.format(e.value),
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: percentage,
                    minHeight: 8,
                    backgroundColor: theme.colorScheme.onSurface.withOpacity(
                      0.05,
                    ),
                    color: theme.colorScheme.primary,
                  ),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }

  Widget _buildTransactionList(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Recent Activity',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 16),
        ..._transactions
            .take(10)
            .map(
              (t) => Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: theme.colorScheme.onSurface.withOpacity(0.02),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: theme.colorScheme.onSurface.withOpacity(0.05),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primary.withOpacity(0.1),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.receipt_rounded,
                        color: theme.colorScheme.primary,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            t.merchant.isNotEmpty ? t.merchant : 'Manual Entry',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          Text(
                            DateFormat('MMM d, yyyy').format(t.date),
                            style: theme.textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                    Text(
                      _rupeeFmt.format(t.amount),
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
            ),
      ],
    );
  }
}
