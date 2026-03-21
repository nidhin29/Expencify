import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';

import 'package:expencify/domain/entities/account.dart';
import 'package:expencify/application/blocs/account/account_bloc.dart';
import 'package:expencify/application/blocs/account/account_event.dart';
import 'package:expencify/application/blocs/account/account_state.dart';

class AccountManagementScreen extends StatefulWidget {
  const AccountManagementScreen({super.key});

  @override
  State<AccountManagementScreen> createState() =>
      _AccountManagementScreenState();
}

class _AccountManagementScreenState extends State<AccountManagementScreen> {
  final _rupeeFmt = NumberFormat.currency(
    locale: 'en_IN',
    symbol: '₹',
    decimalDigits: 2,
  );

  final List<Color> _cardColors = [
    const Color(0xFF6366F1),
    const Color(0xFFEC4899),
    const Color(0xFF10B981),
    const Color(0xFF0EA5E9),
    const Color(0xFFF59E0B),
    const Color(0xFF8B5CF6),
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    context.read<AccountBloc>().add(LoadAccounts());
  }

  void _showAccountModal({Account? existing}) {
    final formKey = GlobalKey<FormState>();
    final nameCtrl = TextEditingController(text: existing?.name ?? '');
    final bankCtrl = TextEditingController(text: existing?.bankName ?? '');
    final accNumCtrl = TextEditingController(
      text: existing?.accountNumber ?? '',
    );
    final balanceCtrl = TextEditingController(
      text: existing?.balance.toStringAsFixed(2) ?? '0',
    );

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
                    existing != null ? 'Edit Account' : 'New Account',
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
                label: 'Account Name',
                controller: nameCtrl,
                hint: 'e.g. Daily Wallet',
                icon: Icons.badge_outlined,
                validator: (v) => (v?.isEmpty ?? true) ? 'Required' : null,
              ),
              const SizedBox(height: 16),
              _buildField(
                label: 'Bank Name',
                controller: bankCtrl,
                hint: 'e.g. HDFC Bank',
                icon: Icons.account_balance_outlined,
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: _buildField(
                      label: 'Last 4 Digits',
                      controller: accNumCtrl,
                      hint: '0000',
                      icon: Icons.pin_outlined,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _buildField(
                      label: 'Balance (₹)',
                      controller: balanceCtrl,
                      hint: '0.00',
                      icon: Icons.account_balance_wallet_outlined,
                      keyboardType: TextInputType.number,
                      validator: (v) =>
                          (v == null || double.tryParse(v) == null)
                          ? 'Invalid'
                          : null,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () async {
                    if (!formKey.currentState!.validate()) return;
                    final a = Account(
                      id: existing?.id,
                      name: nameCtrl.text.trim(),
                      bankName: bankCtrl.text.trim(),
                      accountNumber: accNumCtrl.text.trim(),
                      balance: double.parse(balanceCtrl.text),
                    );
                    if (existing != null) {
                      context.read<AccountBloc>().add(UpdateAccount(a));
                    } else {
                      context.read<AccountBloc>().add(AddAccount(a));
                    }
                    if (ctx.mounted) Navigator.pop(ctx);
                    // No need to call _load(), BLoC state will update
                  },
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: Text(
                    existing != null ? 'Update Account' : 'Create Account',
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: AppBar(
        title: const Text('My Accounts'),
        automaticallyImplyLeading: false,
        backgroundColor: Colors.transparent,
        actions: [
          IconButton(
            icon: const Icon(Icons.add_rounded),
            onPressed: () => _showAccountModal(),
          ),
        ],
      ),
      body: BlocBuilder<AccountBloc, AccountState>(
        builder: (context, state) {
          if (state is AccountLoading) {
            return const Center(child: CircularProgressIndicator());
          } else if (state is AccountLoaded) {
            final accounts = state.accounts;
            return RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 16,
                ),
                children: [
                  if (accounts.isEmpty)
                    Center(
                      child: Padding(
                        padding: const EdgeInsets.all(40),
                        child: Column(
                          children: [
                            Icon(
                              Icons.account_balance_wallet_rounded,
                              size: 60,
                              color: theme.colorScheme.primary.withOpacity(0.3),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'No accounts yet',
                              style: theme.textTheme.titleMedium?.copyWith(
                                color: theme.colorScheme.onSurface.withOpacity(
                                  0.4,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                  else
                    ...accounts.asMap().entries.map((entry) {
                      final i = entry.key;
                      final a = entry.value;
                      final color = _cardColors[i % _cardColors.length];
                      return Dismissible(
                        key: Key('acc_${a.id}'),
                        direction: DismissDirection.endToStart,
                        background: Container(
                          margin: const EdgeInsets.only(bottom: 20),
                          decoration: BoxDecoration(
                            color: Colors.red,
                            borderRadius: BorderRadius.circular(28),
                          ),
                          alignment: Alignment.centerRight,
                          padding: const EdgeInsets.only(right: 24),
                          child: const Icon(
                            Icons.delete_rounded,
                            color: Colors.white,
                          ),
                        ),
                        confirmDismiss: (_) async {
                          if (a.id == 1) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Cannot delete the default wallet',
                                ),
                              ),
                            );
                            return false;
                          }
                          return await showDialog<bool>(
                                context: context,
                                builder: (ctx) => AlertDialog(
                                  title: const Text('Delete Account?'),
                                  content: const Text(
                                    'All transactions for this account remain in the database.',
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed: () =>
                                          Navigator.pop(ctx, false),
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
                              false;
                        },
                        onDismissed: (_) async {
                          context.read<AccountBloc>().add(DeleteAccount(a.id!));
                        },
                        child: GestureDetector(
                          onTap: () => _showAccountModal(existing: a),
                          child: Container(
                            margin: const EdgeInsets.only(bottom: 12),
                            padding: const EdgeInsets.all(18),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.surface,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: theme.brightness == Brightness.dark
                                    ? Color(0xFF27272A)
                                    : Color(0xFFE4E4E7),
                              ),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 44,
                                  height: 44,
                                  decoration: BoxDecoration(
                                    color: color.withOpacity(0.12),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Icon(
                                    Icons.account_balance_rounded,
                                    color: color,
                                    size: 20,
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        a.name,
                                        style: theme.textTheme.titleMedium
                                            ?.copyWith(
                                              fontWeight: FontWeight.w600,
                                            ),
                                      ),
                                      Text(
                                        a.bankName.isNotEmpty
                                            ? a.bankName
                                            : 'Savings Account',
                                        style: theme.textTheme.bodySmall,
                                      ),
                                    ],
                                  ),
                                ),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Text(
                                      _rupeeFmt.format(a.balance),
                                      style: theme.textTheme.titleMedium
                                          ?.copyWith(
                                            fontWeight: FontWeight.w700,
                                          ),
                                    ),
                                    Text(
                                      a.accountNumber.length >= 4
                                          ? '**** ${a.accountNumber.substring(a.accountNumber.length - 4)}'
                                          : a.accountNumber,
                                      style: theme.textTheme.labelSmall,
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    }),
                ],
              ),
            );
          } else if (state is AccountError) {
            return Center(child: Text(state.message));
          }
          return const SizedBox.shrink();
        },
      ),
    );
  }
}
