import 'package:expencify/infrastructure/database/database_helper.dart';

class SmsParserService {
  /// Parses a bank SMS and returns extracted data or null if not a valid bank SMS.
  static Future<Map<String, dynamic>?> parseSms(String sms) async {
    final text = sms.toLowerCase();

    // 1. Initial filter for bank keywords
    if (!_isBankSms(text)) return null;

    // 2. Filter out informational alerts (Avg. bal, OTP, etc.)
    if (_isInformationalAlert(text)) return null;

    // 3. Marketing Shield
    if (_isMarketing(text)) return null;

    // 4. Extract transaction type (Stricter: requires debit/credit keywords)
    final type = _extractType(text);
    if (type == null) return null;

    final amount = _extractAmount(sms, type);
    if (amount == null) return null;

    final merchant = _extractMerchant(sms);
    final account = _extractAccount(sms);
    final lastFour = extractLastFourDigits(sms);
    final balance = _extractBalance(sms);

    return {
      'amount': amount,
      'type': type,
      'merchant': merchant ?? '',
      'account': account ?? '',
      'lastFour': lastFour ?? '',
      'balance': balance,
    };
  }

  static bool needsReview(String sms) {
    final text = sms.toLowerCase();
    return _isBankSms(text) &&
        !_isInformationalAlert(text) &&
        !_isMarketing(text) &&
        _completedActions(text).isNotEmpty;
  }

  /// Extracts just the last 4 digits of account/card from an SMS.
  /// Used to match an SMS to a known account in the DB.
  static String? extractLastFourDigits(String sms) {
    final patterns = [
      // Matches "A/c ends 123", "A/c no. 1234", "A/cXXXXXXXX1234", "card *12"
      RegExp(
        r'(?:a\/c|acct|account|card)\s*(?:number|no\.?|ending|ends|with|in|is|:|#|\.)*\s*(?:ending|ends|no|num)?[\s*x.-]*([0-9]{2,6})',
        caseSensitive: false,
      ),
      // Matches "XX1234", "****123", "X1234" standalone
      RegExp(r'(?:[x*]{2,})[\s-]*([0-9]{2,6})', caseSensitive: false),
      // Only account-ending language; generic 'reference no' is not an account.
      RegExp(
        r'\b(?:ends?|ending)\s+(?:in|with)\s*([0-9]{2,6})(?![0-9])',
        caseSensitive: false,
      ),
    ];
    for (final p in patterns) {
      final m = p.firstMatch(sms);
      if (m != null) return m.group(1);
    }
    return null;
  }

  static bool _isMarketing(String text) {
    // A URL is neither necessary nor sufficient to identify an offer. Completed
    // transaction alerts can contain a support link or a promotional footer.
    if (_completedActions(text).isNotEmpty) return false;
    return RegExp(
      r'\b(?:welcome\s+bonus|offer|apply\s+now|eligible|congratulations|voucher|win|earn|cashback|up\s*to|first\s+(?:load|recharge|purchase)|get\s+\d+\s*%)\b|ഓഫർ|സ്വന്തമാക്കൂ|ക്ലിക്ക്',
      caseSensitive: false,
    ).hasMatch(text);
  }

  static bool _isInformationalAlert(String text) {
    if (RegExp(
      r'\b(?:otp|one[- ]time\s+(?:password|code)|verification\s+code)\b',
      caseSensitive: false,
    ).hasMatch(text)) {
      return true;
    }
    // Failure, negation and pending states never authorize a ledger write.
    if (RegExp(
      r"\b(?:failed|declined|unsuccessful|pending|scheduled|requested)\b",
      caseSensitive: false,
    ).hasMatch(text)) {
      return true;
    }
    if (_completedActions(text).isNotEmpty) return false;
    return RegExp(
      r'\b(?:otp|one[- ]time\s+(?:password|code)|verification\s+code|login|password|statement|kyc|minimum\s+balance|avg\.?\s*bal|amount\s+due|payment\s+due|will\s+be|due\s+on)\b',
      caseSensitive: false,
    ).hasMatch(text);
  }

