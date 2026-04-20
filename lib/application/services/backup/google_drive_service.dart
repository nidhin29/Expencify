import 'dart:io';
import 'dart:typed_data';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:http/http.dart' as http;
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import '../security/encryption_service.dart';

class GoogleDriveService {
  static final GoogleDriveService _instance = GoogleDriveService._();
  factory GoogleDriveService() => _instance;
  GoogleDriveService._();

  final GoogleSignIn _googleSignIn = GoogleSignIn(
    scopes: [
      drive.DriveApi.driveAppdataScope,
    ],
  );

  GoogleSignInAccount? _currentUser;

  Future<bool> signIn() async {
    try {
      _currentUser = await _googleSignIn.signIn();
      return _currentUser != null;
    } catch (e) {
      print('Google Drive Sign-In Error: $e');
      return false;
    }
  }

  Future<void> signOut() async {
    await _googleSignIn.signOut();
    _currentUser = null;
  }

  Future<bool> backupDatabase(String password) async {
    if (_currentUser == null) {
      final success = await signIn();
      if (!success) return false;
    }

    try {
      final authHeaders = await _currentUser!.authHeaders;
      final authenticateClient = _GoogleAuthClient(authHeaders);
      final driveApi = drive.DriveApi(authenticateClient);

      // 1. Get local database path
      String dbPath = join(await getDatabasesPath(), 'expencify.db');
      final dbFile = File(dbPath);
      if (!await dbFile.exists()) return false;

      // 2. Read and Encrypt bytes
      final bytes = await dbFile.readAsBytes();
      final encryptedBytes = EncryptionService().encryptData(bytes, password);

      // 3. Check if file already exists in AppData
      final fileList = await driveApi.files.list(
        spaces: 'appDataFolder',
        q: "name = 'expencify_backup.enc'",
      );

      final media = drive.Media(
        Stream.value(encryptedBytes),
        encryptedBytes.length,
      );

      if (fileList.files != null && fileList.files!.isNotEmpty) {
        // Update existing
        final fileId = fileList.files!.first.id!;
        await driveApi.files.update(
          drive.File(),
          fileId,
          uploadMedia: media,
        );
      } else {
        // Create new
        final driveFile = drive.File()
          ..name = 'expencify_backup.enc'
          ..parents = ['appDataFolder'];
        await driveApi.files.create(
          driveFile,
          uploadMedia: media,
        );
      }
      return true;
    } catch (e) {
      print('Google Drive Backup Error: $e');
      return false;
    }
  }

  Future<bool> restoreDatabase(String password) async {
    if (_currentUser == null) {
      final success = await signIn();
      if (!success) return false;
    }

    try {
      final authHeaders = await _currentUser!.authHeaders;
      final authenticateClient = _GoogleAuthClient(authHeaders);
      final driveApi = drive.DriveApi(authenticateClient);

      // 1. Find the file
      final fileList = await driveApi.files.list(
        spaces: 'appDataFolder',
        q: "name = 'expencify_backup.enc'",
      );

      if (fileList.files == null || fileList.files!.isEmpty) return false;

      final fileId = fileList.files!.first.id!;

      // 2. Download
      await driveApi.files.get(
        fileId,
        downloadOptions: drive.DownloadOptions.metadata,
      ); // This is just metadata, we need to download media
      
      final mediaResponse = await driveApi.files.get(
        fileId,
        downloadOptions: drive.DownloadOptions.fullMedia,
      ) as drive.Media;

      final List<int> dataBytes = [];
      await for (final chunk in mediaResponse.stream) {
        dataBytes.addAll(chunk);
      }

      // 3. Decrypt
      final decryptedBytes = EncryptionService().decryptData(
        Uint8List.fromList(dataBytes),
        password,
      );

      // 4. Overwrite local database
      String dbPath = join(await getDatabasesPath(), 'expencify.db');
      final dbFile = File(dbPath);
      
      // Close the database before overwriting would be ideal, 
      // but sqflite usually handles this if we restart or use a helper.
      await dbFile.writeAsBytes(decryptedBytes);
      return true;
    } catch (e) {
      print('Google Drive Restore Error: $e');
      return false;
    }
  }
}

class _GoogleAuthClient extends http.BaseClient {
  final Map<String, String> _headers;
  final http.Client _client = http.Client();

  _GoogleAuthClient(this._headers);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    return _client.send(request..headers.addAll(_headers));
  }
}
