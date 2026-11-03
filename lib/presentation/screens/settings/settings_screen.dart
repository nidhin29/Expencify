import '../../widgets/app_date_picker.dart';
import '../../widgets/page_loading.dart';
import '../../../application/services/backup/backup_progress.dart';
import 'package:expencify/presentation/theme/app_icons.dart';
import 'dart:async';
import 'package:package_info_plus/package_info_plus.dart';
import '../../widgets/app_pin_dialog.dart';
import '../security/lock_screen.dart';
import '../../../application/services/security/private_file_cleanup.dart';
import 'budget_updates_screen.dart';
import 'sms_review_screen.dart';
import '../setup/sms_tracking_screen.dart';
import '../../../application/services/sms/sms_tracking_preference.dart';
import '../../../application/services/sms/sms_monitor_service.dart';
import 'package:expencify/application/blocs/budget/budget_bloc.dart';
import 'package:expencify/application/blocs/budget/budget_event.dart';
import 'package:expencify/application/blocs/goal/goal_bloc.dart';
import 'package:expencify/application/blocs/goal/goal_event.dart';
import 'package:expencify/application/blocs/category/category_bloc.dart';
import 'package:expencify/application/blocs/category/category_event.dart';
import 'package:expencify/application/blocs/appliance/appliance_bloc.dart';
import 'package:expencify/application/blocs/appliance/appliance_event.dart';
import 'package:expencify/application/blocs/reminder/reminder_bloc.dart';
import 'package:expencify/application/blocs/reminder/reminder_event.dart';
import 'package:expencify/application/blocs/subscription/subscription_bloc.dart';
import 'package:expencify/application/blocs/subscription/subscription_event.dart';
import 'package:expencify/application/blocs/registered_entity/registered_entity_bloc.dart';
import 'package:expencify/application/blocs/registered_entity/registered_entity_event.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:expencify/domain/entities/account.dart';
import 'package:expencify/domain/entities/transaction.dart';
import 'package:expencify/domain/repositories/account_repository.dart';
import 'package:expencify/domain/repositories/transaction_repository.dart';
import 'package:expencify/application/services/auth/auth_service.dart';
import 'package:expencify/application/services/csv/csv_service.dart';
import 'package:expencify/application/services/pdf/pdf_service.dart';
import 'package:expencify/application/services/security/security_service.dart';
import 'package:expencify/presentation/screens/settings/transaction_selection_screen.dart';
import 'package:expencify/presentation/screens/auth/splash_screen.dart';
import 'package:expencify/domain/repositories/category_repository.dart';
import 'package:expencify/application/blocs/account/account_bloc.dart';
import 'package:expencify/application/blocs/account/account_event.dart';
import 'package:expencify/application/blocs/transaction/transaction_bloc.dart';
import 'package:expencify/application/blocs/transaction/transaction_event.dart';
import 'package:expencify/application/services/backup/backup_service.dart';
import 'package:expencify/application/services/backup/google_drive_service.dart';

class SettingsScreen extends StatefulWidget {
  final bool isActive;
  final AuthService? authService;
  const SettingsScreen({super.key, this.isActive = false, this.authService});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final _authService = widget.authService ?? AuthService();
  final _security = SecurityService();
  bool _backupBusy = false;
  String _backupStatus = 'Working on your backup…';
  BackupProgress? _backupProgress;
  String? _version;
  bool _settingsLoaded = false;
  bool _settingsError = false;
  bool _securityBusy = false;
  bool _smsTrackingEnabled = false;
  bool _smsToggleBusy = false;
  DateTime? _lastCloudBackup;
  bool _appLockEnabled = false;
  bool _biometricEnabled = false;
  bool _biometricAvailable = false;

  @override
  void initState() {
    super.initState();
    _loadPrefs();
    unawaited(_loadVersion());
  }

