import 'package:flutter/material.dart';
import '../theme/app_icons.dart';

class ReceiptScanOverlay extends StatelessWidget {
  final bool active;
  final Widget child;
  const ReceiptScanOverlay({
    super.key,
    required this.active,
    required this.child,
  });
  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      ExcludeFocus(
        excluding: active,
        child: ExcludeSemantics(
          excluding: active,
          child: AbsorbPointer(absorbing: active, child: child),
        ),
      ),
      if (active) ...[
        ModalBarrier(
          dismissible: false,
          color: Theme.of(context).colorScheme.scrim.withValues(alpha: .35),
        ),
        const Center(child: ReceiptScanProgress()),
      ],
    ],
  );
}

class ReceiptScanProgress extends StatefulWidget {
  const ReceiptScanProgress({super.key});
  @override
  State<ReceiptScanProgress> createState() => _ReceiptScanProgressState();
}

class _ReceiptScanProgressState extends State<ReceiptScanProgress>
    with SingleTickerProviderStateMixin {
  late final _animation = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _animation.stop();
    } else if (!_animation.isAnimating) {
      _animation.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _animation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final reduced = MediaQuery.disableAnimationsOf(context);
    return Semantics(
      liveRegion: true,
      label: 'Scanning receipt. Reading the total and item amounts.',
      child: ExcludeSemantics(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 340),
            child: Material(
              color: cs.surface,
              borderRadius: BorderRadius.circular(28),
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 96,
                      height: 96,
                      decoration: BoxDecoration(
                        color: cs.primary.withValues(alpha: .08),
                        borderRadius: BorderRadius.circular(24),
                      ),
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          Icon(
                            AppIcons.transactions,
                            size: 48,
                            color: cs.primary,
                          ),
                          if (!reduced)
                            AnimatedBuilder(
                              animation: _animation,
                              builder: (context, _) => Transform.translate(
                                offset: Offset(0, -28 + 56 * _animation.value),
                                child: Container(
                                  key: const ValueKey('receipt-scan-beam'),
                                  width: 72,
                                  height: 3,
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(2),
                                    gradient: LinearGradient(
                                      colors: [
                                        cs.primary.withValues(alpha: 0),
                                        cs.primary,
                                        cs.primary.withValues(alpha: 0),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'Scanning receipt',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Reading the total and item amounts…',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: cs.onSurfaceVariant,
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
  }
}
