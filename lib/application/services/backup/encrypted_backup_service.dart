import 'backup_progress.dart';
import '../security/private_file_cleanup.dart';
import 'dart:io';
import 'package:share_plus/share_plus.dart';
import 'package:file_picker/file_picker.dart';
import 'backup_snapshot.dart';
import 'backup_restore_exception.dart';
import 'dart:typed_data';

class BackupImportResult {
  final bool restored;
  final bool cancelled;
  final String? error;
  const BackupImportResult.success()
    : restored = true,
      cancelled = false,
      error = null;
  const BackupImportResult.cancelled()
    : restored = false,
      cancelled = true,
      error = null;
  const BackupImportResult.failed(this.error)
    : restored = false,
      cancelled = false;
}

class BackupService {
  final BackupSnapshot? snapshot;
  final Future<FilePickerResult?> Function()? pickBackup;
  BackupService({this.snapshot, this.pickBackup});
  Future<bool> exportBackup(
    String password, {
    BackupProgressCallback? onProgress,
  }) async {
    File? file;
    try {
      final bytes = await (snapshot ?? BackupSnapshot()).create(
        password,
        onProgress: onProgress,
      );
      file = await const PrivateFileCleanup().create('spendy', bytes);
      reportBackupProgress(onProgress, BackupStage.readyToShare);
      final result = await Share.shareXFiles([
        XFile(file.path),
      ], subject: 'Spendy encrypted backup');
      return result.status != ShareResultStatus.dismissed;
    } catch (_) {
      return false;
    } finally {
      if (file != null) {
        await const PrivateFileCleanup().removeExport(file.path);
      }
    }
  }

  Future<BackupImportResult> importBackup({
    required Future<String?> Function() requestPassword,
    BackupProgressCallback? onProgress,
  }) async {
    reportBackupProgress(onProgress, BackupStage.readingFile);
    Uint8List bytes;
    String? pickedPath;
    try {
      final result =
          await (pickBackup?.call() ??
              FilePicker.platform.pickFiles(
                type: FileType.any,
                withReadStream: true,
              ));
      if (result == null || result.files.isEmpty) {
        return const BackupImportResult.cancelled();
      }
      final selected = result.files.single;
      pickedPath = selected.path;
      const limit = BackupSnapshot.maxBytes + 1024;
      if (selected.size > limit) {
        return const BackupImportResult.failed(
          'This backup exceeds the 50 MB import limit.',
        );
      }
      final stream =
          selected.readStream ??
          (selected.bytes != null
              ? Stream.value(selected.bytes!)
              : selected.path != null
              ? File(selected.path!).openRead()
              : null);
      if (stream == null) {
        return const BackupImportResult.failed(
          'The selected file could not be read. Save a local copy and select it again.',
        );
      }
      final buffer = BytesBuilder(copy: false);
      await for (final chunk in stream) {
        if (buffer.length + chunk.length > limit) {
          return const BackupImportResult.failed(
            'This backup exceeds the 50 MB import limit.',
          );
        }
        buffer.add(chunk);
      }
      bytes = buffer.takeBytes();
    } catch (_) {
      return const BackupImportResult.failed(
        'The backup file could not be opened. Download it to this device and select it again.',
      );
    } finally {
      if (pickedPath != null) {
        await const PrivateFileCleanup().removePickedBackup(pickedPath);
      }
    }
    if (bytes.isEmpty) {
      return const BackupImportResult.failed(
        'This backup file is empty. Choose the original backup file.',
      );
    }
    var password = '';
    if (!BackupSnapshot.isPlaintextDatabase(bytes)) {
      final entered = await requestPassword();
      if (entered == null) return const BackupImportResult.cancelled();
      password = entered;
    }
    try {
      await (snapshot ?? BackupSnapshot()).restore(
        bytes,
        password,
        onProgress: onProgress,
      );
      return const BackupImportResult.success();
    } on BackupRestoreException catch (e) {
      return BackupImportResult.failed(e.message);
    } on FormatException {
      return const BackupImportResult.failed(
        'This backup contains damaged, incomplete or incompatible records. Your current data was not replaced.',
      );
    } catch (_) {
      return const BackupImportResult.failed(
        'The backup could not be restored. It may be incomplete or from an unsupported format. Your current data was not replaced.',
      );
    }
  }
}
