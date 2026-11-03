import 'package:shared_preferences/shared_preferences.dart';

class SmsTrackingPreference {
  static const enabledKey = 'sms_tracking_enabled';
  static const sinceKey = 'sms_tracking_enabled_since';
  static Future<bool> isEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload(); // Background isolates must see the latest opt-out.
    return prefs.getBool(enabledKey) ?? false;
  }

  static Future<void> initialize({required bool previouslyGranted}) async {
    final prefs = await SharedPreferences.getInstance();
    if (!prefs.containsKey(enabledKey)) {
      // Preserve existing opted-in installations; fresh installs start manual.
      await prefs.setBool(
        enabledKey,
        previouslyGranted && (prefs.getBool('legal_terms_accepted') ?? false),
      );
    }
  }

  static Future<void> setEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    if (enabled) {
      await prefs.setInt(sinceKey, DateTime.now().millisecondsSinceEpoch);
    }
    await prefs.setBool(enabledKey, enabled);
  }
}
