import 'chat_policy.dart';

/// Authoritative app instructions, shared by direct help and model-selected
/// topics. Generated prose cannot invent routes or app capabilities.
class ChatHelpCatalog {
  static const capabilities =
      'I can summarize your saved spending and income, compare periods, check balances, budgets and savings goals, and help you use Spendy. '
      'I don’t provide financial or investment advice.';

  static const instructions = <String, String>{
    'capabilities': capabilities,
    'overview':
        'Use Add for entries, Transactions to review records, Budget for spending limits, and Accounts for bank accounts or wallets. More tools contains Goals and Payments. Settings contains SMS tracking and backups.',
    'sms':
        'In Settings, enable Track bank SMS. Add your bank and last four account digits, then allow SMS access.',
    'backup':
        'In Settings, choose Create backup file or Back up to Google Drive. Keep your backup passphrase to restore it later.',
    'budget':
        'Open Budget and tap Add to set a category limit. Spending updates are available in Settings.',
    'goals':
        'Open More tools, then Goals. Add a target and record contributions to track progress.',
    'payments':
        'Open More tools, then Payments. Add a due date and optional recurrence. Mark the item Done when handled.',
    'export':
        'In Settings, open Export reports. Choose filters and CSV or PDF, select the records, then share the report. CSV and PDF are readable reports; restoring the app requires a backup file.',
    'search':
        'Search in Transactions. Search options lets you enable offline search by meaning.',
    'transactions':
        'Use Add to record a transaction. In Transactions, open a record to edit or correct it.',
  };

  static List<String> topics(String question) => [
    for (final entry in const {
      'sms': r'\bsms\b|\b(?:bank|text) messages?\b',
      'backup': r'\b(?:backup|restore|drive)\b',
      'budget': r'\bbudgets?\b',
      'goals': r'\bgoals?\b',
      'payments': r'\b(?:payments?|reminders?)\b',
      'export': r'\b(?:export|csv|pdf)\b',
      'search': r'\bsearch\b',
      'transactions': r'\btransactions?\b',
    }.entries)
      if (RegExp(entry.value, caseSensitive: false).hasMatch(question))
        entry.key,
  ];

  static String? direct(String question, {required bool hasHelpContext}) {
    if (isCapabilityRequest(question)) return capabilities;
    final selected = topics(question);
    if (selected.length != 1) return null;
    if (selected.single == 'budget' &&
        RegExp(
          r'^(?:how (?:do|can|to)|edit|change|update)\b',
          caseSensitive: false,
        ).hasMatch(question) &&
        RegExp(
          r'\b(edit|change|update)\b',
          caseSensitive: false,
        ).hasMatch(question)) {
      return 'Open Budget, tap the budget you want to edit, update its details, then save.';
    }
    // Procedure questions and explicit answers to a feature clarification are
    // app help. Financial read requests continue to the verified query engine.
    final procedure = RegExp(
      r'\b(?:enable|activate|set up|turn on|switch on|configure|how (?:to|do i|can i) (?:use|add|create|edit|restore|export))\b',
      caseSensitive: false,
    ).hasMatch(question);
    final clarification =
        hasHelpContext &&
        RegExp(
          r'^(?:i mean|i meant|the|that|it s)\b',
          caseSensitive: false,
        ).hasMatch(question);
    return procedure || clarification ? instructions[selected.single] : null;
  }

  /// Explicit navigation names an app capability, rather than a ledger read.
  /// Keep feature instructions owned by the catalog, independent of the model.
  static String? requestedTopic(String question) {
    if (isCapabilityRequest(question)) return 'capabilities';
    final selected = topics(question);
    if (selected.length != 1) return null;
    final navigation = RegExp(
      r'\bwhere (?:do|can|could|should) (?:i|we)\b|'
      r'\bhow (?:do|can|could|should) (?:i|we) (?:use|add|create|edit|restore|export|download|enable|activate|set up|turn on|switch on|configure|find|open|get)\b|'
      r'\bhow to (?:use|add|create|edit|restore|export|download|enable|activate|configure|find|open|get)\b|'
      r'\b(?:can|does|will) (?:this|that|it|the app|spendy) (?:also )?(?:let|allow|support)\b',
      caseSensitive: false,
    ).hasMatch(question);
    return navigation ? selected.single : null;
  }

  /// Self-description comes from app metadata, never from invented services.
  /// These are capability-request forms, not financial read commands.
  static bool isCapabilityRequest(String question) {
    final q = ChatPolicy.normalizedQuestion(question).replaceFirst(
      RegExp(r'^(?:please |can you (?:please )?tell me |tell me )'),
      '',
    );
    const assistant = r'(?:you|spendy|this app|this assistant|this chat)';
    return RegExp(
      r'^(?:help|what is this chat for|'
      'what (?:can|could) $assistant (?:do|help(?: me|us)? with|offer|support)(?: for (?:me|us)| here)?|'
      'how (?:can|could) $assistant help(?: me|us)?|'
      r'what (?:are|is) (?:your|spendy s|this app s) (?:capabilities|features|functions|purpose|role)|'
      r'what are you (?:capable of|able to do)|'
      r'(?:describe|explain|show) (?:me )?(?:your|spendy s|this app s) (?:capabilities|features|functions)|'
      r'what (?:features|capabilities|functions) (?:do you have|does spendy have|are available|are supported))$',
    ).hasMatch(q);
  }
}
