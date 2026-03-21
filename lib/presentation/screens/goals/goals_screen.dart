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
    context.read<GoalBloc>().add(LoadGoals());
    if (mounted) setState(() {});
  }

  Future<void> _showGoalModal({Goal? existing}) async {
    final formKey = GlobalKey<FormState>();
    final nameCtrl = TextEditingController(text: existing?.name ?? '');
    final amountCtrl = TextEditingController(
      text: existing?.targetAmount.toStringAsFixed(0) ?? '',
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
                        onPressed: () => Navigator.pop(ctx),
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  _buildField(
                    label: 'Goal Name',
                    controller: nameCtrl,
                    hint: 'e.g. New iPhone',
                    icon: Icons.flag_outlined,
                    validator: (v) => (v?.isEmpty ?? true) ? 'Required' : null,
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
                    label: 'Target Amount (₹)',
                    controller: amountCtrl,
                    hint: '0.00',
                    icon: Icons.track_changes_outlined,
                    keyboardType: TextInputType.number,
                    validator: (v) => (v == null || double.tryParse(v) == null)
                        ? 'Invalid'
                        : null,
                  ),
                  const SizedBox(height: 16),
                  _buildDatePicker(
                    label: 'Target Date',
                    value: selectedDate,
                    onTap: () async {
                      final d = await showDatePicker(
                        context: ctx,
                        initialDate: selectedDate,
                        firstDate: DateTime.now(),
                        lastDate: DateTime(2030),
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
                    child: ElevatedButton(
                      onPressed: () async {
                        if (!formKey.currentState!.validate()) return;
                        final g = Goal(
                          id: existing?.id,
                          name: nameCtrl.text,
                          targetAmount: double.parse(amountCtrl.text),
                          targetDate: selectedDate,
                          icon: selectedIcon,
                          savedAmount: existing?.savedAmount ?? 0,
                          accountId: selectedAccountId,
                        );
                        context.read<GoalBloc>().add(SaveGoal(g));
                        if (ctx.mounted) Navigator.pop(ctx);
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
    final ctrl = TextEditingController();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
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
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Add to ${goal.name}',
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
              _buildField(
                label: 'Contribution Amount (₹)',
                controller: ctrl,
                hint: '0.00',
                icon: Icons.add_circle_outline_rounded,
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () async {
                    final amount = double.tryParse(ctrl.text);
                    if (amount == null || amount <= 0) return;
                    context.read<GoalBloc>().add(
                      AddGoalContribution(goal.id!, amount),
                    );
                    if (ctx.mounted) Navigator.pop(ctx);
                  },
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: const Text(
                    'Add Contribution',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                ),
              ),
            ],
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
                  Icons.calendar_today_outlined,
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
            IconButton(
              icon: const Icon(Icons.add_rounded),
              onPressed: _showGoalModal,
            ),
          ],
        ),
        body: BlocBuilder<GoalBloc, GoalState>(
          builder: (context, state) {
            if (state is GoalLoading) {
              return const Center(child: CircularProgressIndicator());
            } else if (state is GoalLoaded) {
              final goals = state.goals;
              final showAll = _lastAccountId == null;
              final visibleGoals = goals.where((g) {
                return showAll ||
                    g.accountId == null ||
                    g.accountId == _lastAccountId;
              }).toList();

              if (visibleGoals.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text('💰', style: TextStyle(fontSize: 64)),
                      const SizedBox(height: 16),
                      Text(
                        'No goals yet',
                        style: theme.textTheme.titleLarge?.copyWith(
                          color: theme.colorScheme.onSurface.withOpacity(0.4),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Tap + to start saving for your dreams!',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurface.withOpacity(0.3),
                        ),
                      ),
                    ],
                  ),
                );
              }
              return RefreshIndicator(
                onRefresh: _load,
                child: ListView.builder(
                  padding: const EdgeInsets.all(20),
                  itemCount: visibleGoals.length,
                  itemBuilder: (ctx, i) {
                    final g = visibleGoals[i];
                    final emoji = icon2emoji[g.icon] ?? '💰';
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
                          Icons.delete_rounded,
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
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 16),
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surface,
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(
                            color: g.isCompleted
                                ? Colors.green.withOpacity(0.4)
                                : theme.colorScheme.onSurface.withOpacity(0.08),
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.04),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 80,
                              height: 80,
                              decoration: BoxDecoration(
                                color: Color(g.color).withOpacity(0.1),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(
                                    emoji,
                                    style: const TextStyle(fontSize: 30),
                                  ),
                                  Text(
                                    '${(g.progress * 100).toStringAsFixed(0)}%',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      color: Color(g.color),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Row(
                                          children: [
                                            Text(
                                              g.name,
                                              style: theme.textTheme.titleMedium
                                                  ?.copyWith(
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                            ),
                                            const SizedBox(width: 8),
                                            GestureDetector(
                                              onTap: () =>
                                                  _showGoalModal(existing: g),
                                              child: Icon(
                                                Icons.edit_rounded,
                                                size: 14,
                                                color: theme
                                                    .colorScheme
                                                    .onSurface
                                                    .withOpacity(0.2),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      if (g.isCompleted)
                                        const Text(
                                          '✅',
                                          style: TextStyle(fontSize: 16),
                                        ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    '${_rupeeFmt.format(g.savedAmount)} of ${_rupeeFmt.format(g.targetAmount)}',
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: theme.colorScheme.onSurface
                                          .withOpacity(0.6),
                                    ),
                                  ),
                                  Text(
                                    'By ${DateFormat('d MMM yyyy').format(g.targetDate)}',
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: theme.colorScheme.onSurface
                                          .withOpacity(0.4),
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(6),
                                    child: LinearProgressIndicator(
                                      value: g.progress,
                                      backgroundColor: Color(
                                        g.color,
                                      ).withOpacity(0.1),
                                      color: Color(g.color),
                                      minHeight: 6,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            if (!g.isCompleted)
                              IconButton(
                                icon: const Icon(Icons.add_circle_rounded),
                                color: Color(g.color),
                                onPressed: () => _showContributionModal(g),
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              );
            } else if (state is GoalError) {
              return Center(child: Text(state.message));
            }
            return const SizedBox.shrink();
          },
        ),
      ),
    );
  }
}
