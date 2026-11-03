import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'spendy_splash_visual.dart';

/// Owns the PIN controllers until the dialog's closing animation completes.
class AppPinDialog extends StatefulWidget {
  final Future<void> Function(String) onSave;
  final String title;
  const AppPinDialog({
    super.key,
    required this.onSave,
    this.title = 'Set app PIN',
  });
  @override
  State<AppPinDialog> createState() => _AppPinDialogState();
}

class _AppPinDialogState extends State<AppPinDialog> {
  final _form = GlobalKey<FormState>();
  final _pin = TextEditingController();
  final _confirm = TextEditingController();
  final _confirmFocus = FocusNode();
  bool _saving = false;
  bool _visible = false;
  bool _submitted = false;
  String? _error;
  Color get _errorColor => Theme.of(context).brightness == Brightness.dark
      ? const Color(0xFFFDA4AF)
      : Theme.of(context).colorScheme.error;
  @override
  void dispose() {
    _pin.dispose();
    _confirm.dispose();
    _confirmFocus.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _submitted = true);
    if (!_form.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    final pin = _pin.text;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.onSave(pin);
      if (mounted) Navigator.pop(context, true);
    } catch (_) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = 'Could not save your PIN. Please try again.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final compact = MediaQuery.viewInsetsOf(context).bottom > 0;
    return PopScope(
      canPop: !_saving,
      child: Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        clipBehavior: Clip.antiAlias,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Form(
              key: _form,
              autovalidateMode: _submitted
                  ? AutovalidateMode.onUserInteraction
                  : AutovalidateMode.disabled,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (!compact) ...[
                    Center(
                      child: Container(
                        width: 56,
                        height: 56,
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: cs.primary.withValues(alpha: .1),
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: const ExcludeSemantics(
                          child: CustomPaint(
                            painter: SpendyWalletPainter(
                              progress: 1,
                              centered: true,
                              glow: false,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                  Text(
                    widget.title,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (!compact) ...[
                    const SizedBox(height: 8),
                    Text(
                      'Choose a 4 digit PIN.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                  SizedBox(height: compact ? 20 : 24),
                  TextFormField(
                    controller: _pin,
                    autofocus: true,
                    enabled: !_saving,
                    obscureText: !_visible,
                    autocorrect: false,
                    enableSuggestions: false,
                    enableInteractiveSelection: false,
                    textInputAction: TextInputAction.next,
                    onFieldSubmitted: (_) => _confirmFocus.requestFocus(),
                    onChanged: (_) {
                      if (_error != null) setState(() => _error = null);
                    },
                    style: theme.textTheme.titleMedium?.copyWith(
                      letterSpacing: 4,
                    ),
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    maxLength: 4,
                    decoration: InputDecoration(
                      labelText: 'New PIN',
                      errorStyle: TextStyle(color: _errorColor),
                      counterText: '',
                      suffixIcon: IconButton(
                        tooltip: _visible ? 'Hide PINs' : 'Show PINs',
                        onPressed: _saving
                            ? null
                            : () => setState(() {
                                _visible = !_visible;
                              }),
                        icon: Icon(
                          _visible
                              ? Icons.visibility_off_outlined
                              : Icons.visibility_outlined,
                        ),
                      ),
                    ),
                    validator: (value) => value == null || value.length != 4
                        ? 'Enter 4 digits'
                        : null,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _confirm,
                    focusNode: _confirmFocus,
                    enabled: !_saving,
                    obscureText: !_visible,
                    autocorrect: false,
                    enableSuggestions: false,
                    enableInteractiveSelection: false,
                    textInputAction: TextInputAction.done,
                    onFieldSubmitted: (_) => _save(),
                    onChanged: (_) {
                      if (_error != null) setState(() => _error = null);
                    },
                    style: theme.textTheme.titleMedium?.copyWith(
                      letterSpacing: 4,
                    ),
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    maxLength: 4,
                    decoration: InputDecoration(
                      labelText: 'Confirm PIN',
                      errorStyle: TextStyle(color: _errorColor),
                      counterText: '',
                    ),
                    validator: (value) =>
                        value != _pin.text ? 'PINs do not match' : null,
                  ),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 16),
                      child: Semantics(
                        liveRegion: true,
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: cs.errorContainer,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            _error!,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: cs.onErrorContainer,
                            ),
                          ),
                        ),
                      ),
                    ),
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: _saving ? null : _save,
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(double.infinity, 52),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (_saving) ...[
                          const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                          const SizedBox(width: 10),
                        ],
                        Flexible(
                          child: Text(
                            _saving ? 'Saving…' : 'Save PIN',
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 6),
                  TextButton(
                    onPressed: _saving
                        ? null
                        : () => Navigator.pop(context, false),
                    child: const Text('Cancel'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