  Future<void> _loadVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (mounted) {
        setState(() => _version = '${info.version} (${info.buildNumber})');
      }
    } catch (_) {
      /* Omit unavailable version metadata. */
    }
  }

  void _feedback(String text, {bool error = false}) {
    if (!mounted) return;
    final cs = Theme.of(context).colorScheme;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          persist: false,
          duration: Duration(seconds: error ? 6 : 3),
          backgroundColor: error ? cs.errorContainer : null,
          content: Text(
            text,
            style: error ? TextStyle(color: cs.onErrorContainer) : null,
          ),
        ),
      );
  }

  Future<void> _setAppLock(bool enabled) async {
    if (_securityBusy || _backupBusy) return;
    setState(() => _securityBusy = true);
    try {
      if (enabled && (await _security.getPin())?.isNotEmpty != true) {
        if (mounted) await _handlePinChange(forceEnable: true);
      } else {
        if (!enabled && !await _verifySecurityChange()) return;
        await _security.setSecurityEnabled(enabled);
        if (mounted) setState(() => _appLockEnabled = enabled);
      }
    } catch (_) {
      _feedback('Could not update app lock. Please try again.', error: true);
    } finally {
      if (mounted) setState(() => _securityBusy = false);
    }
  }

  Future<void> _setBiometrics(bool enabled) async {
    if (_securityBusy || _backupBusy) return;
    setState(() => _securityBusy = true);
    try {
      if (!await _verifySecurityChange()) return;
      if (enabled && !await _authService.authenticateWithBiometrics()) return;
      await _security.setBiometricEnabled(enabled);
      if (mounted) setState(() => _biometricEnabled = enabled);
    } catch (_) {
      _feedback('Could not update biometrics. Please try again.', error: true);
    } finally {
      if (mounted) setState(() => _securityBusy = false);
    }
  }

  Future<void> _loadPrefs() async {
    if (mounted) setState(() => _settingsError = false);
    try {
      final prefs = await SharedPreferences.getInstance();
      final lastBackup = prefs.getString('last_drive_backup_at');
      final isLockEnabled = await _security.isSecurityEnabled();
      final isBioEnabled = await _security.isBiometricEnabled();
      if (!mounted) return;
      setState(() {
        _settingsLoaded = true;
        _lastCloudBackup = lastBackup == null
            ? null
            : DateTime.tryParse(lastBackup);
        _smsTrackingEnabled =
            prefs.getBool(SmsTrackingPreference.enabledKey) ?? false;
        _appLockEnabled = isLockEnabled;
        _biometricEnabled = isBioEnabled;
      });
      // Device capability probing must not delay saved preference values.
      try {
        final available = await _authService.isBiometricsAvailable();
        if (mounted) setState(() => _biometricAvailable = available);
      } catch (_) {
        /* No biometric control on unsupported devices. */
      }
    } catch (_) {
      if (mounted) setState(() => _settingsError = true);
    }
  }

  Future<void> _setSmsTracking(bool enabled) async {
    if (_smsToggleBusy) return;
    setState(() => _smsToggleBusy = true);
    try {
      if (enabled) {
        await Navigator.push<bool>(
          context,
          MaterialPageRoute(builder: (_) => const SmsTrackingScreen()),
        );
      } else {
        await SmsMonitorService().stopBackgroundListening();
      }
      await _loadPrefs();
    } catch (_) {
      _feedback(
        'Could not update SMS tracking. Please try again.',
        error: true,
      );
    } finally {
      if (mounted) setState(() => _smsToggleBusy = false);
    }
  }

  Future<void> _showExportDialog() async {
    final accountRepo = context.read<AccountRepository>();
    final categoryRepo = context.read<CategoryRepository>();

    final accounts = await accountRepo.getAll();
    final categories = await categoryRepo.getAll();

    Account? selectedAccount;
    DateTimeRange? dateRange;
    String? selectedType;
    String? selectedCategory;

    if (!mounted) return;

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            insetPadding: const EdgeInsets.symmetric(
              horizontal: 20,
              vertical: 24,
            ),
            title: const Text('Export reports'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Choose the transactions to include.',
                    style: TextStyle(fontSize: 13, color: Colors.grey),
                  ),
                  const SizedBox(height: 20),
                  DropdownButtonFormField<Account?>(
                    isExpanded: true,
                    isDense: false,
                    itemHeight: null,
                    value: selectedAccount,
                    selectedItemBuilder: (_) => [
                      const Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'All accounts',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      ...accounts.map(
                        (a) => Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            '${a.name} (${a.bankName})',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                    ],
                    decoration: const InputDecoration(
                      labelText: 'Account',
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(horizontal: 12),
                    ),
                    items: [
                      const DropdownMenuItem<Account?>(
                        value: null,
                        child: Text('All accounts'),
                      ),
                      ...accounts.map(
                        (a) => DropdownMenuItem<Account?>(
                          value: a,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            child: Text(
                              '${a.name} (${a.bankName})',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                      ),
                    ],
                    onChanged: (v) => setState(() => selectedAccount = v),
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String?>(
                    isExpanded: true,
                    isDense: false,
                    itemHeight: null,
                    value: selectedType,
                    decoration: const InputDecoration(
                      labelText: 'Transaction type',
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(horizontal: 12),
                    ),
                    items: const [
                      DropdownMenuItem(value: null, child: Text('All types')),
                      DropdownMenuItem(
                        value: 'income',
                        child: Text('Income only'),
                      ),
                      DropdownMenuItem(
                        value: 'expense',
                        child: Text('Expense only'),
                      ),
                    ],
                    onChanged: (v) => setState(() => selectedType = v),
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String?>(
                    isExpanded: true,
                    isDense: false,
                    itemHeight: null,
                    value: selectedCategory,
                    selectedItemBuilder: (_) => [
                      const Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'All categories',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      ...categories.map(
                        (c) => Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            c.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                    ],
                    decoration: const InputDecoration(
                      labelText: 'Category',
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(horizontal: 12),
                    ),
                    items: [
                      const DropdownMenuItem(
                        value: null,
                        child: Text('All categories'),
                      ),
                      ...categories.map(
                        (c) => DropdownMenuItem(
                          value: c.name,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            child: Text(
                              c.name,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                      ),
                    ],
                    onChanged: (v) => setState(() => selectedCategory = v),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        final picked = await showAppDateRangePicker(
                          context: context,
                          firstDate: DateTime(2020),
                          lastDate: DateTime.now().add(
                            const Duration(days: 365),
                          ),
                          initialDateRange: dateRange,
                        );
                        if (picked != null) {
                          if (context.mounted) {
                            setState(() => dateRange = picked);
                          }
                        }
                      },
                      icon: const Icon(AppIcons.dateRange),
                      label: Text(
                        dateRange == null
                            ? 'All Time'
                            : '${DateFormat('MMM d, y').format(dateRange!.start)} - ${DateFormat('MMM d, y').format(dateRange!.end)}',
                        style: const TextStyle(fontSize: 13),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton.icon(
                onPressed: () => Navigator.pop(ctx, {
                  'format': 'csv',
                  'account': selectedAccount,
                  'range': dateRange,
                  'type': selectedType,
                  'category': selectedCategory,
                }),
                icon: const Icon(AppIcons.csv, color: Colors.green),
                label: const Text('CSV', style: TextStyle(color: Colors.green)),
              ),
              TextButton.icon(
                onPressed: () => Navigator.pop(ctx, {
                  'format': 'pdf',
                  'account': selectedAccount,
                  'range': dateRange,
                  'type': selectedType,
                  'category': selectedCategory,
                }),
                icon: const Icon(AppIcons.pdf, color: Colors.red),
                label: const Text('PDF', style: TextStyle(color: Colors.red)),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, null),
                child: const Text('Cancel'),
              ),
            ],
          );
        },
      ),
    );

    if (result == null || !mounted) return;

    final format = result['format'] as String;
    final account = result['account'] as Account?;
    final range = result['range'] as DateTimeRange?;
    final filterType = result['type'] as String?;
    final filterCategory = result['category'] as String?;

    final transactionRepo = context.read<TransactionRepository>();

    var transactions = await transactionRepo.getTransactions(
      accountId: account?.id,
      from: range?.start,
      to: range?.end,
      type: filterType,
      category: filterCategory,
      limit: 10000,
    );

    if (transactions.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            persist: false,
            content: Text('No transactions match these filters.'),
          ),
        );
      }
      return;
    }

    // Step 2: Individual Selection
    if (mounted) {
      final selected = await Navigator.push<List<TransactionModel>>(
        context,
        MaterialPageRoute(
          builder: (_) =>
              TransactionSelectionScreen(transactions: transactions),
        ),
      );
      if (selected == null || selected.isEmpty) return;
      transactions = selected;
    }

    String? path;

    if (format == 'csv') {
      path = await CSVService().exportTransactionsToCSV(
        transactions,
        accounts: accounts,
        filterType: filterType,
        filterCategory: filterCategory,
        from: range?.start,
        to: range?.end,
      );
    } else {
      path = await PdfService().exportTransactionsToPDF(
        transactions,
        accounts: accounts,
        filterType: filterType,
        filterCategory: filterCategory,
        from: range?.start,
        to: range?.end,
      );
    }

    if (path == null) return;
    try {
      if (!mounted) return;
      await Share.shareXFiles([
        XFile(path),
      ], text: 'Spendy transactions exported as ${format.toUpperCase()}');
    } finally {
      await const PrivateFileCleanup().removeExport(path);
    }
  }

  Future<void> _handleWipeData() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete financial data?'),
        content: const Text(
          'Permanently delete the financial records on this device? This cannot be undone. Your Google Drive backups will remain.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              'Delete data',
              style: TextStyle(
                color: _danger(Theme.of(ctx)),
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    await _authService.wipeDataOnly();
    // Clear the account selection — the account no longer exists
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('selected_account_id');

    if (mounted) {
      _refreshData();
      // Refresh BLoC state so components lose old cached references
      context.read<AccountBloc>().add(LoadAccounts());
      context.read<TransactionBloc>().add(const LoadTransactions());

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          persist: false,
          content: Text('Financial data deleted from this device.'),
        ),
      );

      // Redirect to SplashScreen to cleanly re-orient flow and reload Home
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const SplashScreen()),
        (route) => false,
      );
    }
  }

  void _refreshData() {
    context.read<AccountBloc>().add(LoadAccounts());
    context.read<TransactionBloc>().add(const LoadTransactions());
    context.read<BudgetBloc>().add(LoadBudgets());
    context.read<GoalBloc>().add(LoadGoals());
    context.read<CategoryBloc>().add(LoadCategories());
    context.read<ApplianceBloc>().add(LoadAppliances());
    context.read<ReminderBloc>().add(LoadReminders());
    context.read<SubscriptionBloc>().add(LoadSubscriptions());
    context.read<RegisteredEntityBloc>().add(LoadRegisteredEntities());
  }

  Future<String?> _backupPassphrase({required bool creating}) =>
      showDialog<String>(
        context: context,
        builder: (_) => BackupPassphraseDialog(creating: creating),
      );

  Future<void> _runBackupAction(
    String status,
    Future<void> Function() action, {
    String failureMessage =
        'Could not finish this backup operation. Please try again.',
  }) async {
    if (_backupBusy) return;
    setState(() {
      _backupBusy = true;
      _backupStatus = status;
      _backupProgress = null;
    });
    try {
      await action();
    } catch (_) {
      _feedback(failureMessage, error: true);
    } finally {
      if (mounted) {
        setState(() {
          _backupBusy = false;
          _backupProgress = null;
        });
      }
    }
  }

  void _onBackupProgress(BackupProgress progress) {
    if (!mounted || !_backupBusy) return;
    setState(() {
      _backupProgress = progress;
      _backupStatus = progress.label;
    });
  }

  Future<void> _handleBackup() async {
    final password = await _backupPassphrase(creating: true);
    if (password == null) return;
    final success = await BackupService().exportBackup(
      password,
      onProgress: _onBackupProgress,
    );
    _feedback(
      success
          ? 'Backup file ready to share'
          : 'Could not create the backup file. Please try again.',
      error: !success,
    );
  }

  Future<void> _handleRestore() async {
    final confirm = await _confirmRestore(cloud: false);

    if (confirm != true || !mounted) return;

    final result = await BackupService().importBackup(
      onProgress: _onBackupProgress,
      requestPassword: () async {
        if (!mounted) return null;
        return _backupPassphrase(creating: false);
      },
    );
    if (mounted) {
      if (result.restored) {
        _refreshData();
        _feedback('Backup restored');
        // Force app reload
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const SplashScreen()),
          (route) => false,
        );
      } else if (!result.cancelled) {
        _feedback(
          result.error ??
              'Restore could not finish. Your current data was not replaced.',
          error: true,
        );
      }
    }
  }

  Future<void> _handleCloudBackup() async {
    final pin = await _backupPassphrase(creating: true);
    if (pin == null || !mounted) return;

    final error = await GoogleDriveService().backupDatabase(
      pin,
      onProgress: _onBackupProgress,
    );
    if (error == null) {
      final now = DateTime.now();
      final prefs = await SharedPreferences.getInstance();
      try {
        await prefs.setString('last_drive_backup_at', now.toIso8601String());
      } catch (_) {
        /* A metadata write does not undo a completed Drive backup. */
      }
      if (mounted) setState(() => _lastCloudBackup = now);
    }

    _feedback(
      error == null
          ? 'Backed up to Google Drive'
          : 'Could not back up to Google Drive. $error',
      error: error != null,
    );
  }

  Future<void> _handleCloudRestore() async {
    if (!await _confirmRestore(cloud: true) || !mounted) return;
    final pin = await _backupPassphrase(creating: false);
    if (pin == null || !mounted) return;

    final error = await GoogleDriveService().restoreDatabase(
      pin,
      onProgress: _onBackupProgress,
    );

    if (mounted) {
      if (error == null) {
        _refreshData();
        _feedback('Backup restored');
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const SplashScreen()),
          (route) => false,
        );
      } else {
        _feedback(
          'Could not restore the Google Drive backup. $error',
          error: true,
        );
      }
    }
  }

  Future<void> _handlePinChange({bool forceEnable = false}) async {
    if (!forceEnable && (_securityBusy || _backupBusy)) return;
    if (!forceEnable) setState(() => _securityBusy = true);
    try {
      if (!forceEnable && !await _verifySecurityChange()) return;
      if (!mounted) return;
      final saved = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (_) => AppPinDialog(
          title: forceEnable ? 'Set app PIN' : 'Change app PIN',
          onSave: (pin) async {
            await _security.setPin(pin);
            if (forceEnable) await _security.setSecurityEnabled(true);
          },
        ),
      );
      if (saved == true && mounted) {
        if (forceEnable) setState(() => _appLockEnabled = true);
        _feedback('PIN updated');
      }
    } finally {
      if (!forceEnable && mounted) setState(() => _securityBusy = false);
    }
  }

  Future<bool> _verifySecurityChange() async {
    if (!await _security.isSecurityEnabled()) return true;
    if (!mounted) return false;
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Dialog.fullscreen(
        child: LockScreen(
          verificationOnly: true,
          authService: _authService,
          securityService: _security,
          onUnlocked: () => Navigator.pop(ctx, true),
          onCancelled: () => Navigator.pop(ctx, false),
        ),
      ),
    );
    return result == true && mounted && _security.isForeground;
  }

  Future<bool> _confirmRestore({required bool cloud}) async =>
      await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Restore backup?'),
          content: Text(
            'Replace the financial data on this device with ${cloud ? 'your Google Drive backup' : 'a backup file'}? This cannot be undone.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(ctx).colorScheme.error,
                foregroundColor: Theme.of(ctx).colorScheme.onError,
              ),
              child: const Text('Restore backup'),
            ),
          ],
        ),
      ) ??
      false;

  Future<void> _launchUrl(String urlString) async {
    final uri = Uri.parse(urlString);
    try {
      if (await launchUrl(uri, mode: LaunchMode.externalApplication)) return;
    } catch (_) {}
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          persist: false,
          content: Text('Could not open this link. Please try again.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return PopScope(
      canPop: !_backupBusy,
      child: Scaffold(
        appBar: AppBar(title: const Text('Settings')),
        bottomNavigationBar: _backupBusy
            ? SafeArea(
                top: false,
                child: Material(
                  color: cs.surface,
                  child: Semantics(
                    liveRegion: true,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        LinearProgressIndicator(
                          value: _backupProgress?.fraction,
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: 16,
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.sync_rounded,
                                color: _accent(theme),
                                size: 22,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  _backupStatus,
                                  style: theme.textTheme.bodyMedium,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              )
            : null,
        body: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
          children: [
            if (_settingsError)
              MaterialBanner(
                content: const Text('Could not load saved settings.'),
                actions: [
                  TextButton(onPressed: _loadPrefs, child: const Text('Retry')),
                ],
              ),
            _buildGroup(theme, 'Tracking', [
              _buildSwitchTile(
                theme,
                Icons.sms_outlined,
                'Track bank SMS',
                _smsTrackingEnabled,
                _setSmsTracking,
                enabled: _settingsLoaded && !_smsToggleBusy,
                subtitle: _smsToggleBusy ? 'Updating SMS tracking…' : null,
              ),
              _buildTile(
                theme,
                Icons.fact_check_outlined,
                'SMS to review',
                () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const SmsReviewScreen()),
                ),
              ),
              _buildTile(
                theme,
                Icons.notifications_active_outlined,
                'Spending updates',
                () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const BudgetUpdatesScreen(),
                  ),
                ),
              ),
            ]),
            const SizedBox(height: 24),
            _buildGroup(theme, 'Security', [
              _buildSwitchTile(
                theme,
                Icons.lock_outline_rounded,
                'App lock',
                _appLockEnabled,
                _setAppLock,
                enabled: _settingsLoaded && !_securityBusy,
              ),
              if (_appLockEnabled && _biometricAvailable)
                _buildSwitchTile(
                  theme,
                  Icons.fingerprint_rounded,
                  'Use device unlock',
                  _biometricEnabled,
                  _setBiometrics,
                  enabled: !_securityBusy,
                ),
              if (_appLockEnabled)
                _buildTile(
                  theme,
                  Icons.pin_outlined,
                  'Change PIN',
                  _handlePinChange,
                ),
            ]),
            const SizedBox(height: 24),
            _buildGroup(theme, 'Data & backups', [
              _buildTile(
                theme,
                Icons.file_upload_outlined,
                'Create backup file',
                () => _runBackupAction('Creating backup file…', _handleBackup),
                subtitle: 'Encrypted · protected by your backup passphrase',
              ),
              _buildTile(
                theme,
                Icons.file_open_outlined,
                'Restore backup file',
                () =>
                    _runBackupAction('Restoring backup file…', _handleRestore),
                subtitle: 'Restore from a saved file',
              ),
              _buildTile(
                theme,
                Icons.cloud_upload_outlined,
                'Back up to Google Drive',
                () => _runBackupAction(
                  'Backing up to Google Drive…',
                  _handleCloudBackup,
                ),
                subtitle: !_settingsLoaded
                    ? (_settingsError
                          ? 'Backup status unavailable'
                          : 'Checking backup status…')
                    : _lastCloudBackup == null
                    ? 'Not backed up from this device'
                    : 'Last backup from this device: ${DateFormat('d MMM, h:mm a').format(_lastCloudBackup!)}',
              ),
              _buildTile(
                theme,
                Icons.cloud_download_outlined,
                'Restore from Google Drive',
                () => _runBackupAction(
                  'Restoring from Google Drive…',
                  _handleCloudRestore,
                ),
              ),
              _buildTile(
                theme,
                Icons.ios_share_rounded,
                'Export reports',
                _showExportDialog,
                subtitle: 'CSV or PDF · not encrypted',
              ),
            ]),
            const SizedBox(height: 24),
            _buildGroup(theme, 'About Spendy', [
              _buildTile(
                theme,
                Icons.privacy_tip_outlined,
                'Privacy policy',
                () => _launchUrl('https://spendy-privacy.devforchange.com/'),
              ),
              _buildTile(
                theme,
                Icons.description_outlined,
                'Terms and conditions',
                () => _launchUrl('https://spendy-terms.devforchange.com/'),
              ),
            ]),
            const SizedBox(height: 24),
            _buildGroup(theme, 'Delete data', [
              _buildTile(
                theme,
                AppIcons.delete,
                'Delete financial data',
                () => _runBackupAction(
                  'Deleting financial data…',
                  _handleWipeData,
                  failureMessage:
                      'Could not delete financial data. Please try again.',
                ),
                color: _danger(theme),
                subtitle: 'Permanently remove records from this device',
              ),
            ]),
            const SizedBox(height: 28),
            Text(
              _version == null ? 'Spendy' : 'Spendy $_version',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'On-device storage · Optional Drive backups',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Color _accent(ThemeData theme) => AppIcons.actionColor(theme);
  Color _danger(ThemeData theme) => AppIcons.dangerColor(theme);

  Widget _buildGroup(ThemeData theme, String title, List<Widget> tiles) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: theme.textTheme.labelLarge?.copyWith(
            color: _accent(theme),
            fontWeight: FontWeight.bold,
            letterSpacing: .1,
          ),
        ),
        const SizedBox(height: 12),
        Container(
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: theme.colorScheme.onSurface.withOpacity(0.08),
            ),
            boxShadow: [
              BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 8),
            ],
          ),
          child: Material(
            type: MaterialType.transparency,
            borderRadius: BorderRadius.circular(20),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                for (var i = 0; i < tiles.length; i++) ...[
                  if (i > 0)
                    Divider(
                      height: 1,
                      indent: 64,
                      endIndent: 16,
                      color: theme.colorScheme.outlineVariant.withValues(
                        alpha: .45,
                      ),
                    ),
                  tiles[i],
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTile(
    ThemeData theme,
    IconData icon,
    String title,
    VoidCallback onTap, {
    Color? color,
    String? subtitle,
  }) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      leading: Icon(icon, color: color ?? _accent(theme)),
      title: Text(
        title,
        style: theme.textTheme.bodyLarge?.copyWith(
          color: color ?? theme.colorScheme.onSurface,
          fontWeight: FontWeight.w500,
        ),
      ),
      subtitle: subtitle != null
          ? Text(
              subtitle,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withOpacity(0.75),
              ),
            )
          : null,
      trailing: Icon(
        AppIcons.chevron,
        color: theme.colorScheme.onSurface.withOpacity(0.4),
      ),
      enabled: !_backupBusy,
      onTap: _backupBusy ? null : onTap,
    );
  }

  Widget _buildSwitchTile(
    ThemeData theme,
    IconData icon,
    String title,
    bool value,
    void Function(bool) onChanged, {
    bool enabled = true,
    String? subtitle,
  }) {
    if (!_settingsLoaded) {
      return ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        leading: Icon(icon, color: _accent(theme)),
        title: Text(
          title,
          style: theme.textTheme.bodyLarge?.copyWith(
            fontWeight: FontWeight.w500,
          ),
        ),
        trailing: _settingsError
            ? Icon(AppIcons.error, color: theme.colorScheme.onSurfaceVariant)
            : const PendingSetting(),
      );
    }
    return SwitchListTile.adaptive(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      secondary: Icon(icon, color: _accent(theme)),
      title: Text(
        title,
        style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w500),
      ),
      subtitle: subtitle == null
          ? null
          : Text(subtitle, style: theme.textTheme.bodySmall),
      thumbColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.disabled)
            ? theme.colorScheme.onSurface.withValues(alpha: .38)
            : states.contains(WidgetState.selected)
            ? Colors.white
            : theme.colorScheme.onSurfaceVariant,
      ),
      trackColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.disabled)
            ? theme.colorScheme.onSurface.withValues(alpha: .08)
            : states.contains(WidgetState.selected)
            ? theme.colorScheme.primary
            : theme.colorScheme.onSurface.withValues(alpha: .10),
      ),
      trackOutlineColor: WidgetStatePropertyAll(
        theme.colorScheme.onSurface.withValues(alpha: .18),
      ),
      value: value,
      onChanged: !_backupBusy && enabled ? onChanged : null,
    );
  }
}

