import 'package:expencify/presentation/theme/app_icons.dart';
import 'package:flutter/services.dart';
import 'sms_tracking_screen.dart';
import '../../../application/services/sms/sms_tracking_preference.dart';
import '../../../application/services/ai/ai_service.dart';
import '../../../application/services/ai/local_ai_model.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:dio/dio.dart';

class SetupRequiredScreen extends StatefulWidget {
  final void Function(BuildContext context) onComplete;
  final AIService? ai;
  final bool aiOnly;
  final bool? aiSupported;
  const SetupRequiredScreen({
    super.key,
    required this.onComplete,
    this.ai,
    this.aiSupported,
    this.aiOnly = false,
  });
  @override
  State<SetupRequiredScreen> createState() => _SetupRequiredScreenState();
}

class _SetupRequiredScreenState extends State<SetupRequiredScreen>
    with WidgetsBindingObserver {
  late final AIService _ai = widget.ai ?? AIService();
  bool _accepted = false,
      _trackSms = false,
      _checking = true,
      _working = false,
      _installed = false,
      _ready = false,
      _paused = false,
      _pauseRequested = false,
      _continuing = false;
  double _progress = 0;
  String? _error;
  bool? _nativeSupported;
  String _stage = 'Checking AI';
  bool get _supported =>
      widget.aiSupported ??
      _nativeSupported ??
      LocalAIModelMetadata.isSupported;
  bool get _canContinue =>
      (widget.aiOnly || _accepted) &&
      !_continuing &&
      (!widget.aiOnly || (_supported && _ready && !_working && !_checking));
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _check();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !_working) _check();
  }

  Future<void> _check() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() => _accepted = prefs.getBool('legal_terms_accepted') ?? false);
    try {
      if (widget.aiSupported == null) {
        final supported = await _ai.supportsCurrentModel();
        if (!mounted) return;
        setState(() => _nativeSupported = supported);
      }
      final exists =
          _supported &&
          await _ai.modelExists(LocalAIModelMetadata.all.first.id);
      if (mounted) {
        setState(() {
          _installed = exists;
          _ready = _supported && _ai.isInitialized;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Could not check AI. Try setup again.');
      }
    } finally {
      if (mounted) setState(() => _checking = false);
    }
    if (mounted && widget.aiOnly && _installed && !_ready && !_working) {
      await _prepareAi();
    }
  }

  Future<void> _prepareAi() async {
    if (_working) {
      if (_stage == 'Downloading AI' && !_pauseRequested) {
        _ai.pauseDownload();
        setState(() {
          _pauseRequested = true;
          _stage = 'Pausing download';
        });
      }
      return;
    }
    setState(() {
      _working = true;
      _paused = false;
      _pauseRequested = false;
      _error = null;
      _stage = 'Preparing AI';
    });
    try {
      final exists = await _ai.modelExists(LocalAIModelMetadata.all.first.id);
      if (!mounted) return;
      setState(() => _installed = exists);
      if (exists) {
        await _ai
            .init(LocalAIModelMetadata.all.first.id)
            .timeout(const Duration(seconds: 180));
      } else {
        setState(() => _stage = 'Downloading AI');
        await _ai.downloadModel(LocalAIModelMetadata.all.first, (progress) {
          if (mounted && !_pauseRequested) {
            setState(() {
              _progress = progress;
              _stage = progress >= 1 ? 'Preparing AI' : 'Downloading AI';
            });
          }
        });
      }
      if (!mounted) return;
      if (_pauseRequested) {
        setState(() => _paused = true);
      } else if (_ai.isInitialized) {
        setState(() {
          _ready = true;
          _installed = true;
        });
      } else {
        setState(() => _error = 'AI is not ready yet. Please try again.');
      }
    } catch (error) {
      var savedModel = _installed;
      try {
        savedModel = await _ai.modelExists(LocalAIModelMetadata.all.first.id);
      } catch (_) {
        // Keep the last known installation state if verification is unavailable.
      }
      if (mounted) {
        setState(() {
          _installed = savedModel;
          final restrictedDownload =
              error is DioException &&
              {401, 403}.contains(error.response?.statusCode);
          _error = restrictedDownload
              ? 'AI download is temporarily unavailable. Please try again later.'
              : savedModel
              ? 'AI could not start. Your download is saved. Try again, or reopen the app if it stays busy.'
              : 'AI setup could not finish. Check your connection or free storage, then retry.';
        });
      }
    } finally {
      if (mounted) {
        setState(() => _working = false);
        if (widget.aiOnly && _ready) widget.onComplete(context);
      }
    }
  }

  Future<void> _continue() async {
    if (!_canContinue) return;
    if (widget.aiOnly) {
      widget.onComplete(context);
      return;
    }
    setState(() => _continuing = true);
    try {
      if (_trackSms) {
        final enabled = await Navigator.push<bool>(
          context,
          MaterialPageRoute(builder: (_) => const SmsTrackingScreen()),
        );
        if (enabled == null || !mounted) return;
        if (!enabled) await SmsTrackingPreference.setEnabled(false);
      } else {
        await SmsTrackingPreference.setEnabled(false);
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('sms_setup_dismissed', true);
      }
      if (mounted) widget.onComplete(context);
    } finally {
      if (mounted) setState(() => _continuing = false);
    }
  }

  Future<void> _openPolicy(String url) async {
    try {
      if (await launchUrl(
        Uri.parse(url),
        mode: LaunchMode.externalApplication,
      )) {
        return;
      }
    } catch (_) {}
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          persist: false,
          content: Text('Could not open this link. Please try again.'),
        ),
      );
    }
  }

  Widget _choice(bool sms, String title, String subtitle, IconData icon) {
    final cs = Theme.of(context).colorScheme;
    final selected = _trackSms == sms;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      color: selected ? cs.primary.withValues(alpha: .06) : cs.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: selected ? cs.primary : cs.onSurface.withValues(alpha: .12),
        ),
      ),
      child: RadioListTile<bool>(
        value: sms,
        groupValue: _trackSms,
        activeColor: cs.primary,
        title: Text(
          title,
          style: TextStyle(color: cs.onSurface, fontWeight: FontWeight.w600),
        ),
        subtitle: Text(subtitle, style: TextStyle(color: cs.onSurfaceVariant)),
        secondary: Icon(
          icon,
          color: selected ? cs.primary : cs.onSurfaceVariant,
        ),
        onChanged: _continuing ? null : (_) => setState(() => _trackSms = sms),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value:
          (theme.brightness == Brightness.dark
                  ? SystemUiOverlayStyle.light
                  : SystemUiOverlayStyle.dark)
              .copyWith(
                statusBarColor: cs.surface,
                systemNavigationBarColor: cs.surface,
                systemNavigationBarIconBrightness:
                    theme.brightness == Brightness.dark
                    ? Brightness.light
                    : Brightness.dark,
              ),
      child: Scaffold(
        backgroundColor: cs.surface,
        bottomNavigationBar: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
            child: FilledButton(
              onPressed: _canContinue ? _continue : null,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 14),
                child: Text(
                  widget.aiOnly
                      ? 'Use AI'
                      : _continuing
                      ? 'Opening…'
                      : _trackSms
                      ? 'Set up bank SMS'
                      : 'Open Spendy',
                ),
              ),
            ),
          ),
        ),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.auto_awesome_outlined, size: 32, color: cs.primary),
                const SizedBox(height: 16),
                Text(
                  widget.aiOnly ? 'Set up AI' : 'Get Spendy ready',
                  style: theme.textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  widget.aiOnly
                      ? 'Enable voice entry and AI chat on this device.'
                      : 'Your tracking, your choice.',
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 24),
                if (!widget.aiOnly) ...[
                  _choice(
                    false,
                    'Use manually',
                    'Add transactions yourself. No SMS access.',
                    AppIcons.edit,
                  ),
                  _choice(
                    true,
                    'Track bank SMS',
                    'Add bank details and allow SMS access next.',
                    Icons.sms_outlined,
                  ),
                  const SizedBox(height: 12),
                ],
                Card(
                  margin: EdgeInsets.zero,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                    side: BorderSide(
                      color: cs.onSurface.withValues(alpha: .12),
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              _ready ? AppIcons.success : Icons.memory_outlined,
                              color: cs.primary,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                _ready ? 'AI is ready' : 'Voice, scans & chat',
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            if (_supported && !_ready) ...[
                              const SizedBox(width: 8),
                              Text(
                                widget.aiOnly ? 'Required' : 'Optional',
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: cs.primary,
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _supported
                              ? (_ready
                                    ? 'Ready for voice, scans and chat.'
                                    : 'Uses an on-device model.')
                              : 'Offline AI is not supported on this device.',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                        if (_supported && !_ready) ...[
                          const SizedBox(height: 8),
                          Text(
                            _installed
                                ? 'Model downloaded · ready to prepare'
                                : 'One-time download · Works offline',
                            style: theme.textTheme.bodySmall,
                          ),
                          if (_working || _checking) ...[
                            const SizedBox(height: 16),
                            LinearProgressIndicator(
                              value: _working && _stage == 'Downloading AI'
                                  ? _progress
                                  : null,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              _checking
                                  ? 'Checking AI…'
                                  : _stage == 'Downloading AI'
                                  ? 'Downloading · ${(_progress * 100).round()}%'
                                  : '$_stage…',
                            ),
                          ],
                          const SizedBox(height: 12),
                          OutlinedButton(
                            style: OutlinedButton.styleFrom(
                              side: BorderSide(
                                color: cs.primary.withValues(alpha: .4),
                              ),
                            ),
                            onPressed:
                                _checking ||
                                    (_working && _stage != 'Downloading AI')
                                ? null
                                : _prepareAi,
                            child: Text(
                              _working
                                  ? 'Pause download'
                                  : _error != null
                                  ? 'Retry AI setup'
                                  : _paused
                                  ? 'Resume download'
                                  : _installed
                                  ? 'Prepare AI'
                                  : 'Download AI',
                            ),
                          ),
                        ],
                        if (_error != null) ...[
                          const SizedBox(height: 10),
                          Text(_error!, style: TextStyle(color: cs.error)),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                if (!widget.aiOnly) ...[
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    value: _accepted,
                    title: const Text(
                      'I accept the Privacy Policy and Terms & Conditions.',
                    ),
                    onChanged: _continuing
                        ? null
                        : (value) async {
                            final prefs = await SharedPreferences.getInstance();
                            await prefs.setBool(
                              'legal_terms_accepted',
                              value ?? false,
                            );
                            if (mounted) {
                              setState(() => _accepted = value ?? false);
                            }
                          },
                  ),
                  Row(
                    children: [
                      const SizedBox(width: 12),
                      Expanded(
                        child: Wrap(
                          spacing: 30,
                          children: [
                            TextButton(
                              onPressed: () => _openPolicy(
                                'https://spendy-privacy.devforchange.com/',
                              ),
                              child: const Text('Privacy Policy'),
                            ),
                            TextButton(
                              onPressed: () => _openPolicy(
                                'https://spendy-terms.devforchange.com/',
                              ),
                              child: const Text('Terms & Conditions'),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
