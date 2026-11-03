/// App status text is displayed to the user but is not a model-authored answer.
/// The legacy entries keep already-saved failed turns out of future prompts.
class ChatReplyStatus {
  static const socialFailure =
      'I could not complete that reply. Please try again.';
  static const scopeReply =
      'That topic is outside Spendy’s scope. I can help with your saved records or app questions.';
  static const boundaryReply =
      'You’re right—Spendy should stay focused on your saved records and app questions.';

  static bool isStatus(String text) {
    final value = text.trim();
    return const {
          scopeReply,
          boundaryReply,
          'I’m here. What would you like to talk about?',
          'I can help with your saved records, this conversation and using Spendy.',
          'I can help with your saved records and using Spendy.',
        }.contains(value) ||
        value.startsWith('I could not complete') ||
        value.startsWith('I could not reliably interpret') ||
        value.startsWith('Couldn’t get an answer.') ||
        value.startsWith('AI is processing') ||
        value.startsWith('This question needs offline AI') ||
        value.startsWith(
          'What would you like to know about your saved records?',
        ) ||
        value.startsWith(
          'I can help with your recorded spending, income, balances and budgets',
        );
  }
}
