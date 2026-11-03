import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class SpendingTimeDialog extends StatefulWidget {
  final String title;
  final TimeOfDay initialTime;
  const SpendingTimeDialog({
    super.key,
    required this.title,
    required this.initialTime,
  });
  @override
  State<SpendingTimeDialog> createState() => _SpendingTimeDialogState();
}

class _SpendingTimeDialogState extends State<SpendingTimeDialog> {
  final _form = GlobalKey<FormState>();
  late final _hour = TextEditingController();
  late final _minute = TextEditingController(
    text: widget.initialTime.minute.toString().padLeft(2, '0'),
  );
  late bool _pm = widget.initialTime.hour >= 12;
  bool? _use24;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_use24 != null) return;
    _use24 = MediaQuery.alwaysUse24HourFormatOf(context);
    final hour = _use24!
        ? widget.initialTime.hour
        : (widget.initialTime.hourOfPeriod == 0
              ? 12
              : widget.initialTime.hourOfPeriod);
    _hour.text = hour.toString().padLeft(2, '0');
  }

  @override
  void dispose() {
    _hour.dispose();
    _minute.dispose();
    super.dispose();
  }

  void _save() {
    if (!_form.currentState!.validate()) return;
    var hour = int.parse(_hour.text);
    if (!_use24!) hour = hour % 12 + (_pm ? 12 : 0);
    Navigator.pop(
      context,
      TimeOfDay(hour: hour, minute: int.parse(_minute.text)),
    );
  }

  Widget _field(
    TextEditingController controller,
    String label,
    int min,
    int max,
  ) => TextFormField(
    controller: controller,
    keyboardType: TextInputType.number,
    inputFormatters: [
      FilteringTextInputFormatter.digitsOnly,
      LengthLimitingTextInputFormatter(2),
    ],
    textAlign: TextAlign.center,
    style: Theme.of(context).textTheme.headlineMedium,
    decoration: InputDecoration(
      labelText: label,
      errorMaxLines: 2,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
    ),
    validator: (value) {
      final n = int.tryParse(value ?? '');
      return n == null || n < min || n > max ? '$min–$max' : null;
    },
    onFieldSubmitted: (_) => _save(),
  );

  @override
  Widget build(BuildContext context) => AlertDialog(
    insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
    scrollable: true,
    title: Text(widget.title),
    content: SizedBox(
      width: 320,
      child: Form(
        key: _form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _field(
                    _hour,
                    'Hour',
                    _use24! ? 0 : 1,
                    _use24! ? 23 : 12,
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8, vertical: 18),
                  child: Text(':'),
                ),
                Expanded(child: _field(_minute, 'Minute', 0, 59)),
              ],
            ),
            if (!_use24!) ...[
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: SegmentedButton<bool>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(value: false, label: Text('AM')),
                    ButtonSegment(value: true, label: Text('PM')),
                  ],
                  selected: {_pm},
                  onSelectionChanged: (value) =>
                      setState(() => _pm = value.single),
                ),
              ),
            ],
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(onPressed: _save, child: const Text('Save')),
    ],
  );
}