  /// The Precision Dictionary: Global keywords for transaction types.
  static final Map<String, List<String>> _dictionary = {
    'income': [
      // English
      'credited',
      'received',
      'deposited',
      'refund',
      'reversed',
      'salary',
      'cashback',
      'income',
      // Malayalam
      'ജമ', 'ക്രെഡിറ്റ്', 'കൂട്ടിച്ചേർത്തു', 'നൽകി',
      // Hindi
      'जमा', 'प्राप्त', 'मिला', 'क्रेडिट',
      // Marathi
      'जमा झाले', 'क्रेडिट झाले',
      // Bengali
      'জমা হয়েছে', 'ক্রেডিট',
      // Telugu
      'క్రెడిట్', 'జమ',
      // Kannada
      'ಜಮೆಯಾಗಿದೆ', 'ಕ್ರೆಡಿಟ್',
      // Gujarati
      'ક્રેડિટ થયા', 'જમા',
      // Punjabi
      'ਕ੍ਰੈਡਿਟ ਹੋਏ', 'ਜਮ੍ਹਾ',
      // Odia
      'କ୍ରେଡିଟ୍', 'ଜମା',
      // Arabic
      'دائن', 'إضافة', 'تم إيداع',
      // Spanish
      'acreditado', 'abonado', 'recibido',
      // French
      'crédité', 'reçu',
    ],
    'expense': [
      // English
      'debited',
      'spent',
      'paid',
      'deducted',
      'withdrawn',
      'payment',
      'purchase',
      'sent',
      'transferred',
      'bill',
      // Malayalam
      'പിൻവലിച്ചു', 'ഡെബിറ്റ്', 'നൽകി', 'നഷ്ടപ്പെട്ടു',
      // Hindi
      'निकाला', 'काटा गया', 'डेबिट', 'भुगतान', 'खर्च',
      // Marathi
      'नावे झाले', 'डेबिट झाले', 'खर्च',
      // Bengali
      'ডেবিট', 'খরচ',
      // Telugu
      'డెబిట్', 'ఖర్చు',
      // Kannada
      'ಡೆಬಿಟ್', 'ಖರ್ಚು',
      // Gujarati
      'ડેબિટ થયા', 'ખર્ચ',
      // Punjabi
      'ਡੈਬਿਟ ਹੋਏ', 'ਖ਼ਰਚ',
      // Odia
      'ଡେବିଟ୍', 'ଖର୍ଚ୍ଚ',
      // Arabic
      'مدين', 'خصم', 'تم سحب',
      // Spanish
      'debitado', 'cargado', 'pagado', 'gasto',
      // French
      'débité', 'payé', 'dépense',
    ],
  };

  static bool _isBankSms(String text) {
    // Universal triggers that appear in almost any financial alert
    final universalTriggers = [
      'txn',
      'transaction',
      'upi',
      'neft',
      'imps',
      'rtgs',
      'atm',
      'a/c',
      'acct',
      'account',
      'inr',
      '₹',
      'rs.',
      're. ',
      'usd',
      '\$',
      'eur',
      '€',
      'gbp',
      '£',
      'aed',
      'sar',
      'balance',
      'bal:',
      'bal ',
      'avail',
      'limit',
    ];

    if (universalTriggers.any((k) => text.contains(k))) return true;

    // Check multilingual dictionary for a "nature of transaction" word
    for (final list in _dictionary.values) {
      if (list.any((k) => text.contains(k))) return true;
    }

    return false;
  }

  static List<({String type, int start, int end})> _completedActions(
    String text,
  ) {
    const weak = {
      'refund',
      'salary',
      'cashback',
      'income',
      'payment',
      'purchase',
      'bill',
      'നൽകി',
    };
    final actions = _accountPostingActions(text);
    for (final entry in _dictionary.entries) {
      for (final token in [
        ...entry.value,
        if (entry.key == 'income') 'refunded',
      ]) {
        if (weak.contains(token)) continue;
        final latin = RegExp(r'^[a-z ]+$').hasMatch(token);
        final pattern = RegExp(
          '${latin ? r"\b" : ""}${RegExp.escape(token)}${latin ? r"\b" : ""}',
          caseSensitive: false,
        );
        for (final match in pattern.allMatches(text)) {
          if (token == 'received' &&
              RegExp(
                r'^\s*(?:(?:an?|your)\s+)?(?:offer|otp|code|request|reminder|voucher|notification|message)\b',
                caseSensitive: false,
              ).hasMatch(text.substring(match.end))) {
            continue;
          }
          if (token == 'ക്രെഡിറ്റ്' &&
              RegExp(
                r'^\s*(?:കാർഡ്|ചെയ്യും|ആകും)',
              ).hasMatch(text.substring(match.end))) {
            continue;
          }
          final prefix = text.substring(
            match.start > 50 ? match.start - 50 : 0,
            match.start,
          );
          if (RegExp(
            r"\b(?:will|would|could|may|might|shall|can)\s+(?:not\s+)?(?:be\s+)?$|\b(?:not|never)\s+(?:been\s+)?$|\bto\s+be\s*$|\b(?:hasn't|wasn't|isn't)\s+(?:been\s+)?$",
            caseSensitive: false,
          ).hasMatch(prefix)) {
            continue;
          }
          if (RegExp(
            r'\b(?:get|earn|avail|eligible)\b[^!?;\n]{0,80}$',
            caseSensitive: false,
          ).hasMatch(prefix)) {
            continue;
          }
          actions.add((type: entry.key, start: match.start, end: match.end));
        }
      }
    }
    for (final match in RegExp(
      r'\b(?:payment|purchase)\b(?:[^.!?;\n]|\.(?=[0-9])){0,60}\b(?:successful|completed)\b',
      caseSensitive: false,
    ).allMatches(text)) {
      final prefix = text.substring(
        match.start > 30 ? match.start - 30 : 0,
        match.start,
      );
      if (!RegExp(
        r'\b(?:will|would|could|may|might|not|never|get|make|ensure)\b',
        caseSensitive: false,
      ).hasMatch('$prefix ${match.group(0)}')) {
        actions.add((type: 'expense', start: match.start, end: match.end));
      }
    }
    return actions;
  }

