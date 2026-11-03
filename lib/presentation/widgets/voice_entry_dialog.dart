import 'dart:async';
import 'package:flutter/material.dart';
import '../../application/services/ai/ai_service.dart';
import '../../application/services/voice/voice_capture.dart';

class VoiceEntryResult {
  final AIAction? action;
  final bool manual;
  const VoiceEntryResult.draft(this.action) : manual = false;
  const VoiceEntryResult.manual() : action = null, manual = true;
}

enum _VoiceStage { starting, listening, processing, error }

/// A modal owns recognition and discards asynchronous results after dismissal.
/// Only a verified draft leaves this screen; review/save belongs to the caller.
class VoiceEntryDialog extends StatefulWidget {
  final VoiceCapture capture;
  final Future<AIAction> Function(String) parse;
  const VoiceEntryDialog({
    super.key,
    required this.capture,
    required this.parse,
  });
  @override
  State<VoiceEntryDialog> createState() => _VoiceEntryDialogState();
}

class _VoiceEntryDialogState extends State<VoiceEntryDialog>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
    lowerBound: 1,
    upperBound: 1.06,
  );
  _VoiceStage _stage = _VoiceStage.starting;
  String _transcript = '', _error = '';
  bool _finishing = false;
  bool _closing = false;
  int _session = 0;
  Timer? _finalTimer;
  bool _current(int session) => mounted && !_closing && session == _session;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _updatePulse();
  }

  void _updatePulse() {
    if (!MediaQuery.disableAnimationsOf(context) &&
        _stage == _VoiceStage.listening &&
        !_finishing) {
      _pulse.repeat(reverse: true);
    } else {
      _pulse.stop();
      _pulse.value = 1;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Ignore inactive: the OS microphone permission prompt may cause it.
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _close();
    }
  }

  Future<void> _start() async {
    if (!mounted) return;
    final session = ++_session;
    _finalTimer?.cancel();
    _finalTimer = null;
    setState(() {
      _stage = _VoiceStage.starting;
      _transcript = '';
      _error = '';
      _finishing = false;
    });
    _updatePulse();
    try {
      final started = await widget.capture.startListening(
        (text) {
          if (_current(session)) _submit(text, session);
        },
        onPartial: (text) {
          if (_current(session) &&
              _stage != _VoiceStage.processing &&
              _stage != _VoiceStage.error) {
            setState(() => _transcript = text);
          }
        },
        onError: (message) {
          if (_current(session) && _stage != _VoiceStage.processing) {
            _fail(message);
          }
        },
        onStopped: () {
          if (_current(session)) _waitForFinal(session);
        },
      );
      if (!_current(session) || _stage != _VoiceStage.starting) return;
      if (!started) {
        _fail('Microphone unavailable. Check microphone access and try again.');
      } else {
        setState(() => _stage = _VoiceStage.listening);
        _updatePulse();
      }
    } catch (_) {
      if (_current(session)) {
        _fail('Couldn’t start listening. Please try again.');
      }
    }
  }

  void _waitForFinal(int session) {
    if (_stage == _VoiceStage.processing || _stage == _VoiceStage.error) return;
    setState(() => _finishing = true);
    _updatePulse();
    // Give the recognizer's final result precedence over the last partial.
    _finalTimer ??= Timer(const Duration(milliseconds: 2500), () {
      if (_current(session)) _submit(_transcript, session);
    });
  }

  Future<void> _done() async {
    if (_finishing || _stage != _VoiceStage.listening) return;
    final session = _session;
    _waitForFinal(session);
    try {
      await widget.capture.stopListening();
    } catch (_) {
      if (_current(session)) {
        _fail('Couldn’t finish recording. Please try again.');
      }
    }
  }

  Future<void> _submit(String text, int session) async {
    if (!_current(session) ||
        _stage == _VoiceStage.processing ||
        _stage == _VoiceStage.error) {
      return;
    }
    _finalTimer?.cancel();
    _finalTimer = null;
    if (text.trim().isEmpty) {
      _fail('No speech detected. Try again or enter the expense manually.');
      return;
    }
    setState(() {
      _transcript = text.trim();
      _stage = _VoiceStage.processing;
    });
    _updatePulse();
    unawaited(widget.capture.cancelListening());
    try {
      final action = await widget.parse(_transcript);
      if (!_current(session)) return;
      if (action.type == AIActionType.chat) {
        _fail(
          action.message ?? 'Couldn’t verify this expense. Please try again.',
        );
      } else {
        _close(VoiceEntryResult.draft(action));
      }
    } catch (_) {
      if (_current(session)) {
        _fail('Couldn’t prepare this expense. Please try again.');
      }
    }
  }

  void _fail(String message) {
    ++_session;
    _finalTimer?.cancel();
    _finalTimer = null;
    setState(() {
      _stage = _VoiceStage.error;
      _error = message;
    });
    _updatePulse();
    unawaited(widget.capture.cancelListening());
  }

  void _close([VoiceEntryResult? result]) {
    if (!mounted || _closing) return;
    _cancelOnExit();
    Navigator.of(context).pop(result);
  }

  void _cancelOnExit() {
    _closing = true;
    ++_session;
    _finalTimer?.cancel();
    unawaited(widget.capture.cancelListening());
  }

  @override
  void dispose() {
    ++_session;
    _finalTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _pulse.dispose();
    unawaited(widget.capture.cancelListening());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final processing = _stage == _VoiceStage.processing;
    final error = _stage == _VoiceStage.error;
    final title = switch (_stage) {
      _VoiceStage.starting => 'Getting ready…',
      _VoiceStage.listening => _finishing ? 'Finishing…' : 'Listening…',
      _VoiceStage.processing => 'Preparing your expense…',
      _VoiceStage.error => 'Let’s try that again',
    };
    return PopScope<VoiceEntryResult>(
      onPopInvokedWithResult: (didPop, _) {
        if (didPop && !_closing) _cancelOnExit();
      },
      child: Dialog.fullscreen(
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 12, 12, 0),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Voice entry',
                        style: theme.textTheme.titleMedium,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Cancel voice entry',
                      onPressed: _close,
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) => SingleChildScrollView(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        minHeight: constraints.maxHeight,
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            ScaleTransition(
                              scale: _pulse,
                              child: Container(
                                width: 96,
                                height: 96,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: error
                                      ? colors.error.withValues(alpha: .08)
                                      : colors.primary.withValues(alpha: .08),
                                ),
                                child: processing
                                    ? Padding(
                                        padding: const EdgeInsets.all(32),
                                        child: CircularProgressIndicator(
                                          strokeWidth: 3,
                                          color: colors.primary,
                                        ),
                                      )
                                    : Icon(
                                        error
                                            ? Icons.mic_off_rounded
                                            : Icons.mic_rounded,
                                        size: 40,
                                        color: error
                                            ? colors.error
                                            : colors.primary,
                                      ),
                              ),
                            ),
                            const SizedBox(height: 28),
                            Semantics(
                              liveRegion: true,
                              header: true,
                              child: Text(
                                title,
                                textAlign: TextAlign.center,
                                style: theme.textTheme.headlineSmall?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              error
                                  ? _error
                                  : processing
                                  ? 'You’ll review the details before saving.'
                                  : 'Try “I spent 500 on dinner”.',
                              textAlign: TextAlign.center,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: colors.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(height: 28),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(20),
                              constraints: const BoxConstraints(minHeight: 112),
                              decoration: BoxDecoration(
                                color: colors.onSurface.withValues(alpha: .025),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                  color: colors.onSurface.withValues(
                                    alpha: .10,
                                  ),
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Your words',
                                    style: theme.textTheme.labelMedium
                                        ?.copyWith(
                                          color: colors.onSurfaceVariant,
                                        ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    _transcript.isEmpty
                                        ? 'Your words will appear here…'
                                        : _transcript,
                                    key: const ValueKey('voiceTranscript'),
                                    style: theme.textTheme.titleMedium
                                        ?.copyWith(
                                          color: _transcript.isEmpty
                                              ? colors.onSurfaceVariant
                                              : colors.onSurface,
                                        ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (!processing)
                      FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: colors.primary,
                          foregroundColor: colors.onPrimary,
                          textStyle: theme.textTheme.labelLarge?.copyWith(
                            color: colors.onPrimary,
                            fontWeight: FontWeight.w600,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        onPressed: error
                            ? _start
                            : _stage == _VoiceStage.listening &&
                                  !_finishing &&
                                  _transcript.trim().isNotEmpty
                            ? _done
                            : null,
                        icon: Icon(
                          error ? Icons.refresh_rounded : Icons.check_rounded,
                        ),
                        label: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          child: Text(error ? 'Try again' : 'Done speaking'),
                        ),
                      ),
                    TextButton(
                      onPressed: error
                          ? () => _close(const VoiceEntryResult.manual())
                          : _close,
                      child: Padding(
                        padding: const EdgeInsets.all(8),
                        child: Text(error ? 'Enter manually' : 'Cancel'),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
