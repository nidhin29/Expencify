import '../../widgets/app_menu_item.dart';
import '../../widgets/page_loading.dart';
import 'package:expencify/presentation/theme/app_icons.dart';
import '../../theme/app_theme.dart';
import '../../widgets/finance_summary_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import '../../../application/services/payments/upcoming_payments.dart';
import '../../../application/services/notifications/budget_update_service.dart';
import '../../../domain/repositories/reminder_repository.dart';
import '../../../domain/repositories/subscription_repository.dart';
import '../../../application/blocs/reminder/reminder_bloc.dart';
import '../../../application/blocs/reminder/reminder_event.dart';
import '../../../application/blocs/subscription/subscription_bloc.dart';
import '../../../application/blocs/subscription/subscription_event.dart';
import '../reminders/reminders_screen.dart';
import '../subscriptions/subscriptions_screen.dart';

class UpcomingPaymentsScreen extends StatefulWidget {
  const UpcomingPaymentsScreen({super.key});
  @override
  State<UpcomingPaymentsScreen> createState() => _UpcomingPaymentsScreenState();
}

class _UpcomingPaymentsScreenState extends State<UpcomingPaymentsScreen> {
  List<UpcomingPayment>? _rows;
  bool _failed = false;
  bool _refreshing = false;
  int _request = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final request = ++_request;
    setState(() {
      _refreshing = true;
      _failed = false;
    });
    try {
      final reminders = await context.read<ReminderRepository>().getAll();
      if (!mounted || request != _request) return;
      final subscriptions = await context.read<SubscriptionRepository>().getAll(
        activeOnly: true,
      );
      if (mounted && request == _request) {
        setState(() {
          _rows = upcomingPayments(reminders, subscriptions, DateTime.now());
          _failed = false;
        });
      }
    } catch (_) {
      if (mounted && request == _request) setState(() => _failed = true);
    } finally {
      if (mounted && request == _request) setState(() => _refreshing = false);
    }
  }

  Future<void> _manage(bool subscription) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => subscription
            ? const SubscriptionsScreen()
            : const RemindersScreen(),
      ),
    );
    if (!mounted) return;
    context.read<ReminderBloc>().add(LoadReminders());
    context.read<SubscriptionBloc>().add(LoadSubscriptions());
    await _load();
  }

  String _count(int count) => '$count ${count == 1 ? 'payment' : 'payments'}';
  int _total(List<UpcomingPayment> rows) =>
      rows.fold(0, (sum, row) => sum + row.cents);
  int _days(DateTime date, DateTime now) => DateTime.utc(
    date.year,
    date.month,
    date.day,
  ).difference(DateTime.utc(now.year, now.month, now.day)).inDays;
  String _dateLabel(DateTime date, DateTime now) {
    final days = _days(date, now);
    if (days == 0) return 'Today';
    if (days == 1) return 'Tomorrow';
    return DateFormat(
      date.year == now.year ? 'EEE, d MMM' : 'EEE, d MMM yyyy',
    ).format(date);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final rows = _rows;
    final now = DateTime.now();
    final overdue = rows?.where((r) => r.overdue(now)).toList() ?? [];
    final due = rows?.where((r) => !r.overdue(now)).toList() ?? [];
    return Scaffold(
      appBar: AppBar(
        title: const Text('Payments'),
        actions: [
          PopupMenuButton<bool>(
            clipBehavior: Clip.antiAlias,
            tooltip: 'Manage payments',
            icon: const Icon(AppIcons.more),
            onSelected: _manage,
            itemBuilder: (_) => const [
              AppMenuItem(
                value: false,
                label: 'Manage reminders',
                icon: AppIcons.reminder,
              ),
              AppMenuItem(
                value: true,
                label: 'Manage subscriptions',
                icon: AppIcons.recurring,
              ),
            ],
          ),
        ],
      ),
      body: LoadingFeedback(
        loading: _refreshing && _rows != null,
        error: _rows != null && _failed
            ? 'Could not refresh. Your previous data is still shown.'
            : null,
        onRetry: _load,
        child: _failed && _rows == null
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(AppIcons.error, size: 40),
                      const SizedBox(height: 12),
                      Text(
                        'Could not load payments',
                        style: theme.textTheme.titleMedium,
                      ),
                      const SizedBox(height: 12),
                      FilledButton(
                        onPressed: _load,
                        child: const Text('Try again'),
                      ),
                    ],
                  ),
                ),
              )
            : rows == null
            ? const PageLoading(label: 'Loading payments')
            : rows.isEmpty
            ? RefreshIndicator(
                onRefresh: _load,
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(24, 56, 24, 32),
                  children: [_empty(theme)],
                ),
              )
            : RefreshIndicator(
                onRefresh: _load,
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
                  children: [
                    FinanceSummaryCard(
                      label: 'Due in the next 7 days',
                      value: BudgetUpdateService.amount(_total(due)),
                      caption: '${_count(due.length)} scheduled · All accounts',
                      icon: Icons.calendar_month_outlined,
                    ),
                    if (overdue.isNotEmpty) ...[
                      const SizedBox(height: 28),
                      _section(
                        'Overdue',
                        overdue.length,
                        theme,
                        overdue: true,
                        total: _total(overdue),
                      ),
                      const SizedBox(height: 12),
                      ...overdue.map((row) => _payment(row, now)),
                    ],
                    if (due.isNotEmpty) ...[
                      const SizedBox(height: 24),
                      _section('Coming up', due.length, theme),
                      const SizedBox(height: 8),
                      ..._byDate(due, now, theme),
                    ] else
                      Padding(
                        padding: const EdgeInsets.only(top: 20),
                        child: Text(
                          'No payments scheduled for the next 7 days.',
                          style: theme.textTheme.bodyMedium,
                        ),
                      ),
                  ],
                ),
              ),
      ),
    );
  }

  Color _alert(ThemeData theme) => theme.brightness == Brightness.dark
      ? const Color(0xFFFDA4AF)
      : theme.colorScheme.error;
  Widget _section(
    String title,
    int count,
    ThemeData theme, {
    bool overdue = false,
    int? total,
  }) {
    final color = overdue ? _alert(theme) : theme.colorScheme.onSurface;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            if (overdue) ...[
              Icon(AppIcons.error, size: 20, color: color),
              const SizedBox(width: 8),
            ],
            Expanded(
              child: Text(
                title,
                style: theme.textTheme.titleMedium?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: color.withValues(alpha: .08),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '$count',
                style: theme.textTheme.labelMedium?.copyWith(color: color),
              ),
            ),
          ],
        ),
        if (total != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              '${BudgetUpdateService.amount(total)} outstanding',
              style: theme.textTheme.bodyMedium?.copyWith(color: color),
            ),
          ),
      ],
    );
  }

  List<Widget> _byDate(
    List<UpcomingPayment> rows,
    DateTime now,
    ThemeData theme,
  ) {
    final result = <Widget>[];
    DateTime? previous;
    for (final row in rows) {
      final date = DateTime(row.due.year, row.due.month, row.due.day);
      if (date != previous) {
        result.add(
          Padding(
            padding: const EdgeInsets.only(top: 12, bottom: 10),
            child: Text(
              _dateLabel(date, now),
              style: theme.textTheme.labelLarge?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        );
        previous = date;
      }
      result.add(_payment(row, now));
    }
    return result;
  }

  Widget _payment(UpcomingPayment row, DateTime now) {
    final theme = Theme.of(context), cs = theme.colorScheme;
    final late = row.overdue(now);
    final color = late ? _alert(theme) : cs.primary;
    final stacked = MediaQuery.textScalerOf(context).scale(1) > 1.3;
    final amount = Text(
      BudgetUpdateService.amount(row.cents),
      style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
    );
    final details = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          row.name,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 5),
        Text(
          late
              ? '${row.kind} · Due ${DateFormat(row.due.year == now.year ? 'd MMM' : 'd MMM yyyy').format(row.due)}'
              : row.kind,
          style: theme.textTheme.bodySmall?.copyWith(
            color: cs.onSurfaceVariant,
          ),
        ),
      ],
    );
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: late
              ? color.withValues(alpha: .3)
              : theme.brightness == Brightness.dark
              ? AppTheme.darkBorder
              : AppTheme.lightBorder,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => _manage(row.kind == 'Subscription'),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: .09),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      row.kind == 'Subscription'
                          ? AppIcons.recurring
                          : AppIcons.reminder,
                      color: color,
                      size: 21,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(child: details),
                  if (!stacked) ...[
                    const SizedBox(width: 12),
                    ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth: MediaQuery.sizeOf(context).width * .30,
                      ),
                      child: amount,
                    ),
                  ],
                  const SizedBox(width: 8),
                  Icon(AppIcons.chevron, size: 18, color: cs.onSurfaceVariant),
                ],
              ),
              if (stacked)
                Padding(padding: const EdgeInsets.only(top: 12), child: amount),
              if (late)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: .08),
                      borderRadius: BorderRadius.circular(7),
                    ),
                    child: Text(
                      '${-_days(row.due, now)} ${-_days(row.due, now) == 1 ? 'day' : 'days'} overdue',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: color,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _empty(ThemeData theme) => Padding(
    padding: EdgeInsets.zero,
    child: Column(
      children: [
        Container(
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            color: theme.colorScheme.primary.withValues(alpha: .08),
            shape: BoxShape.circle,
          ),
          child: Icon(
            Icons.event_available_outlined,
            size: 40,
            color: theme.colorScheme.primary,
          ),
        ),
        const SizedBox(height: 20),
        Text('Nothing due', style: theme.textTheme.titleLarge),
        const SizedBox(height: 8),
        Text(
          'No payments scheduled for the next 7 days.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: 24),
        OutlinedButton(
          onPressed: () => _manage(false),
          child: const Text('Manage reminders'),
        ),
      ],
    ),
  );
}