  /// Bank abbreviations describe a posting only when attached to an account.
  /// In "Dr. from A/C ... and Cr. to paytm...", the credit is the recipient's.
  static List<({String type, int start, int end})> _accountPostingActions(
    String text,
  ) {
    final actions = <({String type, int start, int end})>[];
    final posting = RegExp(
      r'\b(dr|cr)\.?\s+(from|to|into|in)\s+(?:(?:your|ur)\s+)?(?:a/c|acct|account|card)\b',
      caseSensitive: false,
    );
    for (final match in posting.allMatches(text)) {
      final marker = match.group(1)!.toLowerCase();
      final direction = match.group(2)!.toLowerCase();
      if ((marker == 'dr' && direction != 'from') ||
          (marker == 'cr' && direction == 'from')) {
        continue;
      }
      final prefix = text.substring(
        match.start > 50 ? match.start - 50 : 0,
        match.start,
      );
      if (RegExp(
        r"\b(?:will|would|could|may|might|shall|can)\s+(?:not\s+)?(?:be\s+)?$|\b(?:not|never)\s+(?:been\s+)?$|\bto\s+be\s*$",
        caseSensitive: false,
      ).hasMatch(prefix)) {
        continue;
      }
      actions.add((
        type: marker == 'dr' ? 'expense' : 'income',
        start: match.start,
        end: match.start + 2,
      ));
    }
    return actions;
  }

  static String? _extractType(String text) {
    final types = _completedActions(text).map((action) => action.type).toSet();
    // Mixed debit/credit messages need review; never prefer income just because
    // 'credited' appears somewhere in a debit alert.
    return types.length == 1 ? types.single : null;
  }

  static double? _extractAmount(String sms, String type) {
    final text = sms.toLowerCase();
    final actions = _completedActions(
      text,
    ).where((a) => a.type == type).toList();
    const number = r'(?:[0-9]{1,3}(?:,[0-9]{2,3})+|[0-9]+)(?:\.[0-9]{1,2})?';
    const currency =
        r'(?:(?<![a-z])(?:rs\.?|inr|usd|eur|gbp|aed|sar)(?![a-z])|₹|درهم|\$|€|£)';
    final patterns = [
      RegExp('$currency\\s*($number)(?![0-9,]|\\.[0-9])', caseSensitive: false),
      RegExp('(?<![0-9.,])($number)\\s*$currency', caseSensitive: false),
      RegExp(
        '\\b(?:amount|amt)[:\\s]+($number)(?![0-9,]|\\.[0-9])',
        caseSensitive: false,
      ),
    ];
    final candidates = <({double amount, int start, int end, int distance})>[];
    for (final pattern in patterns) {
      for (final match in pattern.allMatches(text)) {
        final amount = double.tryParse(match.group(1)!.replaceAll(',', ''));
        if (amount == null || !amount.isFinite || amount <= 0) continue;
        if (candidates.any((c) => match.start < c.end && match.end > c.start)) {
          continue;
        }
        final prefix = text.substring(
          match.start > 75 ? match.start - 75 : 0,
          match.start,
        );
        final suffix = text.substring(
          match.end,
          match.end + 25 < text.length ? match.end + 25 : text.length,
        );
        // Exclude balances, card limits, offers and numeric account identifiers.
        if (RegExp(
          r'\b(?:balance|bal|limit|outstanding|cashback\s+up\s+to|up\s*to|minimum|min)\b[^0-9;\n]{0,24}$',
          caseSensitive: false,
        ).hasMatch(prefix)) {
          continue;
        }
        if (RegExp(
          r'^\s*(?:is\s+)?(?:your\s+)?(?:available\s+)?(?:balance|limit)\b',
          caseSensitive: false,
        ).hasMatch(suffix)) {
          continue;
        }
        var distance = 100000;
        for (final action in actions) {
          final gap = action.end <= match.start
              ? match.start - action.end
              : action.start >= match.end
              ? action.start - match.end
              : 0;
          final between = action.end <= match.start
              ? text.substring(action.end, match.start)
              : action.start >= match.end
              ? text.substring(match.end, action.start)
              : '';
          // Do not associate amounts across another balance/offer clause.
          if (RegExp(r'[.!?;](?:\s|$)|\n').hasMatch(between)) continue;
          if (RegExp(
            r'\b(?:balance|bal|limit|up\s*to)\b',
            caseSensitive: false,
          ).hasMatch(between)) {
            continue;
          }
          if (gap < distance) distance = gap;
        }
        if (distance <= 80) {
          candidates.add((
            amount: amount,
            start: match.start,
            end: match.end,
            distance: distance,
          ));
        }
      }
    }
    if (candidates.isEmpty) return null;
    // Multiple distinct transaction values (fees, refunds, transfers, etc.) are
    // not safe to collapse into one amount without an explicit format rule.
    final amounts = candidates.map((c) => c.amount).toSet();
    return amounts.length == 1 ? amounts.single : null;
  }

