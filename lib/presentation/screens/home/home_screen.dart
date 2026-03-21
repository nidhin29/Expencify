import 'package:flutter/material.dart';
import 'dart:async';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:expencify/presentation/screens/setup/setup_required_screen.dart';
import 'package:expencify/application/services/ai/local_ai_model.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:shimmer/shimmer.dart';
import 'package:intl/intl.dart';
import 'dart:ui';

import 'package:expencify/presentation/theme/app_theme.dart';
import 'package:expencify/presentation/screens/transactions/transaction_entry_screen.dart';
import 'package:expencify/presentation/screens/transactions/transaction_list_screen.dart';
import 'package:expencify/presentation/screens/accounts/accounts_screen.dart';
import 'package:expencify/presentation/screens/budgets/budgets_screen.dart';
import 'package:expencify/presentation/screens/reports/reports_screen.dart';
import 'package:expencify/presentation/screens/settings/settings_screen.dart';
import 'package:expencify/presentation/screens/goals/goals_screen.dart';
import 'package:expencify/presentation/screens/reminders/reminders_screen.dart';
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
import 'package:expencify/application/services/ocr/ocr_service.dart';
import 'package:expencify/application/blocs/transaction/transaction_bloc.dart';
import 'package:expencify/application/blocs/transaction/transaction_event.dart';
import 'package:expencify/application/blocs/transaction/transaction_state.dart';
import 'package:expencify/application/services/sms/sms_monitor_service.dart';
import 'package:image_picker/image_picker.dart';
import 'package:collection/collection.dart';

