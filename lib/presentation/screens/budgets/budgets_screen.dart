import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import 'dart:async';
import 'package:collection/collection.dart';
import 'package:expencify/application/services/sms/sms_monitor_service.dart';
import 'package:expencify/application/blocs/transaction/transaction_bloc.dart';
import 'package:expencify/application/blocs/transaction/transaction_state.dart';

import 'package:expencify/presentation/theme/app_theme.dart';
import 'package:expencify/domain/entities/budget.dart';
import 'package:expencify/domain/repositories/transaction_repository.dart';
import 'package:expencify/domain/repositories/category_repository.dart';
import 'package:expencify/application/blocs/budget/budget_bloc.dart';
import 'package:expencify/application/blocs/budget/budget_event.dart';
import 'package:expencify/application/blocs/budget/budget_state.dart';
import 'package:expencify/application/blocs/account/account_bloc.dart';
import 'package:expencify/application/blocs/account/account_state.dart';

class BudgetScreen extends StatefulWidget {
  final VoidCallback? onRefresh;
  const BudgetScreen({super.key, this.onRefresh});

  @override
  State<BudgetScreen> createState() => _BudgetScreenState();
}

class _BudgetScreenState extends State<BudgetScreen> {
  final _rupeeFmt = NumberFormat.currency(
    locale: 'en_IN',
    symbol: '₹',
    decimalDigits: 0,
  );
  String _period = 'monthly';
  int? _lastAccountId;
  StreamSubscription? _smsSub;

  @override
  void initState() {
    super.initState();
    _load();
    _smsSub = SmsMonitorService.onSmsProcessed.stream.listen((_) => _load());
  }

  @override
  void dispose() {
    _smsSub?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    if (!mounted) return;

    final accountState = context.read<AccountBloc>().state;
    final selectedId = accountState is AccountLoaded
        ? accountState.selectedAccountId
        : null;
    _lastAccountId = selectedId;

    context.read<BudgetBloc>().add(LoadBudgets(period: _period));
  }

  DateTime _getFromDate() {
    final now = DateTime.now();
    if (_period == 'weekly') return now.subtract(const Duration(days: 7));
    if (_period == 'yearly') return DateTime(now.year, 1, 1);
    return DateTime(now.year, now.month, 1);
  }

  Future<double> _getSpentForBudget(Budget b) async {
    final targetAccountId = b.accountId ?? _lastAccountId;
    final totals = await context
        .read<TransactionRepository>()
        .getCategoryTotals(
          type: 'expense',
          from: _getFromDate(),
          accountId: targetAccountId,
        );
    return totals.entries
            .firstWhereOrNull(
              (e) => e.key.toLowerCase() == b.category.toLowerCase(),
            )
            ?.value ??
        0.0;
  }

  String _getAccountName(int id) {
    final state = context.read<AccountBloc>().state;
    if (state is AccountLoaded) {
      final a = state.accounts.firstWhereOrNull((a) => a.id == id);
      return a?.name ?? "Unknown";
    }
    return "Account $id";
  }