  static String? _extractMerchant(String sms) {
    // List of common keywords that mark the end of a merchant name in bank SMS
    final stopWords = [
      'using',
      'on',
      'at',
      'towards',
      'info',
      'avl',
      'bal',
      'from',
    ];

    final patterns = [
      RegExp(
        r'(?:at|to|towards)\s+([A-Z][A-Z0-9\s\-&@]{2,30})',
        caseSensitive: false,
      ),
      RegExp(
        r'(?:merchant|mcc):\s*([A-Z][A-Z0-9\s\-&@]{2,25})',
        caseSensitive: false,
      ),
      RegExp(r'VPA\s+([a-zA-Z0-9._@-]+)'),
      RegExp(r'(?:info:?)\s+([A-Z][A-Z0-9\s]{2,20})', caseSensitive: false),
      // Fallback for Income transactions that use "from XYZ"
      RegExp(r'(?:from)\s+([A-Z][A-Z0-9\s\-&@]{2,30})', caseSensitive: false),
    ];
    for (final p in patterns) {
      final match = p.firstMatch(sms);
      if (match != null) {
        var m = match.group(1)!.trim();

        // Truncate at stop words using robust word boundaries
        for (final word in stopWords) {
          final stopRegex = RegExp('\\b$word\\b', caseSensitive: false);
          final stopMatch = stopRegex.firstMatch(m);
          if (stopMatch != null) {
            m = m.substring(0, stopMatch.start).trim();
          }
        }

        // 1. Aggressive newline stripping (dates often follow newlines)
        m = m.split('\n').first.trim();

        // 2. Aggressive cleanup for trailing date info like "On 26", "On 26/02"
        // Also handle cases where there's no space but a boundary
        m = m.replaceAll(
          RegExp(r'\s+on\s+\d+.*$', caseSensitive: false, multiLine: true),
          '',
        );
        m = m.replaceAll(
          RegExp(r'\s+on\s+[A-Z]{3}.*$', caseSensitive: false, multiLine: true),
          '',
        );

        if (m.isNotEmpty && !_isNoise(m)) return m.split('.').first.trim();
      }
    }
    return null;
  }

  static String? _extractAccount(String sms) {
    final p = RegExp(
      r'(?:a\/c|acct|account)[.:\s#]+(?:ending\s+)?(?:x+)?([0-9]{4})',
      caseSensitive: false,
    );
    final match = p.firstMatch(sms);
    return match != null ? 'XX${match.group(1)}' : null;
  }

  static double? _extractBalance(String sms) {
    final p = RegExp(
      r'(?:avl\.?|available|bal\.?|balance)[:\s]+(?:rs\.?|inr|₹)?\s*([0-9,]+(?:\.[0-9]{1,2})?)',
      caseSensitive: false,
    );
    final match = p.firstMatch(sms);
    if (match == null) return null;
    return double.tryParse(match.group(1)!.replaceAll(',', ''));
  }

