import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:expencify/domain/entities/category.dart';
import 'package:expencify/application/blocs/category/category_bloc.dart';
import 'package:expencify/application/blocs/category/category_event.dart';
import 'package:expencify/application/blocs/category/category_state.dart';

class CategoriesScreen extends StatefulWidget {
  const CategoriesScreen({super.key});

  @override
  State<CategoriesScreen> createState() => _CategoriesScreenState();
}

class _CategoriesScreenState extends State<CategoriesScreen> {
  final List<Map<String, dynamic>> _iconOptions = [
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

  final List<Color> _colorOptions = [
    const Color(0xFFF44336),
    const Color(0xFFE91E63),
    const Color(0xFF9C27B0),
    const Color(0xFF673AB7),
    const Color(0xFF3F51B5),
    const Color(0xFF2196F3),
    const Color(0xFF03A9F4),
    const Color(0xFF00BCD4),
    const Color(0xFF009688),
    const Color(0xFF4CAF50),
    const Color(0xFF8BC34A),
    const Color(0xFFCDDC39),
    const Color(0xFFFFEB3B),
    const Color(0xFFFFC107),
    const Color(0xFFFF9800),
    const Color(0xFFFF5722),
    const Color(0xFF795548),
    const Color(0xFF607D8B),
  ];

  IconData _iconData(String name) {
    final found = _iconOptions.firstWhere(
      (o) => o['name'] == name,
      orElse: () => _iconOptions.last,
    );
    return found['icon'] as IconData;
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    context.read<CategoryBloc>().add(const LoadCategories());
  }

  void _addCategoryDialog({Category? existing}) {
    final formKey = GlobalKey<FormState>();
    final nameCtrl = TextEditingController(text: existing?.name ?? '');
    String selectedIcon = existing?.icon ?? 'category';
    int selectedColor = existing?.color ?? 0xFF6366F1;
    String selectedType = existing?.type ?? 'expense';

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: Text(existing != null ? 'Edit Category' : 'New Category'),
          content: Form(
            key: formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextFormField(
                    controller: nameCtrl,
                    decoration: const InputDecoration(labelText: 'Name'),
                    validator: (v) => (v?.isEmpty ?? true) ? 'Required' : null,
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: ['expense', 'income']
                        .map(
                          (t) => GestureDetector(
                            onTap: () => setS(() => selectedType = t),
                            child: Container(
                              margin: const EdgeInsets.only(right: 8),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                color: selectedType == t
                                    ? (t == 'expense'
                                              ? Colors.red
                                              : Colors.green)
                                          .withOpacity(0.15)
                                    : Colors.grey.shade100,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: selectedType == t
                                      ? (t == 'expense'
                                            ? Colors.red
                                            : Colors.green)
                                      : Colors.transparent,
                                ),
                              ),
                              child: Text(
                                t == 'expense' ? 'Expense' : 'Income',
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  color: selectedType == t
                                      ? (t == 'expense'
                                            ? Colors.red
                                            : Colors.green)
                                      : Colors.grey,
                                ),
                              ),
                            ),
                          ),
                        )
                        .toList(),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Icon',
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _iconOptions
                        .map(
                          (opt) => GestureDetector(
                            onTap: () => setS(() => selectedIcon = opt['name']),
                            child: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: selectedIcon == opt['name']
                                    ? Color(selectedColor).withOpacity(0.2)
                                    : Colors.grey.shade100,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: selectedIcon == opt['name']
                                      ? Color(selectedColor)
                                      : Colors.transparent,
                                ),
                              ),
                              child: Icon(
                                opt['icon'] as IconData,
                                size: 22,
                                color: selectedIcon == opt['name']
                                    ? Color(selectedColor)
                                    : Colors.grey.shade600,
                              ),
                            ),
                          ),
                        )
                        .toList(),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Color',
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _colorOptions
                        .map(
                          (c) => GestureDetector(
                            onTap: () => setS(() => selectedColor = c.value),
                            child: Container(
                              width: 32,
                              height: 32,
                              decoration: BoxDecoration(
                                color: c,
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: selectedColor == c.value
                                      ? Colors.black
                                      : Colors.transparent,
                                  width: 2,
                                ),
                              ),
                            ),
                          ),
                        )
                        .toList(),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                if (!formKey.currentState!.validate()) return;
                final cat = Category(
                  id: existing?.id,
                  name: nameCtrl.text.trim(),
                  icon: selectedIcon,
                  color: selectedColor,
                  type: selectedType,
                );
                if (existing != null) {
                  context.read<CategoryBloc>().add(SaveCategory(cat));
                } else {
                  context.read<CategoryBloc>().add(SaveCategory(cat));
                }
                if (ctx.mounted) Navigator.pop(ctx);
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: const Color(0xFFF8FAFC), // Modern off-white background
        appBar: AppBar(
          systemOverlayStyle: SystemUiOverlayStyle(
            statusBarColor: Colors.transparent,
            statusBarIconBrightness: theme.brightness == Brightness.dark
                ? Brightness.light
                : Brightness.dark,
            statusBarBrightness: theme.brightness, // For iOS
          ),
          title: const Text(
            'Categories',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          backgroundColor: Colors.transparent,
          elevation: 0,
          actions: [
            IconButton(
              icon: const Icon(Icons.add_rounded),
              onPressed: () => _addCategoryDialog(),
            ),
          ],
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(50),
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.grey.shade200,
                borderRadius: BorderRadius.circular(25),
              ),
              child: TabBar(
                dividerColor: Colors.transparent,
                indicatorSize: TabBarIndicatorSize.tab,
                labelColor: Colors.white,
                unselectedLabelColor: Colors.grey.shade600,
                labelStyle: const TextStyle(fontWeight: FontWeight.bold),
                indicator: BoxDecoration(
                  borderRadius: BorderRadius.circular(25),
                  color: theme.colorScheme.primary,
                ),
                tabs: const [
                  Tab(text: 'Expense'),
                  Tab(text: 'Income'),
                ],
              ),
            ),
          ),
        ),
        body: BlocBuilder<CategoryBloc, CategoryState>(
          builder: (context, state) {
            if (state is CategoryLoading) {
              return const Center(child: CircularProgressIndicator());
            } else if (state is CategoryLoaded) {
              final categories = state.categories;
              return TabBarView(
                children: [
                  _buildGrid(
                    categories.where((c) => c.type == 'expense').toList(),
                    theme,
                    'expense',
                  ),
                  _buildGrid(
                    categories.where((c) => c.type == 'income').toList(),
                    theme,
                    'income',
                  ),
                ],
              );
            } else if (state is CategoryError) {
              return Center(child: Text(state.message));
            }
            return const SizedBox.shrink();
          },
        ),
      ),
    );
  }

  Widget _buildGrid(List<Category> cats, ThemeData theme, String type) {
    if (cats.isEmpty) {
      return Center(
        child: Text(
          'No categories for $type yet.',
          style: const TextStyle(color: Colors.grey, fontSize: 16),
        ),
      );
    }
    return GridView.builder(
      padding: const EdgeInsets.all(20),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 16,
        crossAxisSpacing: 16,
        childAspectRatio: 0.9,
      ),
      itemCount: cats.length,
      itemBuilder: (ctx, idx) {
        final c = cats[idx];
        return GestureDetector(
          onTap: () => _addCategoryDialog(existing: c),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.03),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Stack(
              children: [
                Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Color(c.color).withOpacity(0.1),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          _iconData(c.icon),
                          color: Color(c.color),
                          size: 26,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        c.name,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                Positioned(
                  top: 4,
                  right: 4,
                  child: GestureDetector(
                    onTap: () => _showDeleteConfirm(c),
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: Colors.red.withOpacity(0.08),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.close_rounded,
                        size: 14,
                        color: Colors.red,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showDeleteConfirm(Category c) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Category?'),
        content: Text('Are you sure you want to delete "${c.name}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              context.read<CategoryBloc>().add(DeleteCategory(c.id!));
              Navigator.pop(ctx);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}
