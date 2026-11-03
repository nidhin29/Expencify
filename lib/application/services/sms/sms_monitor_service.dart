import 'sms_tracking_preference.dart';
import 'dart:io';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
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
      if (call.method == 'processPendingSms') {
        final complete = await processPendingSms();
        onSmsProcessed.add(null);
        return complete;
      }
      if (call.method == 'onSmsReceived') {
        try {
          final data = call.arguments as Map;
          final body = data['body'] as String;
          final ts = data['timestamp'] as int;
          final sender = data['sender'] as String;

          final date = DateTime.fromMillisecondsSinceEpoch(ts);
          debugPrint('>>> [SmsMonitorService] SMS captured via main channel');
          final success = await processSms(body, date: date, sender: sender);
          onSmsProcessed.add(null);
          return success;
        } catch (e) {
          debugPrint(
            '>>> [SmsMonitorService] Main Channel Error: ${e.runtimeType}',
          );
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

  /// Capture uses native broadcasts; bounded jobs drain the encrypted queue.
  Future<void> startBackgroundListening() async {
    if (kIsWeb || !Platform.isAndroid) return;
    await SmsTrackingPreference.initialize(
      previouslyGranted: await Permission.sms.isGranted,
    );
    if (!await SmsTrackingPreference.isEnabled()) {
      await const MethodChannel(
        'com.example.expencify/native_sms',
      ).invokeMethod<void>('cancelSmsWork');
      return;
    }
    debugPrint('>>> [SmsMonitorService] Starting...');

    // ── Step 1: Permission check ────────────────────────────────────────────
    bool granted = await Permission.sms.isGranted;
    if (!granted) {
      await SmsTrackingPreference.setEnabled(false);
      await const MethodChannel(
        'com.example.expencify/native_sms',
      ).invokeMethod<void>('cancelSmsWork');
      debugPrint(
        '>>> [SmsMonitorService] SMS permission not granted yet – aborting background listener startup.',
      );
      return;
    }
    debugPrint('>>> [SmsMonitorService] SMS permission granted');

    // ── Step 1b: Drain encrypted SMS saved while the app was closed ───
    // The native receiver persists encrypted messages before scheduling work.
    // This prevents ANR/Signal 3 crashes.
    unawaited(
      processPendingSms().catchError((Object e) {
        debugPrint('Pending SMS will retry: ${e.runtimeType}');
        return false;
      }),
    );

    // ── Step 1c: Startup inbox scan (safety net) ─────────────────────────────
    // Recovers messages missed while background delivery was restricted.
    unawaited(_runStartupScan());

    await const MethodChannel(
      'com.example.expencify/native_sms',
    ).invokeMethod<void>('scheduleSmsWork');
  }

  Future<void> stopBackgroundListening() async {
    await SmsTrackingPreference.setEnabled(false);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('sms_setup_dismissed', true);
    if (kIsWeb || !Platform.isAndroid) return;
    try {
      await const MethodChannel(
        'com.example.expencify/native_sms',
      ).invokeMethod<void>('cancelSmsWork');
    } catch (_) {}
    try {
      await const MethodChannel(
        'com.example.expencify/native_sms',
      ).invokeMethod<void>('clearPendingSms');
    } catch (_) {}
  }

  /// Reads all SMS from inbox and returns only bank/financial ones, parsed.
  Future<List<Map<String, dynamic>>> readBankSmsFromInbox({
    int limit = 100,
  }) async {
    if (!await SmsTrackingPreference.isEnabled()) return [];
    final granted = await hasPermission();
    if (!granted) return [];

    final List<SmsMessage> messages = await _telephony.getInboxSms(
      columns: [
        SmsColumn.ADDRESS,
        SmsColumn.BODY,
        SmsColumn.DATE,
        SmsColumn.DATE_SENT,
      ],
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
      final dateMs = (msg.dateSent ?? 0) > 0
          ? msg.dateSent!
          : msg.date ?? DateTime.now().millisecondsSinceEpoch;
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
    if (!await SmsTrackingPreference.isEnabled()) return;
    try {
      final prefs = await SharedPreferences.getInstance();

      // Read the last scan watermark. Default to 24h ago on first run
      // (avoids a 30-day flood on install while still catching missed SMS).
      var lastScanMs =
          prefs.getInt('sms_last_scan_ts') ??
          DateTime.now()
              .subtract(const Duration(hours: 24))
              .millisecondsSinceEpoch;

      final enabledSince = prefs.getInt(SmsTrackingPreference.sinceKey) ?? 0;
      if (enabledSince > lastScanMs) lastScanMs = enabledSince;
      debugPrint(
        '>>> [SmsMonitorService] Scanning SMS since ${DateTime.fromMillisecondsSinceEpoch(lastScanMs)}',
      );

      final scanStarted = DateTime.now().millisecondsSinceEpoch;
      final msgs = await _telephony.getInboxSms(
        columns: [
          SmsColumn.ADDRESS,
          SmsColumn.BODY,
          SmsColumn.DATE,
          SmsColumn.DATE_SENT,
        ],
        filter: SmsFilter.where(
          SmsColumn.DATE,
        ).greaterThan(lastScanMs.toString()),
        sortOrder: [OrderBy(SmsColumn.DATE, sort: Sort.ASC)],
      );

      int found = 0;
      for (final msg in msgs) {
        final body = msg.body ?? '';
        if (body.isEmpty) continue;
        final sentMs = (msg.dateSent ?? 0) > 0 ? msg.dateSent : msg.date;
        final msgDate = sentMs != null
            ? DateTime.fromMillisecondsSinceEpoch(sentMs)
            : DateTime.now();
        final success = await processSms(
          body,
          date: msgDate,
          sender: msg.address,
          suppressNotification: true,
        );
        if (!success) return;
        found++;
      }

      // Advance the watermark to now so the next scan won't re-process these.
      await prefs.setInt('sms_last_scan_ts', scanStarted);

      debugPrint(
        '>>> [SmsMonitorService] Startup scan complete — processed $found new messages',
      );
    } catch (e) {
      debugPrint(
        '>>> [SmsMonitorService] Startup scan failed (non-fatal): ${e.runtimeType}',
      );
    }
  }
}