  static bool _isNoise(String s) {
    final noise = [
      'your',
      'bank',
      'upi',
      'from',
      'avl',
      'balance',
      'info',
      'ref',
      'neft',
      'imps',
      'txn',
      'using',
    ];
    final lower = s.toLowerCase();

    // Use word boundaries so that containing words (e.g. "okfcbank") aren't treated as noise
    return noise.any((n) {
      final regex = RegExp('\\b${RegExp.escape(n)}\\b', caseSensitive: false);
      return regex.hasMatch(lower);
    });
  }

  /// Applies Smart Rules and guesses category. Returns {'category': ..., 'merchant': ...}
  static Future<Map<String, String>> applySmartRules(
    String merchant,
    String smsText,
    String type,
  ) async {
    final combined = '${merchant.toLowerCase()} ${smsText.toLowerCase()}';
    final combinedNoSpace = combined.replaceAll(' ', '');

    // 1. Check Registered Entities first
    try {
      final db = DatabaseHelper();
      final entities = await db.queryAll('registered_entities');
      entities.sort(
        (a, b) => (b['keyword'] as String).length.compareTo(
          (a['keyword'] as String).length,
        ),
      );
      for (final entity in entities) {
        final keyword = (entity['keyword'] as String).trim().toLowerCase();
        if (keyword.isEmpty) continue;
        final keywordNoSpace = keyword.replaceAll(' ', '');

        if (combined.contains(keyword) ||
            combinedNoSpace.contains(keywordNoSpace)) {
          if (entity['type'] == type || entity['type'] == 'both') {
            return {
              'category': entity['category'] as String,
              'merchant': entity['name'] as String,
            };
          }
        }
      }
    } catch (_) {}

    // 2. Default Keyword-based Guessing
    final category = _guessCategoryDefault(combined, type);
    return {'category': category, 'merchant': merchant};
  }

  static String _guessCategoryDefault(String combined, String type) {
    if (type == 'income') {
      if (_containsAny(combined, [
        'salary',
        'payroll',
        'stipend',
        'credited by employer',
      ])) {
        return 'Salary';
      }
      if (_containsAny(combined, ['refund', 'reversed', 'reversal'])) {
        return 'Refund';
      }
      if (_containsAny(combined, ['cashback', 'reward'])) {
        return 'Cashback';
      }
      if (_containsAny(combined, [
        'upi from',
        'neft from',
        'imps from',
        'transfer from',
        'credited by',
        'sent by',
        'from',
        'transfer',
      ])) {
        return 'Transfer';
      }
    }

    if (_containsAny(combined, [
      'swiggy',
      'zomato',
      'restaurant',
      'dining',
      'food',
      'cafe',
      'pizza',
      'burger',
      'biryani',
      'dhaba',
      'hotel meal',
    ])) {
      return 'Food';
    }
    if (_containsAny(combined, [
      'uber',
      'ola',
      'metro',
      'petrol',
      'fuel',
      'transport',
      'bus',
      'cab',
      'auto',
      'rapido',
      'yulu',
    ])) {
      return 'Fuel';
    }
    if (_containsAny(combined, [
      'amazon',
      'flipkart',
      'myntra',
      'shop',
      'mall',
      'store',
      'fashion',
      'meesho',
      'ajio',
    ])) {
      return 'Shopping';
    }
    if (_containsAny(combined, [
      'hospital',
      'pharmacy',
      'medical',
      'doctor',
      'health',
      'clinic',
      'apollo',
      'fortis',
      'medplus',
    ])) {
      return 'Health';
    }
    if (_containsAny(combined, [
      'electricity',
      'water',
      'gas',
      'broadband',
      'utility',
      'bill',
      'bsnl',
      'airtel',
      'jio',
      'vi ',
      'recharge',
      'dth',
    ])) {
      return 'Bills';
    }
    if (_containsAny(combined, ['rent', 'housing', 'flat', 'pg', 'hostel'])) {
      return 'Rent';
    }
    if (_containsAny(combined, [
      'grocery',
      'dmart',
      'bigbasket',
      'supermarket',
      'reliance fresh',
      'zepto',
      'blinkit',
      'instamart',
      'grocery store',
    ])) {
      return 'Grocery';
    }
    if (_containsAny(combined, [
      'flight',
      'hotel',
      'travel',
      'booking',
      'makemytrip',
      'irctc',
      'railway',
      'cleartrip',
      'vistara',
      'indigo',
      'akasa',
    ])) {
      return 'Travel';
    }
    if (_containsAny(combined, [
      'salary',
      'credited by employer',
      'payroll',
      'stipend',
    ])) {
      return 'Salary';
    }
    return 'Other';
  }

  static bool _containsAny(String text, List<String> keywords) =>
      keywords.any((k) => text.contains(k));
}
