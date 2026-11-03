import '../../widgets/app_date_picker.dart';
import '../../widgets/page_loading.dart';
import 'package:expencify/presentation/theme/app_icons.dart';
import '../../../domain/entities/account.dart';
import 'dart:async';
import '../../widgets/form_save_button.dart';
import '../../../application/services/notifications/notification_service.dart';
import '../../widgets/tool_cards.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import '../../../domain/entities/subscription.dart';
import '../../../application/blocs/subscription/subscription_bloc.dart';
import '../../../application/blocs/subscription/subscription_event.dart';
import '../../../application/blocs/subscription/subscription_state.dart';
import '../../../application/blocs/account/account_bloc.dart';
import '../../../application/blocs/account/account_state.dart';
import 'package:flutter/services.dart';

class SubscriptionsScreen extends StatefulWidget {
  const SubscriptionsScreen({super.key});

  @override
  State<SubscriptionsScreen> createState() => _SubscriptionsScreenState();
}

class _SubscriptionsScreenState extends State<SubscriptionsScreen> {
  final _amountFmt = NumberFormat.currency(
    locale: 'en_IN',
    symbol: '₹',
    decimalDigits: 0,
  );
  final _dateFmt = DateFormat('d MMM yyyy');

  @override
  void initState() {
    super.initState();
    context.read<SubscriptionBloc>().add(ScanForPotentialSubscriptions());
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
        title: const Text('Subscriptions'),
        backgroundColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.maybePop(context),
        ),
        actions: [
          BlocBuilder<SubscriptionBloc, SubscriptionState>(
            builder: (context, state) =>
                state is SubscriptionLoaded && state.subscriptions.isEmpty
                ? const SizedBox.shrink()
                : IconButton(
                    tooltip: 'Add subscription',
                    icon: const Icon(AppIcons.add),
                    onPressed: () => _showAddSubscriptionModal(context),
                  ),
          ),
        ],
      ),
      body: RefreshFeedback<SubscriptionBloc, SubscriptionState>(
        onRetry: () =>
            context.read<SubscriptionBloc>().add(LoadSubscriptions()),
        child: BlocBuilder<SubscriptionBloc, SubscriptionState>(
          builder: (context, state) {
            if (state is SubscriptionLoading || state is SubscriptionInitial) {
              return const PageLoading(
                label: 'Loading subscription',
                summary: false,
              );
            }

            if (state is SubscriptionLoaded) {
              if (state.subscriptions.isEmpty && state.potentials.isEmpty) {
                return _buildEmptyState(theme);
              }
              return ListView(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 8,
                ),
                physics: const BouncingScrollPhysics(),
                children: [
                  if (state.potentials.isNotEmpty)
                    _buildPotentialsSection(theme, state.potentials),
                  if (state.subscriptions.isEmpty)
                    _buildEmptyState(theme)
                  else
                    _buildActiveSubscriptions(
                      theme,
                      state.subscriptions,
                      showHeading: state.potentials.isNotEmpty,
                    ),
                  const SizedBox(height: 100),
                ],
              );
            }

            if (state is SubscriptionError) {
              return PageLoadFailure(
                onRetry: () =>
                    context.read<SubscriptionBloc>().add(LoadSubscriptions()),
              );
            }

            return const SizedBox.shrink();
          },
        ),
      ),
    );
  }

  Widget _buildPotentialsSection(
    ThemeData theme,
    List<SubscriptionModel> potentials,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Text(
            'SUGGESTED FOR YOU',
            style: theme.textTheme.labelLarge?.copyWith(
              color: theme.colorScheme.primary,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.2,
            ),
          ),
        ),
        SizedBox(
          height: 160,
          child: ListView.builder(
            clipBehavior: Clip.none,
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            itemCount: potentials.length,
            itemBuilder: (context, index) {
              final p = potentials[index];
              return _buildPotentialCard(theme, p);
            },
          ),
        ),
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 24),
          child: Divider(),
        ),
      ],
    );
  }

  Widget _buildPotentialCard(ThemeData theme, SubscriptionModel p) {
    return Container(
      width: 200,
      margin: const EdgeInsets.only(right: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            theme.colorScheme.primary,
            theme.colorScheme.primary.withOpacity(0.7),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: theme.colorScheme.primary.withOpacity(0.3),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.auto_awesome_rounded,
            color: Colors.white.withOpacity(0.9),
            size: 22,
          ),
          const Spacer(),
          Text(
            p.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            _amountFmt.format(p.amount),
            style: TextStyle(
              color: Colors.white.withOpacity(0.95),
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () async {
                await NotificationService().requestPermission(scheduled: true);
                if (!mounted) return;
                context.read<SubscriptionBloc>().add(AddSubscription(p));
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: theme.colorScheme.primary,
                padding: EdgeInsets.zero,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 0,
              ),
              child: const Text(
                'Track',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(ThemeData theme) => ToolEmptyState(
    icon: AppIcons.recurring,
    title: 'Your subscriptions in one place',
    action: 'Add subscription',
    onAction: () => _showAddSubscriptionModal(context),
  );

  Widget _buildActiveSubscriptions(
    ThemeData theme,
    List<SubscriptionModel> subscriptions, {
    bool showHeading = false,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (showHeading)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              'Tracked subscriptions',
              style: theme.textTheme.labelLarge?.copyWith(
                color: theme.colorScheme.onSurface.withOpacity(0.4),
                fontWeight: FontWeight.w800,
                letterSpacing: 1.2,
              ),
            ),
          ),
        ...subscriptions.map((s) => _buildSubscriptionListTile(theme, s)),
      ],
    );
  }

  Widget _buildSubscriptionListTile(ThemeData theme, SubscriptionModel s) {
    final daysRemaining = s.nextDueDate.difference(DateTime.now()).inDays;
    return ToolCard(
      title: s.name,
      amount: _amountFmt.format(s.amount),
      detail:
          '${s.frequency.capitalize()} · Next ${_dateFmt.format(s.nextDueDate)}',
      icon: AppIcons.recurring,
      status: daysRemaining < 0
          ? 'Past due'
          : daysRemaining <= 3
          ? 'Due soon'
          : null,
      urgent: daysRemaining < 0,
      onDelete: () =>
          context.read<SubscriptionBloc>().add(DeleteSubscription(s.id!)),
    );
  }

  void _showAddSubscriptionModal(BuildContext context) {
    final nameCtrl = TextEditingController();
    final amountCtrl = TextEditingController();
    final merchantCtrl = TextEditingController();
    final formKey = GlobalKey<FormState>();
    final accountState = context.read<AccountBloc>().state;
    final accounts = accountState is AccountLoaded
        ? accountState.accounts
        : <Account>[];
    int? selectedAccountId = accountState is AccountLoaded
        ? accountState.selectedAccountId
        : null;
    if (selectedAccountId == null && accounts.length == 1) {
      selectedAccountId = accounts.single.id;
    }
    DateTime selectedDate = DateTime.now();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) {
          final theme = Theme.of(ctx);
          final dark = theme.brightness == Brightness.dark;

          return Container(
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(28),
              ),
            ),
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(ctx).viewInsets.bottom,
            ),
            child: SafeArea(
              child: SingleChildScrollView(
                child: Form(
                  key: formKey,
                  child: Padding(
                    padding: const EdgeInsets.only(
                      top: 20,
                      left: 20,
                      right: 20,
                      bottom: 20,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'New Subscription',
                              style: theme.textTheme.titleLarge?.copyWith(
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
                          theme: theme,
                          label: 'Name (e.g. Netflix)',
                          controller: nameCtrl,
                          icon: Icons.subscriptions_outlined,
                        ),
                        const SizedBox(height: 16),
                        DropdownButtonFormField<int>(
                          initialValue: selectedAccountId,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: 'Paying account',
                          ),
                          items: accounts
                              .map(
                                (a) => DropdownMenuItem(
                                  value: a.id,
                                  child: Text(a.name),
                                ),
                              )
                              .toList(),
                          validator: (value) =>
                              value == null ? 'Choose an account' : null,
                          onChanged: (value) =>
                              setS(() => selectedAccountId = value),
                        ),
                        const SizedBox(height: 16),
                        _buildField(
                          theme: theme,
                          label: 'Monthly Amount (₹)',
                          controller: amountCtrl,
                          icon: Icons.attach_money_rounded,
                          type: TextInputType.number,
                        ),
                        const SizedBox(height: 16),
                        _buildField(
                          theme: theme,
                          label: 'SMS Keywords (Optional)',
                          controller: merchantCtrl,
                          icon: Icons.memory_rounded,
                        ),
                        const SizedBox(height: 16),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Next Billing Date',
                              style: theme.textTheme.labelMedium?.copyWith(
                                color: theme.colorScheme.onSurface.withOpacity(
                                  0.6,
                                ),
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 8),
                            InkWell(
                              onTap: () async {
                                final d = await showAppDatePicker(
                                  title: 'Next renewal',
                                  context: ctx,
                                  initialDate: selectedDate,
                                  firstDate: DateTime(2020),
                                  lastDate: DateTime(2100),
                                );
                                if (d != null) setS(() => selectedDate = d);
                              },
                              borderRadius: BorderRadius.circular(14),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 14,
                                ),
                                decoration: BoxDecoration(
                                  color: dark
                                      ? const Color(0xFF18181B)
                                      : const Color(0xFFF4F4F5),
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      AppIcons.calendar,
                                      size: 20,
                                      color: theme.colorScheme.primary,
                                    ),
                                    const SizedBox(width: 12),
                                    Text(
                                      _dateFmt.format(selectedDate),
                                      style: theme.textTheme.bodyMedium,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 24),
                        SizedBox(
                          width: double.infinity,
                          child: FormSaveButton(
                            onSaved: () => Navigator.pop(ctx),
                            onSave: () async {
                              if (!formKey.currentState!.validate()) {
                                return null;
                              }
                              final accountState = context
                                  .read<AccountBloc>()
                                  .state;
                              if (accountState is AccountLoaded &&
                                  accountState.accounts.isNotEmpty) {
                                final sub = SubscriptionModel(
                                  name: nameCtrl.text.trim(),
                                  amount: double.parse(amountCtrl.text),
                                  merchant: merchantCtrl.text.isEmpty
                                      ? nameCtrl.text
                                      : merchantCtrl.text,
                                  startDate: selectedDate,
                                  nextDueDate:
                                      selectedDate, // Start tracking from this date
                                  accountId: selectedAccountId!,
                                );
                                await NotificationService().requestPermission(
                                  scheduled: true,
                                );
                                if (!context.mounted || !ctx.mounted) {
                                  return null;
                                }
                                final completion = Completer<bool>();
                                context.read<SubscriptionBloc>().add(
                                  AddSubscription(sub, completion: completion),
                                );
                                return completion.future;
                              }
                              return false;
                            },
                            style: ElevatedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                            ),
                            child: const Text(
                              'Save Subscription',
                              style: TextStyle(
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
        },
      ),
    );
  }

  Widget _buildField({
    required ThemeData theme,
    required String label,
    required TextEditingController controller,
    IconData? icon,
    TextInputType? type,
  }) {
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
          validator: (value) {
            if (type == TextInputType.number) {
              final amount = double.tryParse(value ?? '');
              return amount == null || !amount.isFinite || amount <= 0
                  ? 'Enter an amount greater than zero'
                  : null;
            }
            if (label.startsWith('Name') &&
                (value == null || value.trim().isEmpty)) {
              return 'Enter a name';
            }
            return null;
          },
          controller: controller,
          keyboardType: type,
          decoration: InputDecoration(
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
}

extension StringExtension on String {
  String capitalize() {
    if (isEmpty) return this;
    return '${this[0].toUpperCase()}${substring(1)}';
  }
}
