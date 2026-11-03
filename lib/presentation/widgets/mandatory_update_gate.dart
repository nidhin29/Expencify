import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class MandatoryUpdateGate extends StatefulWidget {
  final Widget child;
  final bool? enabled;
  const MandatoryUpdateGate({super.key, required this.child, this.enabled});
  @override
  State<MandatoryUpdateGate> createState() => _MandatoryUpdateGateState();
}

class _MandatoryUpdateGateState extends State<MandatoryUpdateGate>
    with WidgetsBindingObserver {
  static const _channel = MethodChannel('com.nidhi.expencify/play_update');
  bool _checking = true;
  bool _required = false;
  bool _busy = false;
  String? _error;
  bool get _enabled =>
      widget.enabled ??
      (!kIsWeb &&
          defaultTargetPlatform == TargetPlatform.android &&
          kReleaseMode);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (_enabled) {
      _channel.setMethodCallHandler((call) async {
        if (call.method == 'flowFinished') await _check();
      });
      unawaited(_check(autoStart: true));
    } else {
      _checking = false;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_enabled && state == AppLifecycleState.resumed) unawaited(_check());
  }

  Future<void> _check({bool autoStart = false}) async {
    if (_busy) return;
    _busy = true;
    bool resume = false;
    try {
      final status = await _channel
          .invokeMapMethod<String, dynamic>('check')
          .timeout(const Duration(seconds: 15));
      if (!mounted) return;
      // Once required, a same-process check cannot unlock the installed build.
      _required = _required || status?['required'] == true;
      resume = status?['inProgress'] == true;
      _error = null;
    } catch (_) {
      // Native code retains a detected target across restarts. If the bridge
      // itself fails, fail closed rather than accidentally bypassing it.
      _error = 'Could not check for updates. Please try again.';
    } finally {
      _busy = false;
      if (mounted) {
        setState(() {
          _checking = false;
        });
      }
    }
    if (mounted && _required && (autoStart || resume)) await _start();
  }

  Future<void> _start() async {
    if (_busy) return;
    if (!_required) {
      await _check(autoStart: true);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _channel.invokeMethod<void>('start');
    } catch (_) {
      if (mounted) {
        _error =
            'Could not start the update. Check your connection and try again.';
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (_enabled) _channel.setMethodCallHandler(null);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final blocked = _checking || _required || _error != null;
    return Stack(
      children: [
        Offstage(offstage: blocked, child: widget.child),
        if (blocked)
          Positioned.fill(
            child: Material(
              color: Theme.of(context).scaffoldBackgroundColor,
              child: SafeArea(
                child: Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (_checking) ...[
                          const CircularProgressIndicator(),
                          const SizedBox(height: 24),
                          const Text('Checking for updates…'),
                        ] else ...[
                          Icon(
                            Icons.system_update_rounded,
                            size: 64,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                          const SizedBox(height: 24),
                          Text(
                            'Update required',
                            style: Theme.of(context).textTheme.headlineSmall,
                          ),
                          const SizedBox(height: 12),
                          const Text(
                            'Install the latest version of Spendy to continue.',
                            textAlign: TextAlign.center,
                          ),
                          if (_error != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 16),
                              child: Text(_error!, textAlign: TextAlign.center),
                            ),
                          const SizedBox(height: 28),
                          FilledButton(
                            onPressed: _busy ? null : _start,
                            child: Text(
                              _busy ? 'Opening update…' : 'Update now',
                            ),
                          ),
                          TextButton(
                            onPressed: () => SystemNavigator.pop(),
                            child: const Text('Exit'),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
