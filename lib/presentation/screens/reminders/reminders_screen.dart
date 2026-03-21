import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';

import 'package:expencify/domain/entities/reminder.dart';
import 'package:expencify/application/blocs/reminder/reminder_bloc.dart';
import 'package:expencify/application/blocs/reminder/reminder_event.dart';
import 'package:expencify/application/blocs/reminder/reminder_state.dart';

class RemindersScreen extends StatefulWidget {
  const RemindersScreen({super.key});

  @override
  State<RemindersScreen> createState() => _RemindersScreenState();
}

class _RemindersScreenState extends State<RemindersScreen> {
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
    context.read<ReminderBloc>().add(LoadReminders());
  }

  Future<void> _showReminderModal({Reminder? existing}) async {
    final formKey = GlobalKey<FormState>();
    final titleCtrl = TextEditingController(text: existing?.title ?? '');
    final amountCtrl = TextEditingController(
      text: existing?.amount.toStringAsFixed(0) ?? '',
    );
    DateTime selectedDate =
        existing?.dueDate ?? DateTime.now().add(const Duration(days: 30));
    bool isRecurring = existing?.isRecurring ?? false;
    String frequency = existing?.frequency ?? 'monthly';

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
                        existing != null ? 'Edit Reminder' : 'New Reminder',
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
                    label: 'Bill / EMI Name',
                    controller: titleCtrl,
                    hint: 'e.g. Internet Bill',
                    icon: Icons.notifications_active_outlined,
                    validator: (v) => (v?.isEmpty ?? true) ? 'Required' : null,
                  ),
                  const SizedBox(height: 16),
                  _buildField(
                    label: 'Amount (₹)',
                    controller: amountCtrl,
                    hint: '0.00',
                    icon: Icons.payments_outlined,
                    keyboardType: TextInputType.number,
                    validator: (v) => (v == null || double.tryParse(v) == null)
                        ? 'Invalid'
                        : null,
                  ),
                  const SizedBox(height: 16),
                  _buildDatePicker(
                    label: 'Due Date',
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
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Recurring Reminder',
                              style: Theme.of(ctx).textTheme.labelMedium
                                  ?.copyWith(
                                    color: Theme.of(
                                      ctx,
                                    ).colorScheme.onSurface.withOpacity(0.6),
                                    fontWeight: FontWeight.bold,
                                  ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Repeat this reminder automatically',
                              style: Theme.of(ctx).textTheme.bodySmall
                                  ?.copyWith(
                                    color: Theme.of(
                                      ctx,
                                    ).colorScheme.onSurface.withOpacity(0.4),
                                  ),
                            ),
                          ],
                        ),
                      ),
                      Switch.adaptive(
                        value: isRecurring,
                        onChanged: (v) => setS(() => isRecurring = v),
                      ),
                    ],
                  ),
                  if (isRecurring) ...[
                    const SizedBox(height: 16),
                    _buildDropdown(
                      label: 'Frequency',
                      value: frequency,
                      items: ['monthly', 'weekly', 'yearly']
                          .map(
                            (f) => DropdownMenuItem(
                              value: f,
                              child: Text(f.capitalize()),
                            ),
                          )
                          .toList(),
                      onChanged: (v) => setS(() => frequency = v!),
                    ),
                  ],
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () async {
                        if (!formKey.currentState!.validate()) return;
                        final r = Reminder(
                          id: existing?.id,
                          title: titleCtrl.text,
                          amount: double.parse(amountCtrl.text),
                          dueDate: selectedDate,
                          isRecurring: isRecurring,
                          frequency: frequency,
                        );

                        context.read<ReminderBloc>().add(SaveReminder(r));
                        if (context.mounted) Navigator.pop(context);
                      },
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      child: Text(
                        existing != null ? 'Update Reminder' : 'Save Reminder',
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

  Widget _buildDropdown({
    required String label,
    required String? value,
    required List<DropdownMenuItem<String>> items,
    required void Function(String?) onChanged,
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
          decoration: InputDecoration(
            prefixIcon: Icon(
              Icons.repeat_rounded,
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
    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: AppBar(
        systemOverlayStyle: SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: theme.brightness == Brightness.dark
              ? Brightness.light
              : Brightness.dark,
          statusBarBrightness: theme.brightness, // For iOS
        ),
        title: const Text('Due Date Alerts'),
        backgroundColor: Colors.transparent,
        actions: [
          IconButton(
            icon: const Icon(Icons.add_rounded),
            onPressed: _showReminderModal,
          ),
        ],
      ),
      body: BlocBuilder<ReminderBloc, ReminderState>(
        builder: (context, state) {
          if (state is ReminderLoading) {
            return const Center(child: CircularProgressIndicator());
          } else if (state is ReminderLoaded) {
            final reminders = state.reminders;
            if (reminders.isEmpty) {
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text('🔔', style: const TextStyle(fontSize: 60)),
                    const SizedBox(height: 12),
                    Text(
                      'No reminders yet',
                      style: theme.textTheme.titleLarge?.copyWith(
                        color: theme.colorScheme.onSurface.withOpacity(0.4),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Never miss an EMI or bill!',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurface.withOpacity(0.3),
                      ),
                    ),
                  ],
                ),
              );
            }
            return ListView.builder(
              padding: const EdgeInsets.all(20),
              itemCount: reminders.length,
              itemBuilder: (ctx, i) {
                final r = reminders[i];
                return Dismissible(
                  key: Key('reminder_${r.id}'),
                  direction: DismissDirection.endToStart,
                  background: Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: Colors.red,
                      borderRadius: BorderRadius.circular(18),
                    ),
                    alignment: Alignment.centerRight,
                    padding: const EdgeInsets.only(right: 20),
                    child: const Icon(
                      Icons.delete_rounded,
                      color: Colors.white,
                    ),
                  ),
                  onDismissed: (_) async {
                    context.read<ReminderBloc>().add(DeleteReminder(r.id!));
                  },
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surface,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color: r.isOverdue
                            ? Colors.red.withOpacity(0.4)
                            : r.isDueSoon
                            ? Colors.orange.withOpacity(0.4)
                            : theme.colorScheme.onSurface.withOpacity(0.08),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.04),
                          blurRadius: 8,
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: r.isOverdue
                                ? Colors.red.withOpacity(0.1)
                                : r.isDueSoon
                                ? Colors.orange.withOpacity(0.1)
                                : const Color(0xFF6366F1).withOpacity(0.1),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Icon(
                            Icons.alarm_rounded,
                            color: r.isOverdue
                                ? Colors.red
                                : r.isDueSoon
                                ? Colors.orange
                                : const Color(0xFF6366F1),
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Text(
                                    r.title,
                                    style: theme.textTheme.titleMedium
                                        ?.copyWith(fontWeight: FontWeight.bold),
                                  ),
                                  const SizedBox(width: 8),
                                  GestureDetector(
                                    onTap: () =>
                                        _showReminderModal(existing: r),
                                    child: Icon(
                                      Icons.edit_rounded,
                                      size: 14,
                                      color: theme.colorScheme.onSurface
                                          .withOpacity(0.2),
                                    ),
                                  ),
                                ],
                              ),
                              Text(
                                'Due: ${DateFormat('d MMM yyyy').format(r.dueDate)}',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: r.isOverdue
                                      ? Colors.red
                                      : theme.colorScheme.onSurface.withOpacity(
                                          0.5,
                                        ),
                                ),
                              ),
                              if (r.isRecurring)
                                Text(
                                  'Recurring · ${r.frequency.capitalize()}',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.onSurface
                                        .withOpacity(0.4),
                                  ),
                                ),
                            ],
                          ),
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              _rupeeFmt.format(r.amount),
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 4),
                            if (r.isOverdue)
                              _badge('OVERDUE', Colors.red)
                            else if (r.isDueSoon)
                              _badge('DUE SOON', Colors.orange)
                            else
                              Text(
                                '${r.daysUntilExpiry} days',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onSurface
                                      .withOpacity(0.4),
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            );
          } else if (state is ReminderError) {
            return Center(child: Text(state.message));
          }
          return const SizedBox.shrink();
        },
      ),
    );
  }

  Widget _badge(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

extension _StringCap on String {
  String capitalize() =>
      isEmpty ? '' : '${this[0].toUpperCase()}${substring(1)}';
}
