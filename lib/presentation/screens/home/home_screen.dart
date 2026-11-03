import '../../widgets/voice_entry_dialog.dart';
import '../../widgets/app_date_picker.dart';
import '../../widgets/home_spending_chart.dart';
import '../../widgets/page_loading.dart';
import 'package:expencify/presentation/theme/app_icons.dart';
import '../../../application/services/payments/upcoming_payments.dart';
import '../../../application/services/notifications/budget_update_service.dart';
import '../../../application/blocs/subscription/subscription_bloc.dart';
import '../../../application/blocs/subscription/subscription_state.dart';
import '../payments/upcoming_payments_screen.dart';
import '../../../application/services/search/semantic_search_service.dart';
import '../../widgets/ai_feature_gate.dart';
import '../../widgets/account_editor.dart';
import '../setup/sms_tracking_screen.dart';
import '../../../application/services/sms/sms_tracking_preference.dart';
import '../../widgets/home_back_handler.dart';
import '../../widgets/spendy_bottom_bar.dart';
import '../../widgets/finance_summary_card.dart';
import 'package:expencify/application/services/notifications/notification_service.dart';
import 'package:flutter/material.dart';
import 'dart:async';
import 'package:flutter/services.dart';
import 'package:expencify/presentation/screens/setup/setup_required_screen.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:expencify/presentation/theme/app_theme.dart';
import 'package:expencify/presentation/screens/transactions/transaction_entry_screen.dart';
import 'package:expencify/presentation/screens/transactions/transaction_list_screen.dart';
import 'package:expencify/presentation/screens/accounts/accounts_screen.dart';
import 'package:expencify/presentation/screens/budgets/budgets_screen.dart';
import 'package:expencify/presentation/screens/reports/reports_screen.dart';
import 'package:expencify/presentation/screens/settings/settings_screen.dart';
import 'package:expencify/presentation/screens/goals/goals_screen.dart';
import 'package:expencify/presentation/screens/categories/categories_screen.dart';
import 'package:expencify/presentation/screens/appliances/appliances_screen.dart';
import 'package:expencify/presentation/screens/chat/chat_screen.dart';
import 'package:expencify/application/blocs/reminder/reminder_bloc.dart';
import 'package:expencify/application/blocs/reminder/reminder_state.dart';
import 'package:expencify/application/blocs/reminder/reminder_event.dart';
import 'package:expencify/domain/entities/transaction.dart';
import 'package:expencify/domain/entities/account.dart';
import 'package:expencify/domain/repositories/account_repository.dart';
import 'package:expencify/domain/repositories/transaction_repository.dart';
import 'package:expencify/application/blocs/account/account_bloc.dart';
import 'package:expencify/application/blocs/account/account_event.dart';
import 'package:expencify/application/blocs/account/account_state.dart';
import 'package:expencify/application/services/voice/voice_service.dart';
import 'package:expencify/application/services/ai/ai_service.dart';
import 'package:expencify/application/blocs/transaction/transaction_bloc.dart';
import 'package:expencify/application/blocs/transaction/transaction_event.dart';
import 'package:expencify/application/blocs/transaction/transaction_state.dart';
import 'package:expencify/application/services/sms/sms_monitor_service.dart';
import 'package:collection/collection.dart';

