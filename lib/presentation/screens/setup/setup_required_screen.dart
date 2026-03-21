import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:expencify/application/services/ai/ai_service.dart';
import 'package:expencify/application/services/ai/local_ai_model.dart';

class SetupRequiredScreen extends StatefulWidget {
  final VoidCallback onComplete;
  const SetupRequiredScreen({super.key, required this.onComplete});

  @override
  State<SetupRequiredScreen> createState() => _SetupRequiredScreenState();
}

class _SetupRequiredScreenState extends State<SetupRequiredScreen>
    with WidgetsBindingObserver {
  bool _hasSmsPermission = false;
  bool _isBatteryOptimizationIgnored = false;
  bool _isAiModelInstalled = false;
  bool _isDownloading = false;
  double _downloadProgress = 0;

  final _aiService = AIService();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkRequirements();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkRequirements();
    }
  }

  Future<void> _checkRequirements() async {
    final sms = await Permission.sms.isGranted;
    final battery = await Permission.ignoreBatteryOptimizations.isGranted;
    final ai = await _aiService.modelExists(LocalAIModelType.qwenLite);

    if (mounted) {
      setState(() {
        _hasSmsPermission = sms;
        _isBatteryOptimizationIgnored = battery;
        _isAiModelInstalled = ai;
      });
    }
  }

  Future<void> _requestSms() async {
    await Permission.sms.request();
    _checkRequirements();
  }

  Future<void> _requestBattery() async {
    await Permission.ignoreBatteryOptimizations.request();
    _checkRequirements();
  }

  Future<void> _downloadAi() async {
    setState(() {
      _isDownloading = true;
      _downloadProgress = 0;
    });

    try {
      final metadata = LocalAIModelMetadata.all.firstWhere(
        (m) => m.id == LocalAIModelType.qwenLite,
      );
      await _aiService.downloadModel(metadata, (progress) {
        if (mounted) setState(() => _downloadProgress = progress);
      });
      _checkRequirements();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Download failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _isDownloading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Scaffold(
      backgroundColor: cs.surface,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 60),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: cs.primary.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.security_rounded,
                  color: cs.primary,
                  size: 40,
                ),
              ),
              const SizedBox(height: 32),
              Text(
                'Complete Setup',
                style: theme.textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  letterSpacing: -1,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'To ensure 100% accurate and automatic tracking, Expencify requires the following settings to be enabled.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: cs.onSurface.withOpacity(0.6),
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 48),
              _buildStepCard(
                context,
                title: 'SMS Access',
                description:
                    'Required to detect bank transaction alerts instantly.',
                icon: Icons.sms_rounded,
                isDone: _hasSmsPermission,
                onTap: _requestSms,
              ),
              const SizedBox(height: 20),
              _buildStepCard(
                context,
                title: 'Background Reliability',
                description: 'Ensures the app is never killed by the system.',
                icon: Icons.bolt_rounded,
                isDone: _isBatteryOptimizationIgnored,
                onTap: _requestBattery,
              ),
              const SizedBox(height: 20),
              _buildStepCard(
                context,
                title: 'AI Categorization',
                description: 'Intelligent brain for auto-sorting expenses.',
                icon: Icons.psychology_rounded,
                isDone: _isAiModelInstalled,
                isProcessing: _isDownloading,
                progress: _downloadProgress,
                onTap: _isDownloading ? null : _downloadAi,
                actionLabel: _isDownloading ? 'Downloading...' : 'Download',
              ),
              const SizedBox(height: 48),
              if (_hasSmsPermission &&
                  _isBatteryOptimizationIgnored &&
                  _isAiModelInstalled)
                ElevatedButton(
                  onPressed: widget.onComplete,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                    minimumSize: const Size(double.infinity, 64),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                    elevation: 8,
                    shadowColor: Colors.green.withOpacity(0.4),
                  ),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        'Continue to Dashboard',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      SizedBox(width: 8),
                      Icon(Icons.arrow_forward_rounded),
                    ],
                  ),
                )
              else
                Center(
                  child: Column(
                    children: [
                      Icon(
                        Icons.lock_outline_rounded,
                        color: cs.onSurface.withOpacity(0.2),
                        size: 24,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Setup all requirements to unlock',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: cs.onSurface.withOpacity(0.3),
                          letterSpacing: 1.2,
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStepCard(
    BuildContext context, {
    required String title,
    required String description,
    required IconData icon,
    required bool isDone,
    bool isProcessing = false,
    double progress = 0,
    required VoidCallback? onTap,
    String? actionLabel,
  }) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return AnimatedOpacity(
      duration: const Duration(milliseconds: 300),
      opacity: isDone ? 1.0 : 1.0,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: isDone ? cs.primary.withOpacity(0.05) : cs.surface,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: isDone
                ? cs.primary.withOpacity(0.2)
                : cs.onSurface.withOpacity(0.1),
            width: isDone ? 2 : 1,
          ),
        ),
        child: Column(
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: isDone ? cs.primary : cs.onSurface.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(
                    isDone ? Icons.check_rounded : icon,
                    color: isDone
                        ? Colors.white
                        : cs.onSurface.withOpacity(0.4),
                    size: 24,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: isDone ? cs.primary : cs.onSurface,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        description,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: cs.onSurface.withOpacity(0.5),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (!isDone) ...[
              const SizedBox(height: 20),
              if (isProcessing) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 8,
                    backgroundColor: cs.onSurface.withOpacity(0.05),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '${(progress * 100).toStringAsFixed(0)}%',
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ] else
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: onTap,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: cs.primary,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: Text(
                      actionLabel ?? 'Setup Now',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}
