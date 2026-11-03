import 'dart:async';

/// A timeout stops waiting, never closes a native session that is still running.
/// Further work fails fast until the original native operation finishes.
class InferenceQueue {
  final Duration timeout;
  InferenceQueue({this.timeout = const Duration(seconds: 20)});
  Future<void> _tail = Future.value();
  bool _quarantined = false;
  Future<T> run<T>(Future<T> Function() action) {
    if (_quarantined) {
      return Future.error(StateError('Inference is still finishing'));
    }
    final result = _tail.then((_) => action());
    _tail = result.then<void>(
      (_) {
        _quarantined = false;
      },
      onError: (Object _, StackTrace __) {
        _quarantined = false;
      },
    );
    return result.timeout(
      timeout,
      onTimeout: () {
        _quarantined = true;
        throw TimeoutException('Inference exceeded its time budget');
      },
    );
  }

  Future<T> cleanup<T>(Future<T> Function() action) {
    final result = _tail.then((_) => action());
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return result;
  }
}
