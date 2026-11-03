import 'package:flutter/material.dart';
import '../theme/app_icons.dart';

/// Shared overflow action. Labels can wrap at larger accessibility text sizes.
class AppMenuItem<T> extends PopupMenuItem<T> {
  final String label;
  final IconData icon;
  final bool destructive;
  const AppMenuItem({
    super.key,
    super.value,
    super.enabled,
    required this.label,
    required this.icon,
    this.destructive = false,
  }) : super(
         height: 48,
         padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
         child: null,
       );
  @override
  PopupMenuItemState<T, AppMenuItem<T>> createState() => _AppMenuItemState<T>();
}

class _AppMenuItemState<T> extends PopupMenuItemState<T, AppMenuItem<T>> {
  @override
  Widget buildChild() => _MenuLabel(
    label: widget.label,
    icon: widget.icon,
    enabled: widget.enabled,
    destructive: widget.destructive,
  );
}

class _MenuLabel extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool enabled, destructive;
  const _MenuLabel({
    required this.label,
    required this.icon,
    required this.enabled,
    required this.destructive,
  });
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = !enabled
        ? theme.colorScheme.onSurfaceVariant.withValues(alpha: .45)
        : destructive
        ? AppIcons.dangerColor(theme)
        : theme.colorScheme.onSurface;
    return Row(
      children: [
        Icon(icon, size: 20, color: color),
        const SizedBox(width: 12),
        Flexible(
          child: Text(
            label,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              height: 1.4,
              color: color,
            ),
          ),
        ),
      ],
    );
  }
}
