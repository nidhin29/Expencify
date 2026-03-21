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
    try {
      security.setAuthenticating(true);
      final bool didAuthenticate = await auth.authenticate(
        localizedReason: 'Please authenticate to access your finances',
        options: const AuthenticationOptions(
          stickyAuth: true,
          biometricOnly: false,
        ),
      );
      security.setAuthenticating(false);
      return didAuthenticate;
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
    await _db.wipeAllData();
  }

  /// Wipes all transactions, accounts, budgets etc. but keeps the user session.
  Future<void> wipeDataOnly() => _db.wipeDataOnly();
}
