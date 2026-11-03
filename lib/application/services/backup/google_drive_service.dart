import 'backup_restore_exception.dart';
import 'backup_progress.dart';
import 'dart:typed_data';
import 'backup_snapshot.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:http/http.dart' as http;

class GoogleDriveService {
  static final GoogleDriveService _instance = GoogleDriveService._();
  factory GoogleDriveService() => _instance;
  GoogleDriveService._();

  final GoogleSignIn _googleSignIn = GoogleSignIn(
    scopes: [drive.DriveApi.driveAppdataScope],
  );

  GoogleSignInAccount? _currentUser;

  Future<String?> signIn() async {
    try {
      _currentUser = await _googleSignIn.signIn();
      return _currentUser != null ? null : 'Sign-in was cancelled or failed.';
    } catch (e) {
      return 'Could not sign in to Google Drive. Please try again.';
    }
  }

  Future<void> signOut() async {
    await _googleSignIn.signOut();
    _currentUser = null;
  }

  Future<String?> backupDatabase(
    String password, {
    BackupProgressCallback? onProgress,
  }) async {
    if (_currentUser == null) {
      final error = await signIn();
      if (error != null) return error;
    }

    _GoogleAuthClient? authenticateClient;
    try {
      final authHeaders = await _currentUser!.authHeaders;
      authenticateClient = _GoogleAuthClient(authHeaders);
      final driveApi = drive.DriveApi(authenticateClient);

      final encryptedBytes = await BackupSnapshot().create(
        password,
        onProgress: onProgress,
      );

      reportBackupProgress(onProgress, BackupStage.uploading);
      // 3. Check if file already exists in AppData
      final fileList = await driveApi.files.list(
        spaces: 'appDataFolder',
        q: "name = 'spendy_backup.enc'",
      );

      final media = drive.Media(
        Stream.value(encryptedBytes),
        encryptedBytes.length,
      );

      if (fileList.files != null && fileList.files!.isNotEmpty) {
        // Update existing
        final fileId = fileList.files!.first.id!;
        await driveApi.files.update(drive.File(), fileId, uploadMedia: media);
      } else {
        // Create new
        final driveFile = drive.File()
          ..name = 'spendy_backup.enc'
          ..parents = ['appDataFolder'];
        await driveApi.files.create(driveFile, uploadMedia: media);
      }
      return null;
    } catch (e) {
      return 'Check your connection and Google Drive access, then try again.';
    } finally {
      authenticateClient?.close();
    }
  }

  Future<String?> restoreDatabase(
    String password, {
    BackupProgressCallback? onProgress,
  }) async {
    if (_currentUser == null) {
      final error = await signIn();
      if (error != null) return error;
    }

    _GoogleAuthClient? authenticateClient;
    try {
      final authHeaders = await _currentUser!.authHeaders;
      authenticateClient = _GoogleAuthClient(authHeaders);
      final driveApi = drive.DriveApi(authenticateClient);

      // 1. Find the file
      final fileList = await driveApi.files.list(
        spaces: 'appDataFolder',
        q: "name = 'spendy_backup.enc'",
      );

      if (fileList.files == null || fileList.files!.isEmpty) {
        return 'No backup file found in Google Drive.';
      }

      final fileId = fileList.files!.first.id!;

      final mediaResponse =
          await driveApi.files.get(
                fileId,
                downloadOptions: drive.DownloadOptions.fullMedia,
              )
              as drive.Media;

      reportBackupProgress(onProgress, BackupStage.downloading);
      final dataBytes = BytesBuilder(copy: false);
      await for (final chunk in mediaResponse.stream) {
        dataBytes.add(chunk);
        if (dataBytes.length > BackupSnapshot.maxBytes + 1024) {
          throw const FormatException('Backup too large.');
        }
      }

      await BackupSnapshot().restore(
        dataBytes.takeBytes(),
        password,
        onProgress: onProgress,
      );
      return null;
    } on BackupRestoreException catch (error) {
      return error.message;
    } catch (e) {
      return 'The backup could not be restored. Check your connection and passphrase. Your current data was not replaced.';
    } finally {
      authenticateClient?.close();
    }
  }
}

class _GoogleAuthClient extends http.BaseClient {
  final Map<String, String> _headers;
  final http.Client _client = http.Client();

  _GoogleAuthClient(this._headers);

  @override
  void close() {
    _client.close();
    super.close();
  }

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    return _client.send(request..headers.addAll(_headers));
  }
}
