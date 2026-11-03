import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:encrypt/encrypt.dart' as encrypt;
import 'package:pointycastle/export.dart';

class EncryptionService {
  static const _magic = 'SPENDY02';
  static const _iterations = 600000;
  Uint8List _random(int length) {
    final random = Random.secure();
    return Uint8List.fromList(
      List.generate(length, (_) => random.nextInt(256)),
    );
  }

  encrypt.Key _key(String password, Uint8List salt) {
    final kdf = PBKDF2KeyDerivator(HMac(SHA256Digest(), 64))
      ..init(Pbkdf2Parameters(salt, _iterations, 32));
    return encrypt.Key(kdf.process(Uint8List.fromList(utf8.encode(password))));
  }

  Uint8List encryptData(Uint8List data, String password) {
    final salt = _random(16);
    final nonce = _random(12);
    final cipher = encrypt.Encrypter(
      encrypt.AES(_key(password, salt), mode: encrypt.AESMode.gcm),
    );
    final header = Uint8List.fromList([
      ...ascii.encode(_magic),
      ...salt,
      ...nonce,
    ]);
    return Uint8List.fromList([
      ...header,
      ...cipher
          .encryptBytes(data, iv: encrypt.IV(nonce), associatedData: header)
          .bytes,
    ]);
  }

  Uint8List decryptData(Uint8List bytes, String password) {
    if (bytes.length >= 52 &&
        ascii.decode(bytes.sublist(0, 8), allowInvalid: true) == _magic) {
      final header = bytes.sublist(0, 36);
      final cipher = encrypt.Encrypter(
        encrypt.AES(
          _key(password, bytes.sublist(8, 24)),
          mode: encrypt.AESMode.gcm,
        ),
      );
      return Uint8List.fromList(
        cipher.decryptBytes(
          encrypt.Encrypted(bytes.sublist(36)),
          iv: encrypt.IV(bytes.sublist(24, 36)),
          associatedData: header,
        ),
      );
    }
    // Read-only compatibility; legacy data is validated before restoring it.
    if (bytes.length < 32 || bytes.length % 16 != 0) {
      throw const FormatException('Invalid encrypted backup.');
    }
    final key = encrypt.Key(
      Uint8List.fromList(sha256.convert(utf8.encode(password)).bytes),
    );
    return Uint8List.fromList(
      encrypt.Encrypter(
        encrypt.AES(key, mode: encrypt.AESMode.cbc),
      ).decryptBytes(
        encrypt.Encrypted(bytes.sublist(16)),
        iv: encrypt.IV(bytes.sublist(0, 16)),
      ),
    );
  }
}
