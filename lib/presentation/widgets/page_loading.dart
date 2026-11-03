import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../application/blocs/refresh_status.dart';

Future<void> waitForPageLoad<S>(
  Stream<S> stream,
  bool Function(S) settled,
  VoidCallback start,
) async {
  final result = stream.firstWhere(settled);
  start();
  try {
    await result;
  } on StateError {
    /* Provider closed while leaving. */
  }
}

class PendingSetting extends StatefulWidget {
  const PendingSetting({super.key});
  @override
  State<PendingSetting> createState() => _PendingSettingState();
}

class _PendingSettingState extends State<PendingSetting> {
  Timer? _timer;
  bool _visible = false;
  @override
  void initState() {
    super.initState();
    _timer = Timer(const Duration(milliseconds: 220), () {
      if (mounted) setState(() => _visible = true);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 48,
    height: 32,
    child: _visible
        ? const Center(
            child: SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                semanticsLabel: 'Loading saved setting',
              ),
            ),
          )
        : null,
  );
}

/// Delayed, static placeholders avoid flashes and respect reduced motion.
class PageLoading extends StatefulWidget {
  final String label;
  final bool summary;
  const PageLoading({super.key, this.label = 'Loading', this.summary = false});
  @override
  State<PageLoading> createState() => _PageLoadingState();
}

class _PageLoadingState extends State<PageLoading> {
  Timer? _timer;
  bool _visible = false;
  @override
  void initState() {
    super.initState();
    _timer = Timer(const Duration(milliseconds: 220), () {
      if (mounted) setState(() => _visible = true);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_visible) return const SizedBox.expand();
    final colors = Theme.of(context).colorScheme;
    Widget bar(double width, double height) => Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: colors.onSurface.withValues(alpha: .07),
        borderRadius: BorderRadius.circular(8),
      ),
    );
    return Semantics(
      label: widget.label,
      liveRegion: true,
      child: ExcludeSemantics(
        child: SingleChildScrollView(
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              if (widget.summary) ...[
                Container(
                  width: double.infinity,
                  height: 160,
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: colors.onSurface.withValues(alpha: .04),
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      bar(110, 14),
                      const SizedBox(height: 24),
                      bar(180, 32),
                      const SizedBox(height: 14),
                      bar(140, 12),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
              ],
              for (var i = 0; i < 4; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: colors.outlineVariant.withValues(alpha: .4),
                      ),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      children: [
                        bar(44, 44),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              FractionallySizedBox(
                                widthFactor: .65,
                                child: bar(double.infinity, 14),
                              ),
                              const SizedBox(height: 10),
                              FractionallySizedBox(
                                widthFactor: .42,
                                child: bar(double.infinity, 10),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class RefreshFeedback<B extends StateStreamable<S>, S> extends StatelessWidget {
  final Widget child;
  final VoidCallback onRetry;
  const RefreshFeedback({
    super.key,
    required this.child,
    required this.onRetry,
  });
  @override
  Widget build(BuildContext context) => BlocBuilder<B, S>(
    builder: (context, state) {
      final status = state is RefreshStatus ? state : null;
      return LoadingFeedback(
        loading: status?.refreshing ?? false,
        error: status?.refreshError,
        onRetry: onRetry,
        child: child,
      );
    },
  );
}

/// Its content subtree stays mounted, preserving list offsets and local state.
class LoadingFeedback extends StatelessWidget {
  final Widget child;
  final bool loading;
  final String? error;
  final VoidCallback onRetry;
  const LoadingFeedback({
    super.key,
    required this.child,
    required this.onRetry,
    this.loading = false,
    this.error,
  });
  @override
  Widget build(BuildContext context) => Column(
    children: [
      if (error != null)
        MaterialBanner(
          content: Text(error!),
          actions: [TextButton(onPressed: onRetry, child: const Text('Retry'))],
        ),
      Expanded(
        key: const ValueKey('retained-page-content'),
        child: Stack(
          fit: StackFit.expand,
          children: [
            child,
            if (loading)
              const Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: _RefreshProgress(),
              ),
          ],
        ),
      ),
    ],
  );
}

class _RefreshProgress extends StatefulWidget {
  const _RefreshProgress();
  @override
  State<_RefreshProgress> createState() => _RefreshProgressState();
}

class _RefreshProgressState extends State<_RefreshProgress> {
  Timer? _timer;
  bool _visible = false;
  @override
  void initState() {
    super.initState();
    _timer = Timer(const Duration(milliseconds: 220), () {
      if (mounted) setState(() => _visible = true);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _visible
      ? Semantics(
          label: 'Refreshing',
          liveRegion: true,
          child: const LinearProgressIndicator(minHeight: 3),
        )
      : const SizedBox(height: 3);
}

class PageLoadFailure extends StatelessWidget {
  final VoidCallback onRetry;
  final String message;
  const PageLoadFailure({
    super.key,
    required this.onRetry,
    this.message = 'Could not load this page.',
  });
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.refresh_rounded,
            size: 40,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: 16),
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 16),
          FilledButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    ),
  );
}
