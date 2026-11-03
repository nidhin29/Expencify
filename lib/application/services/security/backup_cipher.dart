import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'backup_crypto.dart';

/// Native acceleration keeps the existing authenticated format and KDF strength.
class BackupCipher {
  final bool _nativeEnabled;
  final MethodChannel _channel;
  BackupCipher({bool? nativeEnabled, MethodChannel? channel})
    : _nativeEnabled = nativeEnabled ?? (!kIsWeb && Platform.isAndroid),
      _channel =
          channel ?? const MethodChannel('com.nidhi.expencify/backup_crypto');
  Future<Uint8List> encrypt(Uint8List bytes, String password) =>
      _run('encrypt', bytes, password);
  Future<Uint8List> decrypt(Uint8List bytes, String password) async {
    // Platform-channel/isolate byte views can be read-only. Restore owns this
    // writable copy and can erase it after decoding without rejecting a backup.
    return Uint8List.fromList(await _run('decrypt', bytes, password));
  }

  Future<Uint8List> _run(
    String operation,
    Uint8List bytes,
    String password,
  ) async {
    final modern =
        bytes.length >= 8 && String.fromCharCodes(bytes.take(8)) == 'SPENDY02';
    if (_nativeEnabled && (operation == 'encrypt' || modern)) {
      try {
        final result = await _channel.invokeMethod<Uint8List>(operation, {
          'bytes': bytes,
          'password': password,
        });
        if (result == null) throw StateError('Empty native crypto response');
        return result;
      } on MissingPluginException {
        // Other engines/platforms retain the compatible Dart implementation.
      } on PlatformException catch (error) {
        if (error.code != 'UNSUPPORTED') rethrow;
      }
    }
    return compute(operation == 'encrypt' ? _encrypt : _decrypt, (
      bytes,
      password,
    ));
  }
}

Uint8List _encrypt((Uint8List, String) input) =>
    EncryptionService().encryptData(input.$1, input.$2);
Uint8List _decrypt((Uint8List, String) input) =>
    EncryptionService().decryptData(input.$1, input.$2);
