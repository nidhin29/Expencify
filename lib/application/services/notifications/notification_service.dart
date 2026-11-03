import 'reminder_plan.dart';
import 'reminder_maintenance.dart';
import 'dart:io';
import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import '../../../infrastructure/database/database_helper.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

class NotificationService {
  static final NotificationService _instance = NotificationService._();
  factory NotificationService() => _instance;
  NotificationService._()
    : _helper = DatabaseHelper(),
      _clock = DateTime.now,
      _timeZone = null;
  NotificationService.withDependencies({
    required FlutterLocalNotificationsPlugin plugin,
    required DatabaseHelper helper,
    required DateTime Function() clock,
    Future<String> Function()? timeZone,
  }) : _pluginOverride = plugin,
       _helper = helper,
       _clock = clock,
       _timeZone = timeZone;
  final DatabaseHelper _helper;
  final DateTime Function() _clock;
  final Future<String> Function()? _timeZone;
  FlutterLocalNotificationsPlugin? _pluginOverride;
  Future<void> _scheduling = Future<void>.value();

  final FlutterLocalNotificationsPlugin _defaultPlugin =
      FlutterLocalNotificationsPlugin();
  FlutterLocalNotificationsPlugin get _plugin =>
      _pluginOverride ?? _defaultPlugin;

  bool _initialized = false;
  Future<void>? _initializing;
  void Function(String payload)? onTap;
  String? pendingPayload;

  Future<bool> canShowNotification(String channelId) async {
    await init();
    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    if (android == null) return true;
    if (await android.areNotificationsEnabled() == false) return false;
    final channels = await android.getNotificationChannels();
    final channel = channels?.where((c) => c.id == channelId).firstOrNull;
    return channel?.importance != Importance.none;
  }

  Future<void> cancelAll() async {
    await init();
    await _plugin.cancelAll();
  }

  Future<void> rescheduleAll() => _reconcile();

