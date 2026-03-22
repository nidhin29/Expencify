import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:telephony/telephony.dart';
import '../sms/sms_parser_service.dart';
import '../sms/background_sms_handler.dart';

class SmsMonitorService {
  static final SmsMonitorService _instance = SmsMonitorService._();
  factory SmsMonitorService() => _instance;
  SmsMonitorService._() {
    _initNativeSmsChannel();
  }

  void _initNativeSmsChannel() {
    const channel = MethodChannel('com.example.expencify/native_sms');
    channel.setMethodCallHandler((call) async {
      if (call.method == 'onSmsReceived') {
        try {
          final data = call.arguments as Map;
          final body = data['body'] as String;
          final ts = data['timestamp'] as int;
          final sender = data['sender'] as String;

          final date = DateTime.fromMillisecondsSinceEpoch(ts);
          debugPrint(
            '>>> [SmsMonitorService] SMS Captured via Main Channel: $sender',
          );
          await processSms(body, date: date);

          // Notify Main isolate UI state streams to reload BLoC
          onSmsProcessed.add(null);
        } catch (e) {
          debugPrint('>>> [SmsMonitorService] Main Channel Error: $e');
        }
      }
      return null;
    });
  }

  final Telephony _telephony = Telephony.instance;

  /// Global broadcast stream for incoming SMS parsed asynchronously inside tasks
  static final StreamController<void> onSmsProcessed =
      StreamController<void>.broadcast();

  /// Request SMS and Notification permissions. Returns true if SMS granted.
  Future<bool> requestPermission() async {
    final Map<Permission, PermissionStatus> statuses = await [
      Permission.sms,
      Permission.notification,
    ].request();
    return statuses[Permission.sms]!.isGranted;
  }

  Future<bool> hasPermission() async => await Permission.sms.isGranted;

  /// Start SMS monitoring.
  /// Step 1: Register the SMS listener (critical — must always succeed)
  /// Step 2: Start the foreground service (best-effort — to keep process alive)
  Future<void> startBackgroundListening() async {
    debugPrint('>>> [SmsMonitorService] Starting...');

    // ── Step 1: Permission check ────────────────────────────────────────────
    bool granted = await Permission.sms.isGranted;
    if (!granted) {
      granted = await requestPermission();
    }
    if (!granted) {
      debugPrint('>>> [SmsMonitorService] SMS permission denied – aborting.');
      return;
    }
    debugPrint('>>> [SmsMonitorService] SMS permission granted');

    // ── Step 1b: Drain any SMS saved while app was CLOSED (SharedPrefs queue) ───
    // The SmsReceiver writes to SharedPrefs instead of launching a 2nd engine.
    // This prevents ANR/Signal 3 crashes.
    unawaited(processPendingSms());

    // ── Step 1c: Startup inbox scan (safety net) ─────────────────────────────
    // Catches any bank SMS that arrived while the foreground service was killed.
    unawaited(_runStartupScan());

    // ── Step 2: Register SMS listener ────────────────────────────────────────
    // MUST happen before starting the foreground service.
    // Only call listenIncomingSms ONCE; a second call overwrites the first.
    try {
      _telephony.listenIncomingSms(
        onNewMessage: (SmsMessage message) {
          debugPrint('>>> [SmsMonitorService] onNewMessage: ${message.body}');
          onBackgroundSmsReceived(message);
        },
        // DO NOT pass onBackgroundMessage — the telephony package is discontinued
        // and its _flutterSmsSetupBackgroundChannel lacks @pragma('vm:entry-point'),
        // causing AOT tree-shaking to remove it, which crashes the background isolate:
        // "Could not closurize _flutterSmsSetupBackgroundChannel from native code"
        // The foreground service keeps our process alive, so onNewMessage is sufficient.
        listenInBackground: false,
      );
      debugPrint('>>> [SmsMonitorService] SMS listener registered ✓');
    } catch (e) {
      debugPrint('>>> [SmsMonitorService] listenIncomingSms failed: $e');
    }

    // ── Step 2b: Setup port callback to receive Isolate events ────────────
    FlutterForegroundTask.addTaskDataCallback((data) {
      if (data is Map && data['type'] == 'sms_parsed') {
        debugPrint('>>> [SmsMonitorService] Isolate reports SMS parsed.');
        onSmsProcessed.add(null); // Trigger UI broadcast
      }
    });
    debugPrint('>>> [SmsMonitorService] Task Data Callback registered ✓');

    // ── Step 3: Foreground service (keeps process alive when app is closed) ──
    // This is best-effort. Even if it fails, the SMS listener above is still
    // registered and will work while the app is open or in the recent apps list.
    try {
      FlutterForegroundTask.init(
        androidNotificationOptions: AndroidNotificationOptions(
          channelId: 'expencify_sms_service',
          channelName: 'SMS Monitor',
          channelDescription: 'Monitoring bank SMS in the background.',
          channelImportance: NotificationChannelImportance.LOW,
          priority: NotificationPriority.LOW,
        ),
        iosNotificationOptions: const IOSNotificationOptions(),
        foregroundTaskOptions: ForegroundTaskOptions(
          eventAction: ForegroundTaskEventAction.repeat(15000),
          autoRunOnBoot: true,
          allowWakeLock: true,
          allowWifiLock: true,
        ),
      );

      if (await FlutterForegroundTask.isRunningService) {
        // Service is already running with its SMS listener — leave it alone!
        // Calling restartService() would destroy the old isolate's listener
        // and the new isolate might not start correctly in the same process.
        debugPrint(
          '>>> [SmsMonitorService] Foreground service already running — leaving it intact ✓',
        );
        // Optionally update the notification text only
        await FlutterForegroundTask.updateService(
          notificationTitle: 'Expencify',
          notificationText: 'Watching for bank transactions...',
        );
      } else {
        await FlutterForegroundTask.startService(
          serviceId: 1001,
          notificationTitle: 'Expencify',
          notificationText: 'Watching for bank transactions...',
          callback: startForegroundSmsService,
        );
      }
      debugPrint('>>> [SmsMonitorService] Foreground service started ✓');
    } catch (e) {
      // Service failed — SMS listener still works while app is open
      debugPrint(
        '>>> [SmsMonitorService] Foreground service failed (non-fatal): $e',
      );
    }
  }

