import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:expencify/domain/entities/transaction.dart';
import 'package:expencify/presentation/theme/app_theme.dart';

class TransactionSelectionScreen extends StatefulWidget {
  final List<TransactionModel> transactions;

  const TransactionSelectionScreen({super.key, required this.transactions});

  @override
  State<TransactionSelectionScreen> createState() =>
      _TransactionSelectionScreenState();
}

class _TransactionSelectionScreenState
    extends State<TransactionSelectionScreen> {
  late List<bool> _selected;
  final _rupeeFmt = NumberFormat.currency(
    locale: 'en_IN',
    symbol: '₹',
    decimalDigits: 0,
  );

  @override
  void initState() {
    super.initState();
    _selected = List.filled(widget.transactions.length, true);
  }

  void _toggleAll(bool value) {
    setState(() {
      _selected = List.filled(widget.transactions.length, value);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final selectedCount = _selected.where((s) => s).length;
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: AppBar(
        backgroundColor: theme.colorScheme.surface,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: Text(
          'Filter Export',
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w800,
            letterSpacing: -0.5,
          ),
        ),
        centerTitle: true,
        leading: IconButton(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
        ),
        actions: [
          _ActionButton(
            label: 'All',
            onTap: () => _toggleAll(true),
            isSelected: _selected.every((s) => s),
          ),
          const SizedBox(width: 8),
          _ActionButton(
            label: 'None',
            onTap: () => _toggleAll(false),
            isSelected: _selected.every((s) => !s),
          ),
          const SizedBox(width: 16),
        ],
      ),
      body: Column(
        children: [
          // ── Selection Counter Badge ──────────────────────────────────────────
          AnimatedSize(
            duration: const Duration(milliseconds: 300),
            child: Container(
              margin: const EdgeInsets.fromLTRB(20, 12, 20, 16),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: theme.colorScheme.primary.withOpacity(0.08),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: theme.colorScheme.primary.withOpacity(0.12),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.check_circle_outline_rounded,
                    size: 16,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 10),
                  Text(
                    '$selectedCount of ${widget.transactions.length} transactions selected',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ── Transaction List ───────────────────────────────────────────────
          Expanded(
            child: ListView.builder(
              itemCount: widget.transactions.length,
              padding: const EdgeInsets.only(bottom: 24),
              itemBuilder: (context, index) {
                final tx = widget.transactions[index];
                final isSelected = _selected[index];
                final isExpense = tx.type == 'expense';
                final color = isExpense ? AppTheme.expense : AppTheme.income;

                return InkWell(
                  onTap: () {
                    setState(() => _selected[index] = !_selected[index]);
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    margin: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 4,
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? theme.colorScheme.primary.withOpacity(0.04)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: isSelected
                            ? theme.colorScheme.primary.withOpacity(0.15)
                            : Colors.transparent,
                      ),
                    ),
                    child: Row(
                      children: [
                        // Custom Checkbox
                        GestureDetector(
                          onTap: () {
                            setState(
                              () => _selected[index] = !_selected[index],
                            );
                          },
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            width: 24,
                            height: 24,
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? cs.primary
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: isSelected
                                    ? cs.primary
                                    : (isDark
                                          ? AppTheme.darkBorder
                                          : AppTheme.lightBorder),
                                width: 1.5,
                              ),
                            ),
                            child: isSelected
                                ? const Icon(
                                    Icons.check,
                                    size: 16,
                                    color: Colors.white,
                                  )
                                : null,
                          ),
                        ),
                        const SizedBox(width: 16),
                        BarIndicator(color: color),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                tx.merchant.isNotEmpty
                                    ? tx.merchant
                                    : tx.category,
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w700,
                                  color: theme.colorScheme.onSurface,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '${tx.category} \u00B7 ${DateFormat('d MMM yyyy').format(tx.date)}',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onSurface
                                      .withOpacity(0.5),
                                ),
                              ),
                            ],
                          ),
                        ),
                        Text(
                          '${isExpense ? '-' : '+'}${_rupeeFmt.format(tx.amount)}',
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: color,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
      bottomNavigationBar: Container(
        padding: EdgeInsets.fromLTRB(
          20,
          12,
          20,
          12 + MediaQuery.of(context).padding.bottom,
        ),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          border: Border(
            top: BorderSide(
              color: isDark ? AppTheme.darkBorder : AppTheme.lightBorder,
              width: 0.5,
            ),
          ),
        ),
        child: ElevatedButton(
          onPressed: selectedCount > 0
              ? () {
                  final result = <TransactionModel>[];
                  for (int i = 0; i < widget.transactions.length; i++) {
                    if (_selected[i]) result.add(widget.transactions[i]);
                  }
                  Navigator.pop(context, result);
                }
              : null,
          style: ElevatedButton.styleFrom(
            backgroundColor: cs.primary,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            elevation: 0,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.file_upload_outlined, size: 20),
              const SizedBox(width: 10),
              Text(
                'Export $selectedCount ${selectedCount == 1 ? 'Transaction' : 'Transactions'}',
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  final bool isSelected;

  const _ActionButton({
    required this.label,
    required this.onTap,
    this.isSelected = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Center(
      child: Material(
        color: isSelected ? theme.colorScheme.primary : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: isSelected
                    ? theme.colorScheme.primary
                    : (isDark ? AppTheme.darkBorder : AppTheme.lightBorder),
              ),
            ),
            child: Text(
              label,
              style: theme.textTheme.labelMedium?.copyWith(
                color: isSelected ? Colors.white : theme.colorScheme.onSurface,
                fontWeight: FontWeight.w700,
                fontSize: 11,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
