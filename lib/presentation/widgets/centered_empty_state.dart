import 'package:flutter/material.dart';

/// Center empty content in its viewport; allow scrolling when text is larger.
class CenteredEmptyState extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  const CenteredEmptyState({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(24),
  });
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => SingleChildScrollView(
      physics: constraints.hasBoundedHeight
          ? const AlwaysScrollableScrollPhysics()
          : const NeverScrollableScrollPhysics(),
      padding: padding,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          minHeight: constraints.hasBoundedHeight
              ? (constraints.maxHeight - padding.vertical).clamp(
                  0,
                  double.infinity,
                )
              : 0,
        ),
        child: Center(child: child),
      ),
    ),
  );
}
