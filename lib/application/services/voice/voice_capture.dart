/// Recognition lifecycle used by voice entry; stop preserves a final result,
/// while cancel discards it.
abstract interface class VoiceCapture {
  Future<bool> startListening(
    void Function(String) onResult, {
    void Function(String)? onPartial,
    void Function(String)? onError,
    void Function()? onStopped,
  });
  Future<void> stopListening();
  Future<void> cancelListening();
}
