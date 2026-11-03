import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum HealthOperation {
  firstFrame,
  startupReady,
  databaseOpen,
  transactionsRead,
  backupCreate,
  backupRestore,
  backupEncode,
  backupEncrypt,
  backupDecrypt,
  backupValidate,
  backupWrite,
  aiInitialize,
}

/// Only fixed event names and bounded numeric metadata can enter this report.
/// Never accepts exception text, SQL, paths, SMS, queries or financial records.
class LocalDiagnostics extends ChangeNotifier {
  static final instance = LocalDiagnostics._();
  LocalDiagnostics._() : _clock = DateTime.now;
  @visibleForTesting
  LocalDiagnostics.withPreferences(
    SharedPreferences preferences, {
    DateTime Function()? clock,
  }) : _preferences = preferences,
       _clock = clock ?? DateTime.now;
  static const enabledKey = 'local_diagnostics_enabled';
  static const _recordsKey = 'local_diagnostics_records';
  static const nativeKey = 'local_diagnostics_native';
  static const maxEntries = 120;
  static const retention = Duration(days: 3);
  final DateTime Function() _clock;
  SharedPreferences? _preferences;
  Future<void>? _initializing;
  Future<void> _writes = Future.value();
  Future<void>? _activeWrite;
  bool _writePending = false;
  Timer? _flushTimer;
  bool _enabled = false;
  List<Map<String, Object>> _records = [];
  bool get enabled => _enabled;
  List<Map<String, Object>> get records => _records
      .map((r) => Map<String, Object>.unmodifiable(r))
      .toList(growable: false);
  int get _cutoff => _clock().subtract(retention).millisecondsSinceEpoch;

  Future<void> initialize() =>
      _initializing ??= Future<void>.microtask(_initialize).catchError((
        Object error,
        StackTrace stack,
      ) {
        _initializing = null;
        Error.throwWithStackTrace(error, stack);
      });
  Future<void> _initialize() async {
    final prefs = _preferences ??= await SharedPreferences.getInstance();
    _enabled = prefs.getBool(enabledKey) ?? false;
    if (_enabled) {
      try {
        final text = prefs.getString(_recordsKey) ?? '[]';
        final raw = text.length <= 65536 ? jsonDecode(text) : <Object>[];
        if (raw is List) {
          _records = raw
              .map(_sanitize)
              .whereType<Map<String, Object>>()
              .where((r) => (r['at_minute'] as int) >= _cutoff)
              .toList();
        }
        _trim();
      } catch (_) {
        _records = [];
      }
    } else {
      await prefs.remove(_recordsKey);
      await prefs.remove(nativeKey);
    }
    notifyListeners();
  }

  Future<void> setEnabled(bool value) async {
    await initialize();
    if (value == _enabled && value) return;
    if (!value) {
      _enabled = false;
      _writePending = false;
      _flushTimer?.cancel();
      _flushTimer = null;
      _records.clear();
    }
    if (!await _preferences!.setBool(enabledKey, value)) {
      throw StateError('Could not save diagnostic preference');
    }
    if (value) {
      _enabled = true;
    } else {
      await _writes;
      await _preferences!.remove(_recordsKey);
      await _preferences!.remove(nativeKey);
      await _clearNative();
    }
    notifyListeners();
  }

  Future<void> clear() async {
    await initialize();
    _writePending = false;
    _flushTimer?.cancel();
    _flushTimer = null;
    _records.clear();
    await _writes;
    await _preferences!.remove(_recordsKey);
    await _preferences!.remove(nativeKey);
    await _clearNative();
    notifyListeners();
  }

  Future<void> _clearNative() async {
    if (!Platform.isAndroid) return;
    try {
      await const MethodChannel(
        'com.nidhi.expencify/diagnostics',
      ).invokeMethod<void>('clear');
    } catch (_) {
      /* SharedPreferences cleanup remains available on other platforms. */
    }
  }

  void refresh() {
    _trim();
    notifyListeners();
  }

