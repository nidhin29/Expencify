import 'package:flutter/material.dart';

class CategoryAppearance {
  static const List<Map<String, dynamic>> icons = [
    {'name': 'restaurant', 'icon': Icons.restaurant_rounded, 'label': 'Food'},
    {
      'name': 'directions_car',
      'icon': Icons.directions_car_rounded,
      'label': 'Transport',
    },
    {
      'name': 'shopping_cart',
      'icon': Icons.shopping_cart_rounded,
      'label': 'Shopping',
    },
    {'name': 'movie', 'icon': Icons.movie_rounded, 'label': 'Movies'},
    {
      'name': 'local_hospital',
      'icon': Icons.local_hospital_rounded,
      'label': 'Medical',
    },
    {'name': 'school', 'icon': Icons.school_rounded, 'label': 'Education'},
    {'name': 'home', 'icon': Icons.home_rounded, 'label': 'Home'},
    {'name': 'bolt', 'icon': Icons.bolt_rounded, 'label': 'Utilities'},
    {'name': 'flight', 'icon': Icons.flight_rounded, 'label': 'Travel'},
    {'name': 'credit_card', 'icon': Icons.credit_card_rounded, 'label': 'EMI'},
    {
      'name': 'fitness_center',
      'icon': Icons.fitness_center_rounded,
      'label': 'Gym',
    },
    {'name': 'pets', 'icon': Icons.pets_rounded, 'label': 'Pets'},
    {'name': 'money', 'icon': Icons.attach_money_rounded, 'label': 'Money'},
    {'name': 'business', 'icon': Icons.business_rounded, 'label': 'Business'},
    {
      'name': 'trending_up',
      'icon': Icons.trending_up_rounded,
      'label': 'Investment',
    },
    {'name': 'category', 'icon': Icons.category_rounded, 'label': 'Other'},
  ];

  static const List<Color> colors = [
    Color(0xFF7C3AED),
    Color(0xFF2196F3),
    Color(0xFF009688),
    Color(0xFF4CAF50),
    Color(0xFFFFC107),
    Color(0xFFFF9800),
    Color(0xFFF44336),
    Color(0xFFE91E63),
  ];

  static String colorName(int value) => switch (value) {
    0xFF7C3AED => 'Violet',
    0xFFF44336 => 'Red',
    0xFFE91E63 => 'Pink',
    0xFF9C27B0 => 'Purple',
    0xFF673AB7 => 'Violet',
    0xFF3F51B5 => 'Indigo',
    0xFF2196F3 => 'Blue',
    0xFF03A9F4 => 'Light blue',
    0xFF00BCD4 => 'Cyan',
    0xFF009688 => 'Teal',
    0xFF4CAF50 => 'Green',
    0xFF8BC34A => 'Light green',
    0xFFCDDC39 => 'Lime',
    0xFFFFEB3B => 'Yellow',
    0xFFFFC107 => 'Amber',
    0xFFFF9800 => 'Orange',
    0xFFFF5722 => 'Deep orange',
    0xFF795548 => 'Brown',
    0xFF607D8B => 'Blue grey',
    _ => 'Custom colour',
  };

  static IconData icon(String name) =>
      icons.firstWhere(
            (option) => option['name'] == name,
            orElse: () => icons.last,
          )['icon']
          as IconData;

  static Color ink(int value, ThemeData theme) {
    final source = Color(value);
    final surface = theme.colorScheme.surface;
    final target = theme.brightness == Brightness.dark
        ? Colors.white
        : Colors.black;
    for (var step = 0; step <= 10; step++) {
      final color = Color.lerp(source, target, step / 10)!;
      final a = color.computeLuminance();
      final b = surface.computeLuminance();
      if (((a > b ? a : b) + .05) / ((a < b ? a : b) + .05) >= 3) return color;
    }
    return target;
  }
}
