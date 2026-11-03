/// User-safe diagnostics; native errors can contain database paths or SQL values.
class BackupRestoreException extends FormatException {
  const BackupRestoreException(super.message);
}
