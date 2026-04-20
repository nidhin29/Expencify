import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'infrastructure/database/database_helper.dart';
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
import 'presentation/screens/security/lock_screen.dart';
import 'application/services/auth/auth_service.dart';
import 'application/services/notifications/notification_service.dart';
import 'application/services/sms/sms_monitor_service.dart';
import 'application/services/security/security_service.dart';
import 'application/services/notifications/budget_alert_service.dart';
import 'presentation/screens/auth/splash_screen.dart';
import 'presentation/screens/home/home_screen.dart' show homeRouteObserver;
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:upgrader/upgrader.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize port for isolate communication
  FlutterForegroundTask.initCommunicationPort();

  // Initialize Database
  final dbHelper = DatabaseHelper();
  await dbHelper.database;

  // Initialize Notification Service
  await NotificationService().init();

  // Start background SMS monitoring (asynchronous - doesn't block startup)
  try {
    SmsMonitorService().startBackgroundListening();
  } catch (e) {
    debugPrint('>>> [main] SmsMonitorService failed: $e');
  }

  final authService = AuthService();
  final securityService = SecurityService();
  await securityService.init();

  // SplashScreen handles onboarding/login checks
  const initialScreen = SplashScreen();

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
    WithForegroundTask(
      child: MultiRepositoryProvider(
        providers: [
          RepositoryProvider.value(value: dbHelper),
          RepositoryProvider.value(value: authService),
          RepositoryProvider.value(value: securityService),
          RepositoryProvider<AccountRepository>.value(value: accountRepo),
          RepositoryProvider<TransactionRepository>.value(
            value: transactionRepo,
          ),
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
    ),
  );
}

class ExpencifyApp extends StatefulWidget {
  final Widget initialScreen;
  const ExpencifyApp({super.key, required this.initialScreen});

  @override
  State<ExpencifyApp> createState() => _ExpencifyAppState();
}

class _ExpencifyAppState extends State<ExpencifyApp> {
  final _security = SecurityService();

  @override
  void initState() {
    super.initState();
    _security.addListener(_update);
  }

  @override
  void dispose() {
    _security.removeListener(_update);
    super.dispose();
  }

  void _update() => setState(() {});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Expencify',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: ThemeMode.light,
      navigatorObservers: [homeRouteObserver],
      builder: (context, child) {
        return Stack(
          children: [
            if (child != null) child,
            if (_security.isLocked)
              LockScreen(onUnlocked: () => _security.unlock()),
          ],
        );
      },
      home: UpgradeAlert(
        showIgnore: false,
        showLater: false,
        dialogStyle: UpgradeDialogStyle.cupertino,
        child: widget.initialScreen,
      ),
    );
  }
}
