import 'application/services/security/receipt_store.dart';
import 'application/services/security/private_file_cleanup.dart';
import 'package:flutter/services.dart';
import 'presentation/screens/reports/weekly_recap_screen.dart';
import 'application/services/notifications/weekly_recap_notification.dart';
import 'application/services/notifications/budget_update_scheduler.dart';
import 'application/services/notifications/budget_update_service.dart';
import 'application/services/performance/performance_probe.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';
import 'presentation/screens/reminders/reminders_screen.dart';
import 'presentation/screens/budgets/budgets_screen.dart';
import 'presentation/screens/subscriptions/subscriptions_screen.dart';
import 'presentation/screens/appliances/appliances_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'infrastructure/database/database_helper.dart';
import 'infrastructure/database/live_database_store.dart';
import 'infrastructure/repositories/sqlite_account_repository.dart';
import 'infrastructure/repositories/sqlite_transaction_repository.dart';
import 'infrastructure/repositories/sqlite_budget_repository.dart';
import 'infrastructure/repositories/sqlite_goal_repository.dart';
import 'infrastructure/repositories/sqlite_reminder_repository.dart';
import 'infrastructure/repositories/sqlite_category_repository.dart';
import 'infrastructure/repositories/sqlite_appliance_repository.dart';
import 'infrastructure/repositories/sqlite_registered_entity_repository.dart';
import 'infrastructure/repositories/sqlite_subscription_repository.dart';
import 'domain/repositories/account_repository.dart';
import 'domain/repositories/transaction_repository.dart';
import 'domain/repositories/budget_repository.dart';
import 'domain/repositories/goal_repository.dart';
import 'domain/repositories/reminder_repository.dart';
import 'domain/repositories/category_repository.dart';
import 'domain/repositories/appliance_repository.dart';
import 'domain/repositories/registered_entity_repository.dart';
import 'domain/repositories/subscription_repository.dart';
import 'application/blocs/account/account_bloc.dart';
import 'application/blocs/account/account_event.dart';
import 'application/blocs/transaction/transaction_bloc.dart';
import 'application/blocs/budget/budget_bloc.dart';
import 'application/blocs/goal/goal_bloc.dart';
import 'application/blocs/reminder/reminder_bloc.dart';
import 'application/blocs/category/category_bloc.dart';
import 'application/blocs/appliance/appliance_bloc.dart';
import 'application/blocs/registered_entity/registered_entity_bloc.dart';
import 'application/blocs/registered_entity/registered_entity_event.dart';
import 'application/blocs/subscription/subscription_bloc.dart';
import 'application/blocs/subscription/subscription_event.dart';
import 'presentation/theme/app_theme.dart';
// Screens are now routed via SplashScreen
import 'presentation/widgets/app_lock_gate.dart';
import 'application/services/auth/auth_service.dart';
import 'application/services/notifications/notification_service.dart';
import 'application/services/sms/sms_monitor_service.dart';
import 'application/services/security/security_service.dart';
import 'application/services/notifications/budget_alert_service.dart';
import 'presentation/screens/auth/splash_screen.dart';
import 'presentation/screens/home/home_screen.dart' show homeRouteObserver;
import 'presentation/widgets/mandatory_update_gate.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  PerformanceProbe.install();
  final startupReady = Completer<void>();
  // Reparent the same splash into the initialized app without replaying it.
  final splash = SplashScreen(
    key: GlobalKey(),
    ready: startupReady.future,
    firstFrame: WidgetsBinding.instance.waitUntilFirstFrameRasterized,
  );
  runApp(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      home: splash,
    ),
  );
  // Paint before secure storage, database keying and migration start.
  await WidgetsBinding.instance.endOfFrame;
  await WidgetsBinding.instance.waitUntilFirstFrameRasterized;
  await _startApplication(splash, startupReady);
}

