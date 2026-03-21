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

    final amount = _extractAmount(sms);
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

  /// Extracts just the last 4 digits of account/card from an SMS.
  /// Used to match an SMS to a known account in the DB.
  static String? extractLastFourDigits(String sms) {
    final patterns = [
      // Matches "A/c ends 123", "A/c no. 1234", "A/cXXXXXXXX1234", "card *12"
      RegExp(
        r'(?:a\/c|acct|account|card|bank)[a-z\s.:#]*(?:ending|ends|no|num)?[\s*x.-]*([0-9]{2,6})',
        caseSensitive: false,
      ),
      // Matches "XX1234", "****123", "X1234" standalone
      RegExp(r'(?:[x*]{2,})[\s-]*([0-9]{2,6})', caseSensitive: false),
      // Matches "account number 1234", "ends with 1234" (no prefix)
      RegExp(
        r'(?:end|ends|ending|no|num|number)\s*(?:in|is|with)?\s*([0-9]{2,6})',
        caseSensitive: false,
      ),
    ];
    for (final p in patterns) {
      final m = p.firstMatch(sms);
      if (m != null) return m.group(1);
    }
    return null;
  }

  /// High-performance filter to catch marketing SMS and scams.
  static bool _isMarketing(String text) {
    // Detection of common marketing links
    final hasUrl =
        text.contains('http://') ||
        text.contains('https://') ||
        text.contains('www.') ||
        text.contains('.in/') ||
        text.contains('.com/');

    if (hasUrl) {
      // If it has a URL AND marketing words, it's garbage.
      final marketingKeywords = [
        'offer',
        'card',
        'limit',
        'apply',
        'gift',
        'won',
        'voucher',
        'click',
        'ഓഫർ',
        'കാർഡ്',
        'ക്ലിക്ക്',
        'നൽകുന്നു',
        'സ്വന്തമാക്കൂ',
      ];
      if (marketingKeywords.any((k) => text.contains(k))) return true;
    }
    return false;
  }

  static bool _isInformationalAlert(String text) {
    final ignoreKeywords = [
      'avg. bal',
      'maintained',
      'non-maintenance',
      'minimum balance',
      'otp',
      'login',
      'password',
      'code',
      'statement',
      'due to expire',
      'kyc',
      'rewards earned',
      'congratulations',
      'loan',
      'insurance',
    ];
    return ignoreKeywords.any((k) => text.contains(k));
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

  static String? _extractType(String text) {
    if (_dictionary['income']!.any((k) => text.contains(k))) return 'income';
    if (_dictionary['expense']!.any((k) => text.contains(k))) return 'expense';
    return null;
  }

  static double? _extractAmount(String sms) {
    final patterns = [
      // Standard formats: Rs. 500, Rs 500, INR 500, ₹ 500
      RegExp(
        r'(?:rs\.?|inr|₹)\s*([0-9,]+(?:\.[0-9]{1,2})?)',
        caseSensitive: false,
      ),
      // Reversed: 500 Rs
      RegExp(
        r'([0-9,]+(?:\.[0-9]{1,2})?)\s*(?:rs\.?|inr|₹)',
        caseSensitive: false,
      ),
      // Explicit amount keyword: amount 500
      RegExp(
        r'(?:amount|amt)[:\s]+(?:rs\.?|inr|₹)?\s*([0-9,]+(?:\.[0-9]{1,2})?)',
        caseSensitive: false,
      ),
      // Contextual: "for rs 500", "of rs 500"
      RegExp(
        r'(?:of|for)\s+rs\.?\s*([0-9,]+(?:\.[0-9]{1,2})?)',
        caseSensitive: false,
      ),
      // Plain amount at start or after punctuation (Risky but helpful)
      RegExp(r'(?:^|[\s:])([0-9,]+\.[0-9]{2})(?:\s+|$)', caseSensitive: false),
    ];
    for (final p in patterns) {
      final match = p.firstMatch(sms);
      if (match != null) {
        final raw = match.group(1)!.replaceAll(',', '');
        return double.tryParse(raw);
      }
    }
    return null;
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
      for (final entity in entities) {
        final keyword = (entity['keyword'] as String).toLowerCase();
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
