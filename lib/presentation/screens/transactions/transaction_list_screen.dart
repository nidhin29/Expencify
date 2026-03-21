import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';

import 'package:expencify/presentation/theme/app_theme.dart';
import 'package:expencify/domain/entities/transaction.dart';
import 'package:expencify/domain/repositories/transaction_repository.dart';

import 'package:expencify/application/blocs/transaction/transaction_bloc.dart';
import 'package:expencify/application/blocs/transaction/transaction_event.dart';
import 'package:expencify/application/blocs/transaction/transaction_state.dart';
import 'package:expencify/application/blocs/account/account_bloc.dart';
import 'package:expencify/application/blocs/account/account_state.dart';
import 'package:expencify/presentation/screens/transactions/receipt_fullscreen.dart';
import 'package:expencify/presentation/screens/transactions/transaction_entry_screen.dart';
import 'package:expencify/presentation/screens/transactions/split_expense_sheet.dart';

class TransactionListScreen extends StatefulWidget {
  final VoidCallback? onRefresh;
  const TransactionListScreen({super.key, this.onRefresh});

  @override
  State<TransactionListScreen> createState() => _TransactionListScreenState();
}

class _TransactionListScreenState extends State<TransactionListScreen> {
  final _searchCtrl = TextEditingController();
  final _rupeeFmt = NumberFormat.currency(
    locale: 'en_IN',
    symbol: '\u20B9',
    decimalDigits: 0,
  );

  String? _filterType;
  String? _filterCategory;
  DateTime? _filterDateFrom;
  DateTime? _filterDateTo;
  String? _dateLabel;

  // Optimistic-deletion: track items removed but not yet committed (undo window)
  final Set<int> _removedIds = {};

  @override
  void initState() {
    super.initState();
    _load();
    _searchCtrl.addListener(() => _load());
  }

  Future<void> _load() async {
    if (!mounted) return;

    final accountState = context.read<AccountBloc>().state;
    int? selectedId;
    if (accountState is AccountLoaded) {
      selectedId = accountState.selectedAccountId;
    }

    context.read<TransactionBloc>().add(
      LoadTransactions(
        accountId: selectedId,
        type: _filterType,
        category: _filterCategory,
        from: _filterDateFrom,
        to: _filterDateTo,
        search: _searchCtrl.text.trim(),
      ),
    );
  }