  Future<void> _reconcile({ReminderRecord? override, String? excludedKey}) {
    final work = _scheduling.catchError((Object _) {}).then((_) async {
      await init();
      final now = _clock();
      final db = await _helper.database;
      var anyRecords = false;
      Object? failure;
      // Serializes foreground edits and headless maintenance across isolates.
      // The notification plugin uses its own storage, not this transaction.
      await db.transaction((txn) async {
        final records = <ReminderRecord>[];
        void load(List<Map<String, Object?>> rows, ReminderKind kind) {
          for (final row in rows) {
            try {
              records.add(switch (kind) {
                ReminderKind.payment => ReminderRecord(
                  kind: kind,
                  id: row['id'] as int,
                  name: row['title'] as String,
                  amount: (row['amount'] as num).toDouble(),
                  due: DateTime.parse(row['due_date'] as String),
                  anchor: row['recurrence_anchor'] == null
                      ? null
                      : DateTime.parse(row['recurrence_anchor'] as String),
                  frequency: row['is_recurring'] == 1
                      ? row['frequency'] as String?
                      : null,
                ),
                ReminderKind.subscription => ReminderRecord(
                  kind: kind,
                  id: row['id'] as int,
                  name: row['name'] as String,
                  amount: (row['amount'] as num).toDouble(),
                  due: DateTime.parse(row['next_due_date'] as String),
                  frequency: row['frequency'] as String?,
                ),
                ReminderKind.appliance => ReminderRecord(
                  kind: kind,
                  id: row['id'] as int,
                  name: row['name'] as String,
                  brand: row['brand'] as String,
                  due: DateTime.parse(row['amc_expiry_date'] as String),
                ),
              });
            } catch (error) {
              failure ??= error;
            }
          }
        }

        load(await txn.query('reminders'), ReminderKind.payment);
        load(
          await txn.query('subscriptions', where: 'is_active = 1'),
          ReminderKind.subscription,
        );
        load(await txn.query('appliances'), ReminderKind.appliance);
        records.removeWhere((r) => r.key == excludedKey);
        // Fresh persisted rows win over stale asynchronous save callbacks.
        final catchUpKey =
            override != null && records.any((r) => r.sameSchedule(override))
            ? override.key
            : null;
        final plan = <PlannedReminder>[];
        for (final record in records) {
          try {
            plan.addAll(
              ReminderPlan.forRecord(
                record,
                now,
                catchUp: record.key == catchUpKey,
              ),
            );
          } catch (error) {
            failure ??= error;
          }
        }
        anyRecords = plan.isNotEmpty;
        final pending = await _plugin.pendingNotificationRequests();
        final futureIds = plan.map((p) => p.id).toSet();
        final preserved = <int>{};
        // A newly-created catch-up alert may still be waiting its five seconds.
        // Renewal must neither cancel it nor keep postponing it by five seconds.
        for (final record in records) {
          try {
            final candidate = ReminderPlan.forRecord(
              record,
              now,
              catchUp: true,
            ).firstOrNull;
            if (candidate != null &&
                !futureIds.contains(candidate.id) &&
                pending.any(
                  (p) =>
                      p.id == candidate.id &&
                      p.title == candidate.title &&
                      p.body == candidate.body,
                )) {
              plan.add(candidate);
              preserved.add(candidate.id);
            }
          } catch (_) {
            /* Invalid records are already reported above. */
          }
        }
        plan.sort((a, b) {
          final time = a.at.compareTo(b.at);
          return time != 0 ? time : a.id.compareTo(b.id);
        });
        // Samsung limits per-app alarms; iOS has a smaller pending queue. Keep
        // the nearest alerts across all records, then refill in the background.
        final selected = plan.take(Platform.isIOS ? 60 : 400).toList();
        final wanted = selected.map((p) => p.id).toSet();
        for (final item in pending) {
          if (ReminderPlan.managed(item.id) && !wanted.contains(item.id)) {
            await _plugin.cancel(item.id);
          }
        }
        final android = _plugin
            .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin
            >();
        final precise = await android?.canScheduleExactNotifications() == true;
        for (final item in selected) {
          if (preserved.contains(item.id)) continue;
          try {
            await _schedulePlanned(item, precise);
          } catch (error) {
            failure ??= error;
          }
        }
      });
      await ReminderMaintenance.configure(anyRecords);
      if (failure != null) {
        throw StateError(
          'Some reminders could not be scheduled; background renewal will retry.',
        );
      }
    });
    _scheduling = work;
    return work;
  }

  Future<void> _schedulePlanned(PlannedReminder item, bool precise) async {
    Future<void> schedule(AndroidScheduleMode mode) => _plugin.zonedSchedule(
      item.id,
      item.title,
      item.body,
      tz.TZDateTime.from(item.at, tz.local),
      NotificationDetails(
        android: AndroidNotificationDetails(
          item.channel,
          item.channel,
          importance: Importance.high,
          priority: Priority.high,
          visibility: NotificationVisibility.private,
        ),
        iOS: const DarwinNotificationDetails(),
      ),
      androidScheduleMode: mode,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      payload: item.channel,
    );
    try {
      await schedule(
        precise
            ? AndroidScheduleMode.exactAllowWhileIdle
            : AndroidScheduleMode.inexactAllowWhileIdle,
      );
    } on PlatformException catch (error) {
      if (!precise || error.code != 'exact_alarms_not_permitted') rethrow;
      await schedule(AndroidScheduleMode.inexactAllowWhileIdle);
    }
  }

  Future<void> _cancelRecord(ReminderKind kind, int id) async {
    await init();
    final db = await _helper.database;
    await db.transaction((_) async {
      for (final notificationId in ReminderPlan.cancellationIds(kind, id)) {
        await _plugin.cancel(notificationId);
      }
    });
    await _reconcile(excludedKey: '${kind.channel}:$id');
  }

