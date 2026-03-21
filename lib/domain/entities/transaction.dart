import 'package:equatable/equatable.dart';

class TransactionModel extends Equatable {
  final int? id;
  final int accountId;
  final double amount;
  final String type; // 'income' or 'expense'
  final String category;
  final DateTime date;
  final String note;
  final String merchant;
  final bool isOcr;
  final bool isVoice;
  final bool isSms;
  final String? imagePath;
  final int? parentId;

  const TransactionModel({
    this.id,
    required this.accountId,
    required this.amount,
    required this.type,
    required this.category,
    required this.date,
    this.note = '',
    this.merchant = '',
    this.isOcr = false,
    this.isVoice = false,
    this.isSms = false,
    this.imagePath,
    this.parentId,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'account_id': accountId,
      'amount': amount,
      'type': type,
      'category': category,
      'date': date.toIso8601String(),
      'note': note,
      'merchant': merchant,
      'is_ocr': isOcr ? 1 : 0,
      'is_voice': isVoice ? 1 : 0,
      'is_sms': isSms ? 1 : 0,
      'image_path': imagePath,
      'parent_id': parentId,
    };
  }

  factory TransactionModel.fromMap(Map<String, dynamic> map) {
    return TransactionModel(
      id: map['id'],
      accountId: map['account_id'],
      amount: (map['amount'] as num).toDouble(),
      type: map['type'],
      category: map['category'],
      date: DateTime.parse(map['date']),
      note: map['note'] ?? '',
      merchant: map['merchant'] ?? '',
      isOcr: map['is_ocr'] == 1,
      isVoice: map['is_voice'] == 1,
      isSms: map['is_sms'] == 1,
      imagePath: map['image_path'] as String?,
      parentId: map['parent_id'],
    );
  }

  TransactionModel copyWith({
    int? id,
    int? accountId,
    double? amount,
    String? type,
    String? category,
    DateTime? date,
    String? note,
    String? merchant,
    bool? isOcr,
    bool? isVoice,
    bool? isSms,
    String? imagePath,
    int? parentId,
  }) {
    return TransactionModel(
      id: id ?? this.id,
      accountId: accountId ?? this.accountId,
      amount: amount ?? this.amount,
      type: type ?? this.type,
      category: category ?? this.category,
      date: date ?? this.date,
      note: note ?? this.note,
      merchant: merchant ?? this.merchant,
      isOcr: isOcr ?? this.isOcr,
      isVoice: isVoice ?? this.isVoice,
      isSms: isSms ?? this.isSms,
      imagePath: imagePath ?? this.imagePath,
      parentId: parentId ?? this.parentId,
    );
  }

  @override
  List<Object?> get props => [
    id,
    accountId,
    amount,
    type,
    category,
    date,
    note,
    merchant,
    isOcr,
    isVoice,
    isSms,
    imagePath,
    parentId,
  ];
}