Future<void> _startApplication(
  SplashScreen initialScreen,
  Completer<void> startupReady,
) async {
  // Initialize Database
  final dbHelper = DatabaseHelper();
  try {
    final db = await dbHelper.database;
    await ReceiptStore().migrate(db);
    try {
      await const MethodChannel(
        'com.example.expencify/native_sms',
      ).invokeMethod<int>('securePendingSms');
    } on MissingPluginException {
      /* Non-Android platform. */
    }
    await const PrivateFileCleanup().sweep(startup: true);
  } catch (e) {
    runApp(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  e is ReceiptSecurityException
                      ? e.message
                      : e is DatabaseEncryptionException
                      ? e.message
                      : 'Your data could not be opened. It has not been erased.',
                ),
                const SizedBox(height: 16),
                FilledButton(onPressed: main, child: const Text('Retry')),
              ],
            ),
          ),
        ),
      ),
    );
    return;
  }

  final authService = AuthService();
  final securityService = SecurityService();
  try {
    await securityService.init();
  } catch (e) {
    runApp(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Secure storage is unavailable. Unlock your device and retry.',
                ),
                FilledButton(onPressed: main, child: const Text('Retry')),
              ],
            ),
          ),
        ),
      ),
    );
    return;
  }
  // Define Repositories
  final accountRepo = SqliteAccountRepository(dbHelper);
  final transactionRepo = SqliteTransactionRepository(dbHelper);
  final budgetRepo = SqliteBudgetRepository(dbHelper);
  final goalRepo = SqliteGoalRepository(dbHelper);
  final reminderRepo = SqliteReminderRepository(dbHelper);
  final categoryRepo = SqliteCategoryRepository(dbHelper);
  final applianceRepo = SqliteApplianceRepository(dbHelper);
  final registeredRepo = SqliteRegisteredEntityRepository();
  final subscriptionRepo = SqliteSubscriptionRepository(dbHelper);

  runApp(
    MultiRepositoryProvider(
      providers: [
        RepositoryProvider.value(value: dbHelper),
        RepositoryProvider.value(value: authService),
        RepositoryProvider<AccountRepository>.value(value: accountRepo),
        RepositoryProvider<TransactionRepository>.value(value: transactionRepo),
        RepositoryProvider<BudgetRepository>.value(value: budgetRepo),
        RepositoryProvider<GoalRepository>.value(value: goalRepo),
        RepositoryProvider<ReminderRepository>.value(value: reminderRepo),
        RepositoryProvider<CategoryRepository>.value(value: categoryRepo),
        RepositoryProvider<RegisteredEntityRepository>.value(
          value: registeredRepo,
        ),
        RepositoryProvider.value(value: NotificationService()),
        RepositoryProvider<ApplianceRepository>.value(value: applianceRepo),
        RepositoryProvider<SubscriptionRepository>.value(
          value: subscriptionRepo,
        ),
      ],
      child: MultiBlocProvider(
        providers: [
          BlocProvider(
            create: (_) => AccountBloc(accountRepo)..add(LoadAccounts()),
          ),
          BlocProvider(
            create: (ctx) {
              final budgetAlerts = BudgetAlertService(
                transactionRepo,
                budgetRepo,
                ctx.read<NotificationService>(),
              );
              return TransactionBloc(
                transactionRepo,
                accountRepo,
                ctx.read<AccountBloc>(),
                budgetAlerts: budgetAlerts,
              );
            },
          ),
          BlocProvider(create: (_) => BudgetBloc(budgetRepo)),
          BlocProvider(create: (_) => GoalBloc(goalRepo)),
          BlocProvider(
            create: (context) => ReminderBloc(
              context.read<ReminderRepository>(),
              context.read<NotificationService>(),
            ),
          ),
          BlocProvider(create: (_) => CategoryBloc(categoryRepo)),
          BlocProvider(create: (_) => ApplianceBloc(applianceRepo)),
          BlocProvider(
            create: (_) =>
                RegisteredEntityBloc(registeredRepo)
                  ..add(LoadRegisteredEntities()),
          ),
          BlocProvider(
            create: (context) => SubscriptionBloc(
              subscriptionRepo,
              context.read<NotificationService>(),
            )..add(LoadSubscriptions()),
          ),
        ],
        child: ExpencifyApp(initialScreen: initialScreen),
      ),
    ),
  );
  await WidgetsBinding.instance.endOfFrame;
  PerformanceProbe.mark('app.core_ready');
  startupReady.complete();
  unawaited(_startOptionalServices());
}

