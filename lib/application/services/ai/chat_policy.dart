/// Chat is restricted to describing saved records and fixed app help.
/// This is a conservative allowlist, not a general-purpose safety classifier.
class ChatPolicy {
  static String normalizedQuestion(String value) {
    // Discourse markers change the conversational tone, not the requested
    // operation. Only strip them before a request; preserve names and subjects.
    final text = _normalize(value).replaceFirst(
      RegExp(
        r'^(?:(?:so|well|okay|ok|then|alright) )+(?=(?:what|how|where|which|when|why|is|are|can|could|show|list|compare|tell|give|find)\b)',
      ),
      '',
    );
    return switch (text) {
      'total spending' ||
      'total expenses' ||
      'spending total' ||
      'overall spending' => 'what is my spending all time',
      'total income' || 'income total' => 'what is my income all time',
      _ => text,
    };
  }

  static String? socialReply(String value) => switch (_normalize(value)) {
    'hi' ||
    'hello' ||
    'hey' ||
    'good morning' ||
    'good evening' => 'Hi! What would you like to check in your saved records?',
    'thanks' || 'thank you' => 'You’re welcome.',
    _ => null,
  };
  static const monthNamePattern =
      r'(?:jan(?:uary)?|feb(?:ruary)?|mar(?:ch)?|apr(?:il)?|may|jun(?:e)?|jul(?:y)?|aug(?:ust)?|sep(?:tember)?|sept(?:ember)?|oct(?:ober)?|nov(?:ember)?|dec(?:ember)?)';
  static const periodPattern =
      r'(?:today|yesterday|this month|last month|this week|last week|this year|last year|all time|(?:in |during |for )?'
      '$monthNamePattern'
      r'(?: (?:19|20)[0-9]{2})?)';
  static const adviceReply =
      'Spendy does not provide financial or investment advice. I can help you review your recorded transactions and balances.';
  static const scopeReply =
      'I can help with your recorded spending, income, balances and budgets, or explain how to use Spendy.';
  static const safetyReply =
      'I can only help review saved transactions or use Spendy.';
  static String _normalize(String value) => value
      .toLowerCase()
      .replaceAll(RegExp(r'[\u200B-\u200F\u202A-\u202E\u2060\uFEFF]'), '')
      .replaceAll(RegExp(r'[^a-z0-9\s]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  static final _unsafe = RegExp(
    r'\b(?:hack(?:ing)?|phish(?:ing)?|malware|ransomware|steal|stolen|fraud|scam|launder(?:ing)?|exploit|bypass|forge|forgery|evade|weapon|bomb|poison|kill|hurt|suicide|self harm|password|otp|pin|cvv|seed phrase|private key|api key|system prompt|jailbreak|roleplay)\b|\b(?:ignore|override|forget)\b.{0,50}\b(?:instructions|rules|policy|previous|system)\b',
  );
  static final _investing = RegExp(
    r'\b(?:invest|investing|investments?|stocks?|shares?|mutual funds?|sip|crypto(?:currency)?|bitcoin|ethereum|trading|portfolio|asset allocation|tax(?:es)?|financial advice|retirement(?: plan(?:ning)?)?|loans?|insurance|guaranteed returns?)\b',
  );
  static final _advice = RegExp(
    r'\b(?:can|could|should) i (?:afford|invest|borrow|buy|spend)\b|\bhow (?:can|could|should|do|to)\b.{0,60}\b(?:save|invest|reduce|cut|grow|borrow)\b|\b(?:best|profitable|safe)\b.{0,40}\b(?:loan|insurance|fund|investment|stock|crypto)\b|\b(?:reduce|cut|optimize)\b.{0,30}\b(?:spending|expenses|tax)\b',
  );
  static final _outputAdvice = RegExp(
    r'\b(?:you should|you must|i recommend|i suggest|i advise|consider|try reducing|try cutting|cut back|spend less|save more|reduce your|cut your|avoid spending|limit your spending|save money|saving money|take out a loan|buy shares|sell shares|diversify)\b',
  );
  static final _facts = RegExp(
    r'^(?:(?:what|how much) (?:did|have) i (?:spend|spent|earn|earned|receive|received|save|saved)|'
    r'what (?:is|was|are|were) my (?:balance|income|expenses|spending|budget|budgets|savings)|'
    r'show(?: me)?(?: my)?(?: recent)? (?:transactions|payments|expenses|income|spending|balance|budgets|savings)|'
    r'where did my money go|which category did i spend (?:the )?most on|'
    r'help me understand my recent spending|summari[sz]e my (?:spending|transactions|expenses|income)|'
    r'(?:and|what about) (?:my )?(?:income|expenses|balance|budgets|savings))'
    r'(?:(?: '
    '$periodPattern'
    r')?'
    r'(?: (?:on|for) (?:food|fuel|shopping|rent|travel|health|bills|grocery|groceries|transport|entertainment))?'
    r'| (?:on|for) (?:food|fuel|shopping|rent|travel|health|bills|grocery|groceries|transport|entertainment)'
    r'(?: '
    '$periodPattern'
    r')?)$',
  );

  static String? unsafeOrAdviceReply(String query) {
    final text = _normalize(query);
    if (_unsafe.hasMatch(text)) return safetyReply;
    final investmentText =
        RegExp(
          r'\b(?:merchant|category|spending|expenses|income|payments|transactions)\b',
        ).hasMatch(text)
        ? text.replaceAll(RegExp(r'\bshares?\b'), '')
        : text;
    if (_investing.hasMatch(investmentText) || _advice.hasMatch(text)) {
      return adviceReply;
    }
    return null;
  }

  /// A non-null reply is returned directly without asking the model or reading records.
  static String? requestReply(String query) {
    // Unknown scripts/encodings must not disappear into an otherwise allowed query.
    if (RegExp(r'[^\x00-\x7F₹’‘“”…–—]').hasMatch(query)) return scopeReply;
    final text = normalizedQuestion(query);
    final refusal = unsafeOrAdviceReply(query);
    if (refusal != null) return refusal;
    final social = socialReply(query);
    if (social != null) return social;
    if (RegExp(
      r'^(?:what can you do|help|what is this chat for)$',
    ).hasMatch(text)) {
      return scopeReply;
    }
    if (RegExp(
      r'^(?:how to use spendy|how (?:do|can) i use spendy|how does spendy work)$',
    ).hasMatch(text)) {
      return 'Use Add to record a transaction, then review it in Transactions. '
          'For automatic tracking, enable Track bank SMS in Settings and add your bank and last four account digits. '
          'Use Budget for spending limits, Goals for savings progress, and Payments for due-date reminders.';
    }
    if (RegExp(
      r'^how (?:do|can) i (?:add|record) (?:a )?transaction$',
    ).hasMatch(text)) {
      return 'Tap Add, enter the transaction details, then save.';
    }
    if (RegExp(
      r'^how (?:do|can) i (?:edit|correct) (?:a )?transaction$',
    ).hasMatch(text)) {
      return 'Open a transaction in Transactions and choose Edit.';
    }
    if (RegExp(
      r'^how (?:do|can) i (?:enable|turn on) (?:bank )?sms(?: tracking)?$',
    ).hasMatch(text)) {
      return 'Open Settings, then turn on Track bank SMS and complete bank setup.';
    }
    if (RegExp(
      r'^how (?:do|can) i (?:enable|turn on|improve) (?:improved )?search$',
    ).hasMatch(text)) {
      return 'In Transactions, open Search options and choose Improve search.';
    }
    if (!_facts.hasMatch(text)) return scopeReply;
    return null;
  }

  static String? responseReply(String response) {
    final text = _normalize(response);
    if (_unsafe.hasMatch(text)) return safetyReply;
    if (_investing.hasMatch(text) ||
        _advice.hasMatch(text) ||
        _outputAdvice.hasMatch(text)) {
      return adviceReply;
    }
    return null;
  }
}