  void timing(
    HealthOperation operation,
    int milliseconds, {
    bool failed = false,
  }) => _add({
    'kind': 'timing',
    'operation': operation.name,
    'duration_ms': _bound(milliseconds, 86400000),
    'failed': failed,
  });
  void error({
    required bool unhandled,
    required String category,
    StackTrace? stack,
  }) {
    const allowed = {'framework', 'format', 'state', 'platform', 'other'};
    final locations =
        RegExp(r'package:expencify/[A-Za-z0-9_/]+\.dart:\d+(?::\d+)?')
            .allMatches(stack?.toString() ?? '')
            .map((m) => m.group(0)!)
            .take(4)
            .toList();
    final fresh = _add({
      'kind': unhandled ? 'unhandled_error' : 'flutter_error',
      'category': allowed.contains(category) ? category : 'other',
      if (locations.isNotEmpty)
        'locations': List<String>.unmodifiable(locations),
    });
    if (fresh) unawaited(flush());
  }

  void frames({
    required int count,
    required int slow,
    required int buildUs,
    required int rasterUs,
    required int budgetUs,
  }) => _add({
    'kind': 'frames',
    'frames': _bound(count, 100000),
    'slow_frames': _bound(slow, count),
    'worst_build_us': _bound(buildUs, 60000000),
    'worst_raster_us': _bound(rasterUs, 60000000),
    'budget_us': _bound(budgetUs, 1000000),
  });
  void memory({required int rssBytes, int? cpuMs}) => _add({
    'kind': 'memory',
    'rss_bytes': _bound(rssBytes, 1 << 40),
    if (cpuMs != null) 'process_cpu_ms': _bound(cpuMs, 86400000),
  });
  void memoryPressure() => _add({'kind': 'memory_pressure'});
  static int _bound(int value, int maximum) =>
      value.clamp(0, maximum < 0 ? 0 : maximum);

  bool _add(Map<String, Object> record) {
    if (!_enabled) return false;
    final at = _clock().millisecondsSinceEpoch ~/ 60000 * 60000;
    // Collapse an error storm without retaining individual event content.
    if (_records.isNotEmpty && record['kind'].toString().endsWith('_error')) {
      final last = _records.last;
      if (last['kind'] == record['kind'] &&
          last['category'] == record['category'] &&
          last['at_minute'] == at &&
          listEquals(
            last['locations'] as List?,
            record['locations'] as List?,
          )) {
        last['count'] = _bound((last['count'] as int? ?? 1) + 1, 100000);
        _scheduleFlush();
        return false;
      }
    }
    _records.add({'at_minute': at, ...record});
    _trim();
    _scheduleFlush();
    return true;
  }

  void _trim() {
    _records.removeWhere((r) => (r['at_minute'] as int) < _cutoff);
    if (_records.length > maxEntries) {
      _records.removeRange(0, _records.length - maxEntries);
    }
  }

  void _scheduleFlush() {
    _flushTimer ??= Timer(const Duration(seconds: 2), () {
      _flushTimer = null;
      unawaited(flush());
    });
  }

  Future<void> flush() {
    _flushTimer?.cancel();
    _flushTimer = null;
    if (!_enabled || _preferences == null) return Future.value();
    _writePending = true;
    if (_activeWrite != null) return _activeWrite!;
    final completion = Completer<void>();
    _activeWrite = completion.future;
    _writes = completion.future;
    unawaited(() async {
      try {
        // Coalesce bursts into a bounded writer instead of queuing snapshots.
        while (_writePending && _enabled) {
          _writePending = false;
          _trim();
          await _preferences!.setString(_recordsKey, jsonEncode(_records));
        }
      } catch (_) {
        /* Diagnostics never blocks the app. */
      } finally {
        _activeWrite = null;
        completion.complete();
      }
    }());
    return completion.future;
  }

