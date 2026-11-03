import 'dart:io';
import 'package:permission_handler/permission_handler.dart';

class NotificationAccess {
  const NotificationAccess();
  Future<bool?> status() async {
    if (!Platform.isAndroid && !Platform.isIOS) return null;
    final status = await Permission.notification.status;
    return status.isGranted || status.isProvisional;
  }

  Future<void> request() async {
    if (Platform.isAndroid || Platform.isIOS) {
      await Permission.notification.request();
    }
  }

  Future<bool> openSettings() => openAppSettings();
}
