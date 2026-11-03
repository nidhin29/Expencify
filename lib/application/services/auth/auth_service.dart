import '../security/receipt_store.dart';
import '../security/private_file_cleanup.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../notifications/notification_service.dart';
import 'package:local_auth/local_auth.dart';
import 'package:expencify/infrastructure/database/database_helper.dart';
import 'package:expencify/application/services/security/security_service.dart';

class AuthService {
  final LocalAuthentication auth = LocalAuthentication();
  final DatabaseHelper _db = DatabaseHelper();

  // ------- Biometrics -------

  Future<bool> isBiometricsAvailable() async {
    final bool canAuthenticateWithBiometrics = await auth.canCheckBiometrics;
    final bool canAuthenticate =
        canAuthenticateWithBiometrics || await auth.isDeviceSupported();
    return canAuthenticate;
  }

  Future<bool> authenticateWithBiometrics() async {
    final security = SecurityService();
    if (security.isAuthenticating) return false;
    try {
      security.setAuthenticating(true);
      final bool didAuthenticate = await auth.authenticate(
        localizedReason: 'Please authenticate to access your finances',
        options: const AuthenticationOptions(
          stickyAuth: false,
          biometricOnly: false,
        ),
      );
      return await security.completeAuthentication(didAuthenticate);
    } catch (e) {
      security.setAuthenticating(false);
      return false;
    }
  }

  // ------- Onboarding flags (stored in local SQLite) -------

  Future<bool> isOnboarded() async {
    final rows = await _db.queryAll('user_settings');
    if (rows.isEmpty) return false;
    return rows.first['has_onboarded'] == 1;
  }

  Future<void> setOnboarded() async {
    final rows = await _db.queryAll('user_settings');
    if (rows.isEmpty) {
      await _db.insert('user_settings', {'has_onboarded': 1});
    } else {
      await _db.update('user_settings', {'has_onboarded': 1}, rows.first['id']);
    }
  }

  // ------- Account Deletion -------

  Future<void> deleteAccount() async {
    // 1. Wipe all local financial data
    await _resetSideEffects();
    await _db.wipeAllData();
    await ReceiptStore().clearOwned();
    await const PrivateFileCleanup().clearExports();
    await SecurityService().reset();
  }

  /// Wipes all transactions, accounts, budgets etc. but keeps the user session.
  Future<void> wipeDataOnly() async {
    await _resetSideEffects();
    await _db.wipeDataOnly();
    await ReceiptStore().clearOwned();
    await const PrivateFileCleanup().clearExports();
  }

  Future<void> _resetSideEffects() async {
    await NotificationService().cancelAll();
    final prefs = await SharedPreferences.getInstance();
    for (final key
        in prefs
            .getKeys()
            .where(
              (key) =>
                  key.startsWith('budget_alert_') ||
                  [
                    'selected_account_id',
                    'pending_sms_list',
                    'sms_last_scan_ts',
                  ].contains(key),
            )
            .toList()) {
      await prefs.remove(key);
    }
    await prefs.setInt(
      'sms_last_scan_ts',
      DateTime.now().millisecondsSinceEpoch,
    );
    try {
      await const MethodChannel(
        'com.example.expencify/native_sms',
      ).invokeMethod<void>('clearPendingSms');
    } on MissingPluginException {
      /* Non-Android platform. */
    }
  }
}
