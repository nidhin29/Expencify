import '../../widgets/page_loading.dart';
import 'package:expencify/presentation/theme/app_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../domain/entities/category.dart';
import '../../../application/blocs/category/category_bloc.dart';
import '../../../application/blocs/category/category_event.dart';
import '../../../application/blocs/category/category_state.dart';
import '../../widgets/category_appearance.dart';
import '../../widgets/category_editor.dart';
import '../../widgets/tool_cards.dart';

class CategoriesScreen extends StatefulWidget {
  const CategoriesScreen({super.key});
  @override
  State<CategoriesScreen> createState() => _CategoriesScreenState();
}

class _CategoriesScreenState extends State<CategoriesScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    _load();
  }

  void _load() => context.read<CategoryBloc>().add(const LoadCategories());
  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _edit({Category? category}) async {
    final bloc = context.read<CategoryBloc>();
    final state = bloc.state;
    if (state is! CategoryLoaded) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: false,
      isDismissible: false,
      enableDrag: false,
      builder: (_) => CategoryEditor(
        existing: category,
        initialType: _tabs.index == 0 ? 'expense' : 'income',
        categories: state.categories,
        onSave: (value) async {
          final result = bloc.stream.firstWhere(
            (state) => state is CategorySaved || state is CategoryError,
          );
          bloc.add(SaveCategory(value));
          final saved = await result;
          if (saved is CategoryError) throw StateError('Category save failed');
          if (mounted) _tabs.animateTo(value.type == 'income' ? 1 : 0);
        },
        onDelete: category?.id == null
            ? null
            : () async {
                final result = bloc.stream.firstWhere(
                  (state) => state is CategoryDeleted || state is CategoryError,
                );
                bloc.add(DeleteCategory(category!.id!));
                if (await result is CategoryError) {
                  throw StateError('Category delete failed');
                }
              },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return BlocConsumer<CategoryBloc, CategoryState>(
      listener: (context, state) {
        if (state is CategorySaved || state is CategoryDeleted) {
          ScaffoldMessenger.of(context).hideCurrentSnackBar();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                state is CategorySaved ? 'Category saved' : 'Category deleted',
              ),
              duration: const Duration(seconds: 2),
            ),
          );
        }
      },
      builder: (context, state) => Scaffold(
        appBar: AppBar(
          title: const Text('Categories'),
          actions: [
            IconButton(
              tooltip: 'Add category',
              onPressed: state is CategoryLoaded ? () => _edit() : null,
              icon: const Icon(AppIcons.add),
            ),
          ],
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(64),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest.withValues(alpha: .55),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: TabBar(
                  controller: _tabs,
                  dividerColor: Colors.transparent,
                  padding: const EdgeInsets.all(4),
                  indicatorSize: TabBarIndicatorSize.tab,
                  indicator: BoxDecoration(
                    color: cs.primary,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  labelColor: cs.onPrimary,
                  unselectedLabelColor: cs.onSurfaceVariant,
                  tabs: const [
                    Tab(text: 'Expense'),
                    Tab(text: 'Income'),
                  ],
                ),
              ),
            ),
          ),
        ),
        body: LoadingFeedback(
          loading: state is CategoryLoaded && state.refreshing,
          error: state is CategoryLoaded ? state.refreshError : null,
          onRetry: _load,
          child: state is CategoryLoaded
              ? TabBarView(
                  controller: _tabs,
                  children: [
                    _list(
                      state.categories
                          .where((c) => c.type == 'expense')
                          .toList(),
                      'expense',
                    ),
                    _list(
                      state.categories
                          .where((c) => c.type == 'income')
                          .toList(),
                      'income',
                    ),
                  ],
                )
              : state is CategoryError
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          AppIcons.error,
                          size: 44,
                          color: cs.onSurfaceVariant,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Could not load categories',
                          style: theme.textTheme.titleMedium,
                        ),
                        const SizedBox(height: 20),
                        FilledButton(
                          onPressed: _load,
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  ),
                )
              : const PageLoading(label: 'Loading categories'),
        ),
      ),
    );
  }

  Widget _list(List<Category> categories, String type) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    if (categories.isEmpty) {
      return ToolEmptyState(
        icon: AppIcons.categories,
        title: 'No $type categories yet',
        action: 'Add category',
        onAction: () => _edit(),
      );
    }
    categories.sort(
      (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns =
            constraints.maxWidth >= 640 &&
                MediaQuery.textScalerOf(context).scale(1) <= 1.4
            ? 2
            : 1;
        final rows = (categories.length / columns).ceil();
        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
          itemCount: rows,
          separatorBuilder: (_, _) => const SizedBox(height: 12),
          itemBuilder: (_, row) => IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var col = 0; col < columns; col++) ...[
                  if (col > 0) const SizedBox(width: 12),
                  Expanded(
                    child: row * columns + col >= categories.length
                        ? const SizedBox.shrink()
                        : _tile(categories[row * columns + col], theme, cs),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _tile(Category category, ThemeData theme, ColorScheme cs) => Semantics(
    button: true,
    label: 'Edit ${category.name}',
    onTap: () => _edit(category: category),
    excludeSemantics: true,
    child: Material(
      color: cs.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: cs.outlineVariant.withValues(alpha: .6)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _edit(category: category),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: Color(category.color).withValues(alpha: .12),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(
                  CategoryAppearance.icon(category.icon),
                  color: CategoryAppearance.ink(category.color, theme),
                  size: 24,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(category.name, style: theme.textTheme.titleSmall),
              ),
              const SizedBox(width: 8),
              Icon(AppIcons.chevron, size: 20, color: cs.onSurfaceVariant),
            ],
          ),
        ),
      ),
    ),
  );
}
