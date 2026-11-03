import 'dart:async';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

class PinCooldownException extends StateError {
  final Duration remaining;
  PinCooldownException(this.remaining)
    : super('Too many attempts. Please wait and try again.');
}

class SecurityService extends WidgetsBindingObserver implements Listenable {
  static final SecurityService _instance = SecurityService._internal();
  factory SecurityService() => _instance;
  SecurityService._internal() : _clock = DateTime.now;
  @visibleForTesting
  SecurityService.withClock(this._clock);
  final DateTime Function() _clock;

  static const _secure = FlutterSecureStorage();
  static const _privacy = MethodChannel('com.nidhi.expencify/app_lock');
  bool _enabled = false;
  AppLifecycleState _lifecycle = AppLifecycleState.resumed;
  Future<void>? _verification;
  Completer<bool>? _authResume;
  bool _isLocked = false;
  bool _isSplashActive = true;

  bool get isSplashActive => _isSplashActive;
  bool get isLocked => _isLocked && !_isSplashActive;
  bool get isAuthenticating => _isAuthenticating || _authResume != null;
  bool get isForeground => _lifecycle == AppLifecycleState.resumed;
  bool get isPrivacyCovered => _enabled && !isForeground && !_isSplashActive;

  void setSplashActive(bool active) {
    if (_isSplashActive != active) {
      _isSplashActive = active;
      _notifyListeners();
    }
  }

  bool _isAuthenticating = false;

  void setAuthenticating(bool value, {bool succeeded = false}) {
    _isAuthenticating = value;
    if (!value && !succeeded && !isForeground && _enabled) _isLocked = true;
    _notifyListeners();
  }

  Future<bool> completeAuthentication(bool succeeded) async {
    _isAuthenticating = false;
    if (!succeeded || isForeground) {
      if (!succeeded && !isForeground && _enabled) _isLocked = true;
      _notifyListeners();
      return succeeded && isForeground;
    }
    // Device-credential Activities can report success just before onResume.
    // Wait only for that return; a new background event cancels this result.
    final resumed = Completer<bool>();
    _authResume = resumed;
    _notifyListeners();
    var accepted = false;
    try {
      accepted =
          await resumed.future.timeout(
            const Duration(seconds: 2),
            onTimeout: () => false,
          ) &&
          isForeground;
      return accepted;
    } finally {
      if (identical(_authResume, resumed)) _authResume = null;
      if (!accepted && !isForeground && _enabled) _isLocked = true;
      _notifyListeners();
    }
  }

  final Set<VoidCallback> _listeners = {};

  @override
  void addListener(VoidCallback listener) => _listeners.add(listener);
  @override
  void removeListener(VoidCallback listener) => _listeners.remove(listener);

  void _notifyListeners() {
    for (final listener in List<VoidCallback>.of(_listeners)) {
      listener();
    }
  }

  Future<void> init() async {
    await getPin();
    _enabled = await isSecurityEnabled();
    _isLocked = _enabled;
    _isAuthenticating = false;
    _isSplashActive = true;
    final state = WidgetsBinding.instance.lifecycleState;
    _lifecycle = state == null || state == AppLifecycleState.detached
        ? AppLifecycleState.resumed
        : state;
    await _screenPrivacy(_enabled);
    WidgetsBinding.instance.removeObserver(this);
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _lifecycle = state;
    // Suppress only the active OS prompt, never a later timed grace window.
    if (_enabled &&
        !_isAuthenticating &&
        (state == AppLifecycleState.paused ||
            state == AppLifecycleState.hidden ||
            state == AppLifecycleState.detached)) {
      _isLocked = true;
      if (_authResume?.isCompleted == false) _authResume!.complete(false);
    }
    if (state == AppLifecycleState.resumed &&
        _authResume?.isCompleted == false) {
      _authResume!.complete(true);
    }
    _notifyListeners();
  }

  void unlock() {
    if (!isForeground) return;
    _isLocked = false;
    _notifyListeners();
  }

