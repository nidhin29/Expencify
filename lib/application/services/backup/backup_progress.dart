enum BackupStage {
  readingFile,
  readingData,
  collectingReceipts,
  encoding,
  encrypting,
  uploading,
  downloading,
  decrypting,
  validating,
  restoringReceipts,
  savingData,
  schedulingReminders,
  readyToShare,
}

class BackupProgress {
  final BackupStage stage;
  final int? completed;
  final int? total;
  const BackupProgress(this.stage, {this.completed, this.total});
  double? get fraction => total != null && total! > 0 && completed != null
      ? (completed! / total!).clamp(0, 1)
      : null;
  String get label => switch (stage) {
    BackupStage.readingFile => 'Reading backup file…',
    BackupStage.readingData => 'Reading your data…',
    BackupStage.collectingReceipts => 'Collecting receipts…',
    BackupStage.encoding => 'Preparing backup…',
    BackupStage.encrypting => 'Protecting your backup…',
    BackupStage.uploading => 'Uploading to Google Drive…',
    BackupStage.downloading => 'Downloading your backup…',
    BackupStage.decrypting => 'Unlocking your backup…',
    BackupStage.validating => 'Checking the backup…',
    BackupStage.restoringReceipts => 'Restoring receipts…',
    BackupStage.savingData => 'Saving your data…',
    BackupStage.schedulingReminders => 'Updating reminders…',
    BackupStage.readyToShare => 'Opening sharing options…',
  };
}

typedef BackupProgressCallback = void Function(BackupProgress progress);
void reportBackupProgress(
  BackupProgressCallback? callback,
  BackupStage stage, {
  int? completed,
  int? total,
}) {
  try {
    callback?.call(BackupProgress(stage, completed: completed, total: total));
  } catch (_) {
    /* A UI observer must never interrupt an atomic restore. */
  }
}
