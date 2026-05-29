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
import 'package:expencify/presentation/theme/app_theme.dart';

class SubscriptionsScreen extends StatefulWidget {
  const SubscriptionsScreen({super.key});

  @override
  State<SubscriptionsScreen> createState() => _SubscriptionsScreenState();
}

class _SubscriptionsScreenState extends State<SubscriptionsScreen> {
  final _amountFmt = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);
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
          IconButton(
            icon: const Icon(Icons.add_rounded),
            onPressed: () => _showAddSubscriptionModal(context),
          ),
        ],
      ),
      body: BlocBuilder<SubscriptionBloc, SubscriptionState>(
        builder: (context, state) {
          if (state is SubscriptionLoading) {
            return const Center(child: CircularProgressIndicator());
          }

          if (state is SubscriptionLoaded) {
            return ListView(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              physics: const BouncingScrollPhysics(),
              children: [
                if (state.potentials.isNotEmpty) _buildPotentialsSection(theme, state.potentials),
                if (state.subscriptions.isEmpty)
                  _buildEmptyState(theme)
                else
                  _buildActiveSubscriptions(theme, state.subscriptions),
                const SizedBox(height: 100),
              ],
            );
          }

          if (state is SubscriptionError) {
            return Center(child: Text('Error: ${state.message}'));
          }

          return const SizedBox.shrink();
        },
      ),
    );
  }

  Widget _buildPotentialsSection(ThemeData theme, List<SubscriptionModel> potentials) {
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
          colors: [theme.colorScheme.primary, theme.colorScheme.primary.withOpacity(0.7)],
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
          Icon(Icons.auto_awesome_rounded, color: Colors.white.withOpacity(0.9), size: 22),
          const Spacer(),
          Text(
            p.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
          ),
          const SizedBox(height: 2),
          Text(
            _amountFmt.format(p.amount),
            style: TextStyle(color: Colors.white.withOpacity(0.95), fontSize: 18, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () {
                context.read<SubscriptionBloc>().add(AddSubscription(p));
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: theme.colorScheme.primary,
                padding: EdgeInsets.zero,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                elevation: 0,
              ),
              child: const Text('Track', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(ThemeData theme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          children: [
            Icon(
              Icons.subscriptions_outlined,
              size: 64,
              color: theme.colorScheme.primary.withOpacity(0.2),
            ),
            const SizedBox(height: 16),
            Text(
              'No active subscriptions',
              style: theme.textTheme.titleMedium?.copyWith(
                color: theme.colorScheme.onSurface.withOpacity(0.4),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Tap + to track Netflix, Spotify, Gym, etc.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withOpacity(0.3),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActiveSubscriptions(ThemeData theme, List<SubscriptionModel> subscriptions) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Text(
            'ACTIVE',
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
    final dark = theme.brightness == Brightness.dark;

    return Dismissible(
      key: Key('sub_${s.id}'),
      direction: DismissDirection.endToStart,
      background: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: AppTheme.expense,
          borderRadius: BorderRadius.circular(12),
        ),
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        child: const Icon(Icons.delete_rounded, color: Colors.white),
      ),
      onDismissed: (_) {
        context.read<SubscriptionBloc>().add(DeleteSubscription(s.id!));
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: dark ? AppTheme.darkBorder : AppTheme.lightBorder,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: theme.colorScheme.primary.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(Icons.subscriptions_rounded, color: theme.colorScheme.primary),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    s.name,
                    style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Next: ${_dateFmt.format(s.nextDueDate)}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: daysRemaining <= 3 ? Colors.orange : theme.colorScheme.onSurface.withOpacity(0.4),
                      fontWeight: daysRemaining <= 3 ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  _amountFmt.format(s.amount),
                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.5),
                ),
                Text(
                  s.frequency.capitalize(),
                  style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurface.withOpacity(0.3)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _showAddSubscriptionModal(BuildContext context) {
    final nameCtrl = TextEditingController();
    final amountCtrl = TextEditingController();
    final merchantCtrl = TextEditingController();
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
              borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            ),
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(ctx).viewInsets.bottom,
            ),
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.only(top: 20, left: 20, right: 20, bottom: 20),
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
                      onPressed: () => Navigator.pop(ctx),
                      icon: const Icon(Icons.close_rounded),
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
                        color: theme.colorScheme.onSurface.withOpacity(0.6),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    InkWell(
                      onTap: () async {
                        final d = await showDatePicker(
                          context: ctx,
                          initialDate: selectedDate,
                          firstDate: DateTime(2020),
                          lastDate: DateTime(2100),
                        );
                        if (d != null) setS(() => selectedDate = d);
                      },
                      borderRadius: BorderRadius.circular(14),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                        decoration: BoxDecoration(
                          color: dark ? const Color(0xFF18181B) : const Color(0xFFF4F4F5),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.calendar_today_rounded, size: 20, color: theme.colorScheme.primary),
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
                  child: ElevatedButton(
                    onPressed: () {
                      final accountState = context.read<AccountBloc>().state;
                      if (accountState is AccountLoaded) {
                        final sub = SubscriptionModel(
                          name: nameCtrl.text,
                          amount: double.tryParse(amountCtrl.text) ?? 0.0,
                          merchant: merchantCtrl.text.isEmpty ? nameCtrl.text : merchantCtrl.text,
                          startDate: selectedDate,
                          nextDueDate: selectedDate, // Start tracking from this date
                          accountId: accountState.selectedAccountId ?? accountState.accounts.first.id!,
                        );
                        context.read<SubscriptionBloc>().add(AddSubscription(sub));
                        Navigator.pop(ctx);
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: const Text(
                      'Save Subscription',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                    ),
                  ),
                ],
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
        TextField(
          controller: controller,
          keyboardType: type,
          decoration: InputDecoration(
            prefixIcon: icon != null ? Icon(icon, size: 20, color: theme.colorScheme.primary) : null,
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
