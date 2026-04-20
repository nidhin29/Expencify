import 'dart:io';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import 'package:share_plus/share_plus.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:expencify/infrastructure/database/database_helper.dart';

class BackupService {
  static const String _backupExtension = '.expencify';

  /// Exports the current database to a shared file.
  Future<bool> exportBackup() async {
    try {
      final dbPath = join(await getDatabasesPath(), 'expencify.db');
      final dbFile = File(dbPath);

      if (!await dbFile.exists()) return false;

      // Create a temporary file with our custom extension for sharing
      final tempDir = await getTemporaryDirectory();
      final backupPath = join(
        tempDir.path,
        'expencify_backup_${DateTime.now().millisecondsSinceEpoch}$_backupExtension',
      );

      await dbFile.copy(backupPath);

      await Share.shareXFiles(
        [XFile(backupPath)],
        subject: 'Expencify Data Backup',
        text: 'Your Expencify data backup file. Keep this safe!',
      );

      return true;
    } catch (e) {
      return false;
    }
  }

  /// Imports a backup file and replaces the current database.
  Future<bool> importBackup() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.any,
        // Using any because custom extensions can be tricky on some platforms
      );

      if (result == null || result.files.single.path == null) return false;

      final backupFile = File(result.files.single.path!);

      // Basic validation: ensure it's not a random large file
      if (await backupFile.length() > 50 * 1024 * 1024) {
        // 50MB limit
        return false;
      }

      // Close current database connection
      final dbHelper = DatabaseHelper();
      final db = await dbHelper.database;
      await db.close();

      // Replace the database file
      final dbPath = join(await getDatabasesPath(), 'expencify.db');
      await backupFile.copy(dbPath);

      return true;
    } catch (e) {
      return false;
    }
  }
}
