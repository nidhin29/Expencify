import 'package:equatable/equatable.dart';

class Appliance extends Equatable {
  final int? id;
  final String name;
  final String brand;
  final DateTime purchaseDate;
  final DateTime amcExpiryDate;
  final double amcAmount;

  const Appliance({
    this.id,
    required this.name,
    required this.brand,
    required this.purchaseDate,
    required this.amcExpiryDate,
    this.amcAmount = 0,
  });

  bool get isExpired => amcExpiryDate.isBefore(DateTime.now());
  bool get isDueSoon =>
      amcExpiryDate.difference(DateTime.now()).inDays <= 30 && !isExpired;
  int get daysUntilExpiry => amcExpiryDate.difference(DateTime.now()).inDays;

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'brand': brand,
      'purchase_date': purchaseDate.toIso8601String(),
      'amc_expiry_date': amcExpiryDate.toIso8601String(),
      'amc_amount': amcAmount,
    };
  }

  factory Appliance.fromMap(Map<String, dynamic> map) {
    return Appliance(
      id: map['id'],
      name: map['name'],
      brand: map['brand'],
      purchaseDate: DateTime.parse(map['purchase_date']),
      amcExpiryDate: DateTime.parse(map['amc_expiry_date']),
      amcAmount: map['amc_amount'] ?? 0,
    );
  }

  @override
  List<Object?> get props => [
    id,
    name,
    brand,
    purchaseDate,
    amcExpiryDate,
    amcAmount,
  ];
}
