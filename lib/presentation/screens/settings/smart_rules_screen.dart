import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:expencify/application/blocs/registered_entity/registered_entity_bloc.dart';
import 'package:expencify/application/blocs/registered_entity/registered_entity_event.dart';
import 'package:expencify/application/blocs/registered_entity/registered_entity_state.dart';
import 'package:expencify/domain/entities/registered_entity.dart';
import 'package:expencify/domain/entities/category.dart';
import 'package:expencify/domain/repositories/category_repository.dart';

class SmartRulesScreen extends StatefulWidget {
  const SmartRulesScreen({super.key});

  @override
  State<SmartRulesScreen> createState() => _SmartRulesScreenState();
}

class _SmartRulesScreenState extends State<SmartRulesScreen>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkBatteryOptimization();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkBatteryOptimization();
    }
  }

  Future<void> _checkBatteryOptimization() async {
    // No-op as this is now handled globally
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: AppBar(
        systemOverlayStyle: SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: theme.brightness == Brightness.dark
              ? Brightness.light
              : Brightness.dark,
          statusBarBrightness: theme.brightness,
        ),
        title: const Text('Smart Rules'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
      ),
      body: BlocBuilder<RegisteredEntityBloc, RegisteredEntityState>(
        builder: (context, state) {
          if (state is RegisteredEntityLoading) {
            return const Center(child: CircularProgressIndicator());
          }
          if (state is RegisteredEntityError) {
            return Center(child: Text(state.message));
          }
          if (state is RegisteredEntityLoaded) {
            final entities = state.entities;

            return ListView(
              padding: EdgeInsets.fromLTRB(
                20,
                16,
                20,
                32 + MediaQuery.of(context).padding.bottom,
              ),
              children: [
                _buildAddRuleBanner(context, theme),
                const SizedBox(height: 32),
                if (entities.isEmpty)
                  _buildEmptyListState(theme)
                else ...[
                  Row(
                    children: [
                      Text(
                        'Active Rules'.toUpperCase(),
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: theme.colorScheme.onSurface.withOpacity(0.4),
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.2,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primary.withOpacity(0.1),
                          shape: BoxShape.circle,
                        ),
                        child: Text(
                          entities.length.toString(),
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: theme.colorScheme.primary,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  ...entities.map(
                    (e) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _buildRuleCard(context, theme, e),
                    ),
                  ),
                ],
                const SizedBox(height: 40),
              ],
            );
          }
          return const SizedBox();
        },
      ),
    );
  }

  Widget _buildAddRuleBanner(BuildContext context, ThemeData theme) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            theme.colorScheme.primary,
            theme.colorScheme.primary.withBlue(255).withRed(100),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: theme.colorScheme.primary.withOpacity(0.3),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _showRuleDialog(context),
          borderRadius: BorderRadius.circular(28),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.auto_awesome_rounded,
                    color: Colors.white,
                    size: 32,
                  ),
                ),
                const SizedBox(width: 20),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Register a New Entity',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Teach the app to recognize family members or specific stores.',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.8),
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(
                  Icons.arrow_forward_ios_rounded,
                  color: Colors.white,
                  size: 16,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyListState(ThemeData theme) {
    return Center(
      child: Column(
        children: [
          const SizedBox(height: 40),
          Icon(
            Icons.rule_folder_rounded,
            size: 64,
            color: theme.colorScheme.onSurface.withOpacity(0.1),
          ),
          const SizedBox(height: 16),
          Text(
            'No Rules Configured',
            style: theme.textTheme.titleMedium?.copyWith(
              color: theme.colorScheme.onSurface.withOpacity(0.3),
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRuleCard(
    BuildContext context,
    ThemeData theme,
    RegisteredEntity entity,
  ) {
    Color typeColor;
    IconData typeIcon;
    String typeLabel;

    switch (entity.type) {
      case 'income':
        typeColor = Colors.green;
        typeIcon = Icons.keyboard_arrow_down_rounded;
        typeLabel = 'Income';
        break;
      case 'expense':
        typeColor = Colors.red;
        typeIcon = Icons.keyboard_arrow_up_rounded;
        typeLabel = 'Expense';
        break;
      default:
        typeColor = theme.colorScheme.primary;
        typeIcon = Icons.sync_rounded;
        typeLabel = 'Income & Expense';
    }

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: theme.colorScheme.onSurface.withOpacity(0.06),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: ExpansionTile(
          shape: const RoundedRectangleBorder(side: BorderSide.none),
          leading: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: typeColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(typeIcon, color: typeColor, size: 24),
          ),
          title: Text(
            entity.name,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          subtitle: Text(
            'Keyword: ${entity.keyword}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurface.withOpacity(0.4),
            ),
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: Icon(
                  Icons.edit_outlined,
                  color: theme.colorScheme.primary,
                  size: 20,
                ),
                onPressed: () =>
                    _showRuleDialog(context, initialEntity: entity),
              ),
              IconButton(
                icon: const Icon(
                  Icons.delete_outline_rounded,
                  color: Colors.redAccent,
                  size: 20,
                ),
                onPressed: () => _confirmDelete(context, entity),
              ),
            ],
          ),
          childrenPadding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          children: [
            const Divider(height: 1),
            const SizedBox(height: 16),
            Row(
              children: [
                _buildRuleDetail(theme, 'RULE APPLIES TO', typeLabel),
                const Spacer(),
                _buildRuleDetail(theme, 'CATEGORY', entity.category),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRuleDetail(ThemeData theme, String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurface.withOpacity(0.3),
            letterSpacing: 1.0,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          value,
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.bold,
            color: theme.colorScheme.onSurface.withOpacity(0.8),
          ),
        ),
      ],
    );
  }

  void _confirmDelete(BuildContext context, RegisteredEntity entity) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Text('Remove Rule?'),
        content: Text(
          'Are you sure you want to stop recognizing "${entity.name}"? This won\'t delete existing transactions.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              'Keep',
              style: TextStyle(color: Theme.of(context).colorScheme.primary),
            ),
          ),
          TextButton(
            onPressed: () {
              if (entity.id != null) {
                context.read<RegisteredEntityBloc>().add(
                  DeleteRegisteredEntity(entity.id!),
                );
              }
              Navigator.pop(ctx);
            },
            child: const Text('Remove', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  void _showRuleDialog(
    BuildContext context, {
    RegisteredEntity? initialEntity,
  }) async {
    final nameCtrl = TextEditingController(text: initialEntity?.name);
    final keywordCtrl = TextEditingController(text: initialEntity?.keyword);
    String selectedType = initialEntity?.type ?? 'both';
    String? selectedCategory = initialEntity?.category;

    // Load actual categories
    final categoryRepo = context.read<CategoryRepository>();
    final allCategories = await categoryRepo.getAll();

    if (!context.mounted) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      useSafeArea: true,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setState) => Container(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(36)),
          ),
          child: SafeArea(
            bottom: false, // Handled manually below
            child: Padding(
              padding: EdgeInsets.only(
                bottom:
                    MediaQuery.of(context).viewInsets.bottom +
                    MediaQuery.of(context).padding.bottom +
                    20,
              ),
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(28, 24, 28, 32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 40,
                        height: 5,
                        decoration: BoxDecoration(
                          color: Theme.of(
                            context,
                          ).colorScheme.onSurface.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      initialEntity == null
                          ? 'Define New Rule'
                          : 'Edit Smart Rule',
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(
                            fontWeight: FontWeight.bold,
                            letterSpacing: -0.5,
                          ),
                    ),
                    const SizedBox(height: 32),
                    _buildInputField(
                      context,
                      controller: nameCtrl,
                      label: 'Rule Name',
                      hint: 'e.g. Sister, Google, Amazon',
                      icon: Icons.bookmark_outline_rounded,
                    ),
                    const SizedBox(height: 20),
                    _buildInputField(
                      context,
                      controller: keywordCtrl,
                      label: 'SMS Keyword',
                      hint: 'The exact name in the SMS (e.g. NIKITA)',
                      icon: Icons.search_rounded,
                      textCapitalization: TextCapitalization.none,
                    ),
                    const SizedBox(height: 32),
                    Text(
                      'RULE TYPE',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: Theme.of(
                          context,
                        ).colorScheme.onSurface.withOpacity(0.4),
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.2,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        _buildSelectionChip(
                          context,
                          setState,
                          'Both',
                          'both',
                          selectedType,
                          (v) {
                            selectedType = v;
                            final categories = _getCategories(v, allCategories);
                            if (!categories.contains(selectedCategory)) {
                              selectedCategory = categories.first;
                            }
                          },
                        ),
                        const SizedBox(width: 8),
                        _buildSelectionChip(
                          context,
                          setState,
                          'Income',
                          'income',
                          selectedType,
                          (v) {
                            selectedType = v;
                            final categories = _getCategories(v, allCategories);
                            if (!categories.contains(selectedCategory)) {
                              selectedCategory = categories.first;
                            }
                          },
                        ),
                        const SizedBox(width: 8),
                        _buildSelectionChip(
                          context,
                          setState,
                          'Expense',
                          'expense',
                          selectedType,
                          (v) {
                            selectedType = v;
                            final categories = _getCategories(v, allCategories);
                            if (!categories.contains(selectedCategory)) {
                              selectedCategory = categories.first;
                            }
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    DropdownButtonFormField<String>(
                      value:
                          selectedCategory ??
                          (_getCategories(
                                selectedType,
                                allCategories,
                              ).isNotEmpty
                              ? _getCategories(
                                  selectedType,
                                  allCategories,
                                ).first
                              : 'Other'),
                      decoration: InputDecoration(
                        labelText: 'Assign Category',
                        prefixIcon: Icon(
                          Icons.category_outlined,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(20),
                          borderSide: BorderSide(
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurface.withOpacity(0.1),
                          ),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(20),
                          borderSide: BorderSide(
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurface.withOpacity(0.1),
                          ),
                        ),
                      ),
                      items: _getCategories(selectedType, allCategories)
                          .map(
                            (c) => DropdownMenuItem(value: c, child: Text(c)),
                          )
                          .toList(),
                      onChanged: (v) {
                        if (v != null) setState(() => selectedCategory = v);
                      },
                    ),
                    const SizedBox(height: 40),
                    SizedBox(
                      width: double.infinity,
                      height: 64,
                      child: ElevatedButton(
                        onPressed: () {
                          if (nameCtrl.text.isEmpty ||
                              keywordCtrl.text.isEmpty) {
                            return;
                          }
                          if (initialEntity != null) {
                            context.read<RegisteredEntityBloc>().add(
                              UpdateRegisteredEntity(
                                RegisteredEntity(
                                  id: initialEntity.id,
                                  name: nameCtrl.text,
                                  keyword: keywordCtrl.text.trim(),
                                  category:
                                      selectedCategory ??
                                      (_getCategories(
                                            selectedType,
                                            allCategories,
                                          ).isNotEmpty
                                          ? _getCategories(
                                              selectedType,
                                              allCategories,
                                            ).first
                                          : 'Other'),
                                  type: selectedType,
                                ),
                              ),
                            );
                          } else {
                            context.read<RegisteredEntityBloc>().add(
                              AddRegisteredEntity(
                                RegisteredEntity(
                                  name: nameCtrl.text,
                                  keyword: keywordCtrl.text.trim(),
                                  category:
                                      selectedCategory ??
                                      (_getCategories(
                                            selectedType,
                                            allCategories,
                                          ).isNotEmpty
                                          ? _getCategories(
                                              selectedType,
                                              allCategories,
                                            ).first
                                          : 'Other'),
                                  type: selectedType,
                                ),
                              ),
                            );
                          }
                          Navigator.pop(ctx);
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Theme.of(
                            context,
                          ).colorScheme.primary,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(24),
                          ),
                          elevation: 0,
                        ),
                        child: const Text(
                          'Save Smart Rule',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildInputField(
    BuildContext context, {
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    TextCapitalization textCapitalization = TextCapitalization.words,
  }) {
    return TextField(
      controller: controller,
      textCapitalization: textCapitalization,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: Icon(icon, color: Theme.of(context).colorScheme.primary),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(20),
          borderSide: BorderSide(
            color: Theme.of(context).colorScheme.onSurface.withOpacity(0.1),
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(20),
          borderSide: BorderSide(
            color: Theme.of(context).colorScheme.onSurface.withOpacity(0.1),
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(20),
          borderSide: BorderSide(
            color: Theme.of(context).colorScheme.primary,
            width: 2,
          ),
        ),
        filled: true,
        fillColor: Theme.of(context).colorScheme.onSurface.withOpacity(0.02),
      ),
    );
  }

  Widget _buildSelectionChip(
    BuildContext context,
    StateSetter setState,
    String label,
    String value,
    String selected,
    Function(String) onSelect,
  ) {
    final isSelected = selected == value;

    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => onSelect(value)),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: isSelected
                ? Theme.of(context).colorScheme.primary.withOpacity(0.1)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isSelected
                  ? Theme.of(context).colorScheme.primary
                  : Colors.grey.withOpacity(0.2),
              width: 1.5,
            ),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: isSelected
                  ? Theme.of(context).colorScheme.primary
                  : Colors.grey,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              fontSize: 13,
            ),
          ),
        ),
      ),
    );
  }

  List<String> _getCategories(String type, List<Category> all) {
    if (type == 'expense') {
      return all.where((c) => c.type == 'expense').map((c) => c.name).toList()
        ..add('Other');
    }
    if (type == 'income') {
      return all.where((c) => c.type == 'income').map((c) => c.name).toList()
        ..add('Other');
    }
    // For 'both'
    return all.map((c) => c.name).toSet().toList()..add('Other');
  }
}
