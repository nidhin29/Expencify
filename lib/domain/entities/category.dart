import 'package:equatable/equatable.dart';

class Category extends Equatable {
  final int? id;
  final String name;
  final String icon;
  final int color;
  final String type; // 'income' or 'expense'

  const Category({
    this.id,
    required this.name,
    required this.icon,
    required this.color,
    required this.type,
  });

  Map<String, dynamic> toMap() {
    return {'id': id, 'name': name, 'icon': icon, 'color': color, 'type': type};
  }

  factory Category.fromMap(Map<String, dynamic> map) {
    return Category(
      id: map['id'],
      name: map['name'],
      icon: map['icon'],
      color: map['color'],
      type: map['type'],
    );
  }

  @override
  List<Object?> get props => [id, name, icon, color, type];
}
