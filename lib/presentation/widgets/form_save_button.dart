import 'package:flutter/material.dart';

/// true = persisted, false = failed, null = field validation needs attention.
class FormSaveButton extends StatefulWidget {
  final Future<bool?> Function() onSave;
  final VoidCallback onSaved;
  final Widget child;
  final ButtonStyle? style;
  final bool filled;
  const FormSaveButton({
    super.key,
    required this.onSave,
    required this.onSaved,
    required this.child,
    this.style,
    this.filled = false,
  });
  @override
  State<FormSaveButton> createState() => _FormSaveButtonState();
}

class _FormSaveButtonState extends State<FormSaveButton> {
  bool _saving = false;
  String? _error;
  Future<void> _save() async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final result = await widget.onSave();
      if (!mounted) return;
      if (result == true) {
        widget.onSaved();
      } else if (result == false) {
        setState(
          () => _error =
              'Could not save. Your entries are still here. Please try again.',
        );
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'Could not save. Your entries are still here. Please try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (_error != null)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Text(
            _error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ),
      if (widget.filled)
        FilledButton(
          onPressed: _saving ? null : _save,
          style: widget.style,
          child: _saving ? const Text('Saving…') : widget.child,
        )
      else
        ElevatedButton(
          onPressed: _saving ? null : _save,
          style: widget.style,
          child: _saving ? const Text('Saving…') : widget.child,
        ),
    ],
  );
}
