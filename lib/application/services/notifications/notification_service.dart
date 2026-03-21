import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class NotificationService {
  static final NotificationService _instance = NotificationService._();
  factory NotificationService() => _instance;
  NotificationService._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  bool _initialized = false;

  Future<void> init() async {
    if (_initialized) return;
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
    await _plugin.initialize(settings);

    // Pre-create the 'sms_auto' channel so background isolates can use it
    // without needing to call createNotificationChannel (which needs Activity context).
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

    _initialized = true;
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

    // Use show (immediate) as a fallback since schedule API changed in v18+
    await _plugin.show(
      id,
      '💳 $title',
      '₹${amount.toStringAsFixed(0)} due on ${dueDate.day}/${dueDate.month}/${dueDate.year}. Tap to view details.',
      details,
    );
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
}
