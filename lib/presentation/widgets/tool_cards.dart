import 'app_menu_item.dart';
import 'package:expencify/presentation/theme/app_icons.dart';
import 'centered_empty_state.dart';
import 'package:flutter/material.dart';

/// Consistent, responsive cards for the secondary finance tools.
class ToolCard extends StatelessWidget {
  final String title;
  final String amount;
  final String detail;
  final IconData icon;
  final Widget? leading;
  final String? status;
  final bool urgent;
  final double? progress;
  final String? progressLabel;
  final String? actionLabel;
  final VoidCallback? onAction;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  const ToolCard({
    super.key,
    required this.title,
    required this.amount,
    required this.detail,
    required this.icon,
    this.leading,
    this.status,
    this.urgent = false,
    this.progress,
    this.progressLabel,
    this.actionLabel,
    this.onAction,
    this.onEdit,
    this.onDelete,
  });
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final menu = PopupMenuButton<String>(
      clipBehavior: Clip.antiAlias,
      tooltip: 'Options for $title',
      icon: const Icon(AppIcons.more),
      onSelected: (value) {
        if (value == 'edit') onEdit?.call();
        if (value == 'delete') onDelete?.call();
      },
      itemBuilder: (_) => [
        if (onEdit != null)
          const AppMenuItem(value: 'edit', label: 'Edit', icon: AppIcons.edit),
        if (onDelete != null && onEdit != null)
          const PopupMenuDivider(height: 12),
        if (onDelete != null)
          const AppMenuItem(
            value: 'delete',
            label: 'Delete',
            icon: AppIcons.delete,
            destructive: true,
          ),
      ],
    );
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: cs.onSurface.withValues(alpha: .10)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(
                  color: cs.primary.withValues(alpha: .08),
                  borderRadius: BorderRadius.circular(12),
                ),
                child:
                    leading ??
                    Icon(
                      icon,
                      size: AppIcons.detailSize,
                      color: AppIcons.actionColor(theme),
                    ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (progress == null) ...[
                      const SizedBox(height: 4),
                      Text(
                        detail,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (onEdit != null && onDelete == null)
                IconButton(
                  tooltip: 'Edit $title',
                  onPressed: onEdit,
                  icon: const Icon(AppIcons.edit, size: 20),
                )
              else if (onEdit != null || onDelete != null)
                menu,
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                amount,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (status != null)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: urgent ? cs.errorContainer : cs.primaryContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    status!,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: urgent
                          ? cs.onErrorContainer
                          : cs.onPrimaryContainer,
                    ),
                  ),
                ),
              if (progress == null && onAction != null)
                TextButton.icon(
                  onPressed: onAction,
                  icon: const Icon(AppIcons.success, size: 20),
                  label: Text(actionLabel!),
                ),
            ],
          ),
          if (progress != null) ...[
            const SizedBox(height: 6),
            Text(
              detail,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
          ],
          if (progress != null) ...[
            const SizedBox(height: 16),
            Semantics(
              label: 'Savings progress',
              value: '${(progress! * 100).round()} percent',
              child: LinearProgressIndicator(
                value: progress,
                color: cs.primary,
                backgroundColor: cs.primary.withValues(alpha: .12),
                minHeight: 7,
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            if (progressLabel != null) ...[
              const SizedBox(height: 8),
              Text(
                progressLabel!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
              ),
            ],
          ],
          if (onAction != null && progress != null) ...[
            const SizedBox(height: 8),
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: TextButton.icon(
                onPressed: onAction,
                icon: Icon(
                  progress == null ? AppIcons.success : AppIcons.add,
                  size: 20,
                ),
                label: Text(actionLabel!),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class ToolEmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String action;
  final VoidCallback onAction;
  final String? description;
  const ToolEmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.action,
    required this.onAction,
    this.description,
  });
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return CenteredEmptyState(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: AppIcons.emptySize,
            color: AppIcons.actionColor(theme),
          ),
          const SizedBox(height: 16),
          Text(
            title,
            textAlign: TextAlign.center,
            style: theme.textTheme.titleLarge,
          ),
          if (description != null) ...[
            const SizedBox(height: 12),
            Text(
              description!,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium,
            ),
          ],
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: onAction,
            icon: const Icon(AppIcons.add),
            label: Text(action),
          ),
        ],
      ),
    );
  }
}
