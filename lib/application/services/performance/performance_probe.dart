import 'dart:async';
import 'dart:developer';
import 'dart:io';
import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'local_diagnostics.dart';

/// Timings are local and opt-in in release builds; verbose console output stays
/// behind PERFORMANCE_LOGS. Never passes financial values to diagnostics.
class PerformanceProbe {
  static const enabled = bool.fromEnvironment('PERFORMANCE_LOGS');
  static final _startup = Stopwatch();
  static bool _installed = false;
  static bool _listening = false;
  static Timer? _timer;
  static int? _firstFrame;
  static int? _ready;
  static int? _databaseOpen;
  static bool _databaseFailed = false;
  static bool _databaseRecorded = false;
  static bool _firstRecorded = false;
  static bool _readyRecorded = false;
  static int _frames = 0, _slow = 0, _buildUs = 0, _rasterUs = 0;
  static int? _cpu;
  static final _quickSamples = <HealthOperation, DateTime>{};
  static final _health = LocalDiagnostics.instance;
  static const _channel = MethodChannel('com.nidhi.expencify/diagnostics');

  static void install() {
    if (_installed) return;
    _installed = true;
    _startup.start();
    final frameworkHandler = FlutterError.onError;
    FlutterError.onError = (details) {
      _health.error(
        unhandled: false,
        category: _category(details.exception),
        stack: details.stack,
      );
      if (frameworkHandler != null) {
        frameworkHandler(details);
      } else {
        FlutterError.presentError(details);
      }
    };
    final platformHandler = PlatformDispatcher.instance.onError;
    PlatformDispatcher.instance.onError = (error, stack) {
      _health.error(unhandled: true, category: _category(error), stack: stack);
      return platformHandler?.call(error, stack) ?? false;
    };
    WidgetsBinding.instance.addObserver(_HealthLifecycle());
    _health.addListener(_configure);
    unawaited(_health.initialize().catchError((Object _) {}));
    SchedulerBinding.instance.addPostFrameCallback(
      (_) => mark('app.first_frame'),
    );
  }

  static String _category(Object error) => error is FlutterError
      ? 'framework'
      : error is FormatException
      ? 'format'
      : error is StateError
      ? 'state'
      : error is PlatformException
      ? 'platform'
      : 'other';

  static void _configure() {
    final active = WidgetsBinding.instance.lifecycleState;
    if (_health.enabled &&
        (active == null || active == AppLifecycleState.resumed)) {
      if (!_listening) {
        SchedulerBinding.instance.addTimingsCallback(_collect);
        _listening = true;
      }
      _timer ??= Timer.periodic(const Duration(minutes: 1), (_) {
        _publishFrames();
        unawaited(_sample());
      });
      _publishStartup();
      unawaited(_sample());
    } else {
      _stop();
    }
  }

  static void _stop() {
    _timer?.cancel();
    _timer = null;
    if (_listening) SchedulerBinding.instance.removeTimingsCallback(_collect);
    _listening = false;
    _publishFrames();
    _cpu = null;
    unawaited(_health.flush());
  }

  static void _collect(List<FrameTiming> timings) {
    final views = PlatformDispatcher.instance.views;
    final hz = views.isEmpty ? 60.0 : views.first.display.refreshRate;
    final budget = (1000000 / (hz > 0 ? hz : 60)).round();
    for (final timing in timings) {
      _frames++;
      final build = timing.buildDuration.inMicroseconds,
          raster = timing.rasterDuration.inMicroseconds;
      if (build > budget || raster > budget) _slow++;
      if (build > _buildUs) _buildUs = build;
      if (raster > _rasterUs) _rasterUs = raster;
    }
  }

  static void _publishFrames() {
    if (_frames > 0) {
      final views = PlatformDispatcher.instance.views;
      final hz = views.isEmpty ? 60.0 : views.first.display.refreshRate;
      _health.frames(
        count: _frames,
        slow: _slow,
        buildUs: _buildUs,
        rasterUs: _rasterUs,
        budgetUs: (1000000 / (hz > 0 ? hz : 60)).round(),
      );
    }
    _frames = 0;
    _slow = 0;
    _buildUs = 0;
    _rasterUs = 0;
  }

