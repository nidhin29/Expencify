import 'dart:io';
import 'dart:isolate';
import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';

/// Stream large artifact checksums on a native worker on Android. Other
/// platforms still perform the identical SHA-256 check off the UI isolate.
class ModelFileHash {
  static Future<String> sha256File(String path) async {
    if (Platform.isAndroid) {
      try {
        final hash = await const MethodChannel(
          'com.nidhi.expencify/model_integrity',
        ).invokeMethod<String>('sha256File', {'path': path});
        if (hash != null && RegExp(r'^[a-f0-9]{64}$').hasMatch(hash)) {
          return hash;
        }
      } on MissingPluginException {
        // Older native hosts remain verifiable while updating the app.
      } on PlatformException {
        // E.g. read-only asset packs outside the app's private directory.
      }
    }
    return Isolate.run(
      () async => (await sha256.bind(File(path).openRead()).first).toString(),
    );
  }
}