/// Global route observer instance — register in MaterialApp.navigatorObservers.
final RouteObserver<ModalRoute<void>> homeRouteObserver =
    RouteObserver<ModalRoute<void>>();

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with TickerProviderStateMixin, RouteAware {
  late AnimationController _pulseController;
  late AnimationController _orbitController;
  int _currentIndex = 0;
  final _rupeeFmt = NumberFormat.currency(
    locale: 'en_IN',
    symbol: '₹',
    decimalDigits: 0,
  );

  double _balance = 0;
  double _monthIncome = 0;
  double _monthExpense = 0;
  List<TransactionModel> _recent = [];
  Map<String, double> _weeklyExpenses = {};
  DateTime? _filterDateFrom;
  DateTime? _filterDateTo;
  String _dateLabel = 'This month';
  String _chartPeriod = '7 Days';
  bool _loading = true;
  bool _isListening = false;
  bool _isAiThinking = false;
  bool _requirementsMet =
      true; // Assume met on startup to prevent spinner flashing
  final _voiceService = VoiceService();
  final _aiService = AIService();
  final _ocrService = OCRService();
  StreamSubscription? _smsSubscription;

  @override
  void initState() {
    super.initState();
    // Use WidgetsBinding to call _loadData after Provider is accessible
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadData();
    });

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);

    _orbitController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat();

    // Initialize AI Service
    _aiService.init();
    _checkInitialRequirements();

    // Trigger Reminder load for heads-up UI
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<ReminderBloc>().add(LoadReminders());
    });

    // Listen to background SMS isolate alerts to reload UI in real-time
    _smsSubscription = SmsMonitorService.onSmsProcessed.stream.listen((_) {
      if (mounted) {
        context.read<TransactionBloc>().add(LoadTransactions());
        context.read<AccountBloc>().add(LoadAccounts());
        _loadData(silent: true);
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Subscribe to route events so _loadData fires whenever HomeScreen resumes.
    homeRouteObserver.subscribe(this, ModalRoute.of(context)!);
  }

  @override
  void didPopNext() {
    // Called whenever a route above HomeScreen is popped (e.g. TransactionEntry).
    if (mounted) _loadData(silent: true);
  }

  @override
  void dispose() {
    _smsSubscription?.cancel();
    homeRouteObserver.unsubscribe(this);
    _pulseController.dispose();
    _orbitController.dispose();
    _voiceService.stopListening();
    super.dispose();
  }

  Future<void> _checkInitialRequirements() async {
    final sms = await Permission.sms.isGranted;
    final battery = await Permission.ignoreBatteryOptimizations.isGranted;
    final ai = await _aiService.modelExists(LocalAIModelType.qwenLite);

    if (mounted) {
      setState(() {
        _requirementsMet = sms && battery && ai;
      });
    }
  }

  Future<void> _loadData({bool silent = false}) async {
    if (!mounted) return;

    final transactionRepo = context.read<TransactionRepository>();
    final accountState = context.read<AccountBloc>().state;
    int? selectedId;
    if (accountState is AccountLoaded) {
      selectedId = accountState.selectedAccountId;
    }

    if (!silent) {
      setState(() => _loading = true);
    }
    // Compute balance as sum of all-time income minus expenses for the selected
    // account (or all accounts). This is always accurate regardless of whether
    // the `balance` column on the accounts table is in sync.
    final allTimeIncome = await transactionRepo.getRangeTotal(
      'income',
      accountId: selectedId,
    );
    final allTimeExpense = await transactionRepo.getRangeTotal(
      'expense',
      accountId: selectedId,
    );
    final balance = allTimeIncome - allTimeExpense;

    // Default to this month if no filter set
    DateTime? from = _filterDateFrom;
    DateTime? to = _filterDateTo;
    if (from == null && _dateLabel.toLowerCase() == 'this month') {
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

    // Dynamic Chart Data
    final nowChart = DateTime.now();
    DateTime fromChart;
    Map<String, double> chartData = {};

    if (_chartPeriod == '7 Days') {
      fromChart = DateTime(
        nowChart.year,
        nowChart.month,
        nowChart.day,
      ).subtract(const Duration(days: 6));
      chartData = await transactionRepo.getDailyTotals(
        type: 'expense',
        from: fromChart,
        to: nowChart,
        accountId: selectedId,
      );
    } else if (_chartPeriod == '30 Days') {
      fromChart = DateTime(
        nowChart.year,
        nowChart.month,
        nowChart.day,
      ).subtract(const Duration(days: 29));
      chartData = await transactionRepo.getDailyTotals(
        type: 'expense',
        from: fromChart,
        to: nowChart,
        accountId: selectedId,
      );
    } else {
      // This Year
      fromChart = DateTime(nowChart.year, 1, 1);
      chartData = await transactionRepo.getRangeMonthlyTotals(
        type: 'expense',
        from: fromChart,
        to: nowChart,
      );
    }

    if (mounted) {
      setState(() {
        _balance = balance;
        _monthIncome = income;
        _monthExpense = expense;
        _recent = recent;
        _weeklyExpenses = chartData;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    // Intermediate requirements check screen removed to avoid flashing spinners

    if (!_requirementsMet) {
      return SetupRequiredScreen(
        onComplete: () => setState(() => _requirementsMet = true),
      );
    }

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: theme.brightness == Brightness.dark
            ? Brightness.light
            : Brightness.dark,
        statusBarBrightness: theme.brightness, // For iOS
      ),
      child: Scaffold(
        floatingActionButton: _buildVoiceButton(),
        floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
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
                if (state is AccountLoaded) _loadData(silent: true);
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
                      TransactionListScreen(onRefresh: _loadData),
                      BudgetScreen(onRefresh: _loadData),
                      const AccountManagementScreen(),
                      const SettingsScreen(),
                    ],
                  ),
                ),
                if (_isListening || _isAiThinking) _buildVoiceOverlay(theme),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDashboardView(ThemeData theme) {
    return RefreshIndicator(
      onRefresh: () => _loadData(silent: true),
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          _buildAppBar(theme),
          SliverToBoxAdapter(child: _buildHeadsUpReminder(theme)),
          _buildAccountSelectorChips(theme),
          SliverToBoxAdapter(child: _buildBalanceCard(theme)),
          SliverToBoxAdapter(child: _buildQuickActions(theme)),
          SliverToBoxAdapter(
            child: _buildSectionHeader(
              theme,
              'Spending Overview',
              trailing: _buildChartPeriodSelector(theme),
            ),
          ),
          SliverToBoxAdapter(child: _buildSpendingChart(theme)),
          SliverToBoxAdapter(
            child: _buildSectionHeader(theme, 'Recent Transactions'),
          ),
          if (_loading)
            const SliverToBoxAdapter(
              child: Center(
                child: Padding(
                  padding: EdgeInsets.all(32),
                  child: CircularProgressIndicator(),
                ),
              ),
            )
          else if (_recent.isEmpty)
            SliverToBoxAdapter(child: _buildEmptyState(theme))
          else
            _buildRecentTransactions(theme),
          const SliverToBoxAdapter(child: SizedBox(height: 100)),
        ],
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
                          height: 28,
                          width: 28,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        'Expencify',
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
                Icons.psychology_outlined,
                size: 24,
                color: cs.primary,
              ),
              tooltip: 'Ask Expencify AI',
            ),
            IconButton(
              onPressed: _openMoreSheet,
              icon: Icon(
                Icons.grid_view_rounded,
                size: 22,
                color: cs.onSurfaceVariant,
              ),
              tooltip: 'More',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeadsUpReminder(ThemeData theme) {
    return BlocBuilder<ReminderBloc, ReminderState>(
      builder: (context, state) {
        if (state is! ReminderLoaded) return const SizedBox.shrink();

        final activeReminders = state.reminders
            .where((r) => r.isOverdue || r.isDueSoon)
            .toList();
        if (activeReminders.isEmpty) return const SizedBox.shrink();

        // Show the most urgent one
        final r = activeReminders.first;
        final isOverdue = r.isOverdue;

        return Container(
          margin: const EdgeInsets.fromLTRB(20, 8, 20, 16),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: isOverdue
                  ? [
                      Colors.red.shade900.withOpacity(0.8),
                      Colors.red.shade800.withOpacity(0.6),
                    ]
                  : [
                      theme.colorScheme.primary.withOpacity(0.15),
                      theme.colorScheme.primary.withOpacity(0.05),
                    ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isOverdue
                  ? Colors.red.withOpacity(0.3)
                  : theme.colorScheme.primary.withOpacity(0.2),
            ),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: isOverdue ? Colors.red : theme.colorScheme.primary,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  isOverdue
                      ? Icons.priority_high_rounded
                      : Icons.notifications_active_rounded,
                  color: Colors.white,
                  size: 20,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isOverdue ? 'BILL OVERDUE' : 'REMINDER',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: isOverdue
                            ? Colors.red.shade100
                            : theme.colorScheme.primary,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.2,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${r.title}: ${_rupeeFmt.format(r.amount)}',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: isOverdue
                            ? Colors.white
                            : theme.colorScheme.onSurface,
                      ),
                    ),
                    Text(
                      isOverdue
                          ? 'Immediate payment required'
                          : 'Due on ${DateFormat('d MMM').format(r.dueDate)}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color:
                            (isOverdue
                                    ? Colors.white
                                    : theme.colorScheme.onSurface)
                                .withOpacity(0.7),
                      ),
                    ),
                  ],
                ),
              ),
              TextButton(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const RemindersScreen()),
                  );
                },
                style: TextButton.styleFrom(
                  backgroundColor: isOverdue
                      ? Colors.white.withOpacity(0.2)
                      : theme.colorScheme.primary.withOpacity(0.1),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: Text(
                  'VIEW',
                  style: TextStyle(
                    color: isOverdue ? Colors.white : theme.colorScheme.primary,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
        );
      },
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
              height: 48,
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
                          Icons.search_rounded,
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
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isDark ? AppTheme.darkBorder : AppTheme.lightBorder,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Label row
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    'NET BALANCE',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: AppTheme.primary,
                      letterSpacing: 1,
                    ),
                  ),
                ),
                const Spacer(),
                GestureDetector(
                  onTap: _showDateFilter,
                  behavior: HitTestBehavior.opaque,
                  child: Row(
                    children: [
                      Text(
                        _dateLabel,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: AppTheme.primary,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Icon(
                        Icons.keyboard_arrow_down_rounded,
                        size: 14,
                        color: AppTheme.primary,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            // Big balance — read directly from AccountBloc so it updates instantly
            BlocBuilder<AccountBloc, AccountState>(
              builder: (context, accState) {
                if (_loading) {
                  return Container(
                    height: 38,
                    width: 140,
                    decoration: BoxDecoration(
                      color: cs.surfaceVariant,
                      borderRadius: BorderRadius.circular(6),
                    ),
                  );
                }
                final liveBalance = accState is AccountLoaded
                    ? (accState.selectedAccountId != null
                          ? (accState.selectedAccount?.balance ??
                                accState.totalBalance)
                          : accState.totalBalance)
                    : _balance;
                return Text(
                  _rupeeFmt.format(liveBalance),
                  style: theme.textTheme.displayLarge,
                );
              },
            ),
            const SizedBox(height: 16),
            // Divider
            Divider(
              height: 1,
              color: isDark ? AppTheme.darkBorder : AppTheme.lightBorder,
            ),
            const SizedBox(height: 14),
            // Income / Expense row
            Row(
              children: [
                Expanded(
                  child: StatTile(
                    label: 'INCOME',
                    value: _rupeeFmt.format(_monthIncome),
                    valueColor: AppTheme.income,
                    icon: Icons.arrow_downward_rounded,
                  ),
                ),
                Container(
                  width: 1,
                  height: 32,
                  color: isDark ? AppTheme.darkBorder : AppTheme.lightBorder,
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(left: 16),
                    child: StatTile(
                      label: 'EXPENSES',
                      value: _rupeeFmt.format(_monthExpense),
                      valueColor: AppTheme.expense,
                      icon: Icons.arrow_upward_rounded,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickActions(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
      child: Row(
        children: [
          _buildQuickBtn(
            theme,
            Icons.document_scanner_rounded,
            'Scan',
            const Color(0xFFF59E0B),
            () => _handleScan(),
          ),
          const SizedBox(width: 8),
          _buildQuickBtn(
            theme,
            Icons.edit_rounded,
            'Manual',
            const Color(0xFF0EA5E9),
            () async {
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const TransactionEntryScreen(),
                ),
              );
              if (mounted) _loadData();
            },
          ),
        ],
      ),
    );
  }

  Widget _buildQuickBtn(
    ThemeData theme,
    IconData icon,
    String label,
    Color color,
    VoidCallback onTap,
  ) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 11),
          decoration: BoxDecoration(
            color: color.withOpacity(0.08),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: color.withOpacity(0.18)),
          ),
          child: Column(
            children: [
              Icon(icon, color: color, size: 18),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  color: color,
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.3,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSpendingChart(ThemeData theme) {
    final now = DateTime.now();
    List<DateTime> periods = [];
    int count = 0;

    if (_chartPeriod == '7 Days') {
      count = 7;
      periods = List.generate(7, (i) => now.subtract(Duration(days: 6 - i)));
    } else if (_chartPeriod == '30 Days') {
      count = 30;
      periods = List.generate(30, (i) => now.subtract(Duration(days: 29 - i)));
    } else {
      // This Year
      count = 12;
      periods = List.generate(12, (i) => DateTime(now.year, i + 1, 1));
    }

    final maxVal = _weeklyExpenses.values.isEmpty
        ? 1000.0
        : _weeklyExpenses.values
              .reduce((a, b) => a > b ? a : b)
              .clamp(100.0, double.infinity);
    // Calculate a nice interval for Y axis (approx 4-5 labels)
    double interval = 100;
    if (maxVal <= 200) {
      interval = 50;
    } else if (maxVal <= 500) {
      interval = 100;
    } else if (maxVal <= 2500) {
      interval = 500;
    } else if (maxVal <= 10000) {
      interval = 2000;
    } else {
      interval = (maxVal / 4).ceilToDouble();
    }

    // Force maxY to be a multiple of interval for cleaner grid
    final maxY = ((maxVal * 1.25) / interval).ceil() * interval;

    return Container(
      height: 220,
      margin: const EdgeInsets.symmetric(horizontal: 20),
      padding: const EdgeInsets.fromLTRB(8, 20, 16, 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: theme.brightness == Brightness.dark
              ? AppTheme.darkBorder
              : AppTheme.lightBorder,
        ),
      ),
      child: BarChart(
        BarChartData(
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            getDrawingHorizontalLine: (v) => FlLine(
              color: theme.colorScheme.onSurface.withOpacity(0.06),
              strokeWidth: 1,
            ),
          ),
          titlesData: FlTitlesData(
            rightTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            topTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 28,
                getTitlesWidget: (v, _) {
                  final i = v.toInt();
                  if (i < 0 || i >= periods.length) return const SizedBox();

                  // Adaptive labels
                  String label = '';
                  if (_chartPeriod == '7 Days') {
                    label = DateFormat('E').format(periods[i]);
                  } else if (_chartPeriod == '30 Days') {
                    // Show label every 7 days for 30 day view, but avoid overlap with last item
                    if (i % 7 == 0 && i < periods.length - 4) {
                      label = DateFormat('d/M').format(periods[i]);
                    } else if (i == periods.length - 1) {
                      label = DateFormat('d/M').format(periods[i]);
                    }
                  } else {
                    // This Year - show month initials
                    label = DateFormat('MMM').format(periods[i])[0];
                  }

                  if (label.isEmpty) return const SizedBox();

                  return Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      label,
                      style: TextStyle(
                        color: theme.colorScheme.onSurface.withOpacity(0.5),
                        fontSize: 10,
                      ),
                    ),
                  );
                },
              ),
            ),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 44,
                interval: interval,
                getTitlesWidget: (v, _) {
                  if (v == 0) return const SizedBox();
                  String text;
                  if (v >= 1000) {
                    text =
                        '₹${(v / 1000).toStringAsFixed(v % 1000 == 0 ? 0 : 1)}k';
                  } else {
                    text = '₹${v.toInt()}';
                  }
                  return Text(
                    text,
                    style: TextStyle(
                      color: theme.colorScheme.onSurface.withOpacity(0.4),
                      fontSize: 10,
                    ),
                  );
                },
              ),
            ),
          ),
          borderData: FlBorderData(show: false),
          maxY: maxY,
          barGroups: List.generate(count, (i) {
            String key;
            if (_chartPeriod == 'This Year') {
              key = DateFormat('yyyy-MM').format(periods[i]);
            } else {
              key = DateFormat('yyyy-MM-dd').format(periods[i]);
            }

            final val = _weeklyExpenses[key] ?? 0;
            return BarChartGroupData(
              x: i,
              barRods: [
                BarChartRodData(
                  toY: val,
                  color: val > 0
                      ? theme.colorScheme.primary
                      : theme.colorScheme.primary.withOpacity(0.15),
                  width: _chartPeriod == '30 Days'
                      ? 6
                      : (_chartPeriod == 'This Year' ? 14 : 16),
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(4),
                  ),
                ),
              ],
            );
          }),
        ),
      ),
    );
  }

  Widget _buildChartPeriodSelector(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceVariant.withOpacity(0.5),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: ['7D', '30D', 'Year'].map((p) {
          final isSelected =
              (_chartPeriod == '7 Days' && p == '7D') ||
              (_chartPeriod == '30 Days' && p == '30D') ||
              (_chartPeriod == 'This Year' && p == 'Year');
          return GestureDetector(
            onTap: () {
              setState(() {
                if (p == '7D') _chartPeriod = '7 Days';
                if (p == '30D') _chartPeriod = '30 Days';
                if (p == 'Year') _chartPeriod = 'This Year';
              });
              _loadData();
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: isSelected
                    ? theme.colorScheme.surface
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(6),
                boxShadow: isSelected
                    ? [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.05),
                          blurRadius: 4,
                          offset: const Offset(0, 2),
                        ),
                      ]
                    : null,
              ),
              child: Text(
                p,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: isSelected
                      ? theme.colorScheme.primary
                      : theme.colorScheme.onSurface.withOpacity(0.5),
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  fontSize: 10,
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildSectionHeader(
    ThemeData theme,
    String title, {
    Widget? trailing,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 12, 8),
      child: Row(
        children: [
          Text(
            title.toUpperCase(),
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              letterSpacing: 1.2,
              fontWeight: FontWeight.bold,
            ),
          ),
          const Spacer(),
          if (trailing != null)
            trailing
          else
            TextButton(
              onPressed: () => setState(() => _currentIndex = 1),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text(
                'View All',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: AppTheme.primary,
                  letterSpacing: 0.5,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
        ],
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
                  t.merchant.isNotEmpty ? t.merchant : t.category,
                  style: theme.textTheme.titleSmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 1),
                Text(
                  '${t.category} · ${DateFormat('d MMM').format(t.date)}',
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
              Icons.receipt_long_rounded,
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
              'Tap + to add your first one!',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withOpacity(0.4),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomNav(ThemeData theme) {
    return BottomAppBar(
      color: theme.colorScheme.surface,
      elevation: 10,
      surfaceTintColor: theme.colorScheme.surface,
      shadowColor: Colors.black.withOpacity(0.1),
      notchMargin: 8,
      padding: EdgeInsets.zero,
      height: 65,
      shape: const CircularNotchedRectangle(),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildNavItem(theme, 0, Icons.grid_view_rounded, 'Home'),
          _buildNavItem(theme, 1, Icons.receipt_long_rounded, 'Passbook'),
          const SizedBox(width: 40), // FAB notch gap
          _buildNavItem(theme, 2, Icons.pie_chart_rounded, 'Budget'),
          _buildNavItem(
            theme,
            3,
            Icons.account_balance_wallet_rounded,
            'Accounts',
          ),
        ],
      ),
    );
  }

  Widget _buildNavItem(
    ThemeData theme,
    int index,
    IconData icon,
    String label,
  ) {
    bool isSelected = _currentIndex == index;
    final color = isSelected
        ? theme.colorScheme.primary
        : theme.colorScheme.onSurface.withOpacity(0.6);
    return InkWell(
      onTap: () => setState(() => _currentIndex = index),
      customBorder: const CircleBorder(),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 26),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 10,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ],
      ),
    );
  }

  void _openMoreSheet() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        final theme = Theme.of(ctx);
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
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
                  'Quick Access'.toUpperCase(),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    letterSpacing: 1.2,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 20),
                GridView.count(
                  shrinkWrap: true,
                  crossAxisCount: 4,
                  mainAxisSpacing: 16,
                  crossAxisSpacing: 12,
                  childAspectRatio: 0.85,
                  physics: const NeverScrollableScrollPhysics(),
                  children: [
                    _buildMoreItem(
                      ctx,
                      Icons.psychology_rounded,
                      'AI Chat',
                      () {
                        Navigator.pop(ctx);
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const ChatScreen()),
                        );
                      },
                    ),
                    _buildMoreItem(ctx, Icons.bar_chart_rounded, 'Reports', () {
                      Navigator.pop(ctx);
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const ReportsScreen(),
                        ),
                      );
                    }),
                    _buildMoreItem(ctx, Icons.savings_rounded, 'Goals', () {
                      Navigator.pop(ctx);
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const GoalsScreen()),
                      );
                    }),
                    _buildMoreItem(ctx, Icons.alarm_rounded, 'Reminders', () {
                      Navigator.pop(ctx);
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const RemindersScreen(),
                        ),
                      );
                    }),
                    _buildMoreItem(
                      ctx,
                      Icons.category_rounded,
                      'Categories',
                      () {
                        Navigator.pop(ctx);
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const CategoriesScreen(),
                          ),
                        );
                      },
                    ),
                    _buildMoreItem(
                      ctx,
                      Icons.devices_other_rounded,
                      'Appliances',
                      () {
                        Navigator.pop(ctx);
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const AppliancesScreen(),
                          ),
                        );
                      },
                    ),
                    _buildMoreItem(ctx, Icons.settings_rounded, 'Settings', () {
                      Navigator.pop(ctx);
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const SettingsScreen(),
                        ),
                      );
                    }),
                  ],
                ),
                const SizedBox(height: 24),
              ],
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
                'Filter Dashboard',
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
      final picked = await showDateRangePicker(
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

    setState(() {
      _filterDateFrom = from;
      _filterDateTo = to;
      _dateLabel = label;
    });
    _loadData();
  }

  Widget _buildMoreItem(
    BuildContext ctx,
    IconData icon,
    String label,
    VoidCallback onTap,
  ) {
    final theme = Theme.of(ctx);
    final isDark = theme.brightness == Brightness.dark;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceVariant.withOpacity(0.5),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: isDark ? AppTheme.darkBorder : AppTheme.lightBorder,
              ),
            ),
            child: Icon(icon, color: theme.colorScheme.primary, size: 22),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurface.withOpacity(0.6),
              fontSize: 10,
              fontWeight: FontWeight.w500,
            ),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildVoiceButton() {
    if (_isListening || _isAiThinking) return const SizedBox.shrink();

    return GestureDetector(
      onTap: _toggleListening,
      child: Container(
        width: 64,
        height: 64,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: const LinearGradient(
            colors: [AppTheme.primary, AppTheme.accent],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          boxShadow: [
            BoxShadow(
              color: AppTheme.primary.withOpacity(0.3),
              blurRadius: 15,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: const Icon(Icons.mic_rounded, color: Colors.white, size: 30),
      ),
    );
  }

  Widget _buildVoiceOverlay(ThemeData theme) {
    return BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
      child: Container(
        color: Colors.black.withOpacity(0.6),
        width: double.infinity,
        height: double.infinity,
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Close button
            Positioned(
              top: 40,
              right: 20,
              child: IconButton(
                icon: const Icon(
                  Icons.close_rounded,
                  color: Colors.white,
                  size: 32,
                ),
                onPressed: () {
                  _voiceService.stopListening();
                  setState(() {
                    _isListening = false;
                    _isAiThinking = false;
                  });
                },
              ),
            ),
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Stack(
                  alignment: Alignment.center,
                  children: [
                    // Outer pulsing ring
                    AnimatedBuilder(
                      animation: _pulseController,
                      builder: (context, child) {
                        return Container(
                          width: 140 + (60 * _pulseController.value),
                          height: 140 + (60 * _pulseController.value),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: AppTheme.accent.withOpacity(
                                1 - _pulseController.value,
                              ),
                              width: 3,
                            ),
                          ),
                        );
                      },
                    ),
                    // Inner orbiting ring
                    RotationTransition(
                      turns: _orbitController,
                      child: Container(
                        width: 110,
                        height: 110,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: Colors.white.withOpacity(0.2),
                            width: 1,
                          ),
                        ),
                        child: Align(
                          alignment: Alignment.topCenter,
                          child: Container(
                            width: 10,
                            height: 10,
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              color: AppTheme.accent,
                            ),
                          ),
                        ),
                      ),
                    ),
                    // Center core
                    Container(
                      width: 90,
                      height: 90,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          colors: [AppTheme.primary, AppTheme.accent],
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: AppTheme.primary,
                            blurRadius: 30,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                      child: Icon(
                        _isAiThinking
                            ? Icons.auto_awesome_rounded
                            : Icons.mic_rounded,
                        color: Colors.white,
                        size: 44,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 60),
                Shimmer.fromColors(
                  baseColor: Colors.white,
                  highlightColor: AppTheme.accent,
                  child: Text(
                    _isAiThinking ? 'AI IS THINKING...' : 'LISTENING...',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 4,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 40),
                  child: Text(
                    _isAiThinking
                        ? 'Expencify is processing your request'
                        : 'Say something like "I spent 500 on dinner"',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.6),
                      fontSize: 14,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _toggleListening() async {
    if (_isListening) {
      await _voiceService.stopListening();
      setState(() => _isListening = false);
    } else {
      setState(() => _isListening = true);
      bool started = await _voiceService.startListening((text) {
        if (text.isNotEmpty) {
          _handleVoiceCommand(text);
        }
      });
      if (!started && mounted) {
        setState(() => _isListening = false);
      }
    }
  }

  void _handleVoiceCommand(String text) async {
    if (_isAiThinking) return;

    setState(() {
      _isListening = false;
      _isAiThinking = true;
    });

    try {
      // Quick attempt to initialize if not ready
      if (!_aiService.isInitialized) {
        await _aiService.init();
      }

      final action = await _aiService.parseIntent(text);
      if (!mounted) return;

      if (action.type == AIActionType.chat) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(action.message ?? 'I didn\'t catch that.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      } else {
        await _executeAIAction(action);
      }
    } finally {
      if (mounted) setState(() => _isAiThinking = false);
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
      // Streamlined Direct Save: If we have amount and category, save immediately
      if (action.amount != null && action.amount! > 0) {
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
            ),
          );

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'Scan: Added ${action.items!.length} items (Total ₹${action.amount!.toStringAsFixed(0)})',
                ),
                backgroundColor: AppTheme.income,
                behavior: SnackBarBehavior.floating,
              ),
            );
          }
        } else {
          // Standard Single Transaction
          context.read<TransactionBloc>().add(AddTransaction(t));

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  '${isFromOcr ? "Scan" : "Voice"}: Added ₹${action.amount!.toStringAsFixed(0)} to ${action.category ?? "Other"}',
                ),
                backgroundColor: AppTheme.primary,
                behavior: SnackBarBehavior.floating,
              ),
            );
          }
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
          ),
        ),
      );
      _loadData();
    } else if (action.type == AIActionType.delete ||
        action.type == AIActionType.update) {
      final transactions = await transactionRepo.getTransactions(
        limit: 20,
        accountId: selectedId,
      );

      TransactionModel? target;
      if (action.category != null && action.category!.isNotEmpty) {
        final query = action.category!.toLowerCase();
        target = transactions.firstWhereOrNull(
          (t) =>
              t.category.toLowerCase().contains(query) ||
              t.merchant.toLowerCase().contains(query),
        );
      } else {
        target = transactions.firstOrNull;
      }

      if (target == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Could not find a matching transaction to modify.'),
            ),
          );
        }
        return;
      }

      _showActionConfirmation(action, target);
    }
  }

  Future<void> _handleScan() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'SCAN RECEIPT',
              style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1.2),
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildScanOption(
                  ctx,
                  Icons.camera_alt_rounded,
                  'Camera',
                  ImageSource.camera,
                ),
                _buildScanOption(
                  ctx,
                  Icons.photo_library_rounded,
                  'Gallery',
                  ImageSource.gallery,
                ),
              ],
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );

    if (source == null) return;

    setState(() => _isAiThinking = true); // Using existing thinking overlay

    try {
      final text = await _ocrService.pickAndRecognizeText(source);
      if (text == null || text.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No text found on receipt.')),
          );
        }
        return;
      }

      final action = await _aiService.parseIntent(text);
      if (mounted) {
        await _executeAIAction(action, isFromOcr: true);
      }
    } finally {
      if (mounted) setState(() => _isAiThinking = false);
    }
  }

  Widget _buildScanOption(
    BuildContext ctx,
    IconData icon,
    String label,
    ImageSource source,
  ) {
    return InkWell(
      onTap: () => Navigator.pop(ctx, source),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        width: 100,
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Icon(icon, size: 32, color: AppTheme.primary),
            const SizedBox(height: 8),
            Text(label, style: const TextStyle(fontWeight: FontWeight.w500)),
          ],
        ),
      ),
    );
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
                          ? Icons.delete_forever_rounded
                          : Icons.edit_note_rounded,
                      color: isDelete ? Colors.red : Colors.blue,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        '${t.merchant.isNotEmpty ? t.merchant : t.category}: ₹${t.amount}\nDate: ${DateFormat('MMM d').format(t.date)}',
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

    return Container(
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
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
                prefixIcon: const Icon(Icons.search_rounded),
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
                      isAll
                          ? Icons.all_inclusive
                          : Icons.account_balance_rounded,
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
                      ? Icon(Icons.check_circle_rounded, color: cs.primary)
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
