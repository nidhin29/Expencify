import 'package:expencify/presentation/theme/app_icons.dart';
import 'package:flutter/material.dart';

class BudgetWelcomeCard extends StatelessWidget {
  final VoidCallback onCreate;
  const BudgetWelcomeCard({super.key, required this.onCreate});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: theme.colorScheme.primary.withValues(alpha: .045),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: theme.colorScheme.primary.withValues(alpha: .12),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withValues(alpha: .1),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Icon(
              Icons.donut_small_rounded,
              size: 32,
              color: theme.colorScheme.primary,
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'A little plan.\nA lot more clarity.',
            textAlign: TextAlign.center,
            style: theme.textTheme.displaySmall?.copyWith(
              fontWeight: FontWeight.w700,
              height: 1.2,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Start with one spending limit. See what is left as you add expenses.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 24),
          Text('CATEGORY IDEAS', style: theme.textTheme.labelSmall),
          const SizedBox(height: 10),
          const Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: [
              Chip(
                avatar: Icon(Icons.restaurant_outlined, size: 16),
                label: Text('Food'),
              ),
              Chip(
                avatar: Icon(Icons.train_outlined, size: 16),
                label: Text('Transport'),
              ),
              Chip(
                avatar: Icon(Icons.shopping_bag_outlined, size: 16),
                label: Text('Shopping'),
              ),
            ],
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: onCreate,
              icon: const Icon(AppIcons.add),
              label: const Text('Create budget', textAlign: TextAlign.center),
            ),
          ),
        ],
      ),
    );
  }
}
