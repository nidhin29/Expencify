import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

class NotificationService {
  static final NotificationService _instance = NotificationService._();
  factory NotificationService() => _instance;
  NotificationService._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  bool _initialized = false;

  Future<void> init() async {
    if (_initialized) return;

    // Initialize Timezones for scheduled notifications
    tz.initializeTimeZones();
    tz.setLocalLocation(tz.getLocation('Asia/Kolkata'));

    const AndroidInitializationSettings androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const DarwinInitializationSettings iosSettings =
        DarwinInitializationSettings(
          requestAlertPermission: true,
          requestBadgePermission: true,
          requestSoundPermission: true,
        );
    const InitializationSettings settings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );
    await _plugin.initialize(
      settings,
      onDidReceiveNotificationResponse: (NotificationResponse response) {
        debugPrint('🔔 Notification Clicked: ${response.payload}');
      },
    );

    // Request Android 13+ Notification Permissions
    try {
      await _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.requestNotificationsPermission();
    } catch (_) {}

    // Request Android 12+ Exact Alarm Permission
    try {
      await _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.requestExactAlarmsPermission();
    } catch (_) {}

    // Pre-create the 'sms_auto' channel so background isolates can use it
    // without needing to call createNotificationChannel (which needs Activity context).
    try {
      await _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.createNotificationChannel(
            const AndroidNotificationChannel(
              'sms_auto',
              'Auto Transactions',
              description: 'Auto-detected bank SMS transactions',
              importance: Importance.high,
              playSound: true,
              enableVibration: true,
            ),
          );
    } catch (e) {
      debugPrint(
        'NotificationService: createNotificationChannel failed (BG isolate): $e',
      );
    }
    try {
      await _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.createNotificationChannel(
            const AndroidNotificationChannel(
              'appliances',
              'Appliance Reminders',
              description: 'AMC renewal alerts',
              importance: Importance.high,
              playSound: true,
              enableVibration: true,
            ),
          );
    } catch (e) {
      debugPrint('NotificationService: appliances channel failed: $e');
    }

    try {
      await _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.createNotificationChannel(
            const AndroidNotificationChannel(
              'reminders',
              'Bill Reminders',
              description: 'Upcoming bill & EMI reminders',
              importance: Importance.max,
              playSound: true,
              enableVibration: true,
            ),
          );
    } catch (e) {
      debugPrint('NotificationService: reminders channel failed: $e');
    }

    try {
      await _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.createNotificationChannel(
            const AndroidNotificationChannel(
              'subscriptions',
              'Subscription Alerts',
              description: 'Upcoming renewal reminders',
              importance: Importance.max,
              playSound: true,
              enableVibration: true,
            ),
          );
    } catch (e) {
      debugPrint('NotificationService: subscriptions channel failed: $e');
    }

    try {
      await _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.createNotificationChannel(
            const AndroidNotificationChannel(
              'budgets',
              'Budget Alerts',
              description: 'Alerts for budget limits (50%, 80%, 100%)',
              importance: Importance.max,
              playSound: true,
              enableVibration: true,
            ),
          );
    } catch (e) {
      debugPrint('NotificationService: budgets channel failed: $e');
    }

