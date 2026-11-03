import '../../widgets/app_date_picker.dart';
import '../../widgets/page_loading.dart';
import 'package:expencify/presentation/theme/app_icons.dart';
import '../../../application/services/notifications/notification_service.dart';
import '../../widgets/tool_cards.dart';
import 'dart:async';
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
    final bloc = context.read<ReminderBloc>();
    await waitForPageLoad(
      bloc.stream,
      (state) =>
          state is ReminderError ||
          (state is ReminderLoaded && !state.refreshing),
      () => bloc.add(LoadReminders()),
    );
  }

  Future<void> _markHandled(Reminder reminder) async {
    final bloc = context.read<ReminderBloc>();
    final completion = Completer<HandledReminder?>();
    bloc.add(HandleReminder(reminder, completion: completion));
    final result = await completion.future;
    if (!mounted || result == null) return;
    ScaffoldMessenger.of(context).removeCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        persist: false,
        duration: const Duration(seconds: 6),
        content: Text(
          result.next == null
              ? 'Reminder completed'
              : 'Next reminder: ${DateFormat('d MMM').format(result.next!.dueDate)}',
        ),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () => bloc.add(UndoHandleReminder(result)),
        ),
      ),
    );
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
                        tooltip: 'Close',
                        onPressed: () => Navigator.pop(ctx),
                        icon: const Icon(AppIcons.close),
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
                      final d = await showAppDatePicker(
                        title: 'Payment due date',
                        context: ctx,
                        initialDate: selectedDate,
                        firstDate: selectedDate.isBefore(DateTime.now())
                            ? DateUtils.dateOnly(selectedDate)
                            : DateUtils.dateOnly(DateTime.now()),
                        lastDate: DateTime(
                          (selectedDate.year > DateTime.now().year
                                  ? selectedDate.year
                                  : DateTime.now().year) +
                              10,
                        ),
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
                          recurrenceAnchor:
                              existing?.dueDate == selectedDate &&
                                  existing?.frequency == frequency
                              ? existing?.recurrenceAnchor
                              : null,
                          isRecurring: isRecurring,
                          frequency: frequency,
                        );

                        await NotificationService().requestPermission(
                          scheduled: true,
                        );
                        if (!mounted) return;
                        context.read<ReminderBloc>().add(SaveReminder(r));
                        if (ctx.mounted) Navigator.pop(ctx);
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
              AppIcons.recurring,
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
        title: const Text('Reminders'),
        backgroundColor: Colors.transparent,
        actions: [
          BlocBuilder<ReminderBloc, ReminderState>(
            builder: (context, state) =>
                state is ReminderLoaded && state.reminders.isEmpty
                ? const SizedBox.shrink()
                : IconButton(
                    tooltip: 'Add reminder',
                    icon: const Icon(AppIcons.add),
                    onPressed: _showReminderModal,
                  ),
          ),
        ],
      ),
      body: RefreshFeedback<ReminderBloc, ReminderState>(
        onRetry: _load,
        child: BlocBuilder<ReminderBloc, ReminderState>(
          builder: (context, state) {
            if (state is ReminderLoading || state is ReminderInitial) {
              return const PageLoading(
                label: 'Loading reminder',
                summary: false,
              );
            } else if (state is ReminderLoaded) {
              final reminders = state.reminders;
              if (reminders.isEmpty) {
                return ToolEmptyState(
                  icon: AppIcons.reminder,
                  title: 'No reminders yet',
                  action: 'Add reminder',
                  onAction: _showReminderModal,
                );
              }
              return ListView.builder(
                padding: const EdgeInsets.all(20),
                itemCount: reminders.length,
                itemBuilder: (ctx, i) {
                  final r = reminders[i];
                  return ToolCard(
                    title: r.title,
                    amount: _rupeeFmt.format(r.amount),
                    detail:
                        'Due ${DateFormat('d MMM yyyy').format(r.dueDate)}${r.isRecurring ? ' · ${r.frequency.capitalize()}' : ''}',
                    icon: AppIcons.reminder,
                    status: r.isOverdue
                        ? 'Overdue'
                        : r.isDueSoon
                        ? 'Due soon'
                        : null,
                    urgent: r.isOverdue,
                    onEdit: () => _showReminderModal(existing: r),
                    onDelete: () =>
                        context.read<ReminderBloc>().add(DeleteReminder(r.id!)),
                    actionLabel: 'Done',
                    onAction: () => _markHandled(r),
                  );
                },
              );
            } else if (state is ReminderError) {
              return PageLoadFailure(onRetry: _load);
            }
            return const SizedBox.shrink();
          },
        ),
      ),
    );
  }
}

extension _StringCap on String {
  String capitalize() =>
      isEmpty ? '' : '${this[0].toUpperCase()}${substring(1)}';
}
