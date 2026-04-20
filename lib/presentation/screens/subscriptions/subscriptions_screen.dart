import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import '../../../domain/entities/subscription.dart';
import '../../../application/blocs/subscription/subscription_bloc.dart';
import '../../../application/blocs/subscription/subscription_event.dart';
import '../../../application/blocs/subscription/subscription_state.dart';
import '../../../application/blocs/account/account_bloc.dart';
import '../../../application/blocs/account/account_state.dart';

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
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          _buildSliverAppBar(theme),
          BlocBuilder<SubscriptionBloc, SubscriptionState>(
            builder: (context, state) {
              if (state is SubscriptionLoading) {
                return const SliverFillRemaining(
                  child: Center(child: CircularProgressIndicator()),
                );
              }

              if (state is SubscriptionLoaded) {
                return SliverList(
                  delegate: SliverChildListDelegate([
                    if (state.potentials.isNotEmpty) _buildPotentialsSection(theme, state.potentials),
                    if (state.subscriptions.isEmpty)
                      _buildEmptyState(theme)
                    else
                      _buildActiveSubscriptions(theme, state.subscriptions),
                    const SizedBox(height: 100),
                  ]),
                );
              }

              if (state is SubscriptionError) {
                return SliverFillRemaining(
                  child: Center(child: Text('Error: ${state.message}')),
                );
              }

              return const SliverToBoxAdapter(child: SizedBox.shrink());
            },
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAddSubscriptionDialog(context),
        label: const Text('Add subscription'),
        icon: const Icon(Icons.add_rounded),
        backgroundColor: theme.colorScheme.primary,
        foregroundColor: Colors.white,
      ),
    );
  }

  Widget _buildSliverAppBar(ThemeData theme) {
    return SliverAppBar(
      expandedHeight: 120,
      floating: false,
      pinned: true,
      elevation: 0,
      backgroundColor: theme.colorScheme.surface,
      flexibleSpace: FlexibleSpaceBar(
        centerTitle: false,
        titlePadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        title: Text(
          'Subscriptions',
          style: theme.textTheme.displaySmall?.copyWith(fontSize: 24),
        ),
      ),
    );
  }

  Widget _buildPotentialsSection(ThemeData theme, List<SubscriptionModel> potentials) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
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
            padding: const EdgeInsets.symmetric(horizontal: 14),
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
          padding: EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          child: Divider(),
        ),
      ],
    );
  }

  Widget _buildPotentialCard(ThemeData theme, SubscriptionModel p) {
    return Container(
      width: 200,
      margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [theme.colorScheme.primary, theme.colorScheme.secondary],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: theme.colorScheme.primary.withOpacity(0.2),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.auto_awesome_rounded, color: Colors.white.withOpacity(0.8), size: 20),
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
            style: TextStyle(color: Colors.white.withOpacity(0.9), fontSize: 18, fontWeight: FontWeight.w900),
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
    return Padding(
      padding: const EdgeInsets.all(40),
      child: Column(
        children: [
          Icon(Icons.calendar_today_rounded, size: 80, color: theme.colorScheme.onSurface.withOpacity(0.1)),
          const SizedBox(height: 24),
          Text(
            'No active subscriptions',
            style: theme.textTheme.titleMedium?.copyWith(color: theme.colorScheme.onSurface.withOpacity(0.4)),
          ),
          const SizedBox(height: 8),
          Text(
            'Add your Netflix, Spotify or Gym memberships to track them here.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurface.withOpacity(0.3)),
          ),
        ],
      ),
    );
  }

  Widget _buildActiveSubscriptions(ThemeData theme, List<SubscriptionModel> subscriptions) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
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

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: InkWell(
        onTap: () => _showSubscriptionOptions(s),
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: theme.colorScheme.onSurface.withOpacity(0.05)),
            boxShadow: [
              BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 10, offset: const Offset(0, 4)),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(14),
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
                    style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900, letterSpacing: -0.5),
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
      ),
    );
  }

  void _showSubscriptionOptions(SubscriptionModel s) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 12),
          Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 24),
          ListTile(
            leading: const Icon(Icons.delete_outline_rounded, color: Colors.red),
            title: const Text('Delete Subscription', style: TextStyle(color: Colors.red)),
            onTap: () {
              Navigator.pop(ctx);
              context.read<SubscriptionBloc>().add(DeleteSubscription(s.id!));
            },
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  void _showAddSubscriptionDialog(BuildContext context) {
    final nameCtrl = TextEditingController();
    final amountCtrl = TextEditingController();
    final merchantCtrl = TextEditingController();
    DateTime selectedDate = DateTime.now();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('New Subscription'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Name (e.g. Netflix)')),
              TextField(controller: merchantCtrl, decoration: const InputDecoration(labelText: 'Merchant Icon Keywords')),
              TextField(controller: amountCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Monthly Amount')),
              const SizedBox(height: 16),
              ListTile(
                title: const Text('Start Date'),
                subtitle: Text(_dateFmt.format(selectedDate)),
                onTap: () async {
                  final d = await showDatePicker(context: ctx, initialDate: selectedDate, firstDate: DateTime(2020), lastDate: DateTime(2100));
                  if (d != null) selectedDate = d;
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              final accountState = context.read<AccountBloc>().state;
              if (accountState is AccountLoaded) {
                final sub = SubscriptionModel(
                  name: nameCtrl.text,
                  amount: double.tryParse(amountCtrl.text) ?? 0.0,
                  merchant: merchantCtrl.text.isEmpty ? nameCtrl.text : merchantCtrl.text,
                  startDate: selectedDate,
                  nextDueDate: selectedDate.add(const Duration(days: 30)),
                  accountId: accountState.selectedAccountId ?? accountState.accounts.first.id!,
                );
                context.read<SubscriptionBloc>().add(AddSubscription(sub));
                Navigator.pop(ctx);
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }
}

extension StringExtension on String {
  String capitalize() {
    if (isEmpty) return this;
    return '${this[0].toUpperCase()}${substring(1)}';
  }
}
