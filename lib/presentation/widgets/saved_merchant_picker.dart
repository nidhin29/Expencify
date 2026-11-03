import 'package:expencify/presentation/theme/app_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../domain/entities/registered_entity.dart';
import '../../domain/repositories/registered_entity_repository.dart';
import '../screens/settings/smart_rules_screen.dart';

Future<RegisteredEntity?> showSavedMerchantPicker(
  BuildContext context,
  String type,
) => showModalBottomSheet<RegisteredEntity>(
  context: context,
  showDragHandle: true,
  useSafeArea: true,
  isScrollControlled: true,
  builder: (_) => _MerchantPicker(type: type),
);

class _MerchantPicker extends StatefulWidget {
  final String type;
  const _MerchantPicker({required this.type});
  @override
  State<_MerchantPicker> createState() => _MerchantPickerState();
}

class _MerchantPickerState extends State<_MerchantPicker> {
  late Future<List<RegisteredEntity>> entries;
  @override
  void initState() {
    super.initState();
    entries = _load();
  }

  Future<List<RegisteredEntity>> _load() =>
      context.read<RegisteredEntityRepository>().getAll();
  @override
  Widget build(BuildContext context) => SizedBox(
    height: MediaQuery.sizeOf(context).height * .65,
    child: Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Saved merchants',
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ),
        ),
        Expanded(
          child: FutureBuilder<List<RegisteredEntity>>(
            future: entries,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return Center(
                  child: TextButton(
                    onPressed: () => setState(() {
                      entries = _load();
                    }),
                    child: const Text('Could not load merchants. Retry'),
                  ),
                );
              }
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final matching = snapshot.data!
                  .where((e) => e.type == widget.type || e.type == 'both')
                  .toList();
              if (matching.isEmpty) {
                return const Center(child: Text('No saved merchants yet'));
              }
              return ListView.builder(
                itemCount: matching.length,
                itemBuilder: (context, i) {
                  final e = matching[i];
                  return ListTile(
                    leading: const Icon(AppIcons.merchant),
                    title: Text(e.name),
                    subtitle: Text(e.category),
                    onTap: () => Navigator.pop(context, e),
                  );
                },
              );
            },
          ),
        ),
        const Divider(height: 1),
        SafeArea(
          top: false,
          child: ListTile(
            leading: const Icon(Icons.tune_rounded),
            title: const Text('Manage saved merchants'),
            trailing: const Icon(AppIcons.chevron),
            onTap: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SmartRulesScreen()),
              );
              if (mounted) {
                setState(() {
                  entries = _load();
                });
              }
            },
          ),
        ),
      ],
    ),
  );
}
