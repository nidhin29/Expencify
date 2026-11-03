import '../../widgets/app_date_picker.dart';
import '../../widgets/page_loading.dart';
import 'package:expencify/presentation/theme/app_icons.dart';
import '../../../application/services/notifications/notification_service.dart';
import '../../widgets/tool_cards.dart';
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
    final bloc = context.read<ApplianceBloc>();
    await waitForPageLoad(
      bloc.stream,
      (state) =>
          state is ApplianceError ||
          (state is ApplianceLoaded && !state.refreshing),
      () => bloc.add(LoadAppliances()),
    );
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
                        tooltip: 'Close',
                        onPressed: () => Navigator.pop(ctx),
                        icon: const Icon(AppIcons.close),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  _buildField(
                    label: 'Appliance Name',
                    controller: nameCtrl,
                    hint: 'e.g. Living Room AC',
                    icon: AppIcons.appliances,
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
                            final d = await showAppDatePicker(
                              context: ctx,
                              title: 'Purchase date',
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
                            final d = await showAppDatePicker(
                              context: ctx,
                              title: 'AMC expiry date',
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
                        await NotificationService().requestPermission(
                          scheduled: true,
                        );
                        if (!mounted) return;
                        context.read<ApplianceBloc>().add(SaveAppliance(a));
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
        title: const Text('Appliances'),
        backgroundColor: Colors.transparent,
        actions: [
          BlocBuilder<ApplianceBloc, ApplianceState>(
            builder: (context, state) =>
                state is ApplianceLoaded && state.appliances.isEmpty
                ? const SizedBox.shrink()
                : IconButton(
                    tooltip: 'Add appliance',
                    icon: const Icon(AppIcons.add),
                    onPressed: () => _showApplianceModal(),
                  ),
          ),
        ],
      ),
      body: RefreshFeedback<ApplianceBloc, ApplianceState>(
        onRetry: _load,
        child: BlocBuilder<ApplianceBloc, ApplianceState>(
          builder: (context, state) {
            if (state is ApplianceLoading || state is ApplianceInitial) {
              return const PageLoading(
                label: 'Loading appliance',
                summary: false,
              );
            } else if (state is ApplianceLoaded) {
              final appliances = state.appliances;
              if (appliances.isEmpty) {
                return ToolEmptyState(
                  icon: AppIcons.appliances,
                  title: 'Keep your appliances covered',
                  action: 'Add appliance',
                  onAction: () => _showApplianceModal(),
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
                      child: const Icon(AppIcons.delete, color: Colors.white),
                    ),
                    onDismissed: (_) async {
                      context.read<ApplianceBloc>().add(DeleteAppliance(a.id!));
                    },
                    child: ToolCard(
                      title: a.name,
                      amount: a.amcAmount > 0
                          ? _rupeeFmt.format(a.amcAmount)
                          : 'AMC renewal',
                      detail:
                          '${a.brand.isNotEmpty ? '${a.brand} · ' : ''}${DateFormat('d MMM yyyy').format(a.amcExpiryDate)}',
                      icon: AppIcons.appliances,
                      status: a.isExpired
                          ? 'Expired'
                          : a.isDueSoon
                          ? 'Renewing soon'
                          : 'Covered',
                      urgent: a.isExpired,
                      onEdit: () => _showApplianceModal(existing: a),
                    ),
                  );
                },
              );
            } else if (state is ApplianceError) {
              return PageLoadFailure(onRetry: _load);
            }
            return const SizedBox.shrink();
          },
        ),
      ),
    );
  }
}
