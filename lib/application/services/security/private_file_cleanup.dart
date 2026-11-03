import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Readable exports must be plaintext while handed to another app.
/// Keep only that short-lived handoff copy, and expire plugin copies on resume.
class PrivateFileCleanup {
  final String? cachePath, documentsPath;
  const PrivateFileCleanup({this.cachePath, this.documentsPath});
  Future<Directory> shareRoot() async => Directory(
    p.join(cachePath ?? (await getTemporaryDirectory()).path, 'spendy_share'),
  ).create(recursive: true);
  Future<File> create(String extension, List<int> bytes) async {
    if (!['csv', 'pdf', 'spendy', 'json'].contains(extension)) {
      throw ArgumentError('Invalid export type.');
    }
    final folder = await (await shareRoot()).createTemp('handoff_');
    final file = File(
      p.join(
        folder.path,
        'spendy_${DateTime.now().microsecondsSinceEpoch}.$extension',
      ),
    );
    try {
      await file.writeAsBytes(bytes, flush: true);
      return file;
    } catch (_) {
      if (await file.exists()) await file.delete();
      if (await folder.list().isEmpty) await folder.delete();
      rethrow;
    }
  }

  Future<void> removeExport(String path) async {
    final root = await shareRoot();
    final file = File(path);
    if (!p.isWithin(root.absolute.path, file.absolute.path)) return;
    if (await file.exists()) {
      if (!p.isWithin(
        await root.resolveSymbolicLinks(),
        await file.resolveSymbolicLinks(),
      )) {
        return;
      }
      await file.delete();
    }
    final parent = file.parent;
    if (parent.path != root.path &&
        await parent.exists() &&
        await parent.list().isEmpty) {
      await parent.delete();
    }
  }

  Future<void> removePickerCopy(String path) async {
    final cache = Directory(cachePath ?? (await getTemporaryDirectory()).path);
    final file = File(path);
    if (!await file.exists()) return;
    if (p.isWithin(
      await cache.resolveSymbolicLinks(),
      await file.resolveSymbolicLinks(),
    )) {
      await file.delete();
    }
  }

  Future<void> removePickedBackup(String path) async {
    final cache = cachePath ?? (await getTemporaryDirectory()).path;
    final root = Directory(p.join(cache, 'file_picker'));
    final file = File(path);
    if (await file.exists() &&
        await root.exists() &&
        p.isWithin(
          await root.resolveSymbolicLinks(),
          await file.resolveSymbolicLinks(),
        )) {
      await file.delete();
    }
  }

  Future<void> clearExports() async {
    final root = await shareRoot();
    await for (final entity in root.list(recursive: true, followLinks: false)) {
      if (entity is File) await entity.delete();
    }
    await sweep(now: DateTime.now().add(const Duration(days: 365)));
  }

  Future<void> sweep({DateTime? now, bool startup = false}) async {
    final time = now ?? DateTime.now();
    final cache = cachePath ?? (await getTemporaryDirectory()).path;
    final docs =
        documentsPath ?? (await getApplicationDocumentsDirectory()).path;
    final owned = RegExp(r'^spendy_\d+\.(csv|pdf|spendy|json)$');
    for (final root in [
      Directory(docs),
      Directory(cache),
      Directory(p.join(cache, 'share_plus')),
      Directory(p.join(cache, 'file_picker')),
      await shareRoot(),
    ]) {
      if (!await root.exists()) continue;
      final recursive = [
        'spendy_share',
        'file_picker',
      ].contains(p.basename(root.path));
      await for (final entity in root.list(
        recursive: recursive,
        followLinks: false,
      )) {
        if (entity is! File ||
            (p.basename(root.path) != 'file_picker' &&
                !owned.hasMatch(p.basename(entity.path)))) {
          continue;
        }
        final legacy = root.path == docs;
        if (legacy && p.extension(entity.path) == '.json') continue;
        if (legacy ||
            time.difference((await entity.stat()).modified) >=
                const Duration(hours: 1)) {
          await entity.delete();
        }
      }
    }
    final photos = RegExp(
      r'\.(jpg|jpeg|png|webp|heic|heif|gif)$',
      caseSensitive: false,
    );
    await for (final entity in Directory(
      cache,
    ).list(recursive: true, followLinks: false)) {
      if (entity is File &&
          photos.hasMatch(entity.path) &&
          time.difference((await entity.stat()).modified) >=
              const Duration(hours: 1)) {
        await entity.delete();
      }
    }
    // A killed legacy-import attempt must not leave a raw SQLite copy forever.
    await for (final entity in Directory(cache).list(followLinks: false)) {
      if (entity is Directory &&
          p.basename(entity.path).startsWith('spendy_validate_') &&
          (startup ||
              time.difference((await entity.stat()).modified) >=
                  const Duration(hours: 1))) {
        if (p.isWithin(Directory(cache).absolute.path, entity.absolute.path)) {
          await entity.delete(recursive: true);
        }
      }
    }
  }
}
