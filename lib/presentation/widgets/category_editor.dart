import 'package:expencify/presentation/theme/app_icons.dart';
import 'package:flutter/material.dart';
import '../../domain/entities/category.dart';
import 'category_appearance.dart';

class CategoryEditor extends StatefulWidget {
  final Category? existing;
  final String initialType;
  final List<Category> categories;
  final Future<void> Function(Category) onSave;
  final Future<void> Function()? onDelete;
  const CategoryEditor({
    super.key,
    this.existing,
    required this.initialType,
    required this.categories,
    required this.onSave,
    this.onDelete,
  });
  @override
  State<CategoryEditor> createState() => _CategoryEditorState();
}

class _CategoryEditorState extends State<CategoryEditor> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _name;
  late String _type;
  late String _icon;
  late int _color;
  bool _busy = false;
  bool _deleting = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.existing?.name ?? '');
    _type = widget.existing?.type ?? widget.initialType;
    _icon = widget.existing?.icon ?? 'category';
    _color = widget.existing?.color ?? 0xFF7C3AED;
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_busy || !_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.onSave(
        Category(
          id: widget.existing?.id,
          name: _name.text.trim(),
          icon: _icon,
          color: _color,
          type: _type,
        ),
      );
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = 'Could not save this category. Please try again.';
        });
      }
    }
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete category?'),
        content: Text(
          'Remove "${widget.existing!.name}" from your category list? Existing transactions will keep their category label.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep category'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      _busy = true;
      _deleting = true;
      _error = null;
    });
    try {
      await widget.onDelete!();
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = 'Could not delete this category. Please try again.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final ink = CategoryAppearance.ink(_color, theme);
    final colors = [
      if (!CategoryAppearance.colors.any((c) => c.toARGB32() == _color))
        Color(_color),
      ...CategoryAppearance.colors,
    ];
    return PopScope(
      canPop: !_busy,
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight:
                (MediaQuery.sizeOf(context).height -
                        MediaQuery.viewInsetsOf(context).bottom -
                        80)
                    .clamp(180, 900),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 12, 12, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        widget.existing == null
                            ? 'Add category'
                            : 'Edit category',
                        style: theme.textTheme.titleLarge,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Close',
                      onPressed: _busy ? null : () => Navigator.pop(context),
                      icon: const Icon(AppIcons.close),
                    ),
                  ],
                ),
              ),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
                  child: Form(
                    key: _form,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (MediaQuery.viewInsetsOf(context).bottom == 0) ...[
                          Container(
                            padding: const EdgeInsets.all(16),
                            width: double.infinity,
                            decoration: BoxDecoration(
                              color: cs.surfaceContainerHighest.withValues(
                                alpha: .5,
                              ),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: Color(_color).withValues(alpha: .12),
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                  child: Icon(
                                    CategoryAppearance.icon(_icon),
                                    color: ink,
                                    size: 28,
                                  ),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: ValueListenableBuilder(
                                    valueListenable: _name,
                                    builder: (_, value, _) => Text(
                                      value.text.trim().isEmpty
                                          ? 'Your category'
                                          : value.text.trim(),
                                      style: theme.textTheme.titleMedium,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 20),
                        ],
                        TextFormField(
                          controller: _name,
                          enabled: !_busy,
                          textCapitalization: TextCapitalization.sentences,
                          decoration: const InputDecoration(
                            labelText: 'Category name',
                            hintText: 'e.g. Groceries',
                          ),
                          validator: (value) {
                            final name = value?.trim() ?? '';
                            if (name.isEmpty) return 'Enter a category name';
                            if (widget.categories.any(
                              (c) =>
                                  c.id != widget.existing?.id &&
                                  c.type == _type &&
                                  c.name.trim().toLowerCase() ==
                                      name.toLowerCase(),
                            )) {
                              return 'This category already exists';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 20),
                        SizedBox(
                          width: double.infinity,
                          child: SegmentedButton<String>(
                            segments: const [
                              ButtonSegment(
                                value: 'expense',
                                label: Text('Expense'),
                              ),
                              ButtonSegment(
                                value: 'income',
                                label: Text('Income'),
                              ),
                            ],
                            selected: {_type},
                            onSelectionChanged: _busy
                                ? null
                                : (values) => setState(() {
                                    _type = values.first;
                                  }),
                          ),
                        ),
                        const SizedBox(height: 24),
                        Text('Icon', style: theme.textTheme.titleSmall),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: CategoryAppearance.icons.map((option) {
                            final selected = _icon == option['name'];
                            return Semantics(
                              selected: selected,
                              child: Tooltip(
                                message: option['label'] as String,
                                child: SizedBox.square(
                                  dimension: 48,
                                  child: Material(
                                    color: selected
                                        ? cs.primaryContainer
                                        : cs.surfaceContainerHighest.withValues(
                                            alpha: .5,
                                          ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      side: BorderSide(
                                        color: selected
                                            ? cs.primary
                                            : Colors.transparent,
                                        width: 2,
                                      ),
                                    ),
                                    child: InkWell(
                                      borderRadius: BorderRadius.circular(12),
                                      onTap: _busy
                                          ? null
                                          : () => setState(() {
                                              _icon = option['name'] as String;
                                            }),
                                      child: Icon(
                                        option['icon'] as IconData,
                                        semanticLabel:
                                            option['label'] as String,
                                        color: selected
                                            ? cs.onPrimaryContainer
                                            : cs.onSurfaceVariant,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                        const SizedBox(height: 24),
                        Text('Colour', style: theme.textTheme.titleSmall),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 4,
                          runSpacing: 4,
                          children: colors.asMap().entries.map((entry) {
                            final color = entry.value;
                            final selected = color.toARGB32() == _color;
                            return Semantics(
                              label: CategoryAppearance.colorName(
                                color.toARGB32(),
                              ),
                              selected: selected,
                              button: true,
                              child: SizedBox.square(
                                dimension: 48,
                                child: InkWell(
                                  customBorder: const CircleBorder(),
                                  onTap: _busy
                                      ? null
                                      : () => setState(() {
                                          _color = color.toARGB32();
                                        }),
                                  child: Center(
                                    child: Container(
                                      width: 34,
                                      height: 34,
                                      decoration: BoxDecoration(
                                        color: color,
                                        shape: BoxShape.circle,
                                        border: Border.all(
                                          color: selected
                                              ? cs.onSurface
                                              : cs.outlineVariant,
                                          width: selected ? 2 : 1,
                                        ),
                                      ),
                                      child: selected
                                          ? Icon(
                                              AppIcons.check,
                                              size: 22,
                                              color:
                                                  color.computeLuminance() > .45
                                                  ? Colors.black
                                                  : Colors.white,
                                            )
                                          : null,
                                    ),
                                  ),
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_error != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Semantics(
                          liveRegion: true,
                          child: Text(
                            _error!,
                            style: TextStyle(color: cs.error),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: _busy ? null : _save,
                        child: Text(
                          _busy
                              ? (_deleting ? 'Deleting…' : 'Saving changes…')
                              : widget.existing == null
                              ? 'Add category'
                              : 'Save changes',
                        ),
                      ),
                    ),
                    if (widget.onDelete != null)
                      TextButton(
                        onPressed: _busy ? null : _delete,
                        style: TextButton.styleFrom(foregroundColor: cs.error),
                        child: const Text('Delete category'),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