  Future<void> _deleteTransaction(TransactionModel t) async {
    if (t.id == null) return;
    final txBloc = context.read<TransactionBloc>();

    // 1. Optimistically hide the row immediately.
    setState(() => _removedIds.add(t.id!));

    // 2. Commit deletion to DB immediately — balance & home card update now.
    txBloc.add(DeleteTransaction(t));
    widget.onRefresh?.call();

    // 3. Show undo snackbar for 1.5 seconds.
    if (!mounted) return;
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Deleted: ${t.merchant.isNotEmpty ? t.merchant : t.category}',
        ),
        duration: const Duration(milliseconds: 1500),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () {
            // Re-insert the transaction (new row, balance reversed).
            txBloc.add(
              AddTransaction(
                TransactionModel(
                  accountId: t.accountId,
                  amount: t.amount,
                  type: t.type,
                  category: t.category,
                  date: t.date,
                  note: t.note,
                  merchant: t.merchant,
                  isOcr: t.isOcr,
                  isVoice: t.isVoice,
                  isSms: t.isSms,
                  imagePath: t.imagePath,
                  parentId: t.parentId,
                ),
              ),
            );
            if (mounted) {
              ScaffoldMessenger.of(context).hideCurrentSnackBar();
              setState(() => _removedIds.remove(t.id));
              // Give the bloc time to process AddTransaction and save to DB
              // before refreshing the home balance via onRefresh.
              Future.delayed(const Duration(milliseconds: 300), () {
                if (mounted) widget.onRefresh?.call();
              });
            }
          },
        ),
      ),
    );

    // FORCE DISMISS TIMER (Bypasses system accessibility overrides)
    Future.delayed(const Duration(milliseconds: 1800), () {
      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
      }
    });

    // Clean up the optimistic-hide set after the snackbar window.
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) setState(() => _removedIds.remove(t.id));
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return BlocListener<AccountBloc, AccountState>(
      listenWhen: (previous, current) {
        if (previous is AccountLoaded && current is AccountLoaded) {
          return previous.selectedAccountId != current.selectedAccountId;
        }
        return false;
      },
      listener: (context, state) {
        if (state is AccountLoaded) _load();
      },
      child: Scaffold(
        backgroundColor: theme.colorScheme.surface,
        appBar: AppBar(
          title: const Text('Passbook'),
          automaticallyImplyLeading: false,
          backgroundColor: Colors.transparent,
          actions: [
            IconButton(
              icon: const Icon(Icons.filter_list_rounded),
              onPressed: _showFilterSheet,
            ),
          ],
        ),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: TextField(
                controller: _searchCtrl,
                style: theme.textTheme.bodyMedium,
                decoration: InputDecoration(
                  hintText: 'Search...',
                  hintStyle: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  prefixIcon: Icon(
                    Icons.search_rounded,
                    size: 20,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  contentPadding: const EdgeInsets.symmetric(vertical: 0),
                  filled: true,
                  fillColor: theme.brightness == Brightness.dark
                      ? AppTheme.darkElevated
                      : AppTheme.lightElevated,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            if (_filterType != null ||
                _filterCategory != null ||
                _dateLabel != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            if (_filterType != null)
                              _buildFilterChip(
                                'Type: ${_filterType!.capitalize()}',
                                () {
                                  setState(() => _filterType = null);
                                  _load();
                                },
                              ),
                            if (_filterCategory != null)
                              _buildFilterChip('Cat: $_filterCategory', () {
                                setState(() => _filterCategory = null);
                                _load();
                              }),
                            if (_dateLabel != null)
                              _buildFilterChip(_dateLabel!, () {
                                setState(() {
                                  _dateLabel = null;
                                  _filterDateFrom = null;
                                  _filterDateTo = null;
                                });
                                _load();
                              }),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: () {
                        setState(() {
                          _filterType = null;
                          _filterCategory = null;
                          _dateLabel = null;
                          _filterDateFrom = null;
                          _filterDateTo = null;
                        });
                        _load();
                      },
                      child: Text(
                        'Clear',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.primary,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            Expanded(
              child: BlocBuilder<TransactionBloc, TransactionState>(
                builder: (context, state) {
                  if (state is TransactionLoading) {
                    return const Center(child: CircularProgressIndicator());
                  } else if (state is TransactionLoaded) {
                    if (state.transactions.isEmpty) {
                      return _buildEmpty(theme);
                    }
                    return RefreshIndicator(
                      onRefresh: _load,
                      child: ListView.builder(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        itemCount: state.transactions.length,
                        itemBuilder: (ctx, i) {
                          final t = state.transactions[i];
                          // Skip optimistically removed items without rebuilding
                          if (_removedIds.contains(t.id)) {
                            return const SizedBox.shrink();
                          }
                          return _buildItem(theme, t);
                        },
                      ),
                    );
                  } else if (state is TransactionError) {
                    return Center(child: Text(state.message));
                  }
                  return _buildEmpty(theme);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterChip(String label, VoidCallback onRemove) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    return GestureDetector(
      onTap: onRemove,
      child: Container(
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: dark ? AppTheme.darkElevated : AppTheme.lightElevated,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: dark ? AppTheme.darkBorder : AppTheme.lightBorder,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurface,
                fontWeight: FontWeight.w600,
                fontSize: 10,
              ),
            ),
            const SizedBox(width: 6),
            Icon(
              Icons.close_rounded,
              size: 12,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildItem(ThemeData theme, TransactionModel t) {
    final isExpense = t.type == 'expense';
    final color = isExpense ? AppTheme.expense : AppTheme.income;
    return Dismissible(
      key: Key('txn_${t.id}'),
      direction: DismissDirection.horizontal,
      onDismissed: (_) => _deleteTransaction(t),
      confirmDismiss: (direction) async {
        if (direction == DismissDirection.startToEnd) {
          _showSplitSheet(t);
          return false;
        }
        return true;
      },
      secondaryBackground: Container(
        margin: const EdgeInsets.symmetric(vertical: 2),
        decoration: BoxDecoration(
          color: AppTheme.expense,
          borderRadius: BorderRadius.circular(8),
        ),
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        child: const Icon(Icons.delete_outline_rounded, color: Colors.white),
      ),
      background: Container(
        margin: const EdgeInsets.symmetric(vertical: 2),
        decoration: BoxDecoration(
          color: theme.colorScheme.primary,
          borderRadius: BorderRadius.circular(8),
        ),
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.only(left: 20),
        child: const Row(
          children: [
            Icon(Icons.call_split_rounded, color: Colors.white),
            SizedBox(width: 8),
            Text(
              'Split',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
      child: InkWell(
        onTap: () async {
          await Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => TransactionEntryScreen(existing: t),
            ),
          );
          _load();
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: theme.brightness == Brightness.dark
                    ? AppTheme.darkBorder
                    : AppTheme.lightBorder,
                width: 0.5,
              ),
            ),
          ),
          child: Row(
            children: [
              BarIndicator(color: color),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      t.merchant.isNotEmpty ? t.merchant : t.category,
                      style: theme.textTheme.titleSmall,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${t.category} \u00B7 ${DateFormat('d MMM yyyy').format(t.date)}',
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (isExpense)
                        IconButton(
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          icon: Icon(
                            Icons.call_split_rounded,
                            size: 14,
                            color: color.withOpacity(0.5),
                          ),
                          onPressed: () => _showSplitSheet(t),
                        ),
                      if (isExpense) const SizedBox(width: 8),
                      Text(
                        '${isExpense ? '-' : '+'}${_rupeeFmt.format(t.amount)}',
                        style: theme.textTheme.titleSmall?.copyWith(
                          color: color,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Icon(
                        Icons.edit_rounded,
                        size: 14,
                        color: theme.colorScheme.onSurface.withOpacity(0.2),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (t.isSms) _buildSourceBadge('SMS', Colors.green),
                      if (t.isVoice) _buildSourceBadge('Voice', Colors.purple),
                      if (t.isOcr) _buildSourceBadge('OCR', Colors.orange),
                      if (t.imagePath != null)
                        GestureDetector(
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) =>
                                  ReceiptFullscreen(imagePath: t.imagePath!),
                            ),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.only(left: 4),
                            child: Icon(
                              Icons.attach_file_rounded,
                              color: theme.colorScheme.onSurfaceVariant,
                              size: 12,
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSourceBadge(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 9,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  void _showSplitSheet(TransactionModel t) {
    if (t.type != 'expense') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Only expenses can be distributed.')),
      );
      return;
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => SplitExpenseSheet(
        transaction: t,
        onSplit: (splits) {
          final parts = splits
              .map(
                (s) => TransactionModel(
                  accountId: t.accountId,
                  amount: s.amount,
                  type: 'expense',
                  category: s.category,
                  date: t.date,
                  note: s.note,
                  merchant: t.merchant,
                  isSms: t.isSms,
                  isVoice: t.isVoice,
                  isOcr: t.isOcr,
                ),
              )
              .toList();

          context.read<TransactionBloc>().add(SplitTransactions(t, parts));
          Navigator.pop(ctx);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Expense distributed successfully!')),
          );
        },
      ),
    );
  }

  Widget _buildEmpty(ThemeData theme) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.receipt_long_rounded,
            size: 64,
            color: theme.colorScheme.primary.withOpacity(0.2),
          ),
          const SizedBox(height: 16),
          Text(
            'No transactions found',
            style: theme.textTheme.titleMedium?.copyWith(
              color: theme.colorScheme.onSurface.withOpacity(0.4),
            ),
          ),
        ],
      ),
    );
  }

  void _showFilterSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        final theme = Theme.of(ctx);
        return Padding(
          padding: EdgeInsets.fromLTRB(
            24,
            24,
            24,
            24 + MediaQuery.of(ctx).viewInsets.bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Filter',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 24),
              Text(
                'Date Range',
                style: theme.textTheme.labelLarge?.copyWith(
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children:
                    [
                      'All Time',
                      'Today',
                      'This Month',
                      'This Year',
                      'Custom Range',
                    ].map((p) {
                      final isSelected =
                          (p == 'All Time' && _dateLabel == null) ||
                          (_dateLabel == p);
                      return ChoiceChip(
                        label: Text(p),
                        selected: isSelected,
                        onSelected: (val) async {
                          if (!val) return;
                          if (p == 'Custom Range') {
                            Navigator.pop(ctx);
                            // Delay slightly to ensure sheet is dismissed before showing picker
                            Future.delayed(
                              const Duration(milliseconds: 100),
                              () => _applyDateFilter(p),
                            );
                          } else {
                            _applyDateFilter(p);
                            Navigator.pop(ctx);
                          }
                        },
                      );
                    }).toList(),
              ),
              const SizedBox(height: 24),
              Text(
                'Transaction Type',
                style: theme.textTheme.labelLarge?.copyWith(
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                children: ['All Types', 'expense', 'income']
                    .map(
                      (t) => ChoiceChip(
                        label: Text(
                          t == 'All Types' ? 'All Types' : t.capitalize(),
                        ),
                        selected: (t == 'All Types'
                            ? _filterType == null
                            : _filterType == t),
                        onSelected: (_) {
                          setState(
                            () => _filterType = t == 'All Types' ? null : t,
                          );
                          Navigator.pop(ctx);
                          _load();
                        },
                      ),
                    )
                    .toList(),
              ),
              const SizedBox(height: 16),
            ],
          ),
        );
      },
    );
  }

  void _applyDateFilter(String period) async {
    final now = DateTime.now();
    DateTime? from;
    DateTime? to;
    String? label = period;

    if (period == 'Today') {
      from = DateTime(now.year, now.month, now.day);
      to = from
          .add(const Duration(days: 1))
          .subtract(const Duration(milliseconds: 1));
    } else if (period == 'This Month') {
      from = DateTime(now.year, now.month, 1);
      to = DateTime(now.year, now.month + 1, 0, 23, 59, 59);
    } else if (period == 'This Year') {
      from = DateTime(now.year, 1, 1);
      to = DateTime(now.year, 12, 31, 23, 59, 59);
    } else if (period == 'Custom Range') {
      final picked = await showDateRangePicker(
        context: context,
        firstDate: DateTime(2000),
        lastDate: DateTime(2100),
        initialDateRange: _filterDateFrom != null && _filterDateTo != null
            ? DateTimeRange(start: _filterDateFrom!, end: _filterDateTo!)
            : null,
      );
      if (picked != null) {
        from = picked.start;
        to = picked.end
            .add(const Duration(days: 1))
            .subtract(const Duration(milliseconds: 1));
        label =
            '${DateFormat('d MMM').format(from)} - ${DateFormat('d MMM').format(to)}';
      } else {
        return;
      }
    } else {
      // All Time
      from = null;
      to = null;
      label = null;
    }

    setState(() {
      _filterDateFrom = from;
      _filterDateTo = to;
      _dateLabel = label;
    });
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }
}

extension StringCapitalize on String {
  String capitalize() =>
      isEmpty ? '' : '${this[0].toUpperCase()}${substring(1)}';
}

/// Displays the split children of a parent transaction inline.
/// Self-hides when the parent has no children.
class _SplitChildrenView extends StatefulWidget {
  final int parentId;
  final NumberFormat rupeeFmt;
  final ThemeData theme;
  const _SplitChildrenView({
    required this.parentId,
    required this.rupeeFmt,
    required this.theme,
  });
  @override
  State<_SplitChildrenView> createState() => _SplitChildrenViewState();
}

class _SplitChildrenViewState extends State<_SplitChildrenView> {
  late Future<List<TransactionModel>> _childrenFuture;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    _childrenFuture = context
        .read<TransactionRepository>()
        .getChildTransactions(widget.parentId);
  }

  /// Simple bottom sheet: edit just the label (note) and amount.
  Future<void> _editSplitChild(TransactionModel child) async {
    final nameCtrl = TextEditingController(
      text: child.note.isNotEmpty ? child.note : child.merchant,
    );
    final amountCtrl = TextEditingController(
      text: child.amount.toStringAsFixed(0),
    );

    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom,
          ),
          child: Container(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(24),
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 20),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.onSurface.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                Text(
                  'Edit Split Part',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: nameCtrl,
                  autofocus: true,
                  decoration: const InputDecoration(
                    labelText: 'Name',
                    hintText: 'e.g. Lunch with team',
                    prefixIcon: Icon(Icons.label_outline_rounded),
                  ),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: amountCtrl,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Amount',
                    prefixText: '\u20B9 ',
                    prefixIcon: Icon(Icons.currency_rupee_rounded),
                  ),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    child: const Text('Save'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );

    if (saved == true && mounted) {
      final newNote = nameCtrl.text.trim();
      final newAmount = double.tryParse(amountCtrl.text.trim()) ?? child.amount;
      final txBloc = context.read<TransactionBloc>();
      final newChild = child.copyWith(
        note: newNote,
        merchant: newNote,
        amount: newAmount,
      );
      txBloc.add(UpdateTransaction(newChild, child));
      setState(() => _reload());
    }
    nameCtrl.dispose();
    amountCtrl.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<TransactionModel>>(
      future: _childrenFuture,
      builder: (context, snap) {
        if (!snap.hasData || snap.data!.isEmpty) return const SizedBox.shrink();
        final children = snap.data!;
        final theme = widget.theme;
        final dark = theme.brightness == Brightness.dark;

        return Container(
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 10),
          decoration: BoxDecoration(
            color: dark
                ? AppTheme.darkElevated.withOpacity(0.8)
                : AppTheme.lightElevated.withOpacity(0.9),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: AppTheme.expense.withOpacity(0.18),
              width: 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                child: Row(
                  children: [
                    Icon(
                      Icons.call_split_rounded,
                      size: 13,
                      color: AppTheme.expense.withOpacity(0.75),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Split \u00B7 ${children.length} parts',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: AppTheme.expense.withOpacity(0.85),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              Divider(
                height: 1,
                thickness: 0.5,
                color: AppTheme.expense.withOpacity(0.1),
              ),
              // Rows — show note as label, amount on right, tap to edit
              ...children.asMap().entries.map((e) {
                final idx = e.key;
                final child = e.value;
                final isLast = idx == children.length - 1;
                // Label: note field (what user typed), fallback to merchant/category
                final label = child.note.isNotEmpty
                    ? child.note
                    : (child.merchant.isNotEmpty
                          ? child.merchant
                          : child.category);

                return Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: isLast
                        ? const BorderRadius.only(
                            bottomLeft: Radius.circular(10),
                            bottomRight: Radius.circular(10),
                          )
                        : BorderRadius.zero,
                    onTap: () => _editSplitChild(child),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      decoration: !isLast
                          ? BoxDecoration(
                              border: Border(
                                bottom: BorderSide(
                                  color: dark
                                      ? AppTheme.darkBorder
                                      : AppTheme.lightBorder,
                                  width: 0.5,
                                ),
                              ),
                            )
                          : null,
                      child: Row(
                        children: [
                          // Numbered bubble
                          Container(
                            width: 22,
                            height: 22,
                            decoration: BoxDecoration(
                              color: AppTheme.expense.withOpacity(0.1),
                              shape: BoxShape.circle,
                            ),
                            child: Center(
                              child: Text(
                                '${idx + 1}',
                                style: TextStyle(
                                  color: AppTheme.expense,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          // Label
                          Expanded(
                            child: Text(
                              label,
                              style: theme.textTheme.bodySmall?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 8),
                          // Amount + edit hint
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                '-${widget.rupeeFmt.format(child.amount)}',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: AppTheme.expense,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Icon(
                                Icons.edit_outlined,
                                size: 12,
                                color: theme.colorScheme.onSurface.withOpacity(
                                  0.25,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }),
            ],
          ),
        );
      },
    );
  }
}