    _initialized = true;
  }

  /// Shows an immediate notification on the specified channel.
  Future<void> showNotification({
    required int id,
    required String channelId,
    required String title,
    required String body,
    String? payload,
    Color? color,
  }) async {
    await init();
    
    final androidDetails = AndroidNotificationDetails(
      channelId,
      channelId == 'budgets' ? 'Budget Alerts' : (channelId == 'subscriptions' ? 'Subscription Alerts' : 'General Alerts'),
      importance: Importance.max,
      priority: Priority.high,
      color: color,
    );
    
    final details = NotificationDetails(android: androidDetails);
    
    await _plugin.show(id, title, body, details, payload: payload);
  }

  Future<void> scheduleReminder({
    required int id,
    required String title,
    required double amount,
    required DateTime dueDate,
  }) async {
    await init();
    // Notify 1 day before due
    final notify = dueDate.subtract(const Duration(days: 1));
    if (notify.isBefore(DateTime.now())) return;

    const AndroidNotificationDetails androidDetails =
        AndroidNotificationDetails(
          'reminders',
          'Bill Reminders',
          channelDescription: 'Upcoming bill & EMI reminders',
          importance: Importance.high,
          priority: Priority.high,
          color: Color(0xFF6366F1), // Matches AppTheme.primary
          styleInformation: BigTextStyleInformation(
            '',
            contentTitle: '💳 Payment Due: Tomorrow',
            summaryText: 'Bill Alert',
          ),
          actions: <AndroidNotificationAction>[
            AndroidNotificationAction(
              'mark_paid',
              'Mark as Paid',
              showsUserInterface: true,
              cancelNotification: true,
            ),
          ],
        );
    const NotificationDetails details = NotificationDetails(
      android: androidDetails,
    );

    // Schedule future dated notification
    try {
      await _plugin.zonedSchedule(
        id,
        '💳 $title',
        '₹${amount.toStringAsFixed(0)} due on ${dueDate.day}/${dueDate.month}/${dueDate.year}. Tap to view details.',
        tz.TZDateTime.from(notify, tz.local),
        details,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        payload: 'reminders',
      );
      debugPrint('🔔 Reminder scheduled successfully for $notify (ID: $id)');
    } catch (e) {
      debugPrint('🔔 NotificationService scheduleReminder FAILED: $e');
    }
  }

  Future<void> cancelReminder(int id) async {
    await init();
    await _plugin.cancel(id);
  }

  Future<void> showInstant({
    required String title,
    required String body,
  }) async {
    await init();
    const AndroidNotificationDetails androidDetails =
        AndroidNotificationDetails(
          'sms_auto',
          'Auto Transactions',
          channelDescription: 'Auto-detected bank SMS transactions',
          importance: Importance.max,
          priority: Priority.high,
        );
    const NotificationDetails details = NotificationDetails(
      android: androidDetails,
    );
    await _plugin.show(0, title, body, details);
  }

  Future<void> scheduleApplianceAMC({
    required int id,
    required String name,
    required String brand,
    required DateTime amcExpiryDate,
  }) async {
    await init();
    // Notify 7 days before EXP
    final notify = amcExpiryDate.subtract(const Duration(days: 7));
    if (notify.isBefore(DateTime.now())) return;

    const AndroidNotificationDetails androidDetails =
        AndroidNotificationDetails(
          'appliances',
          'Appliance Reminders',
          channelDescription: 'AMC renewal alerts',
          importance: Importance.high,
          priority: Priority.high,
          color: Color(0xFF10B981),
        );
    const NotificationDetails details = NotificationDetails(
      android: androidDetails,
    );

    try {
      await _plugin.zonedSchedule(
        1000 + id, // Unique offset range outside reminders
        '🛠️ AMC Renew: $name',
        'The AMC for your $brand appliance expires on ${amcExpiryDate.day}/${amcExpiryDate.month}.',
        tz.TZDateTime.from(notify, tz.local),
        details,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        payload: 'appliances',
      );
      debugPrint(
        '🔔 Appliance AMC scheduled successfully for $notify (ID: ${1000 + id})',
      );
    } catch (e) {
      debugPrint('🔔 NotificationService scheduleApplianceAMC FAILED: $e');
    }
  }

  Future<void> cancelApplianceAMC(int id) async {
    await init();
    await _plugin.cancel(1000 + id);
  }

  Future<void> scheduleSubscriptionReminder({
    required int id,
    required String name,
    required double amount,
    required DateTime nextDueDate,
  }) async {
    await init();
    // Notify 2 days before due
    final notify = nextDueDate.subtract(const Duration(days: 2));
    if (notify.isBefore(DateTime.now())) return;

    const AndroidNotificationDetails androidDetails =
        AndroidNotificationDetails(
          'subscriptions',
          'Subscription Alerts',
          channelDescription: 'Upcoming renewal reminders',
          importance: Importance.high,
          priority: Priority.high,
          color: Color(0xFFEC4899),
          styleInformation: BigTextStyleInformation(
            '',
            contentTitle: '🔄 Renewal Insight',
          ),
        );
    const NotificationDetails details = NotificationDetails(
      android: androidDetails,
    );

    try {
      await _plugin.zonedSchedule(
        2000 + id, // Unique offset for subscriptions
        '🔄 Renewal Soon: $name',
        'Your subscription for $name (₹${amount.toStringAsFixed(0)}) will renew in 2 days.',
        tz.TZDateTime.from(notify, tz.local),
        details,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        payload: 'subscriptions',
      );
      debugPrint('🔔 Subscription reminder scheduled for $notify (ID: ${2000 + id})');
    } catch (e) {
      debugPrint('🔔 NotificationService scheduleSubscriptionReminder FAILED: $e');
    }
  }

  Future<void> cancelSubscriptionReminder(int id) async {
    await init();
    await _plugin.cancel(2000 + id);
  }
}