/// Global route observer instance — register in MaterialApp.navigatorObservers.
// Only full pages can change dashboard data on return. Popup routes such as
// filters, menus and dialogs must not trigger a second dashboard reload.
final RouteObserver<PageRoute<dynamic>> homeRouteObserver =
    RouteObserver<PageRoute<dynamic>>();

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with RouteAware {
  int _currentIndex = 0;
  final _visitedTabs = <int>{0};
  final _rupeeFmt = NumberFormat.currency(
    locale: 'en_IN',
    symbol: '₹',
    decimalDigits: 0,
  );

  double _balance = 0;
  double _monthIncome = 0;
  double _monthExpense = 0;
  List<TransactionModel> _recent = [];
  DateTime? _filterDateFrom;
  DateTime? _filterDateTo;
  String _dateLabel = 'This month';
  String _chartPeriod = '7 Days';
  bool _loading = true, _refreshing = false, _hasDashboardData = false;
  String? _loadError;
  Object? _dataScope;
  int _dataRequest = 0;
  int _chartRefreshToken = 0;
  int? _dashboardAccountId;
  bool _cashFlowLoading = false;
  String? _cashFlowError;
  bool _voiceEntryOpen = false;
  bool? _requirementsMet = true; // Default true, splash pre-verified it
  final _voiceService = VoiceService();
  final _aiService = AIService();
  StreamSubscription? _smsSubscription;
  List<UpcomingPayment> _lastUpcoming = [];

  @override
  void initState() {
    super.initState();
    // Use WidgetsBinding to call _loadData after Provider is accessible
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadData();
    });

    // Optional search indexing resumes only after reaching Home.
    unawaited(SemanticSearchService().activate());

    // Trigger Reminder load for heads-up UI
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        context.read<ReminderBloc>().add(LoadReminders());
        final notifications = NotificationService();
        if (notifications.pendingPayload != null) {
          notifications.onTap?.call(notifications.pendingPayload!);
        }
      }
    });

    // Listen to background SMS isolate alerts to reload UI in real-time
    _smsSubscription = SmsMonitorService.onSmsProcessed.stream.listen((_) {
      if (mounted) {
        context.read<TransactionBloc>().add(const RefreshTransactions());
        context.read<AccountBloc>().add(LoadAccounts());
        _loadData(silent: true);
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Subscribe to route events so _loadData fires whenever HomeScreen resumes.
    final route = ModalRoute.of(context);
    if (route is PageRoute<dynamic>) homeRouteObserver.subscribe(this, route);
  }

  @override
  void didPopNext() {
    // Called whenever a route above HomeScreen is popped (e.g. TransactionEntry).
    if (mounted) {
      _loadData(silent: true);
    }
  }

  @override
  void dispose() {
    _smsSubscription?.cancel();
    homeRouteObserver.unsubscribe(this);
    unawaited(_voiceService.cancelListening());
    super.dispose();
  }

  Future<void> _loadData({
    bool silent = false,
    bool cashFlowOnly = false,
  }) async {
    if (!mounted) return;

    final transactionRepo = context.read<TransactionRepository>();
    final accountState = context.read<AccountBloc>().state;
    int? selectedId;
    if (accountState is AccountLoaded) {
      selectedId = accountState.selectedAccountId;
    }

    final request = ++_dataRequest;
    final scope = (selectedId, _filterDateFrom, _filterDateTo, _dateLabel);
    final localRefresh =
        cashFlowOnly && _hasDashboardData && _dashboardAccountId == selectedId;
    final retain = localRefresh || _dataScope == scope;
    final filterFrom = _filterDateFrom;
    final filterTo = _filterDateTo;
    final dateLabel = _dateLabel;
    setState(() {
      _hasDashboardData = retain;
      _loading = !retain;
      _refreshing = retain && !silent && !localRefresh;
      _cashFlowLoading = localRefresh;
      _cashFlowError = null;
      _loadError = null;
    });
    try {
      // Compute balance as sum of all-time income minus expenses for the selected
      // account (or all accounts). This is always accurate regardless of whether
      // the `balance` column on the accounts table is in sync.
      var balance = _balance;
      if (!localRefresh) {
        final allTimeIncome = await transactionRepo.getRangeTotal(
          'income',
          accountId: selectedId,
        );
        final allTimeExpense = await transactionRepo.getRangeTotal(
          'expense',
          accountId: selectedId,
        );
        balance = allTimeIncome - allTimeExpense;
      }

      // Default to this month if no filter set
      DateTime? from = filterFrom;
      DateTime? to = filterTo;
      if (from == null && dateLabel.toLowerCase() == 'this month') {
        final now = DateTime.now();
        from = DateTime(now.year, now.month, 1);
        to = DateTime(now.year, now.month + 1, 0, 23, 59, 59);
      }

      final income = await transactionRepo.getRangeTotal(
        'income',
        from: from,
        to: to,
        accountId: selectedId,
      );
      final expense = await transactionRepo.getRangeTotal(
        'expense',
        from: from,
        to: to,
        accountId: selectedId,
      );
      final recent = await transactionRepo.getTransactions(
        from: from,
        to: to,
        limit: 8,
        accountId: selectedId,
      );

      if (mounted && request == _dataRequest) {
        setState(() {
          _dataScope = scope;
          _dashboardAccountId = selectedId;
          _cashFlowLoading = false;
          if (!localRefresh) _chartRefreshToken++;
          _hasDashboardData = true;
          _refreshing = false;
          _balance = balance;
          _monthIncome = income;
          _monthExpense = expense;
          _recent = recent;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted && request == _dataRequest) {
        setState(() {
          _loading = false;
          _refreshing = false;
          _cashFlowLoading = false;
          if (localRefresh) {
            _cashFlowError = 'Could not load this period.';
          } else {
            _loadError = 'Could not refresh your dashboard. Please retry.';
          }
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    if (_requirementsMet == null) {
      return const Scaffold(
        body: PageLoading(summary: true, label: 'Opening dashboard'),
      );
    }

    if (!_requirementsMet!) {
      return SetupRequiredScreen(
        onComplete: (_) => setState(() => _requirementsMet = true),
      );
    }

    return HomeBackHandler(
      selectedIndex: _currentIndex,
      onReturnHome: () => setState(() => _currentIndex = 0),
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: theme.brightness == Brightness.dark
              ? Brightness.light
              : Brightness.dark,
          statusBarBrightness: theme.brightness, // For iOS
        ),
        child: Scaffold(
          bottomNavigationBar: _buildBottomNav(theme),
          body: MultiBlocListener(
            listeners: [
              BlocListener<TransactionBloc, TransactionState>(
                listener: (context, state) {
                  if (state is TransactionLoaded) _loadData(silent: true);
                },
              ),
              BlocListener<AccountBloc, AccountState>(
                listener: (context, state) {
                  if (state is AccountLoaded &&
                      !state.refreshing &&
                      state.refreshError == null) {
                    _loadData(silent: true);
                  }
                },
              ),
            ],
            child: Container(
              decoration: BoxDecoration(color: colorScheme.surface),
              child: Stack(
                children: [
                  SafeArea(
                    child: IndexedStack(
                      index: _currentIndex,
                      children: [
                        _buildDashboardView(theme),
                        _visitedTabs.contains(1)
                            ? TransactionListScreen(
                                onRefresh: _loadData,
                                isActive: _currentIndex == 1,
                              )
                            : const SizedBox.shrink(),
                        _visitedTabs.contains(2)
                            ? BudgetScreen(
                                onRefresh: _loadData,
                                isActive: _currentIndex == 2,
                              )
                            : const SizedBox.shrink(),
                        _visitedTabs.contains(3)
                            ? AccountManagementScreen(
                                isActive: _currentIndex == 3,
                              )
                            : const SizedBox.shrink(),
                      ],
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

  Widget _buildSmsSetupCard() => FutureBuilder<bool>(
    future: () async {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool('sms_setup_dismissed') ?? false) return false;
      final enabled = await SmsTrackingPreference.isEnabled();
      if (!mounted) return false;
      final accounts = await context.read<AccountRepository>().getAll();
      return !enabled || !accounts.any(AccountEditor.hasSmsDetails);
    }(),
    builder: (context, snapshot) {
      if (snapshot.data != true) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Track bank SMS',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Dismiss SMS setup',
                      icon: const Icon(AppIcons.close),
                      onPressed: () async {
                        final prefs = await SharedPreferences.getInstance();
                        await prefs.setBool('sms_setup_dismissed', true);
                        if (mounted) setState(() {});
                      },
                    ),
                  ],
                ),
                const Text('Automatically match new bank transactions.'),
                const SizedBox(height: 8),
                FilledButton(
                  onPressed: () async {
                    await Navigator.push<bool>(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const SmsTrackingScreen(),
                      ),
                    );
                    if (mounted) setState(() {});
                  },
                  child: const Text('Set up SMS tracking'),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );

  Widget _buildDashboardView(ThemeData theme) {
    return LoadingFeedback(
      loading: _refreshing,
      error: _hasDashboardData ? _loadError : null,
      onRetry: () => _loadData(),
      child: RefreshIndicator(
        onRefresh: () => _loadData(silent: true),
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            _buildAppBar(theme),
            SliverToBoxAdapter(child: _buildSmsSetupCard()),
            SliverToBoxAdapter(child: _buildHeadsUpReminder(theme)),
            _buildAccountSelectorChips(theme),
            if (_loadError != null && !_hasDashboardData)
              SliverFillRemaining(
                hasScrollBody: false,
                child: PageLoadFailure(
                  onRetry: () => _loadData(),
                  message: 'Could not load your dashboard.',
                ),
              )
            else if (_loading)
              const SliverToBoxAdapter(
                child: SizedBox(
                  height: 520,
                  child: PageLoading(summary: true, label: 'Loading dashboard'),
                ),
              )
            else ...[
              SliverToBoxAdapter(child: _buildBalanceCard(theme)),
              SliverToBoxAdapter(
                child: HomeSpendingChart(
                  repository: context.read<TransactionRepository>(),
                  accountId: context.read<AccountBloc>().state is AccountLoaded
                      ? (context.read<AccountBloc>().state as AccountLoaded)
                            .selectedAccountId
                      : null,
                  refreshToken: _chartRefreshToken,
                  initialPeriod: _chartPeriod,
                  onPeriodChanged: (period) => _chartPeriod = period,
                ),
              ),
              SliverToBoxAdapter(
                child: _buildSectionHeader(theme, 'Recent Transactions'),
              ),
              if (_cashFlowLoading)
                const SliverToBoxAdapter(
                  child: SizedBox(
                    height: 220,
                    child: PageLoading(
                      label: 'Loading transactions for this period',
                    ),
                  ),
                )
              else if (_cashFlowError != null)
                SliverToBoxAdapter(
                  child: SizedBox(
                    height: 220,
                    child: PageLoadFailure(
                      message: _cashFlowError!,
                      onRetry: () => _loadData(cashFlowOnly: true),
                    ),
                  ),
                )
              else if (_recent.isEmpty)
                SliverToBoxAdapter(child: _buildEmptyState(theme))
              else
                _buildRecentTransactions(theme),
            ],
            const SliverToBoxAdapter(child: SizedBox(height: 100)),
          ],
        ),
      ),
    );
  }

  Widget _buildAppBar(ThemeData theme) {
    final cs = theme.colorScheme;
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(20, 16, 16, 0),
      sliver: SliverToBoxAdapter(
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.asset(
                          'assets/images/logo.png',
                          height: 32,
                          width: 32,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        'Spendy',
                        style: theme.textTheme.headlineMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                          letterSpacing: -1,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            // Removed _buildAccountSelector from Row
            IconButton(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ChatScreen()),
              ),
              icon: Icon(
                AppIcons.chat,
                size: AppIcons.actionSize,
                color: AppIcons.actionColor(theme),
              ),
              tooltip: 'Ask Spendy AI',
            ),
            IconButton(
              tooltip: 'More tools',
              onPressed: _openMoreSheet,
              icon: Icon(
                AppIcons.tools,
                size: AppIcons.actionSize,
                color: cs.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeadsUpReminder(ThemeData theme) {
    return BlocBuilder<ReminderBloc, ReminderState>(
      builder: (context, reminders) => BlocBuilder<SubscriptionBloc, SubscriptionState>(
        builder: (context, subscriptions) {
          final now = DateTime.now();
          if (reminders is ReminderLoaded &&
              subscriptions is SubscriptionLoaded) {
            _lastUpcoming = upcomingPayments(
              reminders.reminders,
              subscriptions.subscriptions,
              now,
            );
          }
          final rows = _lastUpcoming;
          if (rows.isEmpty) return const SizedBox.shrink();
          final overdue = rows.where((r) => r.overdue(now)).toList();
          final due = rows.where((r) => !r.overdue(now)).toList();
          return Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
            child: Card(
              child: InkWell(
                borderRadius: BorderRadius.circular(20),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const UpcomingPaymentsScreen(),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(AppIcons.payments),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Upcoming payments',
                              style: theme.textTheme.titleMedium,
                            ),
                          ),
                          const Icon(AppIcons.chevron),
                        ],
                      ),
                      const SizedBox(height: 10),
                      const Text('All accounts'),
                      Text(
                        '${due.length} due in the next 7 days · ${BudgetUpdateService.amount(due.fold<int>(0, (s, r) => s + r.cents))}',
                      ),
                      if (overdue.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            '${overdue.length} overdue · ${BudgetUpdateService.amount(overdue.fold<int>(0, (s, r) => s + r.cents))}',
                            style: TextStyle(color: theme.colorScheme.error),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildAccountSelectorChips(ThemeData theme) {
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    return SliverPadding(
      padding: const EdgeInsets.only(top: 12, bottom: 4),
      sliver: SliverToBoxAdapter(
        child: FutureBuilder<List<Account>>(
          future: context.read<AccountRepository>().getAll(),
          builder: (context, snapshot) {
            if (!snapshot.hasData || snapshot.data!.isEmpty) {
              return const SizedBox.shrink();
            }
            final accounts = snapshot.data!;
            final accountState = context.watch<AccountBloc>().state;
            final selectedId = accountState is AccountLoaded
                ? accountState.selectedAccountId
                : null;

            return SizedBox(
              height: 32 + 24 * MediaQuery.textScalerOf(context).scale(1),
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                scrollDirection: Axis.horizontal,
                // +1 for "All Banks", +1 for search icon if needed
                itemCount: accounts.length + (accounts.length > 5 ? 2 : 1),
                itemBuilder: (ctx, index) {
                  if (accounts.length > 5 && index == accounts.length + 1) {
                    return Padding(
                      padding: const EdgeInsets.only(left: 4, bottom: 8),
                      child: IconButton(
                        onPressed: () =>
                            _showAccountSearchSheet(context, accounts),
                        icon: Icon(
                          AppIcons.search,
                          color: cs.primary,
                          size: 20,
                        ),
                        style: IconButton.styleFrom(
                          backgroundColor: isDark
                              ? AppTheme.darkElevated
                              : Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                            side: BorderSide(
                              color: isDark
                                  ? AppTheme.darkBorder
                                  : AppTheme.lightBorder,
                            ),
                          ),
                        ),
                      ),
                    );
                  }

                  final isAll = index == 0;
                  final account = isAll ? null : accounts[index - 1];
                  final isSelected = isAll
                      ? selectedId == null
                      : selectedId == account?.id;

                  return Padding(
                    padding: const EdgeInsets.only(right: 10, bottom: 8),
                    child: GestureDetector(
                      onTap: () {
                        context.read<AccountBloc>().add(
                          SelectAccount(isAll ? null : account!.id),
                        );
                        _loadData();
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 250),
                        curve: Curves.easeInOut,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? cs.primary
                              : (isDark
                                    ? AppTheme.darkElevated.withOpacity(0.5)
                                    : Colors.white),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isSelected
                                ? cs.primary
                                : (isDark
                                      ? AppTheme.darkBorder
                                      : AppTheme.lightBorder),
                          ),
                          boxShadow: isSelected
                              ? [
                                  BoxShadow(
                                    color: cs.primary.withOpacity(0.3),
                                    blurRadius: 8,
                                    offset: const Offset(0, 3),
                                  ),
                                ]
                              : null,
                        ),
                        child: Center(
                          child: Text(
                            isAll ? 'All Banks' : account!.bankName,
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: isSelected
                                  ? Colors.white
                                  : cs.onSurface.withOpacity(0.7),
                              fontWeight: isSelected
                                  ? FontWeight.bold
                                  : FontWeight.w500,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            );
          },
        ),
      ),
    );
  }

  void _showAccountSearchSheet(BuildContext context, List<Account> accounts) {
    final accountState = context.read<AccountBloc>().state;
    final selectedId = accountState is AccountLoaded
        ? accountState.selectedAccountId
        : null;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        maxChildSize: 0.9,
        minChildSize: 0.5,
        builder: (_, scrollController) {
          return StatefulBuilder(
            builder: (ctx, setModalState) {
              // We'll manage the query in a simple way for this sheet
              return _AccountSearchContent(
                accounts: accounts,
                selectedId: selectedId,
                scrollController: scrollController,
                onSelect: (id) {
                  context.read<AccountBloc>().add(SelectAccount(id));
                  _loadData();
                  Navigator.pop(ctx);
                },
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildBalanceCard(ThemeData theme) {
    final state = context.watch<AccountBloc>().state;
    final balance = state is AccountLoaded
        ? (state.selectedAccountId == null
              ? state.totalBalance
              : state.selectedAccount?.balance ?? state.totalBalance)
        : _balance;
    final caption = state is AccountLoaded && state.selectedAccount != null
        ? state.selectedAccount!.name
        : 'Across all your accounts';
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FinanceSummaryCard(
            label: 'Available balance',
            value: _loading ? '—' : _rupeeFmt.format(balance),
            caption: caption,
          ),
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, constraints) {
              final heading = Padding(
                padding: const EdgeInsetsDirectional.only(start: 12),
                child: Text(
                  'Your cash flow',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              );
              final period = TextButton.icon(
                onPressed: _showDateFilter,
                iconAlignment: IconAlignment.end,
                icon: const Icon(AppIcons.expand, size: 18),
                label: Text(_dateLabel),
              );
              if (MediaQuery.textScalerOf(context).scale(1) > 1.25 ||
                  _dateLabel.length > 18) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    heading,
                    const SizedBox(height: 4),
                    Align(alignment: Alignment.centerRight, child: period),
                  ],
                );
              }
              return Row(
                children: [
                  Expanded(child: heading),
                  const SizedBox(width: 12),
                  period,
                ],
              );
            },
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _buildCashFlowTile(
                  theme,
                  'Income',
                  _monthIncome,
                  AppTheme.income,
                  Icons.south_west_rounded,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildCashFlowTile(
                  theme,
                  'Expenses',
                  _monthExpense,
                  AppTheme.expense,
                  Icons.north_east_rounded,
                ),
              ),
            ],
          ),
          if (_cashFlowError != null)
            TextButton.icon(
              onPressed: () => _loadData(cashFlowOnly: true),
              icon: const Icon(Icons.refresh_rounded),
              label: Text('${_cashFlowError!} Retry'),
            ),
        ],
      ),
    );
  }

  Widget _buildCashFlowTile(
    ThemeData theme,
    String label,
    double amount,
    Color color,
    IconData icon,
  ) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .045),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: color.withValues(alpha: .12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 6,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Icon(icon, size: 16, color: color),
              Text(label, style: theme.textTheme.bodySmall),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            _loading || _cashFlowLoading || _cashFlowError != null
                ? '—'
                : _rupeeFmt.format(amount),
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(
    ThemeData theme,
    String title, {
    Widget? trailing,
  }) {
    final heading = Text(
      title,
      style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
    );
    final action =
        trailing ??
        TextButton(
          onPressed: () => setState(() {
            _visitedTabs.add(1);
            _currentIndex = 1;
          }),
          child: const Text('View all'),
        );
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth < 330 ||
              MediaQuery.textScalerOf(context).scale(1) > 1.3) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                heading,
                const SizedBox(height: 8),
                Align(alignment: Alignment.centerRight, child: action),
              ],
            );
          }
          return Row(
            children: [
              Expanded(child: heading),
              const SizedBox(width: 12),
              action,
            ],
          );
        },
      ),
    );
  }

  Widget _buildRecentTransactions(ThemeData theme) {
    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (context, i) => _buildTransactionItem(theme, _recent[i]),
        childCount: _recent.length,
      ),
    );
  }

  Widget _buildTransactionItem(ThemeData theme, TransactionModel t) {
    final isExpense = t.type == 'expense';
    final color = isExpense ? AppTheme.expense : AppTheme.income;
    final sign = isExpense ? '-' : '+';
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 2),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      child: Row(
        children: [
          // Colour bar
          Container(
            width: 3,
            height: 34,
            margin: const EdgeInsets.only(right: 12),
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          // Title + sub
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  t.merchant.isNotEmpty
                      ? t.merchant
                      : t.note.isNotEmpty
                      ? t.note
                      : t.category,
                  style: theme.textTheme.titleSmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 1),
                Text(
                  '${t.merchant.isEmpty && t.note.isEmpty ? '' : '${t.category} · '}${DateFormat('d MMM').format(t.date)}',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
          // Amount
          Text(
            '$sign${_rupeeFmt.format(t.amount)}',
            style: theme.textTheme.titleSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(ThemeData theme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          children: [
            Icon(
              AppIcons.transactions,
              size: 64,
              color: theme.colorScheme.primary.withOpacity(0.3),
            ),
            const SizedBox(height: 16),
            Text(
              'No transactions yet',
              style: theme.textTheme.titleMedium?.copyWith(
                color: theme.colorScheme.onSurface.withOpacity(0.5),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Add an expense to see where your money goes.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withOpacity(0.4),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomNav(ThemeData theme) => SpendyBottomBar(
    selectedIndex: _currentIndex,
    onSelect: (index) {
      setState(() {
        _visitedTabs.add(index);
        _currentIndex = index;
      });
    },
    onAdd: _openAddSheet,
  );

  void _openMoreSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        final theme = Theme.of(ctx);
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(ctx).height * .85,
            ),
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 16,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 36,
                        height: 4,
                        decoration: BoxDecoration(
                          color: theme.colorScheme.onSurface.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      'More tools',
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Plan, track and organize your money.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 24),
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final singleColumn =
                            constraints.maxWidth < 280 ||
                            MediaQuery.textScalerOf(ctx).scale(1) > 1.3;
                        final width = singleColumn
                            ? constraints.maxWidth
                            : (constraints.maxWidth - 12) / 2;
                        return Wrap(
                          spacing: 12,
                          runSpacing: 12,
                          children:
                              [
                                    _buildMoreItem(
                                      ctx,
                                      AppIcons.reports,
                                      'Reports',
                                      () {
                                        Navigator.pop(ctx);
                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (_) =>
                                                const ReportsScreen(),
                                          ),
                                        );
                                      },
                                    ),
                                    _buildMoreItem(
                                      ctx,
                                      AppIcons.goals,
                                      'Goals',
                                      () {
                                        Navigator.pop(ctx);
                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (_) => const GoalsScreen(),
                                          ),
                                        );
                                      },
                                    ),
                                    _buildMoreItem(
                                      ctx,
                                      AppIcons.payments,
                                      'Payments',
                                      () {
                                        Navigator.pop(ctx);
                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (_) =>
                                                const UpcomingPaymentsScreen(),
                                          ),
                                        );
                                      },
                                    ),
                                    _buildMoreItem(
                                      ctx,
                                      AppIcons.categories,
                                      'Categories',
                                      () {
                                        Navigator.pop(ctx);
                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (_) =>
                                                const CategoriesScreen(),
                                          ),
                                        );
                                      },
                                    ),
                                    _buildMoreItem(
                                      ctx,
                                      AppIcons.appliances,
                                      'Appliances',
                                      () {
                                        Navigator.pop(ctx);
                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (_) =>
                                                const AppliancesScreen(),
                                          ),
                                        );
                                      },
                                    ),
                                    _buildMoreItem(
                                      ctx,
                                      AppIcons.settings,
                                      'Settings',
                                      () {
                                        Navigator.pop(ctx);
                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (_) =>
                                                const SettingsScreen(),
                                          ),
                                        );
                                      },
                                    ),
                                  ]
                                  .map(
                                    (child) =>
                                        SizedBox(width: width, child: child),
                                  )
                                  .toList(),
                        );
                      },
                    ),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  void _showDateFilter() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        final theme = Theme.of(ctx);
        return Padding(
          padding: EdgeInsets.fromLTRB(
            24,
            24,
            24,
            24 + MediaQuery.of(ctx).viewInsets.bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Cash-flow period',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 24),
              Text(
                'Select Period',
                style: theme.textTheme.labelLarge?.copyWith(
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children:
                    [
                      'All Time',
                      'Today',
                      'This Month',
                      'This Year',
                      'Custom Range',
                    ].map((p) {
                      final isSelected =
                          (_dateLabel == p) ||
                          (p == 'All Time' && _dateLabel == 'All Time');
                      return ChoiceChip(
                        label: Text(p),
                        selected: isSelected,
                        onSelected: (val) async {
                          if (!val) return;
                          if (p == 'Custom Range') {
                            Navigator.pop(ctx);
                            Future.delayed(
                              const Duration(milliseconds: 100),
                              () => _applyDateFilter(p),
                            );
                          } else {
                            _applyDateFilter(p);
                            Navigator.pop(ctx);
                          }
                        },
                      );
                    }).toList(),
              ),
              const SizedBox(height: 16),
            ],
          ),
        );
      },
    );
  }

  void _applyDateFilter(String period) async {
    final now = DateTime.now();
    DateTime? from;
    DateTime? to;
    String label = period;

    if (period == 'Today') {
      from = DateTime(now.year, now.month, now.day);
      to = from
          .add(const Duration(days: 1))
          .subtract(const Duration(milliseconds: 1));
    } else if (period == 'This Month') {
      from = DateTime(now.year, now.month, 1);
      to = DateTime(now.year, now.month + 1, 0, 23, 59, 59);
    } else if (period == 'This Year') {
      from = DateTime(now.year, 1, 1);
      to = DateTime(now.year, 12, 31, 23, 59, 59);
    } else if (period == 'Custom Range') {
      final picked = await showAppDateRangePicker(
        context: context,
        firstDate: DateTime(2000),
        lastDate: DateTime(2100),
        initialDateRange: _filterDateFrom != null && _filterDateTo != null
            ? DateTimeRange(start: _filterDateFrom!, end: _filterDateTo!)
            : null,
      );
      if (picked != null) {
        from = picked.start;
        to = picked.end
            .add(const Duration(days: 1))
            .subtract(const Duration(milliseconds: 1));
        label =
            '${DateFormat('d MMM').format(from)} - ${DateFormat('d MMM').format(to)}';
      } else {
        return;
      }
    } else {
      // All Time
      from = null;
      to = null;
      label = 'All Time';
    }

    if (!mounted) return;
    setState(() {
      _filterDateFrom = from;
      _filterDateTo = to;
      _dateLabel = label;
    });
    _loadData(cashFlowOnly: true);
  }

  Widget _buildMoreItem(
    BuildContext ctx,
    IconData icon,
    String label,
    VoidCallback onTap,
  ) {
    final theme = Theme.of(ctx);
    return Material(
      color: theme.colorScheme.primary.withValues(alpha: .055),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(
          color: theme.colorScheme.primary.withValues(alpha: .10),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                icon,
                color: AppIcons.actionColor(theme),
                size: AppIcons.actionSize,
              ),
              const SizedBox(height: 12),
              Text(
                label,
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
                softWrap: true,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openAddSheet() async {
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
                child: Text(
                  'Add a transaction',
                  style: Theme.of(ctx).textTheme.headlineSmall,
                ),
              ),
              ListTile(
                leading: const Icon(AppIcons.edit),
                title: const Text('Enter manually'),
                subtitle: const Text('A quick amount, account and category'),
                onTap: () => Navigator.pop(ctx, 'manual'),
              ),
              ListTile(
                leading: const Icon(AppIcons.scan),
                title: const Text('Scan a receipt'),
                subtitle: const Text('Review the details before saving'),
                onTap: () => Navigator.pop(ctx, 'scan'),
              ),
              ListTile(
                leading: const Icon(AppIcons.voice),
                title: const Text('Use your voice'),
                subtitle: const Text('Say what you spent and where'),
                onTap: () => Navigator.pop(ctx, 'voice'),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
    if (!mounted || action == null) return;
    if (action == 'voice') {
      _toggleListening();
      return;
    }
    if (action == 'scan') {
      _handleScan();
      return;
    }
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const TransactionEntryScreen()),
    );
    if (mounted) _loadData();
  }

  Future<void> _toggleListening() async {
    if (_voiceEntryOpen) return;
    _voiceEntryOpen = true;
    try {
      if (!await ensureFeatureAiReady(context, service: _aiService) ||
          !mounted) {
        return;
      }
      final result = await showDialog<VoiceEntryResult>(
        context: context,
        barrierDismissible: false,
        builder: (_) => VoiceEntryDialog(
          capture: _voiceService,
          parse: _aiService.parseIntent,
        ),
      );
      if (!mounted || result == null) return;
      if (result.manual) {
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => const TransactionEntryScreen(),
          ),
        );
        if (mounted) _loadData(silent: true);
      } else if (result.action != null) {
        await _executeAIAction(result.action!);
      }
    } finally {
      _voiceEntryOpen = false;
    }
  }

  Future<void> _executeAIAction(
    AIAction action, {
    bool isFromOcr = false,
  }) async {
    final accountState = context.read<AccountBloc>().state;
    final selectedId = accountState is AccountLoaded
        ? accountState.selectedAccountId
        : null;

    int fallbackId = 1;
    if (accountState is AccountLoaded && accountState.accounts.isNotEmpty) {
      fallbackId = accountState.accounts.first.id ?? 1;
    }
    final targetAccountId = selectedId ?? fallbackId;

    final transactionRepo = context.read<TransactionRepository>();

    if (action.type == AIActionType.add) {
      if (!isFromOcr && (action.items?.length ?? 0) > 1) {
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) =>
                TransactionEntryScreen(aiAction: action, isVoiceEntry: true),
          ),
        );
        if (mounted) _loadData(silent: true);
        return;
      }
      // AI-derived values must be reviewed before a financial commit.
      if (action.amount != null &&
          action.amount!.isFinite &&
          action.amount! > 0) {
        final choice = await showDialog<String>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Review transaction'),
            scrollable: true,
            content: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '₹${action.amount!.toStringAsFixed(2)}',
                  style: Theme.of(ctx).textTheme.headlineMedium,
                ),
                const SizedBox(height: 12),
                Text('Category: ${action.category ?? 'Other'}'),
                if (action.merchant?.isNotEmpty ?? false)
                  Text('Merchant: ${action.merchant}'),
                Text(
                  'Account: ${accountState is AccountLoaded ? accountState.accounts.firstWhereOrNull((a) => a.id == targetAccountId)?.name ?? 'Selected account' : 'Selected account'}',
                ),
                Text(
                  'Date: ${DateFormat('d MMM yyyy').format(action.date ?? DateTime.now())}',
                ),
                if (action.items?.isNotEmpty ?? false) ...[
                  const SizedBox(height: 12),
                  const Text('Split items'),
                  ...action.items!.map(
                    (item) => Text(
                      '${item.merchant ?? item.category}: ₹${item.amount.toStringAsFixed(2)}',
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                const Text('Check these details before saving.'),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, 'edit'),
                child: const Text('Edit details'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, 'save'),
                child: const Text('Save expense'),
              ),
            ],
          ),
        );
        if (!mounted || choice == null) return;
        if (choice == 'edit') {
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => TransactionEntryScreen(
                aiAction: action,
                initialTab: isFromOcr ? 1 : 0,
                isVoiceEntry: !isFromOcr,
              ),
            ),
          );
          if (mounted) _loadData();
          return;
        }
        final completion = Completer<bool>();
        final t = TransactionModel(
          accountId: targetAccountId,
          amount: action.amount!,
          category: action.category ?? 'Other',
          merchant: action.merchant ?? '',
          date: action.date ?? DateTime.now(),
          type: 'expense',
          isVoice: !isFromOcr,
          isOcr: isFromOcr,
        );

        // Direct Save or Split Save
        final validItems =
            action.items?.where((item) => item.amount > 0).toList() ?? [];
        if (validItems.isNotEmpty) {
          final parts = validItems
              .map(
                (item) => TransactionModel(
                  accountId: t.accountId,
                  amount: item.amount,
                  category: item.category.isEmpty ? 'Other' : item.category,
                  merchant:
                      item.merchant ??
                      (item.category.isNotEmpty ? item.category : t.merchant),
                  date: t.date,
                  type: 'expense',
                ),
              )
              .toList();

          double splitSum = parts.fold(0, (sum, item) => sum + item.amount);
          if (t.amount > splitSum && (t.amount - splitSum) >= 1.0) {
            parts.add(
              TransactionModel(
                accountId: t.accountId,
                amount: t.amount - splitSum,
                category: 'Other',
                merchant: t.merchant.isNotEmpty
                    ? '${t.merchant} (Other)'
                    : 'Other Items',
                date: t.date,
                type: 'expense',
              ),
            );
          }

          context.read<TransactionBloc>().add(
            AddTransaction(
              t.copyWith(
                note: '[Split] ${action.merchant ?? "Receipt"}'.trim(),
              ),
              splitChildren: parts,
              completion: completion,
            ),
          );
        } else {
          // Standard Single Transaction
          context.read<TransactionBloc>().add(
            AddTransaction(t, completion: completion),
          );
        }
        final saved = await completion.future;
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              persist: false,
              content: Text(
                saved
                    ? 'Transaction saved'
                    : 'Could not save this transaction. Please try again.',
              ),
            ),
          );
        }
        return;
      }

      // Fallback: If AI parsing was incomplete, open manual screen with partial data
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => TransactionEntryScreen(
            initialTab: isFromOcr ? 1 : 0,
            aiAction: action,
            isVoiceEntry: !isFromOcr,
          ),
        ),
      );
      if (mounted) _loadData();
    } else if (action.type == AIActionType.delete ||
        action.type == AIActionType.update) {
      final transactions = await transactionRepo.getTransactions(
        accountId: selectedId,
      );

      final query =
          (action.merchant?.isNotEmpty == true
                  ? action.merchant
                  : action.category)
              ?.trim()
              .toLowerCase();
      final matches = query == null || query.isEmpty
          ? <TransactionModel>[]
          : transactions
                .where(
                  (t) =>
                      (t.category.toLowerCase() == query ||
                          t.merchant.toLowerCase() == query) &&
                      (action.date == null ||
                          DateUtils.isSameDay(t.date, action.date)),
                )
                .toList();
      final target = matches.length == 1 ? matches.single : null;

      if (target == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              persist: false,
              content: Text(
                'Open the transaction you want to change in Transactions.',
              ),
            ),
          );
        }
        return;
      }

      _showActionConfirmation(action, target);
    }
  }

  Future<void> _handleScan() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const TransactionEntryScreen(initialTab: 1),
      ),
    );
    if (mounted) _loadData();
  }

  void _showActionConfirmation(AIAction action, TransactionModel t) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        final isDelete = action.type == AIActionType.delete;
        return Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                isDelete ? 'Confirm Deletion' : 'Confirm Update',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Theme.of(
                    context,
                  ).colorScheme.surfaceVariant.withOpacity(0.5),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Icon(
                      isDelete
                          ? AppIcons.deleteForever
                          : Icons.edit_note_rounded,
                      color: isDelete ? Colors.red : Colors.blue,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        '${t.merchant.isNotEmpty
                            ? t.merchant
                            : t.note.isNotEmpty
                            ? t.note
                            : t.category}: ₹${t.amount}\nDate: ${DateFormat('MMM d').format(t.date)}',
                        style: const TextStyle(fontWeight: FontWeight.w500),
                      ),
                    ),
                  ],
                ),
              ),
              if (!isDelete && action.amount != null) ...[
                const Icon(
                  Icons.arrow_downward_rounded,
                  size: 20,
                  color: Colors.grey,
                ),
                Text(
                  'New Amount: ₹${action.amount}',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.primary,
                  ),
                ),
              ],
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: isDelete
                            ? Colors.red
                            : AppTheme.primary,
                        foregroundColor: Colors.white,
                      ),
                      onPressed: () async {
                        final txBloc = context.read<TransactionBloc>();
                        final messenger = ScaffoldMessenger.of(context);

                        if (isDelete) {
                          txBloc.add(DeleteTransaction(t));
                        } else {
                          final targetAmount = action.amount ?? t.amount;
                          final validItems =
                              action.items
                                  ?.where((item) => item.amount > 0)
                                  .toList() ??
                              [];

                          if (validItems.isNotEmpty) {
                            final parts = validItems
                                .map(
                                  (item) => TransactionModel(
                                    accountId: t.accountId,
                                    amount: item.amount,
                                    category: item.category.isEmpty
                                        ? 'Other'
                                        : item.category,
                                    merchant:
                                        item.merchant ??
                                        (item.category.isNotEmpty
                                            ? item.category
                                            : action.merchant ?? t.merchant),
                                    date: action.date ?? t.date,
                                    type: t.type,
                                  ),
                                )
                                .toList();

                            double splitSum = parts.fold(
                              0,
                              (sum, item) => sum + item.amount,
                            );
                            if (targetAmount > splitSum &&
                                (targetAmount - splitSum) >= 1.0) {
                              parts.add(
                                TransactionModel(
                                  accountId: t.accountId,
                                  amount: targetAmount - splitSum,
                                  category: 'Other',
                                  merchant: t.merchant.isNotEmpty
                                      ? '${t.merchant} (Other)'
                                      : 'Other Items',
                                  date: action.date ?? t.date,
                                  type: t.type,
                                ),
                              );
                            }

                            // Replace old standard transaction with explicitly math-balanced split parent
                            txBloc.add(DeleteTransaction(t));
                            txBloc.add(
                              AddTransaction(
                                TransactionModel(
                                  accountId: t.accountId,
                                  amount: targetAmount,
                                  category: action.category ?? t.category,
                                  merchant: action.merchant ?? t.merchant,
                                  date: action.date ?? t.date,
                                  note:
                                      '[Split] ${action.merchant ?? t.merchant}'
                                          .trim(),
                                  type: t.type,
                                  isVoice: true,
                                ),
                                splitChildren: parts,
                              ),
                            );
                          } else {
                            // Standard Amount or Metadata Update
                            txBloc.add(
                              UpdateTransaction(
                                t.copyWith(
                                  amount: targetAmount,
                                  category: action.category ?? t.category,
                                  merchant: action.merchant ?? t.merchant,
                                  date: action.date ?? t.date,
                                ),
                                t,
                              ),
                            );
                          }
                        }
                        if (context.mounted) {
                          Navigator.pop(ctx);
                          messenger.showSnackBar(
                            SnackBar(
                              persist: false,
                              content: Text(
                                isDelete
                                    ? 'Transaction deleted.'
                                    : 'Transaction updated.',
                              ),
                            ),
                          );
                        }
                      },
                      child: Text(isDelete ? 'Delete' : 'Update'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

class _AccountSearchContent extends StatefulWidget {
  final List<Account> accounts;
  final int? selectedId;
  final ScrollController scrollController;
  final Function(int?) onSelect;

  const _AccountSearchContent({
    required this.accounts,
    required this.selectedId,
    required this.scrollController,
    required this.onSelect,
  });

  @override
  State<_AccountSearchContent> createState() => _AccountSearchContentState();
}

class _AccountSearchContentState extends State<_AccountSearchContent> {
  String _query = "";

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final filtered = widget.accounts
        .where((a) => a.bankName.toLowerCase().contains(_query.toLowerCase()))
        .toList();

    return Material(
      color: cs.surface,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          const SizedBox(height: 12),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: cs.outlineVariant,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 20),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: TextField(
              autofocus: true,
              decoration: InputDecoration(
                hintText: 'Search for a bank...',
                prefixIcon: const Icon(AppIcons.search),
                filled: true,
                fillColor: cs.surfaceVariant.withOpacity(0.3),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(vertical: 0),
              ),
              onChanged: (val) => setState(() => _query = val),
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: ListView.builder(
              controller: widget.scrollController,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              itemCount: filtered.length + 1,
              itemBuilder: (c, idx) {
                final isAll = idx == 0;
                final account = isAll ? null : filtered[idx - 1];
                final isSelected = isAll
                    ? widget.selectedId == null
                    : widget.selectedId == account?.id;

                return ListTile(
                  leading: CircleAvatar(
                    backgroundColor: isSelected
                        ? cs.primary
                        : cs.surfaceVariant.withOpacity(0.5),
                    child: Icon(
                      isAll ? Icons.all_inclusive : AppIcons.bank,
                      color: isSelected ? cs.onPrimary : cs.onSurfaceVariant,
                      size: 18,
                    ),
                  ),
                  title: Text(
                    isAll ? 'All Banks' : account!.bankName,
                    style: TextStyle(
                      fontWeight: isSelected
                          ? FontWeight.bold
                          : FontWeight.normal,
                      color: cs.onSurface,
                    ),
                  ),
                  trailing: isSelected
                      ? Icon(AppIcons.success, color: cs.primary)
                      : null,
                  onTap: () => widget.onSelect(isAll ? null : account!.id),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
