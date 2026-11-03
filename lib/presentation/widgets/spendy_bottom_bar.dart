import 'package:expencify/presentation/theme/app_icons.dart';
import 'package:flutter/material.dart';

/// Destinations and the central creation action have distinct behavior.
/// The raised action stays inside the reserved bar area, clear of page content.
class SpendyBottomBar extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onSelect;
  final VoidCallback onAdd;
  const SpendyBottomBar({
    super.key,
    required this.selectedIndex,
    required this.onSelect,
    required this.onAdd,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final add = Semantics(
      button: true,
      label: 'Add transaction',
      onTap: onAdd,
      excludeSemantics: true,
      child: Tooltip(
        message: 'Add transaction',
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onAdd,
          child: SizedBox(
            width: 64,
            height: 84,
            child: Column(
              children: [
                Material(
                  color: theme.colorScheme.primary,
                  elevation: 3,
                  shadowColor: theme.colorScheme.primary.withValues(alpha: .25),
                  shape: const CircleBorder(),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: onAdd,
                    customBorder: const CircleBorder(),
                    child: const SizedBox(
                      width: 56,
                      height: 56,
                      child: Icon(AppIcons.add, size: 30, color: Colors.white),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  height: 16,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      'Add',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.primary,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    return SafeArea(
      top: false,
      child: SizedBox(
        height: 96,
        child: Stack(
          children: [
            Positioned.fill(
              child: PhysicalShape(
                clipper: _BarClipper(),
                elevation: 8,
                color: theme.colorScheme.surface,
                shadowColor: Colors.black.withValues(alpha: .12),
                clipBehavior: Clip.antiAlias,
                child: const SizedBox.expand(),
              ),
            ),
            Positioned.fill(
              top: 16,
              child: Row(
                children: [
                  _destination(
                    context,
                    0,
                    'Home',
                    AppIcons.home,
                    AppIcons.homeSelected,
                  ),
                  _destination(
                    context,
                    1,
                    'Transactions',
                    AppIcons.transactions,
                    AppIcons.transactionsSelected,
                  ),
                  const Expanded(child: SizedBox.shrink()),
                  _destination(
                    context,
                    2,
                    'Budget',
                    AppIcons.budget,
                    AppIcons.budgetSelected,
                  ),
                  _destination(
                    context,
                    3,
                    'Accounts',
                    AppIcons.accounts,
                    AppIcons.accountsSelected,
                  ),
                ],
              ),
            ),
            Align(alignment: Alignment.topCenter, child: add),
          ],
        ),
      ),
    );
  }

  Widget _destination(
    BuildContext context,
    int index,
    String label,
    IconData icon,
    IconData activeIcon,
  ) {
    final theme = Theme.of(context);
    final selected = selectedIndex == index;
    final color = selected
        ? AppIcons.actionColor(theme)
        : theme.colorScheme.onSurfaceVariant;
    final item = Semantics(
      button: true,
      selected: selected,
      label: label,
      onTap: () => onSelect(index),
      excludeSemantics: true,
      child: Tooltip(
        message: label,
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: () => onSelect(index),
            splashFactory: NoSplash.splashFactory,
            highlightColor: Colors.transparent,
            overlayColor: WidgetStateProperty.resolveWith(
              (states) => states.contains(WidgetState.pressed)
                  ? Colors.transparent
                  : null,
            ),
            borderRadius: BorderRadius.circular(18),
            child: SizedBox(
              height: 80,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      width: 48,
                      height: 34,
                      decoration: BoxDecoration(
                        color: selected
                            ? theme.colorScheme.primary.withValues(alpha: .1)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Icon(
                        selected ? activeIcon : icon,
                        size: AppIcons.actionSize,
                        color: color,
                      ),
                    ),
                    const SizedBox(height: 4),
                    ExcludeSemantics(
                      child: SizedBox(
                        height: 16,
                        width: double.infinity,
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            label,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: color,
                              fontSize: 11,
                              letterSpacing: 0,
                              fontWeight: selected
                                  ? FontWeight.w600
                                  : FontWeight.w500,
                            ),
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
      ),
    );
    return Expanded(child: item);
  }
}

class _BarClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) => const CircularNotchedRectangle().getOuterPath(
    Rect.fromLTWH(0, 18, size.width, size.height - 18),
    Rect.fromCircle(center: Offset(size.width / 2, 28), radius: 34),
  );
  @override
  bool shouldReclip(_BarClipper oldClipper) => false;
}