  Future<bool> isSecurityEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('app_lock_enabled') ?? false;
  }

  Future<void> setSecurityEnabled(bool enabled) async {
    if (enabled && !RegExp(r'^\d{4,6}$').hasMatch(await getPin() ?? '')) {
      throw StateError('Set an app PIN before enabling app lock.');
    }
    final prefs = await SharedPreferences.getInstance();
    await _screenPrivacy(enabled);
    if (!await prefs.setBool('app_lock_enabled', enabled)) {
      await _screenPrivacy(_enabled);
      throw StateError('Could not save app lock settings.');
    }
    _enabled = enabled;
    if (!enabled) _isLocked = false;
    _notifyListeners();
  }

  Future<void> _screenPrivacy(bool enabled) async {
    try {
      await _privacy.invokeMethod<void>('configure', {'enabled': enabled});
    } on MissingPluginException {
      // Android supplies screenshot/recents protection; widget tests do not.
    }
  }

  Future<String?> getPin() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = await _secure.read(key: 'app_pin');
    if (stored != null) {
      await prefs.remove('app_pin');
      return stored;
    }
    final legacy = prefs.getString('app_pin');
    if (legacy != null) {
      await _secure.write(key: 'app_pin', value: legacy);
      await prefs.remove('app_pin');
    }
    return legacy;
  }

  Future<void> setPin(String pin) async {
    if (!RegExp(r'^\d{4}$').hasMatch(pin)) {
      throw ArgumentError('Use a PIN with exactly 4 digits.');
    }
    await _secure.write(key: 'app_pin', value: pin);
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('app_pin');
    await prefs.remove('pin_attempts');
    await prefs.remove('pin_retry_after');
  }

  Future<Duration> pinCooldown() async {
    final prefs = await SharedPreferences.getInstance();
    final ms =
        (prefs.getInt('pin_retry_after') ?? 0) -
        _clock().millisecondsSinceEpoch;
    return Duration(milliseconds: ms > 0 ? ms : 0);
  }

  Future<bool> verifyPin(String pin) {
    final previous = _verification;
    final result = previous == null
        ? _verifyPinOnce(pin)
        : previous.then((_) => _verifyPinOnce(pin));
    late final Future<void> pending;
    void clear() {
      if (identical(_verification, pending)) _verification = null;
    }

    pending = result.then<void>(
      (_) => clear(),
      onError: (Object _, StackTrace __) => clear(),
    );
    _verification = pending;
    return result;
  }

  Future<bool> _verifyPinOnce(String pin) async {
    final remaining = await pinCooldown();
    if (remaining > Duration.zero) throw PinCooldownException(remaining);
    final expected = await getPin();
    if (expected == null || !RegExp(r'^\d{4,6}$').hasMatch(expected)) {
      throw StateError('App PIN unavailable.');
    }
    final prefs = await SharedPreferences.getInstance();
    if (pin == expected) {
      await prefs.remove('pin_attempts');
      await prefs.remove('pin_retry_after');
      return true;
    }
    final attempts = (prefs.getInt('pin_attempts') ?? 0) + 1;
    await prefs.setInt('pin_attempts', attempts % 5);
    if (attempts >= 5) {
      await prefs.setInt(
        'pin_retry_after',
        _clock().add(const Duration(minutes: 1)).millisecondsSinceEpoch,
      );
    }
    return false;
  }

  Future<void> reset() async {
    await _secure.delete(key: 'app_pin');
    final prefs = await SharedPreferences.getInstance();
    for (final key in [
      'app_pin',
      'app_lock_enabled',
      'biometric_enabled',
      'pin_attempts',
      'pin_retry_after',
    ]) {
      await prefs.remove(key);
    }
    _enabled = false;
    _isLocked = false;
    _isAuthenticating = false;
    await _screenPrivacy(false);
    _notifyListeners();
  }

  Future<bool> isBiometricEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('biometric_enabled') ?? false;
  }

  Future<void> setBiometricEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('biometric_enabled', enabled);
  }
}