  static bool _sampling = false;
  static Future<void> _sample() async {
    if (!_health.enabled || _sampling) return;
    _sampling = true;
    try {
      int? delta;
      try {
        final value = Platform.isAndroid
            ? await _channel.invokeMethod<int>('processCpuMs')
            : null;
        if (value != null) {
          if (_cpu != null) delta = (value - _cpu!).clamp(0, 86400000);
          _cpu = value;
        }
      } catch (_) {
        /* Not all platforms expose process CPU time. */
      }
      _health.memory(rssBytes: ProcessInfo.currentRss, cpuMs: delta);
    } catch (_) {
      /* Profiling must not affect the app. */
    } finally {
      _sampling = false;
    }
  }

  static void _publishStartup() {
    if (!_health.enabled) return;
    if (_databaseOpen != null && !_databaseRecorded) {
      _health.timing(
        HealthOperation.databaseOpen,
        _databaseOpen!,
        failed: _databaseFailed,
      );
      _databaseRecorded = true;
    }
    if (_firstFrame != null && !_firstRecorded) {
      _health.timing(HealthOperation.firstFrame, _firstFrame!);
      _firstRecorded = true;
    }
    if (_ready != null && !_readyRecorded) {
      _health.timing(HealthOperation.startupReady, _ready!);
      _readyRecorded = true;
    }
  }

  static void mark(String name) {
    if (name == 'app.first_frame') _firstFrame = _startup.elapsedMilliseconds;
    if (name == 'app.core_ready') _ready = _startup.elapsedMilliseconds;
    _publishStartup();
    if (enabled && {'app.first_frame', 'app.core_ready'}.contains(name)) {
      debugPrint('[PERF] $name elapsed_ms=${_startup.elapsedMilliseconds}');
    }
  }

  static HealthOperation? _operation(String name) => switch (name) {
    'database.open' => HealthOperation.databaseOpen,
    'database.transactions.read' => HealthOperation.transactionsRead,
    'backup.create' => HealthOperation.backupCreate,
    'backup.restore' => HealthOperation.backupRestore,
    'backup.encode' => HealthOperation.backupEncode,
    'backup.encrypt' => HealthOperation.backupEncrypt,
    'backup.decrypt' => HealthOperation.backupDecrypt,
    'backup.validate' => HealthOperation.backupValidate,
    'backup.write' => HealthOperation.backupWrite,
    'ai.initialize' => HealthOperation.aiInitialize,
    _ => null,
  };

  static Future<T> measure<T>(String name, Future<T> Function() action) async {
    final operation = _operation(name);
    if (operation == null ||
        (!enabled &&
            !_health.enabled &&
            !(operation == HealthOperation.databaseOpen && _installed))) {
      return action();
    }
    final timer = Stopwatch()..start();
    final task = enabled ? (TimelineTask()..start(operation.name)) : null;
    var failed = false;
    try {
      return await action();
    } catch (_) {
      failed = true;
      rethrow;
    } finally {
      task?.finish();
      final ms = timer.elapsedMilliseconds;
      if (operation == HealthOperation.databaseOpen && !_databaseRecorded) {
        _databaseOpen = ms;
        _databaseFailed = failed;
        if (_health.enabled) _databaseRecorded = true;
      }
      final now = DateTime.now();
      if (operation != HealthOperation.transactionsRead ||
          ms >= 100 ||
          now
                  .difference(_quickSamples[operation] ?? DateTime(1970))
                  .inMinutes >=
              1) {
        _health.timing(operation, ms, failed: failed);
        _quickSamples[operation] = now;
      }
      if (enabled) debugPrint('[PERF] ${operation.name} ms=$ms');
    }
  }
}

class _HealthLifecycle extends WidgetsBindingObserver {
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      PerformanceProbe._configure();
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      PerformanceProbe._stop();
    }
  }

  @override
  void didHaveMemoryPressure() => LocalDiagnostics.instance.memoryPressure();
}
