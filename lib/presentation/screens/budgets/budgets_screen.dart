import '../../widgets/page_loading.dart';
import 'package:expencify/presentation/theme/app_icons.dart';
import '../../widgets/centered_empty_state.dart';
import '../../../application/services/notifications/budget_period.dart';
import '../settings/budget_updates_screen.dart';
import 'dart:async';
import '../../widgets/form_save_button.dart';
import '../../../application/services/notifications/notification_service.dart';
import '../../widgets/budget_welcome_card.dart';
import '../../widgets/finance_summary_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
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
  final bool isActive;
  const BudgetScreen({super.key, this.onRefresh, this.isActive = false});

  @override
  State<BudgetScreen> createState() => _BudgetScreenState();
}

class _BudgetScreenState extends State<BudgetScreen> {
  final _rupeeFmt = NumberFormat.currency(
    locale: 'en_IN',
    symbol: '₹',
    decimalDigits: 0,
  );
  final Map<Budget, Future<double>> _spentCache = {};
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
    _spentCache.clear();

    final bloc = context.read<BudgetBloc>();
    await waitForPageLoad(
      bloc.stream,
      (state) =>
          state is BudgetError || (state is BudgetLoaded && !state.refreshing),
      () => bloc.add(LoadBudgets(period: _period)),
    );
  }

  Future<double> _getSpentForBudget(Budget b) async {
    final now = DateTime.now();
    if (b.startDate.isAfter(now)) return 0;
    final (start, _) = budgetPeriod(b.period, now);
    final totals = await context
        .read<TransactionRepository>()
        .getCategoryTotals(
          type: 'expense',
          from: b.startDate.isAfter(start) ? b.startDate : start,
          to: now,
          accountId: b.accountId,
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
      text: existing?.amount.toStringAsFixed(2) ?? '',
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
                      tooltip: 'Close',
                      onPressed: () => Navigator.pop(ctx),
                      icon: const Icon(AppIcons.close),
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
                      icon: AppIcons.accounts,
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
                    final amount = double.tryParse(v);
                    if (amount == null || !amount.isFinite || amount <= 0) {
                      return 'Enter an amount greater than zero';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: FormSaveButton(
                    onSaved: () => Navigator.pop(ctx),
                    onSave: () async {
                      if (!formKey.currentState!.validate()) return null;
                      final b = Budget(
                        id: existing?.id,
                        category: selectedCat!,
                        amount: double.parse(amountCtrl.text),
                        period: existing?.period ?? _period,
                        startDate: existing?.startDate ?? DateTime.now(),
                        accountId: selectedAccountId,
                      );
                      await NotificationService().requestPermission();
                      if (!mounted) return null;
                      final completion = Completer<bool>();
                      context.read<BudgetBloc>().add(
                        SaveBudget(b, completion: completion),
                      );
                      return completion.future;
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
              icon ?? AppIcons.categories,
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
              tooltip: 'Spending updates',
              icon: const Icon(AppIcons.reminder),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const BudgetUpdatesScreen()),
              ),
            ),
            BlocBuilder<BudgetBloc, BudgetState>(
              builder: (context, state) {
                if (state is! BudgetLoaded ||
                    _visibleBudgets(state.budgets).isEmpty) {
                  return const SizedBox.shrink();
                }
                return IconButton(
                  tooltip: 'Create budget',
                  icon: const Icon(AppIcons.add),
                  onPressed: _showBudgetModal,
                );
              },
            ),
          ],
        ),
        body: RefreshFeedback<BudgetBloc, BudgetState>(
          onRetry: _load,
          child: BlocBuilder<BudgetBloc, BudgetState>(
            builder: (context, state) {
              if (state is BudgetLoading || state is BudgetInitial) {
                return const PageLoading(
                  label: 'Loading budget',
                  summary: true,
                );
              } else if (state is BudgetLoaded) {
                final visibleBudgets = _visibleBudgets(state.budgets);

                if (visibleBudgets.isEmpty) {
                  return Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                        child: _buildPeriodSelector(theme),
                      ),
                      Expanded(
                        child: RefreshIndicator(
                          onRefresh: _load,
                          child: CenteredEmptyState(
                            padding: const EdgeInsets.all(20),
                            child: _buildEmpty(theme),
                          ),
                        ),
                      ),
                    ],
                  );
                }
                return RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(20),
                    children: [
                      _buildPeriodSelector(theme),
                      const SizedBox(height: 20),
                      FinanceSummaryCard(
                        label: 'Planned spending limits',
                        value: _rupeeFmt.format(
                          visibleBudgets.fold<double>(
                            0,
                            (total, budget) => total + budget.amount,
                          ),
                        ),
                        caption:
                            '${visibleBudgets.length} ${_period.toLowerCase()} ${visibleBudgets.length == 1 ? 'category limit' : 'category limits'}',
                        icon: AppIcons.budget,
                      ),
                      const SizedBox(height: 24),
                      ...visibleBudgets.map((b) => _buildBudgetCard(theme, b)),
                    ],
                  ),
                );
              } else if (state is BudgetError) {
                return PageLoadFailure(onRetry: _load);
              }
              return CenteredEmptyState(child: _buildEmpty(theme));
            },
          ),
        ),
      ),
    );
  }

  List<Budget> _visibleBudgets(List<Budget> budgets) => budgets
      .where(
        (budget) =>
            (_lastAccountId == null ||
                budget.accountId == null ||
                budget.accountId == _lastAccountId) &&
            budget.period.toLowerCase() == _period.toLowerCase(),
      )
      .toList();

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
      future: _spentCache.putIfAbsent(b, () => _getSpentForBudget(b)),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData) {
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
            child: const PageLoading(label: 'Loading budget spending'),
          );
        }

        if (snapshot.hasError) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: SizedBox(
              height: 180,
              child: PageLoadFailure(
                onRetry: _load,
                message: 'Could not load budget spending.',
              ),
            ),
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
            child: const Icon(AppIcons.delete, color: Colors.white),
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
                                  AppIcons.edit,
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
                            '${b.period.capitalize()} · ${(progress * 100).toStringAsFixed(2)}% used',
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

  Widget _buildEmpty(ThemeData theme) =>
      BudgetWelcomeCard(onCreate: () => _showBudgetModal());
}

extension StringCap on String {
  String capitalize() =>
      isEmpty ? '' : '${this[0].toUpperCase()}${substring(1)}';
}
