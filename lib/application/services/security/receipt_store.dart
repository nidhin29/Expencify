import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:encrypt/encrypt.dart' as enc;
import 'package:flutter/foundation.dart' show compute;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import '../../../infrastructure/database/live_database_store.dart';

class ReceiptSecurityException implements Exception {
  final String message;
  const ReceiptSecurityException(this.message);
  @override
  String toString() => message;
}

const _magic = 'SPRCP001';
Uint8List _random(int size) {
  final r = Random.secure();
  return Uint8List.fromList(List.generate(size, (_) => r.nextInt(256)));
}

Uint8List _seal((Uint8List, Uint8List) input) {
  final nonce = _random(12);
  final header = Uint8List.fromList([...ascii.encode(_magic), ...nonce]);
  final cipher = enc.Encrypter(
    enc.AES(enc.Key(input.$2), mode: enc.AESMode.gcm),
  );
  return Uint8List.fromList([
    ...header,
    ...cipher
        .encryptBytes(input.$1, iv: enc.IV(nonce), associatedData: header)
        .bytes,
  ]);
}

Uint8List _unseal((Uint8List, Uint8List) input) {
  final data = input.$1;
  if (data.length < 36 ||
      ascii.decode(data.sublist(0, 8), allowInvalid: true) != _magic) {
    throw const FormatException('Invalid protected receipt.');
  }
  final cipher = enc.Encrypter(
    enc.AES(enc.Key(input.$2), mode: enc.AESMode.gcm),
  );
  return Uint8List.fromList(
    cipher.decryptBytes(
      enc.Encrypted(data.sublist(20)),
      iv: enc.IV(data.sublist(8, 20)),
      associatedData: data.sublist(0, 20),
    ),
  );
}

class ReceiptStore {
  static final ReceiptStore _instance = ReceiptStore._();
  factory ReceiptStore() => _instance;
  ReceiptStore._()
    : directory = null,
      keys = const SecureDatabaseKeyStore(name: 'spendy_receipt_key_v1');
  ReceiptStore.at(this.directory, this.keys);
  final String? directory;
  final DatabaseKeyStore keys;
  Future<Uint8List>? _keyFuture;
  static const maxBytes = 50 * 1024 * 1024;
  Future<Directory> root() async => Directory(
    directory ??
        p.join(
          (await getApplicationSupportDirectory()).path,
          'secure_receipts',
        ),
  ).create(recursive: true);
  Future<Uint8List> _key() => _keyFuture ??= _loadKey();
  Future<Uint8List> _loadKey() async {
    var value = await keys.read();
    if (value == null) {
      await for (final f in (await root()).list(
        recursive: true,
        followLinks: false,
      )) {
        if (f is File && f.path.endsWith('.spreceipt')) {
          throw const ReceiptSecurityException(
            'The receipt encryption key is unavailable. Existing photos were preserved.',
          );
        }
      }
      value = base64Encode(_random(32));
      await keys.write(value);
      if (await keys.read() != value) {
        throw const ReceiptSecurityException(
          'Could not store the receipt encryption key.',
        );
      }
    }
    final key = base64Decode(value);
    if (key.length != 32) {
      throw const ReceiptSecurityException(
        'The receipt encryption key is invalid.',
      );
    }
    return key;
  }

  Future<bool> protected(String path) async {
    final handle = await File(path).open();
    try {
      return ascii.decode(await handle.read(8), allowInvalid: true) == _magic;
    } finally {
      await handle.close();
    }
  }

  Future<Uint8List> read(String path) async {
    final file = File(path);
    if (await file.length() > maxBytes + 36) {
      throw const ReceiptSecurityException('Receipt exceeds the size limit.');
    }
    final bytes = await file.readAsBytes();
    final encrypted =
        bytes.length >= 8 &&
        ascii.decode(bytes.sublist(0, 8), allowInvalid: true) == _magic;
    if (!encrypted) {
      if (path.endsWith('.spreceipt')) {
        throw const ReceiptSecurityException(
          'This protected receipt is damaged.',
        );
      }
      return bytes; // Read-only legacy compatibility; startup migrates retained photos.
    }
    try {
      return await compute(_unseal, (bytes, await _key()));
    } catch (_) {
      throw const ReceiptSecurityException(
        'This receipt could not be authenticated. The file was preserved.',
      );
    }
  }

