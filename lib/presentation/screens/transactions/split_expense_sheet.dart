import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:expencify/domain/entities/transaction.dart';

class SplitExpenseItem {
  final String id;
  double amount;
  String category;
  String note;

  SplitExpenseItem({
    required this.id,
    required this.amount,
    required this.category,
    this.note = '',
  });
}

class SplitExpenseSheet extends StatefulWidget {
  final TransactionModel transaction;
  final Function(List<SplitExpenseItem>) onSplit;

  const SplitExpenseSheet({
    super.key,
    required this.transaction,
    required this.onSplit,
  });

  @override
  State<SplitExpenseSheet> createState() => _SplitExpenseSheetState();
}

class _SplitExpenseSheetState extends State<SplitExpenseSheet> {
  late List<SplitExpenseItem> _splits;
  late List<TextEditingController> _controllers;
  late List<TextEditingController> _noteControllers;
  late List<FocusNode> _focusNodes;
  final _rupeeFmt = NumberFormat.currency(
    locale: 'en_IN',
    symbol: '₹',
    decimalDigits: 2,
  );

  @override
  void initState() {
    super.initState();
    _splits = [
      SplitExpenseItem(
        id: 'initial',
        amount: widget.transaction.amount,
        category: widget.transaction.category,
        note: widget.transaction.note,
      ),
    ];
    _controllers = [
      TextEditingController(text: widget.transaction.amount.toStringAsFixed(2)),
    ];
    _noteControllers = [TextEditingController(text: widget.transaction.note)];
    _focusNodes = [FocusNode()];
  }

  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    for (final nc in _noteControllers) {
      nc.dispose();
    }
    for (final f in _focusNodes) {
      f.dispose();
    }
    super.dispose();
  }

  double get _totalSplitAmount =>
      _splits.fold(0, (sum, item) => sum + item.amount);
  double get _remainingAmount => widget.transaction.amount - _totalSplitAmount;

  void _addSplit() {
    if (_remainingAmount <= 0) return;
    setState(() {
      _splits.add(
        SplitExpenseItem(
          id: DateTime.now().toString(),
          amount: 0,
          category: 'Other',
          note: '',
        ),
      );
      _controllers.add(TextEditingController(text: ''));
      _noteControllers.add(TextEditingController(text: ''));
      _focusNodes.add(FocusNode());
    });
  }

  void _removeSplit(int index) {
    if (_splits.length <= 1) return;
    setState(() {
      _focusNodes[index].unfocus();
      _controllers[index].dispose();
      _noteControllers[index].dispose();
      _focusNodes[index].dispose();
      _controllers.removeAt(index);
      _noteControllers.removeAt(index);
      _focusNodes.removeAt(index);
      _splits.removeAt(index);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isOverLimit = _totalSplitAmount > widget.transaction.amount;

    return Container(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 12),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: theme.colorScheme.onSurface.withOpacity(0.1),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Distribute Expense',
                          style: theme.textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          'Original: ${_rupeeFmt.format(widget.transaction.amount)}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurface.withOpacity(0.5),
                          ),
                        ),
                      ],
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: isOverLimit
                        ? Colors.red.withOpacity(0.05)
                        : theme.colorScheme.primary.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: isOverLimit
                          ? Colors.red.withOpacity(0.2)
                          : theme.colorScheme.primary.withOpacity(0.2),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        isOverLimit
                            ? Icons.error_outline_rounded
                            : Icons.account_balance_wallet_outlined,
                        color: isOverLimit
                            ? Colors.red
                            : theme.colorScheme.primary,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              isOverLimit
                                  ? 'EXCEEDED TOTAL'
                                  : 'REMAINING TO DISTRIBUTE',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: isOverLimit
                                    ? Colors.red
                                    : theme.colorScheme.primary,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 1.1,
                              ),
                            ),
                            Text(
                              _rupeeFmt.format(_remainingAmount.abs()),
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: isOverLimit
                                    ? Colors.red
                                    : theme.colorScheme.onSurface,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Flexible(
            child: ListView.builder(
              shrinkWrap: true,
              padding: const EdgeInsets.symmetric(horizontal: 24),
              itemCount: _splits.length,
              itemBuilder: (ctx, i) => _buildSplitItem(i),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                OutlinedButton.icon(
                  onPressed: _addSplit,
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('Add Distribution Part'),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(double.infinity, 56),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: (_remainingAmount == 0 && !isOverLimit)
                      ? () => widget.onSplit(_splits)
                      : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: theme.colorScheme.primary,
                    foregroundColor: Colors.white,
                    minimumSize: const Size(double.infinity, 64),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                    elevation: 0,
                  ),
                  child: const Text(
                    'Confirm Distribution',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSplitItem(int index) {
    final theme = Theme.of(context);
    final item = _splits[index];
    final controller = _controllers[index];
    final noteController = _noteControllers[index];
    final focusNode = _focusNodes[index];

    return Container(
      key: ValueKey(item.id),
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.onSurface.withOpacity(0.02),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: theme.colorScheme.onSurface.withOpacity(0.05),
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                flex: 3,
                child: TextField(
                  controller: controller,
                  focusNode: focusNode,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    prefixText: '₹ ',
                    labelText: 'Amount',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onChanged: (v) {
                    setState(() {
                      _splits[index].amount = double.tryParse(v) ?? 0;
                    });
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 4,
                child: DropdownButtonFormField<String>(
                  isExpanded: true,
                  value: item.category,
                  decoration: InputDecoration(
                    labelText: 'Category',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  items: _allCategories
                      .map(
                        (c) => DropdownMenuItem(
                          value: c,
                          child: Text(c, style: const TextStyle(fontSize: 13)),
                        ),
                      )
                      .toList(),
                  onChanged: (v) {
                    if (v != null) setState(() => _splits[index].category = v);
                  },
                ),
              ),
              if (_splits.length > 1)
                IconButton(
                  onPressed: () => _removeSplit(index),
                  icon: const Icon(
                    Icons.remove_circle_outline,
                    color: Colors.red,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: noteController,
            decoration: InputDecoration(
              hintText: 'Add a specific note (e.g. Lunch with team)',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 12,
              ),
            ),
            onChanged: (v) => _splits[index].note = v,
          ),
        ],
      ),
    );
  }

  final List<String> _allCategories = [
    'Food',
    'Shopping',
    'Bills',
    'Family',
    'Friends',
    'Travel',
    'Health',
    'Salary',
    'Groceries',
    'Entertainment',
    'Transport',
    'Rent',
    'Transfer',
    'Refund',
    'Cashback',
    'Other',
  ];
}
