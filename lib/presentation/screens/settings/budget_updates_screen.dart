import '../../widgets/spending_time_dialog.dart';
import '../../widgets/page_loading.dart';
import 'package:expencify/presentation/theme/app_icons.dart';
import '../../../application/services/notifications/notification_access.dart';
import 'package:flutter/material.dart';
import '../../../application/services/notifications/budget_update_preferences.dart';
import '../../../application/services/notifications/budget_update_scheduler.dart';

class BudgetUpdatesScreen extends StatefulWidget {
  final NotificationAccess notificationAccess;
  const BudgetUpdatesScreen({
    super.key,
    this.notificationAccess = const NotificationAccess(),
  });
  @override
  State<BudgetUpdatesScreen> createState() => _BudgetUpdatesScreenState();
}

class _BudgetUpdatesScreenState extends State<BudgetUpdatesScreen>
    with WidgetsBindingObserver {
  bool? _notificationsEnabled;
  int _permissionRequest = 0;
  BudgetUpdatePreferences? _prefs;
  bool _busy = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refreshPermission();
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refreshPermission();
  }

  Future<void> _refreshPermission() async {
    final request = ++_permissionRequest;
    try {
      final enabled = await widget.notificationAccess.status();
      if (mounted && request == _permissionRequest) {
        setState(() => _notificationsEnabled = enabled);
      }
    } catch (_) {
      if (mounted && request == _permissionRequest) {
        setState(() => _notificationsEnabled = null);
      }
    }
  }

  Future<void> _openNotificationSettings() async {
    try {
      final opened = await widget.notificationAccess.openSettings();
      if (!mounted) return;
      if (!opened) {
        setState(
          () => _error =
              'Could not open notification settings. Please try again.',
        );
      }
      await _refreshPermission();
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'Could not open notification settings. Please try again.',
        );
      }
    }
  }

  Future<void> _load() async {
    try {
      final p = await BudgetUpdatePreferences.load();
      if (mounted) {
        setState(() {
          _prefs = p;
          _error = null;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not load spending updates.');
    }
  }

  Future<void> _save({
    bool? weekly,
    int? weeklyMinute,
    bool? morning,
    bool? evening,
    bool? limits,
    int? morningMinute,
    int? eveningMinute,
  }) async {
    final old = _prefs!;
    final next = BudgetUpdatePreferences(
      weekly: weekly ?? old.weekly,
      weeklyMinute: weeklyMinute ?? old.weeklyMinute,
      morning: morning ?? old.morning,
      evening: evening ?? old.evening,
      limits: limits ?? old.limits,
      morningMinute: morningMinute ?? old.morningMinute,
      eveningMinute: eveningMinute ?? old.eveningMinute,
    );
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await next.save();
      if (mounted) setState(() => _prefs = next);
      if (weekly == true ||
          morning == true ||
          evening == true ||
          limits == true) {
        await widget.notificationAccess.request();
        await _refreshPermission();
      }
      await BudgetUpdateScheduler.configure();
    } on ArgumentError {
      if (mounted) {
        setState(
          () => _error = 'Choose a morning time before the evening recap.',
        );
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'Could not finish saving or scheduling updates. Please retry.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _time(String kind) async {
    final p = _prefs!;
    final minute = switch (kind) {
      'morning' => p.morningMinute,
      'evening' => p.eveningMinute,
      _ => p.weeklyMinute,
    };
    final title = switch (kind) {
      'morning' => 'Morning plan time',
      'evening' => 'Evening recap time',
      _ => 'Monday recap time',
    };
    final picked = await showDialog<TimeOfDay>(
      context: context,
      builder: (_) => SpendingTimeDialog(
        title: title,
        initialTime: TimeOfDay(hour: minute ~/ 60, minute: minute % 60),
      ),
    );
    if (!mounted || picked == null) return;
    final value = picked.hour * 60 + picked.minute;
    switch (kind) {
      case 'morning':
        await _save(morningMinute: value);
      case 'evening':
        await _save(eveningMinute: value);
      default:
        await _save(weeklyMinute: value);
    }
  }

  String _label(int minute) =>
      TimeOfDay(hour: minute ~/ 60, minute: minute % 60).format(context);

  Widget _updateCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required bool enabled,
    required ValueChanged<bool>? onChanged,
    String? timeLabel,
    int? minute,
    String? kind,
  }) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: .6)),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: cs.primaryContainer.withValues(alpha: .5),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(icon, size: 20, color: cs.primary),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(title, style: theme.textTheme.titleSmall),
                      ),
                      const SizedBox(width: 8),
                      Semantics(
                        label: title,
                        child: Switch.adaptive(
                          value: enabled,
                          onChanged: onChanged,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    subtitle,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            if (minute != null && enabled) ...[
              Divider(
                height: 1,
                indent: 16,
                endIndent: 16,
                color: cs.outlineVariant.withValues(alpha: .6),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 16,
                  runSpacing: 4,
                  children: [
                    Text(
                      timeLabel!,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                    TextButton.icon(
                      key: ValueKey('time-$kind'),
                      onPressed: _busy ? null : () => _time(kind!),
                      icon: const Icon(Icons.schedule_rounded, size: 20),
                      label: Text(_label(minute)),
                      style: TextButton.styleFrom(
                        minimumSize: const Size(112, 48),
                        backgroundColor: cs.primaryContainer.withValues(
                          alpha: .35,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = _prefs;
    final theme = Theme.of(context);
    final scheduled = !_busy && BudgetUpdateScheduler.supported;
    return Scaffold(
      appBar: AppBar(title: const Text('Spending updates')),
      body: p == null
          ? (_error == null
                ? const PageLoading(label: 'Loading spending updates')
                : PageLoadFailure(message: _error!, onRetry: _load))
          : ListView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
              children: [
                SizedBox(
                  height: 3,
                  child: _busy ? const LinearProgressIndicator() : null,
                ),
                if (_notificationsEnabled == false)
                  Card(
                    color: theme.colorScheme.secondaryContainer,
                    margin: const EdgeInsets.only(bottom: 16),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Notifications are off',
                            style: theme.textTheme.titleSmall,
                          ),
                          const SizedBox(height: 6),
                          const Text(
                            'Allow notifications in system settings to receive these updates.',
                          ),
                          TextButton(
                            onPressed: _openNotificationSettings,
                            child: const Text('Open settings'),
                          ),
                        ],
                      ),
                    ),
                  ),
                if (_error != null)
                  MaterialBanner(
                    content: Text(_error!),
                    actions: [
                      TextButton(
                        onPressed: _busy ? null : () => _save(),
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                Padding(
                  padding: const EdgeInsets.only(bottom: 16, top: 8),
                  child: Text(
                    'Your daily check-in',
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                _updateCard(
                  title: 'Morning plan',
                  subtitle: 'Today’s allowance across your budgets',
                  icon: Icons.wb_sunny_outlined,
                  enabled: p.morning,
                  onChanged: scheduled ? (v) => _save(morning: v) : null,
                  minute: p.morningMinute,
                  timeLabel: 'Morning time',
                  kind: 'morning',
                ),
                _updateCard(
                  title: 'Evening recap',
                  subtitle: 'Today’s spending against your allowance',
                  icon: Icons.nights_stay_outlined,
                  enabled: p.evening,
                  onChanged: scheduled ? (v) => _save(evening: v) : null,
                  minute: p.eveningMinute,
                  timeLabel: 'Evening time',
                  kind: 'evening',
                ),
                Padding(
                  padding: const EdgeInsets.only(bottom: 16, top: 12),
                  child: Text(
                    'Stay on track',
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                _updateCard(
                  title: 'Limit alerts',
                  subtitle: 'At 80% and 100% of each budget',
                  icon: Icons.notifications_active_outlined,
                  enabled: p.limits,
                  onChanged: _busy ? null : (v) => _save(limits: v),
                ),
                _updateCard(
                  title: 'Weekly spending recap',
                  subtitle: 'Last week compared with the week before',
                  icon: AppIcons.dateRange,
                  enabled: p.weekly,
                  onChanged: scheduled ? (v) => _save(weekly: v) : null,
                  minute: p.weeklyMinute,
                  timeLabel: 'Every Monday',
                  kind: 'weekly',
                ),
                const SizedBox(height: 8),
                Text(
                  BudgetUpdateScheduler.supported
                      ? 'Delivery times may vary with your phone’s battery settings.'
                      : 'Scheduled spending updates are available on Android.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
    );
  }
}
