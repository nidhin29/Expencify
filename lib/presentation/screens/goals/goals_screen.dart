import '../../widgets/app_date_picker.dart';
import '../../widgets/page_loading.dart';
import 'package:expencify/presentation/theme/app_icons.dart';
import '../../widgets/goal_contribution_sheet.dart';
import '../../../application/services/goals/goal_progress.dart';
import '../../../domain/repositories/goal_repository.dart';
import 'dart:async';
import '../../widgets/form_save_button.dart';
import '../../widgets/tool_cards.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';

import 'package:expencify/domain/entities/goal.dart';
import 'package:expencify/application/blocs/goal/goal_bloc.dart';
import 'package:expencify/application/blocs/goal/goal_event.dart';
import 'package:expencify/application/blocs/goal/goal_state.dart';
import 'package:expencify/application/blocs/account/account_bloc.dart';
import 'package:expencify/application/blocs/account/account_state.dart';

class GoalsScreen extends StatefulWidget {
  const GoalsScreen({super.key});

  @override
  State<GoalsScreen> createState() => _GoalsScreenState();
}

class _GoalsScreenState extends State<GoalsScreen> {
  final _rupeeFmt = NumberFormat.currency(
    locale: 'en_IN',
    symbol: '₹',
    decimalDigits: 0,
  );
  int? _lastAccountId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final accountState = context.read<AccountBloc>().state;
    if (accountState is AccountLoaded) {
      _lastAccountId = accountState.selectedAccountId;
    }
    final bloc = context.read<GoalBloc>();
    await waitForPageLoad(
      bloc.stream,
      (state) =>
          state is GoalError || (state is GoalLoaded && !state.refreshing),
      () => bloc.add(LoadGoals()),
    );
    if (mounted) setState(() {});
  }

  Future<void> _showGoalModal({Goal? existing}) async {
    final formKey = GlobalKey<FormState>();
    final nameCtrl = TextEditingController(text: existing?.name ?? '');
    final amountCtrl = TextEditingController(
      text: existing?.targetAmount.toStringAsFixed(2) ?? '',
    );
    DateTime selectedDate =
        existing?.targetDate ?? DateTime.now().add(const Duration(days: 30));
    final iconOptions = [
      'savings',
      'flight',
      'directions_car',
      'school',
      'phone_android',
      'home',
      'local_hospital',
      'beach_access',
    ];
    String selectedIcon = existing?.icon ?? iconOptions[0];
    int? selectedAccountId = existing?.accountId;
    final icon2emoji = {
      'savings': '💰',
      'flight': '✈️',
      'directions_car': '🚗',
      'school': '📚',
      'phone_android': '📱',
      'home': '🏠',
      'local_hospital': '🏥',
      'beach_access': '🏖️',
    };

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
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        existing != null ? 'Edit Goal' : 'New Savings Goal',
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
                  _buildField(
                    label: 'Goal Name',
                    controller: nameCtrl,
                    hint: 'e.g. New iPhone',
                    icon: Icons.flag_outlined,
                    validator: (v) =>
                        (v?.trim().isEmpty ?? true) ? 'Enter a name' : null,
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
                    label: 'Target Amount (₹)',
                    controller: amountCtrl,
                    hint: '0.00',
                    icon: Icons.track_changes_outlined,
                    keyboardType: TextInputType.number,
                    validator: (v) {
                      final value = double.tryParse(v ?? '');
                      return value == null || !value.isFinite || value <= 0
                          ? 'Enter an amount greater than zero'
                          : null;
                    },
                  ),
                  const SizedBox(height: 16),
                  _buildDatePicker(
                    label: 'Target Date',
                    value: selectedDate,
                    onTap: () async {
                      final d = await showAppDatePicker(
                        title: 'Target date',
                        context: ctx,
                        initialDate: selectedDate,
                        firstDate: selectedDate.isBefore(DateTime.now())
                            ? DateUtils.dateOnly(selectedDate)
                            : DateUtils.dateOnly(DateTime.now()),
                        lastDate: DateTime(2100),
                      );
                      if (d != null) setS(() => selectedDate = d);
                    },
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Choose Icon',
                    style: Theme.of(ctx).textTheme.labelMedium?.copyWith(
                      color: Theme.of(
                        ctx,
                      ).colorScheme.onSurface.withOpacity(0.6),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 60,
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      itemCount: iconOptions.length,
                      itemBuilder: (ctx, i) {
                        final ico = iconOptions[i];
                        final isSelected = selectedIcon == ico;
                        return GestureDetector(
                          onTap: () => setS(() => selectedIcon = ico),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            margin: const EdgeInsets.only(right: 12),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? Theme.of(
                                      context,
                                    ).colorScheme.primary.withOpacity(0.1)
                                  : Theme.of(context).colorScheme.surfaceVariant
                                        .withOpacity(0.3),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: isSelected
                                    ? Theme.of(context).colorScheme.primary
                                    : Colors.transparent,
                              ),
                            ),
                            child: Text(
                              icon2emoji[ico] ?? '💰',
                              style: const TextStyle(fontSize: 24),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: FormSaveButton(
                      onSaved: () => Navigator.pop(ctx),
                      onSave: () async {
                        if (!formKey.currentState!.validate()) return null;
                        final g = Goal(
                          id: existing?.id,
                          name: nameCtrl.text.trim(),
                          targetAmount: double.parse(amountCtrl.text),
                          targetDate: selectedDate,
                          icon: selectedIcon,
                          savedAmount: existing?.savedAmount ?? 0,
                          accountId: selectedAccountId,
                        );
                        final completion = Completer<bool>();
                        context.read<GoalBloc>().add(
                          SaveGoal(g, completion: completion),
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
                        existing != null ? 'Update Goal' : 'Create Goal',
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
      ),
    );
  }

  Future<void> _showContributionModal(Goal goal) async {
    final bloc = context.read<GoalBloc>();
    final repository = context.read<GoalRepository>();
    final result = await showModalBottomSheet<Goal>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      isDismissible: false,
      enableDrag: false,
      builder: (_) => GoalContributionSheet(
        goal: goal,
        onSave: (amount) async {
          final completion = Completer<bool>();
          bloc.add(
            AddGoalContribution(goal.id!, amount, completion: completion),
          );
          if (!await completion.future) {
            throw StateError('Contribution failed.');
          }
          try {
            return (await repository.getAll()).firstWhere(
              (g) => g.id == goal.id,
            );
          } catch (_) {
            return goal.copyWith(
              savedAmount: goal.savedAmount + (amount * 100).round() / 100,
            );
          }
        },
      ),
    );
    if (!mounted || result == null) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        persist: false,
        duration: const Duration(seconds: 4),
        content: Row(
          children: [
            Icon(
              result.isCompleted
                  ? Icons.emoji_events_outlined
                  : AppIcons.success,
              color: Theme.of(context).colorScheme.inversePrimary,
            ),
            const SizedBox(width: 12),
            Expanded(child: Text(goalProgressMessage(goal, result))),
          ],
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

  Widget _buildDatePicker({
    required String label,
    required DateTime value,
    required VoidCallback onTap,
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
        InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: dark ? const Color(0xFF18181B) : const Color(0xFFF4F4F5),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                Icon(
                  AppIcons.calendar,
                  size: 20,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 12),
                Text(
                  DateFormat('d MMM yyyy').format(value),
                  style: theme.textTheme.bodyLarge,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const goalIcons = {
      'savings': AppIcons.goals,
      'flight': Icons.flight_outlined,
      'directions_car': Icons.directions_car_outlined,
      'school': Icons.school_outlined,
      'phone_android': Icons.phone_android_outlined,
      'home': AppIcons.home,
      'local_hospital': Icons.local_hospital_outlined,
      'beach_access': Icons.beach_access_outlined,
    };

    return BlocListener<AccountBloc, AccountState>(
      listener: (context, state) {
        if (state is AccountLoaded) {
          _load();
        }
      },
      child: Scaffold(
        backgroundColor: theme.colorScheme.surface,
        appBar: AppBar(
          systemOverlayStyle: SystemUiOverlayStyle(
            statusBarColor: Colors.transparent,
            statusBarIconBrightness: theme.brightness == Brightness.dark
                ? Brightness.light
                : Brightness.dark,
            statusBarBrightness: theme.brightness, // For iOS
          ),
          title: const Text('Savings Goals'),
          backgroundColor: Colors.transparent,
          actions: [
            BlocBuilder<GoalBloc, GoalState>(
              builder: (context, state) =>
                  state is GoalLoaded &&
                      state.goals
                          .where(
                            (g) =>
                                _lastAccountId == null ||
                                g.accountId == null ||
                                g.accountId == _lastAccountId,
                          )
                          .isEmpty
                  ? const SizedBox.shrink()
                  : IconButton(
                      tooltip: 'Create savings goal',
                      icon: const Icon(AppIcons.add),
                      onPressed: _showGoalModal,
                    ),
            ),
          ],
        ),
        body: RefreshFeedback<GoalBloc, GoalState>(
          onRetry: _load,
          child: BlocBuilder<GoalBloc, GoalState>(
            builder: (context, state) {
              if (state is GoalLoading || state is GoalInitial) {
                return const PageLoading(label: 'Loading goal', summary: false);
              } else if (state is GoalLoaded) {
                final goals = state.goals;
                final showAll = _lastAccountId == null;
                final visibleGoals = goals.where((g) {
                  return showAll ||
                      g.accountId == null ||
                      g.accountId == _lastAccountId;
                }).toList();

                if (visibleGoals.isEmpty) {
                  return ToolEmptyState(
                    icon: AppIcons.goals,
                    title: 'Your next goal starts here',
                    action: 'Create savings goal',
                    onAction: _showGoalModal,
                  );
                }
                return RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(20),
                    itemCount: visibleGoals.length + 1,
                    itemBuilder: (ctx, i) {
                      if (i == 0) {
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 20),
                          child: Text(
                            '${visibleGoals.where((g) => !g.isCompleted).length} active · ${visibleGoals.where((g) => g.isCompleted).length} reached',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        );
                      }
                      final g = visibleGoals[i - 1];
                      return Dismissible(
                        key: Key('goal_${g.id}'),
                        direction: DismissDirection.endToStart,
                        background: Container(
                          margin: const EdgeInsets.only(bottom: 16),
                          decoration: BoxDecoration(
                            color: Colors.red,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          alignment: Alignment.centerRight,
                          padding: const EdgeInsets.only(right: 20),
                          child: const Icon(
                            AppIcons.delete,
                            color: Colors.white,
                          ),
                        ),
                        confirmDismiss: (_) async =>
                            await showDialog<bool>(
                              context: context,
                              builder: (ctx) => AlertDialog(
                                title: const Text('Delete Goal?'),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.pop(ctx, false),
                                    child: const Text('Cancel'),
                                  ),
                                  TextButton(
                                    onPressed: () => Navigator.pop(ctx, true),
                                    child: const Text(
                                      'Delete',
                                      style: TextStyle(color: Colors.red),
                                    ),
                                  ),
                                ],
                              ),
                            ) ??
                            false,
                        onDismissed: (_) async {
                          context.read<GoalBloc>().add(DeleteGoal(g.id!));
                        },
                        child: ToolCard(
                          title: g.name,
                          amount: _rupeeFmt.format(g.savedAmount),
                          detail:
                              'of ${_rupeeFmt.format(g.targetAmount)} · ${DateFormat('d MMM yyyy').format(g.targetDate)}',
                          icon: g.isCompleted
                              ? Icons.emoji_events_outlined
                              : goalIcons[g.icon] ?? AppIcons.goals,
                          status: g.isCompleted ? 'Goal reached' : null,
                          progress: g.progress,
                          progressLabel: g.isCompleted
                              ? '100% complete'
                              : '${(g.progress * 100).floor()}% · ${_rupeeFmt.format(g.targetAmount - g.savedAmount)} left',
                          onEdit: () => _showGoalModal(existing: g),
                          actionLabel: 'Add savings',
                          onAction: g.isCompleted
                              ? null
                              : () => _showContributionModal(g),
                        ),
                      );
                    },
                  ),
                );
              } else if (state is GoalError) {
                return PageLoadFailure(onRetry: _load);
              }
              return const SizedBox.shrink();
            },
          ),
        ),
      ),
    );
  }
}