  Future<void> _showBudgetModal({Budget? existing}) async {
    final formKey = GlobalKey<FormState>();
    final amountCtrl = TextEditingController(
      text: existing?.amount.toStringAsFixed(0) ?? '',
    );
    String? selectedCat = existing?.category;
    int? selectedAccountId = existing?.accountId;
    final categories = await context.read<CategoryRepository>().getAll(
      type: 'expense',
    );
    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => Container(
          decoration: BoxDecoration(
            color: Theme.of(ctx).colorScheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          ),
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
            top: 20,
            left: 20,
            right: 20,
          ),
          child: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      existing != null ? 'Edit Budget' : 'Set Budget',
                      style: Theme.of(ctx).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.5,
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(ctx),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                _buildDropdown(
                  label: 'Category',
                  value: selectedCat,
                  items: categories
                      .map(
                        (c) => DropdownMenuItem(
                          value: c.name,
                          child: Text(c.name),
                        ),
                      )
                      .toList(),
                  onChanged: (v) => setS(() => selectedCat = v),
                  validator: (v) => v == null ? 'Required' : null,
                ),
                const SizedBox(height: 16),
                StatefulBuilder(
                  builder: (ctx, setS2) {
                    final accountState = context.read<AccountBloc>().state;
                    final accounts = accountState is AccountLoaded
                        ? accountState.accounts
                        : [];

                    return _buildDropdown(
                      label: 'Account (Optional)',
                      value: selectedAccountId?.toString(),
                      icon: Icons.account_balance_wallet_outlined,
                      items: [
                        const DropdownMenuItem(
                          value: null,
                          child: Text('All Accounts'),
                        ),
                        ...accounts.map(
                          (a) => DropdownMenuItem(
                            value: a.id.toString(),
                            child: Text(a.name),
                          ),
                        ),
                      ],
                      onChanged: (v) {
                        setS(() {
                          selectedAccountId = v != null ? int.parse(v) : null;
                        });
                      },
                    );
                  },
                ),
                const SizedBox(height: 16),
                _buildField(
                  label: 'Spending Limit (₹)',
                  controller: amountCtrl,
                  hint: '0.00',
                  icon: Icons.track_changes_outlined,
                  keyboardType: TextInputType.number,
                  validator: (v) {
                    if (v == null || v.isEmpty) return 'Required';
                    if (double.tryParse(v) == null) return 'Invalid';
                    return null;
                  },
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () async {
                      if (!formKey.currentState!.validate()) return;
                      final b = Budget(
                        id: existing?.id,
                        category: selectedCat!,
                        amount: double.parse(amountCtrl.text),
                        period: existing?.period ?? _period,
                        startDate: existing?.startDate ?? DateTime.now(),
                        accountId: selectedAccountId,
                      );
                      context.read<BudgetBloc>().add(SaveBudget(b));
                      if (ctx.mounted) Navigator.pop(ctx);
                    },
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: Text(
                      existing != null ? 'Update Budget' : 'Set Budget',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildField({
    required String label,
    required TextEditingController controller,
    String? hint,
    IconData? icon,
    TextInputType? keyboardType,
    String? Function(String?)? validator,
  }) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: theme.textTheme.labelMedium?.copyWith(
            color: theme.colorScheme.onSurface.withOpacity(0.6),
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: controller,
          keyboardType: keyboardType,
          validator: validator,
          decoration: InputDecoration(
            hintText: hint,
            prefixIcon: icon != null
                ? Icon(icon, size: 20, color: theme.colorScheme.primary)
                : null,
            filled: true,
            fillColor: dark ? const Color(0xFF18181B) : const Color(0xFFF4F4F5),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide.none,
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 14,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDropdown({
    required String label,
    required String? value,
    required List<DropdownMenuItem<String>> items,
    required void Function(String?) onChanged,
    String? Function(String?)? validator,
    IconData? icon,
  }) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: theme.textTheme.labelMedium?.copyWith(
            color: theme.colorScheme.onSurface.withOpacity(0.6),
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          value: value,
          items: items,
          onChanged: onChanged,
          validator: validator,
          decoration: InputDecoration(
            prefixIcon: Icon(
              icon ?? Icons.category_outlined,
              size: 20,
              color: theme.colorScheme.primary,
            ),
            filled: true,
            fillColor: dark ? const Color(0xFF18181B) : const Color(0xFFF4F4F5),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide.none,
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 14,
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return MultiBlocListener(
      listeners: [
        BlocListener<AccountBloc, AccountState>(
          listener: (context, state) {
            if (state is AccountLoaded &&
                state.selectedAccountId != _lastAccountId) {
              _load();
            }
          },
        ),
        BlocListener<TransactionBloc, TransactionState>(
          listener: (context, state) {
            if (state is TransactionLoaded) {
              _load();
            }
          },
        ),
      ],
      child: Scaffold(
        backgroundColor: theme.colorScheme.surface,
        appBar: AppBar(
          title: const Text('Budget Planner'),
          automaticallyImplyLeading: false,
          backgroundColor: Colors.transparent,
          actions: [
            IconButton(
              icon: const Icon(Icons.add_rounded),
              onPressed: _showBudgetModal,
            ),
          ],
        ),
        body: BlocBuilder<BudgetBloc, BudgetState>(
          builder: (context, state) {
            if (state is BudgetLoading) {
              return const Center(child: CircularProgressIndicator());
            } else if (state is BudgetLoaded) {
              final budgets = state.budgets;
              final showAll = _lastAccountId == null;
              final visibleBudgets = budgets.where((b) {
                return showAll ||
                    b.accountId == null ||
                    b.accountId == _lastAccountId;
              }).toList();

              return RefreshIndicator(
                onRefresh: _load,
                child: ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    _buildPeriodSelector(theme),
                    const SizedBox(height: 20),
                    if (visibleBudgets.isEmpty) _buildEmpty(theme),
                    ...visibleBudgets.map((b) => _buildBudgetCard(theme, b)),
                  ],
                ),
              );
            } else if (state is BudgetError) {
              return Center(child: Text(state.message));
            }
            return _buildEmpty(theme);
          },
        ),
      ),
    );
  }

  Widget _buildPeriodSelector(ThemeData theme) {
    final dark = theme.brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: dark ? AppTheme.darkElevated : AppTheme.lightElevated,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: ['weekly', 'monthly', 'yearly'].map((p) {
          final isSelected = _period == p;
          return Expanded(
            child: GestureDetector(
              onTap: () {
                setState(() => _period = p);
                _load();
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  color: isSelected
                      ? theme.colorScheme.primary
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(7),
                ),
                child: Text(
                  p[0].toUpperCase() + p.substring(1),
                  textAlign: TextAlign.center,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: isSelected
                        ? Colors.white
                        : theme.colorScheme.onSurfaceVariant,
                    fontSize: 12,
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildBudgetCard(ThemeData theme, Budget b) {
    return FutureBuilder<double>(
      future: _getSpentForBudget(b),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Container(
            margin: const EdgeInsets.only(bottom: 12),
            height: 120,
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: theme.brightness == Brightness.dark
                    ? AppTheme.darkBorder
                    : AppTheme.lightBorder,
              ),
            ),
            child: const Center(child: CircularProgressIndicator()),
          );
        }

        final spent = snapshot.data ?? 0.0;
        final progress = (spent / b.amount).clamp(0.0, 1.0);
        final isOver = spent > b.amount;
        final color = isOver ? AppTheme.expense : theme.colorScheme.primary;
        final dark = theme.brightness == Brightness.dark;

        return Dismissible(
          key: Key('budget_${b.id}'),
          direction: DismissDirection.endToStart,
          background: Container(
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: AppTheme.expense,
              borderRadius: BorderRadius.circular(10),
            ),
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.only(right: 20),
            child: const Icon(Icons.delete_rounded, color: Colors.white),
          ),
          onDismissed: (_) async {
            context.read<BudgetBloc>().add(DeleteBudget(b.id!));
          },
          child: Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isOver
                    ? AppTheme.expense.withOpacity(0.5)
                    : (dark ? AppTheme.darkBorder : AppTheme.lightBorder),
              ),
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                b.category,
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(width: 8),
                              GestureDetector(
                                onTap: () => _showBudgetModal(existing: b),
                                child: Icon(
                                  Icons.edit_rounded,
                                  size: 14,
                                  color: theme.colorScheme.onSurface
                                      .withOpacity(0.2),
                                ),
                              ),
                            ],
                          ),
                          if (b.accountId != null) ...[
                            const SizedBox(height: 4),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: theme.colorScheme.primary.withOpacity(
                                  0.1,
                                ),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                _getAccountName(b.accountId!),
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: theme.colorScheme.primary,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                          const SizedBox(height: 4),
                          Text(
                            '${b.period.capitalize()} · ${(progress * 100).toStringAsFixed(0)}% used',
                            style: theme.textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          '${_rupeeFmt.format(spent)} / ${_rupeeFmt.format(b.amount)}',
                          style: theme.textTheme.titleSmall?.copyWith(
                            color: isOver
                                ? AppTheme.expense
                                : theme.colorScheme.onSurface,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        if (isOver)
                          Text(
                            '+${_rupeeFmt.format(spent - b.amount)}',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: AppTheme.expense,
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: progress,
                    backgroundColor: dark
                        ? AppTheme.darkElevated
                        : AppTheme.lightElevated,
                    color: color,
                    minHeight: 6,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildEmpty(ThemeData theme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          children: [
            Icon(
              Icons.pie_chart_outline_rounded,
              size: 60,
              color: theme.colorScheme.primary.withOpacity(0.2),
            ),
            const SizedBox(height: 12),
            Text(
              'No budgets yet',
              style: theme.textTheme.titleMedium?.copyWith(
                color: theme.colorScheme.onSurface.withOpacity(0.4),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Tap + to set spending limits',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withOpacity(0.3),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

extension StringCap on String {
  String capitalize() =>
      isEmpty ? '' : '${this[0].toUpperCase()}${substring(1)}';
}
