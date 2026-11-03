import 'package:expencify/presentation/theme/app_icons.dart';
import 'package:flutter/material.dart';
import '../../domain/entities/goal.dart';
import '../../application/services/notifications/budget_update_service.dart';

class GoalContributionSheet extends StatefulWidget {
  final Goal goal;
  final Future<Goal> Function(double) onSave;
  const GoalContributionSheet({
    super.key,
    required this.goal,
    required this.onSave,
  });
  @override
  State<GoalContributionSheet> createState() => _GoalContributionSheetState();
}

class _GoalContributionSheetState extends State<GoalContributionSheet> {
  final _amount = TextEditingController();
  final _form = GlobalKey<FormState>();
  bool _busy = false;
  String? _error;
  Future<void> _save() async {
    if (_busy || !_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final updated = await widget.onSave(double.parse(_amount.text.trim()));
      if (mounted) Navigator.pop(context, updated);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'Could not record savings. Your amount is still here. Try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          16,
          20,
          MediaQuery.viewInsetsOf(context).bottom + 20,
        ),
        child: SingleChildScrollView(
          child: Form(
            key: _form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Add to ${widget.goal.name}',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Close',
                      onPressed: _busy ? null : () => Navigator.pop(context),
                      icon: const Icon(AppIcons.close),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  '${BudgetUpdateService.amount(((widget.goal.targetAmount - widget.goal.savedAmount) * 100).round().clamp(0, 1 << 60))} left to reach your goal',
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _amount,
                  enabled: !_busy,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Contribution amount',
                    prefixText: '₹ ',
                  ),
                  validator: (v) {
                    final n = double.tryParse(v ?? '');
                    return n == null ||
                            !n.isFinite ||
                            n > 1e12 ||
                            (n * 100).round() <= 0
                        ? 'Enter an amount of at least ₹0.01'
                        : null;
                  },
                ),
                const SizedBox(height: 12),
                const Text('Records your goal progress. No money is moved.'),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                      _error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: _busy ? null : _save,
                  child: Text(_busy ? 'Recording…' : 'Add savings'),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
