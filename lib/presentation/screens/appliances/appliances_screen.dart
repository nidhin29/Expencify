import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';

import 'package:expencify/domain/entities/appliance.dart';
import 'package:expencify/application/blocs/appliance/appliance_bloc.dart';
import 'package:expencify/application/blocs/appliance/appliance_event.dart';
import 'package:expencify/application/blocs/appliance/appliance_state.dart';

class AppliancesScreen extends StatefulWidget {
  const AppliancesScreen({super.key});

  @override
  State<AppliancesScreen> createState() => _AppliancesScreenState();
}

class _AppliancesScreenState extends State<AppliancesScreen> {
  final _rupeeFmt = NumberFormat.currency(
    locale: 'en_IN',
    symbol: '₹',
    decimalDigits: 0,
  );

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    context.read<ApplianceBloc>().add(LoadAppliances());
  }

  Future<void> _showApplianceModal({Appliance? existing}) async {
    final formKey = GlobalKey<FormState>();
    final nameCtrl = TextEditingController(text: existing?.name ?? '');
    final brandCtrl = TextEditingController(text: existing?.brand ?? '');
    final amcAmtCtrl = TextEditingController(
      text: existing?.amcAmount.toStringAsFixed(0) ?? '',
    );
    DateTime purchaseDate =
        existing?.purchaseDate ??
        DateTime.now().subtract(const Duration(days: 30));
    DateTime amcDate =
        existing?.amcExpiryDate ??
        DateTime.now().add(const Duration(days: 365));

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => Container(
          decoration: BoxDecoration(
            color: Theme.of(ctx).colorScheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          ),
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
            top: 20,
            left: 20,
            right: 20,
          ),
          child: Form(
            key: formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        existing != null ? 'Edit Appliance' : 'New Appliance',
                        style: Theme.of(ctx).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.5,
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(ctx),
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  _buildField(
                    label: 'Appliance Name',
                    controller: nameCtrl,
                    hint: 'e.g. Living Room AC',
                    icon: Icons.devices_other_outlined,
                    validator: (v) => (v?.isEmpty ?? true) ? 'Required' : null,
                  ),
                  const SizedBox(height: 16),
                  _buildField(
                    label: 'Brand',
                    controller: brandCtrl,
                    hint: 'e.g. Samsung / Sony',
                    icon: Icons.branding_watermark_outlined,
                  ),
                  const SizedBox(height: 16),
                  _buildField(
                    label: 'AMC Amount (₹)',
                    controller: amcAmtCtrl,
                    hint: '0.00',
                    icon: Icons.payments_outlined,
                    keyboardType: TextInputType.number,
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: _buildDatePicker(
                          label: 'Purchase Date',
                          value: purchaseDate,
                          icon: Icons.shopping_bag_outlined,
                          onTap: () async {
                            final d = await showDatePicker(
                              context: ctx,
                              initialDate: purchaseDate,
                              firstDate: DateTime(2000),
                              lastDate: DateTime.now(),
                            );
                            if (d != null) setS(() => purchaseDate = d);
                          },
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: _buildDatePicker(
                          label: 'AMC Expiry',
                          value: amcDate,
                          icon: Icons.event_available_outlined,
                          onTap: () async {
                            final d = await showDatePicker(
                              context: ctx,
                              initialDate: amcDate,
                              firstDate: DateTime.now(),
                              lastDate: DateTime(2035),
                            );
                            if (d != null) setS(() => amcDate = d);
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () async {
                        if (!formKey.currentState!.validate()) return;
                        final a = Appliance(
                          id: existing?.id,
                          name: nameCtrl.text.trim(),
                          brand: brandCtrl.text.trim(),
                          purchaseDate: purchaseDate,
                          amcExpiryDate: amcDate,
                          amcAmount: double.tryParse(amcAmtCtrl.text) ?? 0,
                        );
                        if (existing != null) {
                          context.read<ApplianceBloc>().add(SaveAppliance(a));
                        } else {
                          context.read<ApplianceBloc>().add(SaveAppliance(a));
                        }
                        if (ctx.mounted) Navigator.pop(ctx);
                      },
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      child: Text(
                        existing != null ? 'Update Appliance' : 'Add Appliance',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
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
    );
  }

  Widget _buildField({
    required String label,
    required TextEditingController controller,
    String? hint,
    IconData? icon,
    TextInputType? keyboardType,
    String? Function(String?)? validator,
  }) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: theme.textTheme.labelMedium?.copyWith(
            color: theme.colorScheme.onSurface.withOpacity(0.6),
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: controller,
          keyboardType: keyboardType,
          validator: validator,
          decoration: InputDecoration(
            hintText: hint,
            prefixIcon: icon != null
                ? Icon(icon, size: 20, color: theme.colorScheme.primary)
                : null,
            filled: true,
            fillColor: dark ? const Color(0xFF18181B) : const Color(0xFFF4F4F5),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide.none,
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 14,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDatePicker({
    required String label,
    required DateTime value,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: theme.textTheme.labelMedium?.copyWith(
            color: theme.colorScheme.onSurface.withOpacity(0.6),
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
            decoration: BoxDecoration(
              color: dark ? const Color(0xFF18181B) : const Color(0xFFF4F4F5),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                Icon(icon, size: 20, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    DateFormat('d MMM yy').format(value),
                    style: theme.textTheme.bodyMedium,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
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
          statusBarBrightness: theme.brightness, // For iOS
        ),
        title: const Text('Appliances Tracker'),
        backgroundColor: Colors.transparent,
        actions: [
          IconButton(
            icon: const Icon(Icons.add_rounded),
            onPressed: () => _showApplianceModal(),
          ),
        ],
      ),
      body: BlocBuilder<ApplianceBloc, ApplianceState>(
        builder: (context, state) {
          if (state is ApplianceLoading) {
            return const Center(child: CircularProgressIndicator());
          } else if (state is ApplianceLoaded) {
            final appliances = state.appliances;
            if (appliances.isEmpty) {
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text('🏠', style: TextStyle(fontSize: 60)),
                    const SizedBox(height: 12),
                    Text(
                      'No appliances yet',
                      style: theme.textTheme.titleLarge?.copyWith(
                        color: theme.colorScheme.onSurface.withOpacity(0.4),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Track AMC renewals for your appliances',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurface.withOpacity(0.3),
                      ),
                    ),
                  ],
                ),
              );
            }
            return ListView.builder(
              padding: const EdgeInsets.all(20),
              itemCount: appliances.length,
              itemBuilder: (ctx, i) {
                final a = appliances[i];
                return Dismissible(
                  key: Key('appliance_${a.id}'),
                  direction: DismissDirection.endToStart,
                  background: Container(
                    margin: const EdgeInsets.only(bottom: 14),
                    decoration: BoxDecoration(
                      color: Colors.red,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    alignment: Alignment.centerRight,
                    padding: const EdgeInsets.only(right: 20),
                    child: const Icon(
                      Icons.delete_rounded,
                      color: Colors.white,
                    ),
                  ),
                  onDismissed: (_) async {
                    context.read<ApplianceBloc>().add(DeleteAppliance(a.id!));
                  },
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 14),
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surface,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: a.isExpired
                            ? Colors.red.withOpacity(0.4)
                            : a.isDueSoon
                            ? Colors.orange.withOpacity(0.4)
                            : theme.colorScheme.onSurface.withOpacity(0.08),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.04),
                          blurRadius: 8,
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: a.isExpired
                                ? Colors.red.withOpacity(0.1)
                                : a.isDueSoon
                                ? Colors.orange.withOpacity(0.1)
                                : Colors.teal.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Icon(
                            Icons.devices_other_rounded,
                            color: a.isExpired
                                ? Colors.red
                                : a.isDueSoon
                                ? Colors.orange
                                : Colors.teal,
                            size: 28,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                a.name,
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              if (a.brand.isNotEmpty)
                                Text(
                                  a.brand,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.onSurface
                                        .withOpacity(0.5),
                                  ),
                                ),
                              Text(
                                'AMC: ${DateFormat('d MMM yyyy').format(a.amcExpiryDate)}',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: a.isExpired
                                      ? Colors.red
                                      : theme.colorScheme.onSurface.withOpacity(
                                          0.5,
                                        ),
                                ),
                              ),
                              if (a.amcAmount > 0)
                                Text(
                                  'Renewal: ${_rupeeFmt.format(a.amcAmount)}',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.onSurface
                                        .withOpacity(0.4),
                                  ),
                                ),
                            ],
                          ),
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.edit_rounded, size: 18),
                              onPressed: () => _showApplianceModal(existing: a),
                            ),
                            if (a.isExpired)
                              _badge('EXPIRED', Colors.red)
                            else if (a.isDueSoon)
                              _badge('DUE SOON', Colors.orange)
                            else
                              Text(
                                '${a.daysUntilExpiry}d',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onSurface
                                      .withOpacity(0.4),
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            );
          } else if (state is ApplianceError) {
            return Center(child: Text(state.message));
          }
          return const SizedBox.shrink();
        },
      ),
    );
  }

  Widget _badge(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