  Future<String> write(Uint8List plain, {Directory? folder}) async {
    if (plain.isEmpty || plain.length > maxBytes) {
      throw const ReceiptSecurityException(
        'Receipt is empty or exceeds the size limit.',
      );
    }
    final base = await root();
    final target = folder ?? base;
    if (!p.isWithin(base.absolute.path, target.absolute.path) &&
        base.absolute.path != target.absolute.path) {
      throw ArgumentError('Invalid receipt directory.');
    }
    await target.create(recursive: true);
    final realBase = await base.resolveSymbolicLinks(),
        realTarget = await target.resolveSymbolicLinks();
    if (realBase != realTarget && !p.isWithin(realBase, realTarget)) {
      throw ArgumentError('Invalid receipt directory.');
    }
    final name = _random(
      16,
    ).map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    final file = File(p.join(target.path, '$name.spreceipt'));
    final partial = File('${file.path}.part');
    try {
      final key = await _key();
      final sealed = await compute(_seal, (plain, key));
      await partial.writeAsBytes(sealed, flush: true);
      final verified = await compute(_unseal, (
        await partial.readAsBytes(),
        key,
      ));
      if (!listEquals(plain, verified)) {
        throw const ReceiptSecurityException(
          'Receipt encryption verification failed.',
        );
      }
      await partial.rename(file.path);
      return file.path;
    } finally {
      if (await partial.exists()) await partial.delete();
    }
  }

  Future<String> importPhoto(String source) async {
    if (await File(source).length() > maxBytes) {
      throw const ReceiptSecurityException('Receipt exceeds the size limit.');
    }
    return write(await File(source).readAsBytes());
  }

  Future<Directory> restoreFolder() async => Directory(
    p.join(
      (await root()).path,
      'restore_${DateTime.now().microsecondsSinceEpoch}',
    ),
  ).create();

  /// Replace database references only after authenticated ciphertext is durable.
  Future<void> migrate(Database db, {String? documents}) async {
    final docs = documents ?? (await getApplicationDocumentsDirectory()).path;
    final legacy = Directory(p.join(docs, 'receipts'));
    final rows = await db.rawQuery(
      "SELECT DISTINCT image_path FROM transactions WHERE image_path IS NOT NULL AND image_path != ''",
    );
    for (final row in rows) {
      final old = row['image_path'] as String;
      if (!await File(old).exists() ||
          await File(old).length() == 0 ||
          await protected(old)) {
        continue;
      }
      if (old.endsWith('.spreceipt')) {
        throw const ReceiptSecurityException(
          'A protected receipt is damaged. Its original file was preserved.',
        );
      }
      final replacement = await importPhoto(old);
      try {
        await db.update(
          'transactions',
          {'image_path': replacement},
          where: 'image_path = ?',
          whereArgs: [old],
        );
      } catch (_) {
        await File(replacement).delete();
        rethrow;
      }
      if (await _within(legacy, old)) await File(old).delete();
    }
    // Only the app-owned legacy receipts folder; never the user's photo gallery.
    if (await FileSystemEntity.type(legacy.path, followLinks: false) ==
        FileSystemEntityType.directory) {
      final remaining = (await db.rawQuery(
        'SELECT image_path FROM transactions',
      )).map((r) => r['image_path']).toSet();
      await for (final entity in legacy.list(
        recursive: true,
        followLinks: false,
      )) {
        if (entity is File && !remaining.contains(entity.path)) {
          await entity.delete();
        }
      }
    }
  }

  Future<void> clearOwned() async {
    final base = await root();
    await for (final entity in base.list(recursive: true, followLinks: false)) {
      if (entity is File) await entity.delete();
    }
  }

  Future<bool> _within(Directory root, String file) async {
    if (await FileSystemEntity.type(root.path, followLinks: false) !=
        FileSystemEntityType.directory) {
      return false;
    }
    return p.isWithin(
      await root.resolveSymbolicLinks(),
      await File(file).resolveSymbolicLinks(),
    );
  }
}

bool listEquals(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
