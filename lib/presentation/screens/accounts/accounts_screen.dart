import '../../widgets/page_loading.dart';
import 'package:expencify/presentation/theme/app_icons.dart';
import 'dart:async';
import '../setup/sms_tracking_screen.dart';
import '../../widgets/account_editor.dart';
import '../../widgets/finance_summary_card.dart';
import '../../widgets/action_empty_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';

import 'package:expencify/domain/entities/account.dart';
import 'package:expencify/application/blocs/account/account_bloc.dart';
import 'package:expencify/application/blocs/account/account_event.dart';
import 'package:expencify/application/blocs/account/account_state.dart';

class AccountManagementScreen extends StatefulWidget {
  final bool isActive;
  const AccountManagementScreen({super.key, this.isActive = false});

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
    final bloc = context.read<AccountBloc>();
    await waitForPageLoad(
      bloc.stream,
      (state) =>
          state is AccountError ||
          (state is AccountLoaded && !state.refreshing),
      () => bloc.add(LoadAccounts()),
    );
  }

  void _showAccountModal({Account? existing}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => AccountEditor(
        existing: existing,
        onSubmit: (account) async {
          final completion = Completer<bool>();
          context.read<AccountBloc>().add(
            existing == null
                ? AddAccount(account, completion: completion)
                : UpdateAccount(account, completion: completion),
          );
          return completion.future;
        },
      ),
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
          BlocBuilder<AccountBloc, AccountState>(
            builder: (context, state) {
              if (state is! AccountLoaded || state.accounts.isEmpty) {
                return const SizedBox.shrink();
              }
              return IconButton(
                tooltip: 'Add account',
                icon: const Icon(AppIcons.add),
                onPressed: () => _showAccountModal(),
              );
            },
          ),
        ],
      ),
      body: RefreshFeedback<AccountBloc, AccountState>(
        onRetry: _load,
        child: BlocBuilder<AccountBloc, AccountState>(
          builder: (context, state) {
            if (state is AccountLoading || state is AccountInitial) {
              return const PageLoading(label: 'Loading account', summary: true);
            } else if (state is AccountLoaded) {
              final accounts = state.accounts;
              return RefreshIndicator(
                onRefresh: _load,
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 16,
                  ),
                  children: [
                    if (accounts.length > 1) ...[
                      FinanceSummaryCard(
                        label: 'Total balance',
                        value: _rupeeFmt.format(state.totalBalance),
                        caption:
                            'Tracked across ${accounts.length} ${accounts.length == 1 ? 'account' : 'accounts'}',
                      ),
                      const SizedBox(height: 28),

                      Text(
                        'Tap an account to edit its details.',
                        style: theme.textTheme.bodySmall,
                      ),
                      const SizedBox(height: 16),
                    ],
                    if (accounts.isNotEmpty &&
                        accounts.every(AccountEditor.isCash))
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Track bank SMS',
                                style: theme.textTheme.titleMedium,
                              ),
                              const SizedBox(height: 6),
                              const Text(
                                'Add your bank for automatic transaction matching.',
                              ),
                              const SizedBox(height: 12),
                              FilledButton.icon(
                                onPressed: () => Navigator.push<bool>(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => const SmsTrackingScreen(),
                                  ),
                                ),
                                icon: const Icon(AppIcons.bank),
                                label: const Text('Set up bank account'),
                              ),
                            ],
                          ),
                        ),
                      ),
                    if (accounts.isEmpty)
                      ActionEmptyState(
                        icon: AppIcons.accounts,
                        title: 'Your money, in one place',
                        message:
                            'Add a bank account or cash wallet to start tracking your balances.',
                        actionLabel: 'Add account',
                        onAction: () => _showAccountModal(),
                      )
                    else
                      ...accounts.asMap().entries.map((entry) {
                        final i = entry.key;
                        final a = entry.value;
                        final isCash =
                            a.accountNumber.toUpperCase() == 'CASH' ||
                            a.bankName.toLowerCase() == 'cash';
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
                              AppIcons.delete,
                              color: Colors.white,
                            ),
                          ),
                          confirmDismiss: (_) async {
                            if (a.id == 1) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  persist: false,
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
                                      'Accounts with linked transactions cannot be deleted. Move or remove those transactions first.',
                                    ),
                                    actions: [
                                      TextButton(
                                        onPressed: () =>
                                            Navigator.pop(ctx, false),
                                        child: const Text('Cancel'),
                                      ),
                                      TextButton(
                                        onPressed: () =>
                                            Navigator.pop(ctx, true),
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
                            context.read<AccountBloc>().add(
                              DeleteAccount(a.id!),
                            );
                          },
                          child: GestureDetector(
                            onTap: () => _showAccountModal(existing: a),
                            child: Container(
                              width: double.infinity,
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
                              child: Flex(
                                direction:
                                    MediaQuery.textScalerOf(context).scale(1) >
                                        1.3
                                    ? Axis.vertical
                                    : Axis.horizontal,
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Container(
                                    width: 44,
                                    height: 44,
                                    decoration: BoxDecoration(
                                      color: color.withOpacity(0.12),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Icon(
                                      isCash
                                          ? AppIcons.accounts
                                          : AppIcons.bank,
                                      color: color,
                                      size: 20,
                                    ),
                                  ),
                                  SizedBox(
                                    width: 16,
                                    height:
                                        MediaQuery.textScalerOf(
                                              context,
                                            ).scale(1) >
                                            1.3
                                        ? 12
                                        : 0,
                                  ),
                                  Flexible(
                                    fit:
                                        MediaQuery.textScalerOf(
                                              context,
                                            ).scale(1) >
                                            1.3
                                        ? FlexFit.loose
                                        : FlexFit.tight,
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
                                          isCash
                                              ? 'Cash wallet'
                                              : (a.bankName.isNotEmpty
                                                    ? a.bankName
                                                    : 'Bank account'),
                                          style: theme.textTheme.bodySmall,
                                        ),
                                        if (!isCash) ...[
                                          const SizedBox(height: 4),
                                          if (AccountEditor.hasSmsDetails(a))
                                            Text(
                                              'Bank details complete',
                                              style: theme.textTheme.labelSmall,
                                            )
                                          else
                                            TextButton(
                                              onPressed: () =>
                                                  _showAccountModal(
                                                    existing: a,
                                                  ),
                                              child: const Text(
                                                'Complete bank details',
                                              ),
                                            ),
                                        ],
                                      ],
                                    ),
                                  ),
                                  if (MediaQuery.textScalerOf(
                                        context,
                                      ).scale(1) >
                                      1.3)
                                    const SizedBox(height: 12),
                                  const SizedBox(width: 12),
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
                                      if (!isCash && a.accountNumber.isNotEmpty)
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
              return PageLoadFailure(onRetry: _load);
            }
            return const SizedBox.shrink();
          },
        ),
      ),
    );
  }
}