Future<void> _startOptionalServices() async {
  // Register budget work independently of SMS startup. Reminder reconciliation
  // preserves unrelated notifications and their native delivery alarms.
  final notificationSetup = NotificationService().rescheduleAll().catchError((
    Object e,
  ) {
    debugPrint('Notification scheduling will retry: $e');
  });
  await Future.wait([
    notificationSetup,
    SmsMonitorService().startBackgroundListening().catchError((Object e) {
      debugPrint('SMS startup failed: $e');
    }),
    () async {
      try {
        await BudgetUpdateScheduler.configure();
        await notificationSetup;
        await executeBudgetUpdate(
          daily: () => BudgetUpdateService().run(),
          weekly: () => WeeklyRecapNotification().run(),
          rearm: () async {},
        );
      } catch (e) {
        debugPrint('Budget updates will retry: ${e.runtimeType}');
      }
    }(),
  ]);
}

class ExpencifyApp extends StatefulWidget {
  final Widget initialScreen;
  const ExpencifyApp({super.key, required this.initialScreen});

  @override
  State<ExpencifyApp> createState() => _ExpencifyAppState();
}

class _ExpencifyAppState extends State<ExpencifyApp>
    with WidgetsBindingObserver {
  Timer? _fileCleanupTimer;
  void _sweepFiles() {
    unawaited(const PrivateFileCleanup().sweep().catchError((Object _) {}));
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _fileCleanupTimer?.cancel();
    if (state == AppLifecycleState.resumed) {
      _sweepFiles();
      _fileCleanupTimer = Timer.periodic(
        const Duration(minutes: 15),
        (_) => _sweepFiles(),
      );
    }
  }

  final _security = SecurityService();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _fileCleanupTimer = Timer.periodic(
      const Duration(minutes: 15),
      (_) => _sweepFiles(),
    );
    _security.addListener(_update);
    NotificationService().onTap = _openNotification;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _fileCleanupTimer?.cancel();
    NotificationService().onTap = null;
    _security.removeListener(_update);
    super.dispose();
  }

  void _update() {
    setState(() {});
    if (!_security.isLocked) _drainNotification();
  }

  void _drainNotification() {
    final pending = NotificationService().pendingPayload;
    if (pending == null) return;
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _openNotification(pending),
    );
  }

  void _openNotification(String payload) async {
    // Navigation waits for onboarding and the lock overlay to finish.
    if (!mounted || _security.isLocked || _security.isSplashActive) {
      NotificationService().pendingPayload = payload;
      return;
    }
    final onboarded = await AuthService().isOnboarded();
    final prefs = await SharedPreferences.getInstance();
    if (!mounted ||
        !onboarded ||
        prefs.getBool('legal_terms_accepted') != true ||
        _security.isLocked) {
      NotificationService().pendingPayload = payload;
      return;
    }
    final screen = switch (payload) {
      'reminders' => const RemindersScreen(),
      'budgets' => const BudgetScreen(),
      'weekly_recap' => const WeeklyRecapScreen(),
      'subscriptions' => const SubscriptionsScreen(),
      'appliances' => const AppliancesScreen(),
      _ => null,
    };
    if (screen != null) {
      NotificationService().pendingPayload = null;
      navigatorKey.currentState?.push(
        MaterialPageRoute(builder: (_) => screen),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      title: 'Spendy',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: ThemeMode.light,
      navigatorObservers: [homeRouteObserver],
      builder: (context, child) {
        return MandatoryUpdateGate(
          child: AppLockGate(
            security: _security,
            child: child ?? const SizedBox.shrink(),
          ),
        );
      },
      home: widget.initialScreen,
    );
  }
}