/// The dialog owns its controllers through its complete closing animation.
class BackupPassphraseDialog extends StatefulWidget {
  final bool creating;
  const BackupPassphraseDialog({super.key, required this.creating});
  @override
  State<BackupPassphraseDialog> createState() => _BackupPassphraseDialogState();
}

class _BackupPassphraseDialogState extends State<BackupPassphraseDialog> {
  final _passphrase = TextEditingController();
  final _confirmation = TextEditingController();
  bool _obscured = true;
  String? _error;
  @override
  void dispose() {
    _passphrase.dispose();
    _confirmation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.creating ? 'Protect your backup' : 'Unlock your backup'),
    scrollable: true,
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.creating
              ? 'Choose a separate passphrase of at least 12 characters. You will need it on any phone where you restore. The app cannot recover it.'
              : 'Enter this backup’s passphrase. Older cloud backups use the PIN from when they were created. Leave blank only for old unencrypted local backups.',
        ),
        const SizedBox(height: 20),
        TextField(
          controller: _passphrase,
          obscureText: _obscured,
          autocorrect: false,
          enableSuggestions: false,
          textInputAction: widget.creating
              ? TextInputAction.next
              : TextInputAction.done,
          decoration: InputDecoration(
            labelText: 'Backup passphrase',
            errorText: _error,
            suffixIcon: IconButton(
              tooltip: _obscured ? 'Show passphrase' : 'Hide passphrase',
              onPressed: () => setState(() => _obscured = !_obscured),
              icon: Icon(
                _obscured
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined,
              ),
            ),
          ),
        ),
        if (widget.creating) ...[
          const SizedBox(height: 16),
          TextField(
            controller: _confirmation,
            obscureText: _obscured,
            autocorrect: false,
            enableSuggestions: false,
            decoration: const InputDecoration(labelText: 'Confirm passphrase'),
          ),
        ],
      ],
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () {
          if (widget.creating &&
              (_passphrase.text.length < 12 ||
                  _passphrase.text != _confirmation.text)) {
            setState(
              () => _error = 'Use 12+ characters and matching passphrases.',
            );
            return;
          }
          Navigator.pop(context, _passphrase.text);
        },
        child: Text(widget.creating ? 'Encrypt backup' : 'Unlock backup'),
      ),
    ],
  );
}
