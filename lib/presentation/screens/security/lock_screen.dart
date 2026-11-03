import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../application/services/auth/auth_service.dart';
import '../../../application/services/security/security_service.dart';
import '../../widgets/app_pin_dialog.dart';
import '../../widgets/spendy_splash_visual.dart';

const appLockOverlayStyle = SystemUiOverlayStyle(
  statusBarColor: Color(0xFF100A1E),
  statusBarIconBrightness: Brightness.light,
  statusBarBrightness: Brightness.dark,
  systemStatusBarContrastEnforced: false,
  systemNavigationBarColor: Color(0xFF100A1E),
  systemNavigationBarIconBrightness: Brightness.light,
);

class LockScreen extends StatefulWidget {
  final VoidCallback onUnlocked;
  final VoidCallback? onCancelled;
  final bool verificationOnly;
  final SecurityService? securityService;
  final AuthService? authService;
  const LockScreen({
    super.key,
    required this.onUnlocked,
    this.onCancelled,
    this.verificationOnly = false,
    this.securityService,
    this.authService,
  });
  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen> with WidgetsBindingObserver {
  late final _security = widget.securityService ?? SecurityService();
  late final _auth = widget.authService ?? AuthService();
  String _pin = '';
  int _pinLength = 4;
  String? _error;
  bool _loading = true, _loadFailed = false, _missingPin = false;
  bool _checking = false, _bioActive = false, _bioEnabled = false;
  bool _autoPending = true, _ticking = false;
  int _generation = 0;
  bool _finished = false;
  Duration _remaining = Duration.zero;
  Timer? _timer;
  bool get _inputEnabled =>
      !_finished &&
      !_loading &&
      !_loadFailed &&
      !_missingPin &&
      !_checking &&
      !_bioActive &&
      _remaining == Duration.zero;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_load());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if ((state == AppLifecycleState.paused ||
            state == AppLifecycleState.hidden) &&
        !_security.isAuthenticating) {
      _generation++;
      _pin = '';
      if (widget.verificationOnly) _cancelVerification();
    } else if (state == AppLifecycleState.resumed) {
      unawaited(_tick());
      if (_autoPending && _bioEnabled && !_missingPin && !_loading) {
        unawaited(_deviceUnlock());
      }
    }
  }

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _loadFailed = false;
        _error = null;
      });
    }
    try {
      final pin = await _security.getPin();
      final bio = await _security.isBiometricEnabled();
      final cooldown = await _security.pinCooldown();
      if (!mounted) return;
      setState(() {
        _missingPin = !RegExp(r'^\d{4,6}$').hasMatch(pin ?? '');
        _pinLength = pin?.length ?? 4;
        _bioEnabled = bio;
        _loading = false;
      });
      _setCooldown(cooldown);
      if (bio && !_missingPin && _security.isForeground) {
        unawaited(_deviceUnlock());
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _loadFailed = true;
        });
      }
    }
  }

  void _setCooldown(Duration remaining) {
    if (!mounted) return;
    _timer?.cancel();
    setState(() => _remaining = remaining);
    if (remaining > Duration.zero) {
      _timer = Timer.periodic(
        const Duration(seconds: 1),
        (_) => unawaited(_tick()),
      );
    }
  }

  Future<void> _tick() async {
    if (_ticking || !mounted) return;
    _ticking = true;
    try {
      final remaining = await _security.pinCooldown();
      if (!mounted) return;
      setState(() => _remaining = remaining);
      if (remaining == Duration.zero) _timer?.cancel();
    } catch (_) {
      // The service still checks the persisted limit before every attempt.
    } finally {
      _ticking = false;
    }
  }

  Future<void> _deviceUnlock() async {
    if (_checking || _bioActive || !_security.isForeground) return;
    final generation = _generation;
    _autoPending = false;
    setState(() {
      _bioActive = true;
      _pin = '';
      _error = null;
    });
    try {
      final success = await _auth.authenticateWithBiometrics();
      if (!mounted || generation != _generation) return;
      if (!success || !_security.isForeground) {
        setState(() => _error = 'Device verification was not completed.');
        return;
      }
      if (_missingPin && !widget.verificationOnly) {
        final saved = await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (_) =>
              AppPinDialog(title: 'Reset app PIN', onSave: _security.setPin),
        );
        if (!mounted ||
            saved != true ||
            !_security.isForeground ||
            generation != _generation) {
          return;
        }
      }
      _finish();
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'Could not verify your device. Please try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _bioActive = false);
    }
  }

  void _key(String value) {
    if (!_inputEnabled || _pin.length >= _pinLength) return;
    _autoPending = false;
    setState(() {
      _pin += value;
      _error = null;
    });
    if (_pin.length == _pinLength) unawaited(_verify());
  }

  Future<void> _verify() async {
    if (_checking || _bioActive) return;
    final pin = _pin;
    final generation = _generation;
    setState(() => _checking = true);
    try {
      final valid = await _security.verifyPin(pin);
      if (!mounted || generation != _generation || !_security.isForeground) {
        return;
      }
      if (valid) {
        _finish();
      } else {
        setState(() {
          _pin = '';
          _error = 'Incorrect PIN. Try again.';
        });
        _setCooldown(await _security.pinCooldown());
      }
    } on PinCooldownException catch (e) {
      if (mounted) {
        setState(() {
          _pin = '';
          _error = null;
        });
        _setCooldown(e.remaining);
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _pin = '';
          _error = 'Could not check your PIN. Please retry.';
        });
      }
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  @override
  void dispose() {
    _generation++;
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _finish() {
    if (_finished || !_security.isForeground) return;
    _finished = true;
    widget.onUnlocked();
  }

  void _cancelVerification() {
    if (_finished) return;
    _finished = true;
    _generation++;
    widget.onCancelled?.call();
  }

  @override
  Widget build(BuildContext context) {
    final seconds = (_remaining.inMilliseconds + 999) ~/ 1000;
    final title = widget.verificationOnly ? "Verify it's you" : 'Unlock Spendy';
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: appLockOverlayStyle,
      child: PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop && widget.verificationOnly && !_checking && !_bioActive) {
            _cancelVerification();
          }
        },
        child: Scaffold(
          backgroundColor: const Color(0xFF100A1E),
          body: DecoratedBox(
            decoration: const BoxDecoration(
              gradient: RadialGradient(
                center: Alignment(0, -.6),
                radius: 1.4,
                colors: [Color(0xFF281447), Color(0xFF100A1E)],
              ),
            ),
            child: SafeArea(
              child: LayoutBuilder(
                builder: (context, constraints) => SingleChildScrollView(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: constraints.maxHeight,
                    ),
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 360),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (widget.verificationOnly)
                                Align(
                                  alignment: Alignment.centerLeft,
                                  child: IconButton(
                                    tooltip: 'Cancel verification',
                                    onPressed: _checking || _bioActive
                                        ? null
                                        : _cancelVerification,
                                    icon: const Icon(
                                      Icons.close_rounded,
                                      color: Colors.white70,
                                    ),
                                  ),
                                ),
                              Container(
                                width: 76,
                                height: 76,
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: const Color(
                                    0xFF7C3AED,
                                  ).withValues(alpha: .22),
                                  borderRadius: BorderRadius.circular(24),
                                ),
                                child: const ExcludeSemantics(
                                  child: CustomPaint(
                                    painter: SpendyWalletPainter(
                                      progress: 1,
                                      centered: true,
                                      glow: false,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 20),
                              Text(
                                title,
                                textAlign: TextAlign.center,
                                style: Theme.of(context).textTheme.headlineSmall
                                    ?.copyWith(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w700,
                                    ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                _missingPin
                                    ? 'Your app PIN is unavailable.'
                                    : widget.verificationOnly
                                    ? 'Confirm before changing app lock.'
                                    : 'Your finances stay private.',
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: Color(0xFFD9CFEA),
                                  fontSize: 14,
                                ),
                              ),
                              const SizedBox(height: 24),
                              if (_loading)
                                const Padding(
                                  padding: EdgeInsets.all(24),
                                  child: CircularProgressIndicator(
                                    color: Color(0xFFC4B5FD),
                                  ),
                                )
                              else if (_loadFailed) ...[
                                const Text(
                                  'Could not access app lock. Your data is still protected.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(color: Colors.white70),
                                ),
                                TextButton(
                                  onPressed: _load,
                                  child: const Text('Try again'),
                                ),
                              ] else if (_missingPin) ...[
                                const Text(
                                  'Verify your device to continue securely.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(color: Colors.white70),
                                ),
                                const SizedBox(height: 16),
                                FilledButton.icon(
                                  onPressed: _bioActive ? null : _deviceUnlock,
                                  icon: const Icon(
                                    Icons.verified_user_outlined,
                                  ),
                                  label: Text(
                                    _bioActive ? 'Verifying…' : 'Verify device',
                                  ),
                                ),
                                TextButton(
                                  onPressed: _bioActive ? null : _load,
                                  child: const Text('Retry app PIN'),
                                ),
                                if (_error != null) _errorText(_error!),
                              ] else ...[
                                Semantics(
                                  label:
                                      '${_pin.length} of $_pinLength PIN digits entered',
                                  child: ExcludeSemantics(
                                    child: Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: List.generate(
                                        _pinLength,
                                        (i) => Container(
                                          width: 13,
                                          height: 13,
                                          margin: const EdgeInsets.symmetric(
                                            horizontal: 7,
                                          ),
                                          decoration: BoxDecoration(
                                            shape: BoxShape.circle,
                                            color: i < _pin.length
                                                ? const Color(0xFFC4B5FD)
                                                : Colors.white12,
                                            border: Border.all(
                                              color: Colors.white24,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 12),
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 16),
                                  child: _error != null && seconds == 0
                                      ? _errorText(_error!)
                                      : Text(
                                          seconds > 0
                                              ? 'Try your PIN again in ${seconds}s'
                                              : _bioActive
                                              ? 'Verify with your device'
                                              : _checking
                                              ? 'Checking PIN…'
                                              : 'Enter your $_pinLength-digit app PIN',
                                          textAlign: TextAlign.center,
                                          style: const TextStyle(
                                            color: Color(0xFFD9CFEA),
                                            fontSize: 13,
                                          ),
                                        ),
                                ),
                                for (var row = 0; row < 3; row++)
                                  Row(
                                    children: [
                                      for (var col = 1; col <= 3; col++)
                                        _keyButton(
                                          '${row * 3 + col}',
                                          onTap: _inputEnabled
                                              ? () => _key('${row * 3 + col}')
                                              : null,
                                        ),
                                    ],
                                  ),
                                Row(
                                  children: [
                                    _keyButton(
                                      'Use device unlock',
                                      icon: Icons.fingerprint_rounded,
                                      visible: _bioEnabled,
                                      onTap:
                                          _bioEnabled &&
                                              !_checking &&
                                              !_bioActive
                                          ? _deviceUnlock
                                          : null,
                                    ),
                                    _keyButton(
                                      '0',
                                      onTap: _inputEnabled
                                          ? () => _key('0')
                                          : null,
                                    ),
                                    _keyButton(
                                      'Delete digit',
                                      icon: Icons.backspace_outlined,
                                      onTap: _inputEnabled && _pin.isNotEmpty
                                          ? () => setState(() {
                                              _pin = _pin.substring(
                                                0,
                                                _pin.length - 1,
                                              );
                                              _error = null;
                                            })
                                          : null,
                                    ),
                                  ],
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _errorText(String text) => Semantics(
    liveRegion: true,
    child: Text(
      text,
      textAlign: TextAlign.center,
      style: const TextStyle(color: Color(0xFFFDA4AF), fontSize: 13),
    ),
  );

  Widget _keyButton(
    String label, {
    IconData? icon,
    VoidCallback? onTap,
    bool visible = true,
  }) => Expanded(
    child: Padding(
      padding: const EdgeInsets.all(5),
      child: SizedBox(
        height: 64,
        child: !visible
            ? const SizedBox.shrink()
            : Semantics(
                label: label,
                button: true,
                enabled: onTap != null,
                child: ExcludeSemantics(
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: onTap,
                      borderRadius: BorderRadius.circular(20),
                      child: Container(
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(
                            alpha: onTap != null ? .07 : .025,
                          ),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: icon == null
                            ? Text(
                                label,
                                style: TextStyle(
                                  fontSize: 26,
                                  color: onTap != null
                                      ? Colors.white
                                      : Colors.white24,
                                ),
                              )
                            : Icon(
                                icon,
                                size: 26,
                                color: onTap != null
                                    ? const Color(0xFFC4B5FD)
                                    : Colors.white24,
                              ),
                      ),
                    ),
                  ),
                ),
              ),
      ),
    ),
  );
}