  Future<void> requestPermission({bool scheduled = false}) async {
    try {
      await init();
      await _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.requestNotificationsPermission();
      final android = _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      if (scheduled &&
          await android?.areNotificationsEnabled() == true &&
          await android?.canScheduleExactNotifications() == false) {
        await android?.requestExactAlarmsPermission();
      }
      await _plugin
          .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin
          >()
          ?.requestPermissions(alert: true, badge: true, sound: true);
    } catch (_) {
      /* The feature remains usable when notification access is denied. */
    }
  }

  Future<void> init() async {
    if (_initialized) return;
    _initializing ??= _initialize();
    try {
      await _initializing;
    } finally {
      _initializing = null;
    }
  }

  Future<void> _initialize() async {
    // Initialize Timezones for scheduled notifications
    tz.initializeTimeZones();
    final zone = _timeZone == null
        ? (await FlutterTimezone.getLocalTimezone()).identifier
        : await _timeZone();
    tz.setLocalLocation(tz.getLocation(zone));

    const AndroidInitializationSettings androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const DarwinInitializationSettings iosSettings =
        DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        );
    const InitializationSettings settings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );
    await _plugin.initialize(
      settings,
      onDidReceiveNotificationResponse: (NotificationResponse response) {
        final payload = response.payload;
        if (payload != null) {
          if (onTap != null) {
            onTap!(payload);
          } else {
            pendingPayload = payload;
          }
        }
      },
    );

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
              description: 'Alerts near and at your budget limits',
              importance: Importance.max,
              playSound: true,
              enableVibration: true,
            ),
          );
    } catch (e) {
      debugPrint('NotificationService: budgets channel failed: $e');
    }

    final launch = await _plugin.getNotificationAppLaunchDetails();
    if (launch?.didNotificationLaunchApp == true) {
      pendingPayload = launch?.notificationResponse?.payload;
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
      channelId == 'budget_updates'
          ? 'Daily budget updates'
          : channelId == 'budgets'
          ? 'Budget Alerts'
          : (channelId == 'subscriptions'
                ? 'Subscription Alerts'
                : 'General Alerts'),
      importance: channelId == 'budget_updates'
          ? Importance.defaultImportance
          : Importance.max,
      priority: channelId == 'budget_updates'
          ? Priority.defaultPriority
          : Priority.high,
      styleInformation: BigTextStyleInformation(body),
      visibility: NotificationVisibility.private,
      color: color,
    );

    final details = NotificationDetails(
      android: androidDetails,
      iOS: const DarwinNotificationDetails(),
    );

    await _plugin.show(id, title, body, details, payload: payload);
  }

  Future<void> scheduleReminder({
    required int id,
    required String title,
    required double amount,
    required DateTime dueDate,
    String? frequency,
    DateTime? recurrenceAnchor,
  }) {
    final record = ReminderRecord(
      kind: ReminderKind.payment,
      id: id,
      name: title,
      amount: amount,
      due: dueDate,
      frequency: frequency,
      anchor: recurrenceAnchor,
    );
    return _reconcile(override: record);
  }

  Future<void> cancelReminder(int id) =>
      _cancelRecord(ReminderKind.payment, id);

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
  }) {
    final record = ReminderRecord(
      kind: ReminderKind.appliance,
      id: id,
      name: name,
      brand: brand,
      due: amcExpiryDate,
    );
    return _reconcile(override: record);
  }

  Future<void> cancelApplianceAMC(int id) =>
      _cancelRecord(ReminderKind.appliance, id);

  Future<void> scheduleSubscriptionReminder({
    required int id,
    required String name,
    required double amount,
    required DateTime nextDueDate,
    String frequency = 'monthly',
  }) {
    final record = ReminderRecord(
      kind: ReminderKind.subscription,
      id: id,
      name: name,
      amount: amount,
      due: nextDueDate,
      frequency: frequency,
    );
    return _reconcile(override: record);
  }

  Future<void> cancelSubscriptionReminder(int id) =>
      _cancelRecord(ReminderKind.subscription, id);
}
