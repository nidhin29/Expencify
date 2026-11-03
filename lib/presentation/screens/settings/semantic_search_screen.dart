import '../../widgets/app_menu_item.dart';
import 'package:expencify/presentation/theme/app_icons.dart';
import 'package:flutter/material.dart';
import '../../../application/services/search/semantic_search_service.dart';

class SemanticSearchScreen extends StatefulWidget {
  final SemanticSearchService? service;
  const SemanticSearchScreen({super.key, this.service});
  @override
  State<SemanticSearchScreen> createState() => _SemanticSearchScreenState();
}

class _SemanticSearchScreenState extends State<SemanticSearchScreen> {
  late final service = widget.service ?? SemanticSearchService();
  bool _loading = true;
  bool _turningOff = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      await service.activate();
    } catch (_) {
      if (mounted) _error = 'Could not load search settings. Try again.';
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _turnOff() async {
    if (_turningOff) return;
    setState(() {
      _turningOff = true;
      _error = null;
    });
    try {
      await service.disable();
    } catch (_) {
      if (mounted) _error = 'Could not update search settings. Try again.';
    } finally {
      if (mounted) setState(() => _turningOff = false);
    }
  }

  Future<void> _enable() async {
    setState(() => _error = null);
    try {
      await service.enable();
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Could not set up search. Try again.');
      }
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: service,
    builder: (context, _) {
      final theme = Theme.of(context);
      final cs = theme.colorScheme;
      final error = _error ?? service.error;
      final working = service.downloading;
      final preparing = service.enabled && service.indexing;
      final status = _loading
          ? 'Loading…'
          : working
          ? (service.downloadProgress >= 1
                ? 'Finishing setup…'
                : 'Downloading · ${(service.downloadProgress * 100).round()}%')
          : preparing
          ? 'Preparing your transactions…'
          : service.enabled
          ? 'Ready to search'
          : 'One-time download · Works offline';
      return Scaffold(
        appBar: AppBar(
          title: const Text('Improve search'),
          actions: [
            if (service.enabled && !_turningOff)
              PopupMenuButton<String>(
                clipBehavior: Clip.antiAlias,
                tooltip: 'Search options',
                icon: const Icon(AppIcons.more),
                onSelected: (_) => _turnOff(),
                itemBuilder: (_) => const [
                  AppMenuItem(
                    value: 'off',
                    label: 'Turn off',
                    icon: Icons.power_settings_new_rounded,
                  ),
                ],
              ),
          ],
        ),
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) => SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: (constraints.maxHeight - 48).clamp(
                    0.0,
                    double.infinity,
                  ),
                ),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 440),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Center(
                          child: Container(
                            width: 88,
                            height: 88,
                            decoration: BoxDecoration(
                              color: cs.primaryContainer.withValues(alpha: .4),
                              borderRadius: BorderRadius.circular(28),
                            ),
                            child: Icon(
                              Icons.manage_search_rounded,
                              size: 44,
                              color: cs.primary,
                            ),
                          ),
                        ),
                        const SizedBox(height: 28),
                        Text(
                          'Find related transactions',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Search “car expenses” to find fuel and servicing.',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyLarge?.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 32),
                        if (working || preparing) ...[
                          LinearProgressIndicator(
                            value: working && service.downloadProgress < 1
                                ? service.downloadProgress
                                : null,
                          ),
                          const SizedBox(height: 12),
                        ],
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            if (service.enabled &&
                                !preparing &&
                                error == null) ...[
                              Icon(
                                AppIcons.success,
                                size: 18,
                                color: cs.primary,
                              ),
                              const SizedBox(width: 8),
                            ],
                            Flexible(
                              child: Text(
                                status,
                                textAlign: TextAlign.center,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: cs.onSurfaceVariant,
                                ),
                              ),
                            ),
                          ],
                        ),
                        if (error != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 16),
                            child: Text(
                              error,
                              textAlign: TextAlign.center,
                              style: TextStyle(color: cs.error),
                            ),
                          ),
                        const SizedBox(height: 20),
                        if (!service.supported)
                          const Text(
                            'Search by meaning is available on Android and iOS.',
                            textAlign: TextAlign.center,
                          )
                        else
                          FilledButton(
                            onPressed: _loading || _turningOff
                                ? null
                                : working
                                ? service.cancelDownload
                                : error != null
                                ? () {
                                    if (_error != null) {
                                      setState(() {
                                        _loading = true;
                                        _error = null;
                                      });
                                      _load();
                                    } else if (service.enabled) {
                                      service.retryIndexing();
                                    } else {
                                      _enable();
                                    }
                                  }
                                : service.enabled
                                ? () => Navigator.pop(context, true)
                                : _enable,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 4),
                              child: Text(
                                _turningOff
                                    ? 'Turning off…'
                                    : working
                                    ? 'Cancel download'
                                    : error != null
                                    ? 'Try again'
                                    : service.enabled
                                    ? 'Done'
                                    : 'Enable search',
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
        ),
      );
    },
  );
}
