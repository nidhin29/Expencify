import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

Future<DateTime?> showAppDatePicker({
  required BuildContext context,
  required DateTime firstDate,
  required DateTime lastDate,
  DateTime? initialDate,
  String title = 'Choose date',
  bool inputMode = false,
}) => showDialog<DateTime>(
  context: context,
  builder: (_) => _DateDialog(
    title: title,
    inputMode: inputMode,
    firstDate: firstDate,
    lastDate: lastDate,
    initialDate: initialDate ?? DateTime.now(),
  ),
);

Future<DateTimeRange?> showAppDateRangePicker({
  required BuildContext context,
  required DateTime firstDate,
  required DateTime lastDate,
  DateTimeRange? initialDateRange,
  String title = 'Choose period',
}) => showDialog<DateTimeRange>(
  context: context,
  builder: (_) => _RangeDialog(
    title: title,
    first: DateUtils.dateOnly(firstDate),
    last: DateUtils.dateOnly(lastDate),
    initial: initialDateRange,
  ),
);

class _RangeDialog extends StatefulWidget {
  final String title;
  final DateTime first, last;
  final DateTimeRange? initial;
  const _RangeDialog({
    required this.title,
    required this.first,
    required this.last,
    this.initial,
  });
  @override
  State<_RangeDialog> createState() => _RangeDialogState();
}

class _RangeDialogState extends State<_RangeDialog> {
  DateTime? _start, _end;
  bool _editingEnd = false;
  @override
  void initState() {
    super.initState();
    _start = widget.initial?.start;
    _end = widget.initial?.end;
  }

  DateTime _clamp(DateTime date) => date.isBefore(widget.first)
      ? widget.first
      : date.isAfter(widget.last)
      ? widget.last
      : date;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    Widget field(bool end) {
      final date = end ? _end : _start;
      return OutlinedButton(
        onPressed: () => setState(() => _editingEnd = end),
        style: OutlinedButton.styleFrom(
          alignment: Alignment.centerLeft,
          padding: const EdgeInsets.all(12),
          backgroundColor: _editingEnd == end
              ? cs.primary.withValues(alpha: .08)
              : null,
          side: BorderSide(
            color: _editingEnd == end ? cs.primary : cs.outlineVariant,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              end ? 'End date' : 'Start date',
              style: theme.textTheme.labelMedium?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              date == null
                  ? 'Choose date'
                  : DateFormat.yMMMd(
                      Localizations.localeOf(context).toString(),
                    ).format(date),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: cs.onSurface,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      );
    }

    final initial = _clamp(
      (_editingEnd ? _end ?? _start : _start) ?? DateTime.now(),
    );
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        widget.title,
                        style: theme.textTheme.titleMedium,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Type selected date',
                      icon: Icon(Icons.keyboard_rounded, color: cs.primary),
                      onPressed: () async {
                        final date = await showAppDatePicker(
                          context: context,
                          title: _editingEnd ? 'End date' : 'Start date',
                          inputMode: true,
                          initialDate: initial,
                          firstDate: _editingEnd && _start != null
                              ? _start!
                              : widget.first,
                          lastDate: widget.last,
                        );
                        if (date != null && mounted) _choose(date);
                      },
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                child: MediaQuery.textScalerOf(context).scale(1) > 1.5
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          field(false),
                          const SizedBox(height: 8),
                          field(true),
                        ],
                      )
                    : Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: field(false)),
                          const SizedBox(width: 8),
                          Expanded(child: field(true)),
                        ],
                      ),
              ),
              MediaQuery.withClampedTextScaling(
                maxScaleFactor: 1.3,
                child: CalendarDatePicker(
                  key: ValueKey((_editingEnd, _start, _end)),
                  initialDate: initial,
                  firstDate: _editingEnd && _start != null
                      ? _start!
                      : widget.first,
                  lastDate: widget.last,
                  onDateChanged: _choose,
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
                child: Wrap(
                  alignment: WrapAlignment.end,
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Cancel'),
                    ),
                    FilledButton(
                      onPressed: _start != null && _end != null
                          ? () => Navigator.pop(
                              context,
                              DateTimeRange(start: _start!, end: _end!),
                            )
                          : null,
                      child: const Text('Apply'),
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

  void _choose(DateTime date) => setState(() {
    if (_editingEnd) {
      _end = date;
    } else {
      _start = date;
      if (_end != null && _end!.isBefore(date)) _end = null;
      _editingEnd = true;
    }
  });
}

class _DateDialog extends StatefulWidget {
  final String title;
  final bool inputMode;
  final DateTime firstDate, lastDate, initialDate;
  const _DateDialog({
    required this.title,
    this.inputMode = false,
    required this.firstDate,
    required this.lastDate,
    required this.initialDate,
  });
  @override
  State<_DateDialog> createState() => _DateDialogState();
}

class _DateDialogState extends State<_DateDialog> {
  final _form = GlobalKey<FormState>();
  late final _first = DateUtils.dateOnly(widget.firstDate);
  late final _last = DateUtils.dateOnly(widget.lastDate);
  late DateTime _selected = _clamp(widget.initialDate);
  late bool _input = widget.inputMode;
  int _calendarRevision = 0;
  DateTime _clamp(DateTime value) {
    final date = DateUtils.dateOnly(value);
    return date.isBefore(_first)
        ? _first
        : date.isAfter(_last)
        ? _last
        : date;
  }

  void _save() {
    if (_input && !_form.currentState!.validate()) return;
    if (_input) _form.currentState!.save();
    Navigator.pop(context, _selected);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final today = DateUtils.dateOnly(DateTime.now());
    final canUseToday = !today.isBefore(_first) && !today.isAfter(_last);
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(20, 12, 12, 20),
                color: cs.primary.withValues(alpha: .07),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            widget.title,
                            style: theme.textTheme.titleSmall,
                          ),
                        ),
                        IconButton(
                          tooltip: _input ? 'Show calendar' : 'Type a date',
                          onPressed: () => setState(() => _input = !_input),
                          icon: Icon(
                            _input
                                ? Icons.calendar_month_rounded
                                : Icons.keyboard_rounded,
                            color: cs.primary,
                          ),
                        ),
                      ],
                    ),
                    Text(
                      DateFormat.yMMMd(
                        Localizations.localeOf(context).toString(),
                      ).format(_selected),
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              if (_input)
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: Form(
                    key: _form,
                    child: InputDatePickerFormField(
                      initialDate: _selected,
                      firstDate: _first,
                      lastDate: _last,
                      autofocus: true,
                      onDateSaved: (date) => _selected = date,
                    ),
                  ),
                )
              else
                MediaQuery.withClampedTextScaling(
                  maxScaleFactor: 1.3,
                  child: CalendarDatePicker(
                    key: ValueKey(_calendarRevision),
                    initialDate: _selected,
                    firstDate: _first,
                    lastDate: _last,
                    onDateChanged: (date) => setState(() => _selected = date),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
                child: Wrap(
                  alignment: WrapAlignment.end,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (canUseToday)
                      TextButton(
                        onPressed: () => setState(() {
                          _selected = today;
                          _input = false;
                          _calendarRevision++;
                        }),
                        child: const Text('Today'),
                      ),
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Cancel'),
                    ),
                    FilledButton(
                      onPressed: _save,
                      child: const Text('Use date'),
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
