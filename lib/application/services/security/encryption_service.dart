import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:encrypt/encrypt.dart' as encrypt;

class EncryptionService {
  static final EncryptionService _instance = EncryptionService._();
  factory EncryptionService() => _instance;
  EncryptionService._();

  /// Derives a 32-byte key from a user-provided password or PIN using SHA-256.
  encrypt.Key _deriveKey(String password) {
    final bytes = utf8.encode(password);
    final digest = sha256.convert(bytes);
    return encrypt.Key(Uint8List.fromList(digest.bytes));
  }

  /// Encrypts a byte array using AES-256-CBC.
  Uint8List encryptData(Uint8List data, String password) {
    final key = _deriveKey(password);
    final iv = encrypt.IV.fromLength(16);
    final encrypter = encrypt.Encrypter(encrypt.AES(key, mode: encrypt.AESMode.cbc));

    final encrypted = encrypter.encryptBytes(data, iv: iv);
    
    // Prepend IV to the data so we can use it for decryption
    final result = Uint8List(iv.bytes.length + encrypted.bytes.length);
    result.setAll(0, iv.bytes);
    result.setAll(iv.bytes.length, encrypted.bytes);
    
    return result;
  }

  /// Decrypts a byte array using AES-256-CBC (expects IV at the beginning).
  Uint8List decryptData(Uint8List encryptedData, String password) {
    final key = _deriveKey(password);
    final iv = encrypt.IV(encryptedData.sublist(0, 16));
    final data = encryptedData.sublist(16);
    
    final encrypter = encrypt.Encrypter(encrypt.AES(key, mode: encrypt.AESMode.cbc));
    final decrypted = encrypter.decryptBytes(encrypt.Encrypted(data), iv: iv);
    
    return Uint8List.fromList(decrypted);
  }
}
