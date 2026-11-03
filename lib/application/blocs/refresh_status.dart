/// Loaded data remains usable while a same-scope refresh runs or fails.
abstract interface class RefreshStatus {
  bool get refreshing;
  String? get refreshError;
}
