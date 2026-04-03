import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';

import 'package:expencify/domain/entities/account.dart';
import 'package:expencify/domain/entities/transaction.dart';
import 'package:expencify/domain/repositories/account_repository.dart';
import 'package:expencify/domain/repositories/transaction_repository.dart';
import 'package:expencify/application/services/auth/auth_service.dart';
import 'package:expencify/application/services/csv/csv_service.dart';
import 'package:expencify/application/services/pdf/pdf_service.dart';
import 'package:expencify/application/services/security/security_service.dart';
import 'package:expencify/presentation/screens/settings/smart_rules_screen.dart';
import 'package:expencify/presentation/screens/settings/transaction_selection_screen.dart';
import 'package:expencify/presentation/screens/auth/splash_screen.dart';
import 'package:expencify/domain/repositories/category_repository.dart';
import 'package:expencify/application/blocs/account/account_bloc.dart';
import 'package:expencify/application/blocs/account/account_event.dart';
import 'package:expencify/application/blocs/transaction/transaction_bloc.dart';
import 'package:expencify/application/blocs/transaction/transaction_event.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _authService = AuthService();
  final _security = SecurityService();
  bool _appLockEnabled = false;
  bool _biometricEnabled = false;
  bool _biometricAvailable = false;

  @override
  void initState() {
    super.initState();
    _loadPrefs();
  }

  Future<void> _loadPrefs() async {
    final canBio = await _authService.isBiometricsAvailable();
    final isLockEnabled = await _security.isSecurityEnabled();
    final isBioEnabled = await _security.isBiometricEnabled();
    setState(() {
      _appLockEnabled = isLockEnabled;
      _biometricEnabled = isBioEnabled;
      _biometricAvailable = canBio;
    });
  }

  Future<void> _showExportDialog() async {
    final accountRepo = context.read<AccountRepository>();
    final accounts = await accountRepo.getAll();
    final categoryRepo = context.read<CategoryRepository>();
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
            title: const Text('Export Transactions'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Choose filters to customize your export structure.',
                    style: TextStyle(fontSize: 13, color: Colors.grey),
                  ),
                  const SizedBox(height: 20),
                  DropdownButtonFormField<Account?>(
                    value: selectedAccount,
                    decoration: const InputDecoration(
                      labelText: 'Select Wallet / Account',
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(horizontal: 12),
                    ),
                    items: [
                      const DropdownMenuItem<Account?>(
                        value: null,
                        child: Text('All Accounts'),
                      ),
                      ...accounts.map(
                        (a) => DropdownMenuItem<Account?>(
                          value: a,
                          child: Text('${a.name} (${a.bankName})'),
                        ),
                      ),
                    ],
                    onChanged: (v) => setState(() => selectedAccount = v),
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String?>(
                    value: selectedType,
                    decoration: const InputDecoration(
                      labelText: 'Transaction Type',
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(horizontal: 12),
                    ),
                    items: const [
                      DropdownMenuItem(value: null, child: Text('All Types')),
                      DropdownMenuItem(
                        value: 'income',
                        child: Text('Income Only'),
                      ),
                      DropdownMenuItem(
                        value: 'expense',
                        child: Text('Expense Only'),
                      ),
                    ],
                    onChanged: (v) => setState(() => selectedType = v),
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String?>(
                    value: selectedCategory,
                    decoration: const InputDecoration(
                      labelText: 'Category',
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(horizontal: 12),
                    ),
                    items: [
                      const DropdownMenuItem(
                        value: null,
                        child: Text('All Categories'),
                      ),
                      ...categories.map(
                        (c) => DropdownMenuItem(
                          value: c.name,
                          child: Text(c.name),
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
                        final picked = await showDateRangePicker(
                          context: context,
                          firstDate: DateTime(2020),
                          lastDate: DateTime.now().add(
                            const Duration(days: 365),
                          ),
                          initialDateRange: dateRange,
                        );
                        if (picked != null) {
                          setState(() => dateRange = picked);
                        }
                      },
                      icon: const Icon(Icons.date_range_rounded),
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
                icon: const Icon(
                  Icons.table_chart_rounded,
                  color: Colors.green,
                ),
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
                icon: const Icon(
                  Icons.picture_as_pdf_rounded,
                  color: Colors.red,
                ),
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
            content: Text('No transactions found matching filters.'),
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

    if (path == null || !mounted) return;

    // Share the file so user can save/send it anywhere
    await Share.shareXFiles([
      XFile(path),
    ], text: 'Expencify transactions exported as ${format.toUpperCase()}');
  }

  Future<void> _handleWipeData() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Wipe All Data?'),
        content: const Text(
          'This will permanently delete all your transactions, accounts, budgets and goals. '
          'All financial data will be gone. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'WIPE DATA',
              style: TextStyle(
                color: Colors.orange,
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
      // Refresh BLoC state so components lose old cached references
      context.read<AccountBloc>().add(LoadAccounts());
      context.read<TransactionBloc>().add(const LoadTransactions());

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('All data wiped. Your account is still active.'),
          backgroundColor: Colors.orange,
        ),
      );

      // Redirect to SplashScreen to cleanly re-orient flow and reload Home
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const SplashScreen()),
        (route) => false,
      );
    }
  }

  Future<void> _handlePinChange({bool forceEnable = false}) async {
    final formKey = GlobalKey<FormState>();
    final pinCtrl = TextEditingController();
    final confirmCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Set New PIN'),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: pinCtrl,
                obscureText: true,
                keyboardType: TextInputType.number,
                maxLength: 6,
                decoration: const InputDecoration(labelText: 'New PIN'),
                validator: (v) =>
                    (v == null || v.length < 4) ? 'Min 4 digits' : null,
              ),
              TextFormField(
                controller: confirmCtrl,
                obscureText: true,
                keyboardType: TextInputType.number,
                maxLength: 6,
                decoration: const InputDecoration(labelText: 'Confirm PIN'),
                validator: (v) =>
                    v != pinCtrl.text ? 'PINs do not match' : null,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (!formKey.currentState!.validate()) return;
              await _security.setPin(pinCtrl.text);
              if (ctx.mounted) {
                Navigator.pop(ctx);
                if (forceEnable) {
                  await _security.setSecurityEnabled(true);
                  if (mounted) setState(() => _appLockEnabled = true);
                }
                if (mounted) {
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(const SnackBar(content: Text('PIN updated!')));
                }
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
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
        title: const Text('Settings'),
        backgroundColor: Colors.transparent,
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          _buildGroup(theme, 'Data Management', [
            _buildTile(
              theme,
              Icons.file_download_rounded,
              'Export Data (CSV / PDF)',
              _showExportDialog,
            ),
            _buildTile(
              theme,
              Icons.auto_awesome_rounded,
              'Smart Rules (SMS Auto-categorize)',
              () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const SmartRulesScreen()),
                );
              },
            ),
            _buildTile(
              theme,
              Icons.delete_sweep_rounded,
              'Wipe All Data',
              _handleWipeData,
              color: Colors.orange,
              subtitle: 'Clears transactions & accounts',
            ),
          ]),
          const SizedBox(height: 24),
          _buildGroup(theme, 'Security', [
            _buildSwitchTile(
              theme,
              Icons.lock_outline_rounded,
              'Enable App Lock',
              _appLockEnabled,
              (v) async {
                // If enabling, ensure a PIN exists
                if (v) {
                  final pin = await _security.getPin();
                  if (pin == null || pin.isEmpty) {
                    _handlePinChange(forceEnable: true); // Force set PIN
                    return;
                  }
                }
                await _security.setSecurityEnabled(v);
                setState(() => _appLockEnabled = v);
              },
            ),
            if (_appLockEnabled && _biometricAvailable)
              _buildSwitchTile(
                theme,
                Icons.fingerprint_rounded,
                'Use Biometrics',
                _biometricEnabled,
                (v) async {
                  if (v) await _authService.authenticateWithBiometrics();
                  await _security.setBiometricEnabled(v);
                  setState(() => _biometricEnabled = v);
                },
              ),
            if (_appLockEnabled)
              _buildTile(
                theme,
                Icons.vpn_key_rounded,
                'Change PIN',
                _handlePinChange,
              ),
          ]),
          const SizedBox(height: 60),
          Center(
            child: Text(
              'Expencify v1.0.0\nAll financial data is stored locally on your device.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withOpacity(0.5),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGroup(ThemeData theme, String title, List<Widget> tiles) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title.toUpperCase(),
          style: theme.textTheme.labelLarge?.copyWith(
            color: theme.colorScheme.primary,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.2,
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
          child: Column(children: tiles),
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
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
      leading: Icon(icon, color: color ?? theme.colorScheme.primary),
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
                color: theme.colorScheme.onSurface.withOpacity(0.45),
              ),
            )
          : null,
      trailing: Icon(
        Icons.chevron_right_rounded,
        color: theme.colorScheme.onSurface.withOpacity(0.4),
      ),
      onTap: onTap,
    );
  }

  Widget _buildSwitchTile(
    ThemeData theme,
    IconData icon,
    String title,
    bool value,
    void Function(bool) onChanged,
  ) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
      leading: Icon(icon, color: theme.colorScheme.primary),
      title: Text(
        title,
        style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w500),
      ),
      trailing: Switch(
        value: value,
        onChanged: onChanged,
        activeColor: theme.colorScheme.primary,
      ),
    );
  }
}
