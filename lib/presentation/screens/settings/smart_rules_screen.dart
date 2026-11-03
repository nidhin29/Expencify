import '../../widgets/page_loading.dart';
import 'package:expencify/presentation/theme/app_icons.dart';
import '../../widgets/tool_cards.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../application/blocs/registered_entity/registered_entity_bloc.dart';
import '../../../application/blocs/registered_entity/registered_entity_event.dart';
import '../../../application/blocs/registered_entity/registered_entity_state.dart';
import '../../../domain/entities/registered_entity.dart';
import '../../../domain/repositories/registered_entity_repository.dart';
import '../../../domain/repositories/category_repository.dart';
import '../../widgets/form_save_button.dart';

Future<bool?> showSavedMerchantEditor(
  BuildContext context, {
  RegisteredEntity? initial,
  String? keyword,
  String? name,
  String? category,
  String type = 'expense',
}) async {
  if (initial == null && name != null) {
    try {
      final entries = await context.read<RegisteredEntityRepository>().getAll();
      final matching = entries
          .where(
            (e) =>
                (e.name.toLowerCase() == name.toLowerCase() ||
                    e.name.toLowerCase() == keyword?.toLowerCase()) &&
                (e.type == type || e.type == 'both'),
          )
          .toList();
      if (matching.length == 1) initial = matching.single;
    } catch (_) {
      /* The editor still permits a new merchant and retries saving. */
    }
  }
  if (!context.mounted) return null;
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => _MerchantEditor(
      initial: initial,
      keyword: keyword,
      name: name,
      category: category,
      type: type,
    ),
  );
}

class SmartRulesScreen extends StatelessWidget {
  const SmartRulesScreen({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Saved merchants')),
    body: RefreshFeedback<RegisteredEntityBloc, RegisteredEntityState>(
      onRetry: () =>
          context.read<RegisteredEntityBloc>().add(LoadRegisteredEntities()),
      child: BlocBuilder<RegisteredEntityBloc, RegisteredEntityState>(
        builder: (context, state) {
          if (state is RegisteredEntityLoading ||
              state is RegisteredEntityInitial) {
            return const PageLoading(
              label: 'Loading saved merchants',
              summary: false,
            );
          }
          if (state is RegisteredEntityError) {
            return Center(
              child: TextButton.icon(
                onPressed: () => context.read<RegisteredEntityBloc>().add(
                  LoadRegisteredEntities(),
                ),
                icon: const Icon(AppIcons.refresh),
                label: const Text('Could not load merchants. Retry'),
              ),
            );
          }
          final entities = state is RegisteredEntityLoaded
              ? state.entities
              : <RegisteredEntity>[];
          if (entities.isEmpty) {
            return ToolEmptyState(
              icon: AppIcons.merchant,
              title: 'Recognize your regular merchants',
              description: 'AMZN → Amazon · Shopping',
              action: 'Add merchant',
              onAction: () => showSavedMerchantEditor(context),
            );
          }
          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              FilledButton.icon(
                onPressed: () => showSavedMerchantEditor(context),
                icon: const Icon(AppIcons.add),
                label: const Text('Add merchant'),
              ),
              const SizedBox(height: 16),
              const Text('For future SMS transactions'),
              ...entities.map(
                (e) => Card(
                  margin: const EdgeInsets.only(top: 12),
                  child: ListTile(
                    leading: const Icon(AppIcons.merchant),
                    title: Text(e.name),
                    subtitle: Text(
                      '${e.keyword} → ${e.category}\n${e.type == 'both'
                          ? 'Income & expenses'
                          : e.type == 'income'
                          ? 'Income'
                          : 'Expenses'}',
                    ),
                    isThreeLine: true,
                    onTap: () => showSavedMerchantEditor(context, initial: e),
                    trailing: IconButton(
                      tooltip: 'Remove merchant',
                      icon: const Icon(AppIcons.delete),
                      onPressed: () async {
                        final remove = await showDialog<bool>(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            title: Text('Remove ${e.name}?'),
                            content: const Text(
                              'Existing transactions will stay unchanged.',
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(ctx, false),
                                child: const Text('Cancel'),
                              ),
                              TextButton(
                                onPressed: () => Navigator.pop(ctx, true),
                                child: const Text('Remove'),
                              ),
                            ],
                          ),
                        );
                        if (remove != true || !context.mounted) return;
                        try {
                          await context
                              .read<RegisteredEntityRepository>()
                              .delete(e.id!);
                          if (context.mounted) {
                            context.read<RegisteredEntityBloc>().add(
                              LoadRegisteredEntities(),
                            );
                          }
                        } catch (_) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Could not remove merchant. Try again.',
                                ),
                              ),
                            );
                          }
                        }
                      },
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    ),
  );
}

