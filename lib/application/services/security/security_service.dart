import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SecurityService extends WidgetsBindingObserver {
  static final SecurityService _instance = SecurityService._internal();
  factory SecurityService() => _instance;
  SecurityService._internal();

  bool _isLocked = false;
  bool _isSplashActive = true;

  bool get isLocked => _isLocked && !_isSplashActive;

  void setSplashActive(bool active) {
    if (_isSplashActive != active) {
      _isSplashActive = active;
      _notifyListeners();
    }
  }

  // Track if we should show the lock screen on resume
  bool _shouldLockOnResume = false;
  bool _isAuthenticating = false;
  DateTime _lastAuthTime = DateTime.fromMillisecondsSinceEpoch(0);

  void setAuthenticating(bool value) {
    _isAuthenticating = value;
    if (!value) {
      _lastAuthTime = DateTime.now();
      _shouldLockOnResume = false; // forcefully clear
    }
  }

  final Set<VoidCallback> _listeners = {};

  void addListener(VoidCallback listener) => _listeners.add(listener);
  void removeListener(VoidCallback listener) => _listeners.remove(listener);

  void _notifyListeners() {
    for (final listener in _listeners) {
      listener();
    }
  }

  Future<void> init() async {
    WidgetsBinding.instance.addObserver(this);
    // Initial check: if security enabled, we start locked
    final prefs = await SharedPreferences.getInstance();
    final enabled = prefs.getBool('app_lock_enabled') ?? false;
    if (enabled) {
      _isLocked = true;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final bool justAuthenticated =
        DateTime.now().difference(_lastAuthTime).inMilliseconds < 1500;

    // Ignore lifecycle changes if we are currently authenticating, or just finished recently.
    // The OS sends trailing paused/resumed events asynchronously when dismissing the prompt.
    if (_isAuthenticating || justAuthenticated) {
      _shouldLockOnResume = false;
      return;
    }

    if (state == AppLifecycleState.paused) {
      // The user actually switched to another app — lock on next resume.
      // NOTE: `inactive` fires for in-app overlays (notification shade, side
      // panel, biometric prompt) and must NOT trigger a lock.
      _shouldLockOnResume = true;
    } else if (state == AppLifecycleState.resumed) {
      _checkLockOnResume();
    }
  }

  Future<void> _checkLockOnResume() async {
    if (!_shouldLockOnResume) return;

    final bool justAuthenticated =
        DateTime.now().difference(_lastAuthTime).inMilliseconds < 1500;

    // If the app was paused because of a system authentication prompt
    // (like TouchID/FaceID overlay), we shouldn't arbitrarily lock the app.
    if (_isAuthenticating || justAuthenticated) {
      _shouldLockOnResume = false;
      return;
    }

    _shouldLockOnResume = false;

    final prefs = await SharedPreferences.getInstance();
    final enabled = prefs.getBool('app_lock_enabled') ?? false;

    if (enabled) {
      _isLocked = true;
      _notifyListeners();
    }
  }

  void unlock() {
    _isLocked = false;
    _notifyListeners();
  }

  Future<bool> isSecurityEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('app_lock_enabled') ?? false;
  }

  Future<void> setSecurityEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('app_lock_enabled', enabled);
  }

  Future<String?> getPin() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('app_pin');
  }

  Future<void> setPin(String pin) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('app_pin', pin);
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