  static Map<String, Object>? _sanitize(dynamic raw) {
    if (raw is! Map || raw['at_minute'] is! int || raw['kind'] is! String) {
      return null;
    }
    final out = <String, Object>{
      'at_minute': raw['at_minute'] as int,
      'kind': raw['kind'] as String,
    };
    switch (raw['kind']) {
      case 'timing':
        if (!HealthOperation.values.any((o) => o.name == raw['operation']) ||
            raw['duration_ms'] is! int ||
            raw['failed'] is! bool) {
          return null;
        }
        out.addAll({
          'operation': raw['operation'] as String,
          'duration_ms': _bound(raw['duration_ms'] as int, 86400000),
          'failed': raw['failed'] as bool,
        });
        break;
      case 'flutter_error':
      case 'unhandled_error':
        if (!{
          'framework',
          'format',
          'state',
          'platform',
          'other',
        }.contains(raw['category'])) {
          return null;
        }
        out['category'] = raw['category'] as String;
        if (raw['locations'] is List) {
          final locations = (raw['locations'] as List)
              .whereType<String>()
              .where(
                (value) => RegExp(
                  r'^package:expencify/[A-Za-z0-9_/]+\.dart:\d+(?::\d+)?$',
                ).hasMatch(value),
              )
              .take(4)
              .toList();
          if (locations.isNotEmpty) {
            out['locations'] = List<String>.unmodifiable(locations);
          }
        }
        if (raw['count'] is int) {
          out['count'] = _bound(raw['count'] as int, 100000);
        }
        break;
      case 'frames':
        for (final key in [
          'frames',
          'slow_frames',
          'worst_build_us',
          'worst_raster_us',
          'budget_us',
        ]) {
          if (raw[key] is! int) return null;
          out[key] = _bound(raw[key] as int, 60000000);
        }
        break;
      case 'memory':
        if (raw['rss_bytes'] is! int) return null;
        out['rss_bytes'] = _bound(raw['rss_bytes'] as int, 1 << 40);
        if (raw['process_cpu_ms'] is int) {
          out['process_cpu_ms'] = _bound(
            raw['process_cpu_ms'] as int,
            86400000,
          );
        }
        break;
      case 'memory_pressure':
        break;
      default:
        return null;
    }
    return out;
  }

  Future<Map<String, Object>> report() async {
    await initialize();
    await flush();
    _trim();
    final native = <Map<String, Object>>[];
    if (_enabled) {
      await _preferences!.reload();
      try {
        final text = _preferences!.getString(nativeKey) ?? '[]';
        final raw = text.length <= 32768 ? jsonDecode(text) : <Object>[];
        if (raw is List) {
          for (final row in raw.take(60)) {
            if (row is! Map ||
                row['at_minute'] is! int ||
                (row['at_minute'] as int) < _cutoff ||
                !{'success', 'retry', 'skipped'}.contains(row['outcome'])) {
              continue;
            }
            if (row['wall_ms'] is! int || row['process_cpu_ms'] is! int) {
              continue;
            }
            native.add({
              'at_minute': row['at_minute'] as int,
              'outcome': row['outcome'] as String,
              'wall_ms': _bound(row['wall_ms'] as int, 600000),
              'process_cpu_ms': _bound(row['process_cpu_ms'] as int, 600000),
            });
          }
        }
      } catch (_) {
        /* Discard malformed diagnostic metadata only. */
      }
    }
    var version = 'unavailable';
    try {
      final info = await PackageInfo.fromPlatform();
      final candidate = '${info.version}+${info.buildNumber}';
      if (RegExp(r'^[A-Za-z0-9.+_-]{1,64}$').hasMatch(candidate)) {
        version = candidate;
      }
    } catch (_) {}
    int? androidApi;
    if (Platform.isAndroid) {
      try {
        final value = await const MethodChannel(
          'com.nidhi.expencify/diagnostics',
        ).invokeMethod<int>('androidApi');
        if (value != null && value >= 16 && value <= 100) {
          androidApi = value;
        }
      } catch (_) {
        /* Metadata may be unavailable in older builds. */
      }
    }
    return {
      'format': 1,
      'app_version': version,
      if (androidApi != null) 'android_api': androidApi,
      'platform': Platform.operatingSystem,
      'build_mode': kReleaseMode
          ? 'release'
          : kProfileMode
          ? 'profile'
          : 'debug',
      'records': _enabled
          ? _records.map(_sanitize).whereType<Map<String, Object>>().toList()
          : <Object>[],
      'background_sms_jobs': native,
    };
  }

  @override
  void dispose() {
    _flushTimer?.cancel();
    super.dispose();
  }
}