  /// Reads all SMS from inbox and returns only bank/financial ones, parsed.
  Future<List<Map<String, dynamic>>> readBankSmsFromInbox({
    int limit = 100,
  }) async {
    final granted = await requestPermission();
    if (!granted) return [];

    final List<SmsMessage> messages = await _telephony.getInboxSms(
      columns: [SmsColumn.ADDRESS, SmsColumn.BODY, SmsColumn.DATE],
      filter: SmsFilter.where(SmsColumn.DATE).greaterThan(
        DateTime.now()
            .subtract(const Duration(days: 90))
            .millisecondsSinceEpoch
            .toString(),
      ),
      sortOrder: [OrderBy(SmsColumn.DATE, sort: Sort.DESC)],
    );

    final results = <Map<String, dynamic>>[];
    for (final msg in messages.take(limit)) {
      final body = msg.body ?? '';
      if (body.isEmpty) continue;
      final Map<String, dynamic>? data = await SmsParserService.parseSms(body);
      if (data == null) continue;

      final type = data['type'] as String;
      final merchant = (data['merchant'] as String?) ?? '';
      final rulesResult = await SmsParserService.applySmartRules(
        merchant,
        body,
        type,
      );
      final category = rulesResult['category']!;
      final updatedMerchant = rulesResult['merchant']!;
      final dateMs = msg.date ?? DateTime.now().millisecondsSinceEpoch;
      results.add({
        'smsBody': body,
        'sender': msg.address ?? '',
        'amount': data['amount'],
        'type': data['type'],
        'merchant': updatedMerchant,
        'account': data['account'] ?? '',
        'balance': data['balance'],
        'category': category,
        'date': DateTime.fromMillisecondsSinceEpoch(dateMs),
      });
    }
    return results;
  }

  /// On app startup, scan inbox for any bank SMS received after the last scan.
  /// Uses a rolling watermark (stored in SharedPreferences) so that only NEW
  /// messages are processed — this prevents re-adding transactions that the
  /// user intentionally deleted.
  Future<void> _runStartupScan() async {
    debugPrint('>>> [SmsMonitorService] Running startup inbox scan...');
    try {
      final prefs = await SharedPreferences.getInstance();

      // Read the last scan watermark. Default to 24h ago on first run
      // (avoids a 30-day flood on install while still catching missed SMS).
      final lastScanMs =
          prefs.getInt('sms_last_scan_ts') ??
          DateTime.now()
              .subtract(const Duration(hours: 24))
              .millisecondsSinceEpoch;

      debugPrint(
        '>>> [SmsMonitorService] Scanning SMS since ${DateTime.fromMillisecondsSinceEpoch(lastScanMs)}',
      );

      final msgs = await _telephony.getInboxSms(
        columns: [SmsColumn.ADDRESS, SmsColumn.BODY, SmsColumn.DATE],
        filter: SmsFilter.where(
          SmsColumn.DATE,
        ).greaterThan(lastScanMs.toString()),
        sortOrder: [OrderBy(SmsColumn.DATE, sort: Sort.ASC)],
      );

      int found = 0;
      for (final msg in msgs) {
        final body = msg.body ?? '';
        if (body.isEmpty) continue;
        final msgDate = msg.date != null
            ? DateTime.fromMillisecondsSinceEpoch(msg.date!)
            : DateTime.now();
        await processSms(body, date: msgDate, suppressNotification: true);
        found++;
      }

      // Advance the watermark to now so the next scan won't re-process these.
      await prefs.setInt(
        'sms_last_scan_ts',
        DateTime.now().millisecondsSinceEpoch,
      );

      debugPrint(
        '>>> [SmsMonitorService] Startup scan complete — processed $found new messages',
      );
    } catch (e) {
      debugPrint('>>> [SmsMonitorService] Startup scan failed (non-fatal): $e');
    }
  }
}
