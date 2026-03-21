import 'package:equatable/equatable.dart';

class RegisteredEntity extends Equatable {
  final int? id;
  final String name;
  final String keyword;
  final String category;
  final String type; // 'income', 'expense', or 'both'

  const RegisteredEntity({
    this.id,
    required this.name,
    required this.keyword,
    required this.category,
    required this.type,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'keyword': keyword,
      'category': category,
      'type': type,
    };
  }

  factory RegisteredEntity.fromMap(Map<String, dynamic> map) {
    return RegisteredEntity(
      id: map['id'],
      name: map['name'],
      keyword: map['keyword'],
      category: map['category'],
      type: map['type'],
    );
  }

  @override
  List<Object?> get props => [id, name, keyword, category, type];
}