class _MerchantEditor extends StatefulWidget {
  final RegisteredEntity? initial;
  final String? keyword, name, category;
  final String type;
  const _MerchantEditor({
    this.initial,
    this.keyword,
    this.name,
    this.category,
    required this.type,
  });
  @override
  State<_MerchantEditor> createState() => _MerchantEditorState();
}

class _MerchantEditorState extends State<_MerchantEditor> {
  final form = GlobalKey<FormState>();
  late final TextEditingController keyword = TextEditingController(
    text: widget.initial?.keyword ?? widget.keyword,
  );
  late final TextEditingController name = TextEditingController(
    text: widget.name ?? widget.initial?.name,
  );
  late String type = widget.initial?.type ?? widget.type;
  late String? category = widget.category ?? widget.initial?.category;
  List<DropdownMenuItem<String>> categories = [];
  List<({String name, String type})> all = [];
  String? error;
  bool loading = true;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final values = await context.read<CategoryRepository>().getAll();
      if (!mounted) return;
      setState(() {
        all = values.map((c) => (name: c.name, type: c.type)).toList();
        loading = false;
        _categories();
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          loading = false;
          error = 'Could not load categories. Reopen to retry.';
        });
      }
    }
  }

  void _categories() {
    final names = {
      ...all.where((c) => type == 'both' || c.type == type).map((c) => c.name),
      'Other',
    };
    if (widget.initial != null && type == widget.initial!.type) {
      names.add(widget.initial!.category);
    }
    if (!names.contains(category)) category = null;
    categories = names
        .map((c) => DropdownMenuItem(value: c, child: Text(c)))
        .toList();
  }

  @override
  void dispose() {
    keyword.dispose();
    name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(
      20,
      0,
      20,
      MediaQuery.viewInsetsOf(context).bottom + 20,
    ),
    child: SingleChildScrollView(
      child: Form(
        key: form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.initial == null ? 'Save a merchant' : 'Edit merchant',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            const Text('For future SMS transactions'),
            const SizedBox(height: 24),
            TextFormField(
              controller: keyword,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: 'When an SMS contains',
                hintText: 'AMZN',
              ),
              validator: (v) => (v?.trim().length ?? 0) < 3
                  ? 'Use at least 3 characters from the SMS'
                  : null,
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: name,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Show merchant as',
                hintText: 'Amazon',
              ),
              validator: (v) => v == null || v.trim().isEmpty
                  ? 'Enter a merchant name'
                  : null,
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 16),
            if (loading)
              const LinearProgressIndicator()
            else
              DropdownButtonFormField<String>(
                value: category,
                isExpanded: true,
                items: categories,
                decoration: const InputDecoration(labelText: 'Use category'),
                onChanged: (v) => setState(() => category = v),
                validator: (v) => v == null ? 'Choose a category' : null,
              ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: type,
              decoration: const InputDecoration(labelText: 'Applies to'),
              items: const [
                DropdownMenuItem(value: 'expense', child: Text('Expenses')),
                DropdownMenuItem(value: 'income', child: Text('Income')),
                DropdownMenuItem(
                  value: 'both',
                  child: Text('Income & expenses'),
                ),
              ],
              onChanged: (v) => setState(() {
                type = v!;
                _categories();
              }),
            ),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Theme.of(
                  context,
                ).colorScheme.primaryContainer.withValues(alpha: .35),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Text(
                '${keyword.text.trim().isEmpty ? 'AMZN' : keyword.text.trim()} → ${name.text.trim().isEmpty ? 'Amazon' : name.text.trim()} · ${category ?? 'Category'}',
              ),
            ),
            if (error != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            const SizedBox(height: 20),
            FormSaveButton(
              filled: true,
              onSave: () async {
                if (loading || !form.currentState!.validate()) return null;
                final repo = context.read<RegisteredEntityRepository>();
                final existing = await repo.getAll();
                if (!context.mounted) return false;
                final normalized = keyword.text.trim().toLowerCase().replaceAll(
                  RegExp(r'\s+'),
                  '',
                );
                if (existing.any(
                  (e) =>
                      e.id != widget.initial?.id &&
                      e.keyword.toLowerCase().replaceAll(RegExp(r'\s+'), '') ==
                          normalized &&
                      (e.type == type || e.type == 'both' || type == 'both'),
                )) {
                  setState(
                    () => error =
                        'This SMS text already has a saved merchant. Edit that merchant instead.',
                  );
                  return null;
                }
                final entry = RegisteredEntity(
                  id: widget.initial?.id,
                  name: name.text.trim(),
                  keyword: keyword.text.trim(),
                  category: category!,
                  type: type,
                );
                if (widget.initial == null) {
                  await repo.add(entry);
                } else {
                  await repo.update(entry);
                }
                if (context.mounted) {
                  context.read<RegisteredEntityBloc>().add(
                    LoadRegisteredEntities(),
                  );
                }
                return true;
              },
              onSaved: () => Navigator.pop(context, true),
              child: const Text('Save merchant'),
            ),
          ],
        ),
      ),
    ),
  );
}
