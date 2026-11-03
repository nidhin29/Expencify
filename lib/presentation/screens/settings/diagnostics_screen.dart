import '../../widgets/page_loading.dart';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import '../../../application/services/performance/local_diagnostics.dart';
import '../../../application/services/security/private_file_cleanup.dart';
import '../../theme/app_icons.dart';
import '../../widgets/centered_empty_state.dart';

class DiagnosticsScreen extends StatefulWidget {
  final LocalDiagnostics? diagnostics;
  const DiagnosticsScreen({super.key, this.diagnostics});
  @override
  State<DiagnosticsScreen> createState() => _DiagnosticsScreenState();
}

class _DiagnosticsScreenState extends State<DiagnosticsScreen> {
  late final _store = widget.diagnostics ?? LocalDiagnostics.instance;
  Future<Map<String, Object>>? _report;
  bool _busy = false;
  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    setState(() {
      _report = _store.report();
    });
  }

  Future<void> _toggle(bool value) async {
    setState(() {
      _busy = true;
    });
    try {
      await _store.setEnabled(value);
      if (mounted) _reload();
    } catch (_) {
      _feedback('Could not save this setting. Please try again.');
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  void _feedback(String text) {
    if (mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(text), persist: false));
    }
  }

  Future<void> _clear() async {
    setState(() {
      _busy = true;
    });
    try {
      await _store.clear();
      if (mounted) {
        _reload();
        _feedback('Diagnostics cleared');
      }
    } catch (_) {
      _feedback('Could not clear diagnostics. Please try again.');
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  Future<void> _share() async {
    setState(() {
      _busy = true;
    });
    try {
      final report = await _store.report();
      final text = const JsonEncoder.withIndent('  ').convert(report);
      if (!mounted) return;
      final approved = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Review diagnostics'),
          content: SizedBox(
            width: 560,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'This is the complete report that will be shared.',
                  ),
                  const SizedBox(height: 16),
                  SelectableText(
                    text,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton.icon(
              onPressed: () => Navigator.pop(context, true),
              icon: const Icon(AppIcons.share),
              label: const Text('Share report'),
            ),
          ],
        ),
      );
      if (approved != true || !mounted) return;
      final file = await const PrivateFileCleanup().create(
        'json',
        utf8.encode(text),
      );
      try {
        await Share.shareXFiles([
          XFile(file.path),
        ], subject: 'Spendy diagnostics');
      } finally {
        await const PrivateFileCleanup().removeExport(file.path);
      }
    } catch (_) {
      _feedback('Could not prepare diagnostics. Please try again.');
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Diagnostics'),
        actions: [
          IconButton(
            tooltip: 'Refresh report',
            onPressed: _busy ? null : _reload,
            icon: const Icon(AppIcons.refresh),
          ),
        ],
      ),
      body: FutureBuilder<Map<String, Object>>(
        future: _report,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const PageLoading(label: 'Loading diagnostics');
          }
          if (snapshot.hasError) {
            return Center(
              child: FilledButton(
                onPressed: _reload,
                child: const Text('Retry'),
              ),
            );
          }
          final report = snapshot.data!;
          final entries = (report['records'] as List)
              .cast<Map<String, Object>>();
          final jobs = report['background_sms_jobs'] as List;
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                child: Material(
                  color: theme.colorScheme.surface,
                  borderRadius: BorderRadius.circular(18),
                  child: SwitchListTile.adaptive(
                    title: const Text('Collect diagnostics'),
                    subtitle: const Text(
                      'On this device · No automatic uploads',
                    ),
                    value: _store.enabled,
                    onChanged: _busy ? null : _toggle,
                  ),
                ),
              ),
              if (entries.isEmpty && jobs.isEmpty)
                Expanded(
                  child: CenteredEmptyState(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          AppIcons.diagnostics,
                          size: 48,
                          color: AppIcons.actionColor(theme),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          _store.enabled
                              ? 'No diagnostics yet'
                              : 'Diagnostics are off',
                          style: theme.textTheme.titleLarge,
                          textAlign: TextAlign.center,
                        ),
                        if (_store.enabled)
                          const Padding(
                            padding: EdgeInsets.only(top: 12),
                            child: Text(
                              'Performance samples appear as you use Spendy.',
                              textAlign: TextAlign.center,
                            ),
                          ),
                      ],
                    ),
                  ),
                )
              else
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                    children: [
                      Text(
                        'Recent app health',
                        style: theme.textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      const Text('Last 3 days · Up to 120 app samples'),
                      const SizedBox(height: 12),
                      for (final entry in entries.reversed.take(30))
                        _entry(entry, theme),
                      if (jobs.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 16),
                          child: Text(
                            'Background SMS work: ${jobs.length} samples · ${jobs.fold<int>(0, (sum, row) => sum + (row as Map)['wall_ms'] as int)} ms total runtime',
                            style: theme.textTheme.bodyMedium,
                          ),
                        ),
                      const SizedBox(height: 20),
                      Wrap(
                        spacing: 12,
                        runSpacing: 8,
                        children: [
                          FilledButton.icon(
                            onPressed: _busy ? null : _share,
                            icon: const Icon(AppIcons.share),
                            label: const Text('Review report'),
                          ),
                          TextButton.icon(
                            onPressed: _busy ? null : _clear,
                            icon: const Icon(AppIcons.delete),
                            label: const Text('Clear diagnostics'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _entry(Map<String, Object> entry, ThemeData theme) {
    String title, detail;
    switch (entry['kind']) {
      case 'timing':
        final operation = HealthOperation.values.firstWhere(
          (value) => value.name == entry['operation'],
        );
        title = _operationLabel(operation);
        detail =
            '${entry['duration_ms']} ms${entry['failed'] == true ? ' · Failed' : ''}';
        break;
      case 'memory':
        title = 'Process memory';
        detail = '${((entry['rss_bytes'] as int) / (1024 * 1024)).round()} MB';
        break;
      case 'frames':
        title = 'Display smoothness';
        detail =
            '${entry['slow_frames']} of ${entry['frames']} frames over budget';
        break;
      case 'memory_pressure':
        title = 'System memory pressure';
        detail = 'The system requested memory cleanup';
        break;
      default:
        title = entry['kind'] == 'flutter_error'
            ? 'Flutter error'
            : 'Unhandled Dart error';
        detail = '${entry['category']} · ${entry['count'] ?? 1} occurrence(s)';
    }
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(title),
      subtitle: Text(detail),
      trailing: Text(
        TimeOfDay.fromDateTime(
          DateTime.fromMillisecondsSinceEpoch(entry['at_minute'] as int),
        ).format(context),
        style: theme.textTheme.bodySmall,
      ),
    );
  }

  String _operationLabel(HealthOperation operation) => switch (operation) {
    HealthOperation.firstFrame => 'First frame',
    HealthOperation.startupReady => 'Startup ready',
    HealthOperation.databaseOpen => 'Open database',
    HealthOperation.transactionsRead => 'Read transactions',
    HealthOperation.backupCreate => 'Create backup',
    HealthOperation.backupRestore => 'Restore backup',
    HealthOperation.backupEncode => 'Prepare backup',
    HealthOperation.backupEncrypt => 'Encrypt backup',
    HealthOperation.backupDecrypt => 'Unlock backup',
    HealthOperation.backupValidate => 'Validate backup',
    HealthOperation.backupWrite => 'Save restored records',
    HealthOperation.aiInitialize => 'Prepare AI',
  };
}
